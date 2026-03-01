import Foundation
import UIKit

// MARK: - Safety Analysis Service

/// Runs a periodic safety check loop alongside the main Gemini conversation.
///
/// Every `interval` seconds it:
///  1. Grabs the latest video frame from the shared FrameStore
///  2. Sends the frame + a silent safety prompt via the Gemini live connection
///  3. Parses the response through SafetyClassifier
///  4. Calls onSafetyAlert when level is WARNING or STOP
///
/// The loop is completely non-blocking — it uses a background Task and stops
/// itself when `stop()` is called or when the owning object is deallocated.
@MainActor
final class SafetyAnalysisService {

    // MARK: - Public

    /// Called on the main actor whenever a WARNING or STOP assessment is produced.
    var onSafetyAlert: ((SafetyAssessment) -> Void)?

    private let classifier: SafetyClassifier
    private let geminiService: GeminiLiveServicing
    private let interval: TimeInterval
    private var loopTask: Task<Void, Never>?
    private var currentStep: String?

    init(
        geminiService: GeminiLiveServicing,
        interval: TimeInterval? = nil
    ) {
        self.geminiService = geminiService
        self.classifier = SafetyClassifier(geminiService: geminiService)
        
        if let passedInterval = interval {
            self.interval = passedInterval
        } else if let configString = Bundle.main.object(forInfoDictionaryKey: "SafetyAnalysisInterval") as? String,
                  let configuredInterval = TimeInterval(configString) {
            self.interval = configuredInterval
        } else {
            self.interval = 5.0 // fallback
        }
    }

    /// Update the step description used in the safety prompt.
    func updateCurrentStep(_ step: String?) {
        currentStep = step
    }

    /// Begin the periodic safety analysis loop.
    func start() {
        guard loopTask == nil else { return }
        NSLog("[SafetyAnalysis] Starting — interval: %.1fs", interval)
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.analyzeFrame()
            }
        }
    }

    /// Stop the loop. Safe to call multiple times.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        NSLog("[SafetyAnalysis] Stopped")
    }

    // MARK: - Private

    private func analyzeFrame() async {
        // Pull the latest frame from the shared store
        guard let frame = FrameStore.shared.latestFrame else {
            return
        }

        // Send the frame so Gemini can see the current scene.
        // The system prompt already instructs RepairMate to verbally warn about hazards —
        // we do NOT send a separate conversation turn, which would cause JSON to appear in
        // the transcript and get spoken aloud.
        geminiService.sendVideoFrame(image: frame)
        
        let frameData = frame.jpegData(compressionQuality: 0.5) ?? Data()
        let assessment = await classifier.analyzeFrame(frameData, currentStep: currentStep)

        if assessment.level != .safe {
            onSafetyAlert?(assessment)
        }
    }
}

// MARK: - FrameStore

/// A lightweight shared store for the most recent video frame from the glasses.
/// StreamSessionViewModel writes here; SafetyAnalysisService reads here.
final class FrameStore {
    static let shared = FrameStore()
    private init() {}

    /// The most recently received video frame. Written from the main thread.
    @MainActor var latestFrame: UIImage?
}
