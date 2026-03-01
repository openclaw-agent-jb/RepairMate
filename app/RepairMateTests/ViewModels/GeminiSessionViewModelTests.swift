import Foundation
import UIKit
import XCTest

@testable import RepairMate

@MainActor
private final class MockGeminiService: GeminiLiveServicing {
    var connectionState: GeminiConnectionState = .disconnected
    var isModelSpeaking: Bool = false
    var systemInstructionOverride: String?

    var onAudioReceived: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?
    var onInputTranscription: ((String) -> Void)?
    var onOutputTranscription: ((String) -> Void)?
    var onToolCall: ((GeminiToolCall) -> Void)?
    var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)?

    var connectResult = true

    // Track repair mode calls
    private(set) var enableRepairMateModeCalls: [(domain: String, procedure: String?)] = []
    private(set) var disableRepairMateModeCalled = false

    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0
    private(set) var sendAudioCalls = 0
    private(set) var sendVideoFrameCalls = 0
    private(set) var toolResponseCalls = 0
    private(set) var sendClientContentCalls = 0
    private(set) var lastClientContentTurns: [ConversationTurn] = []

    func connect() async -> Bool {
        connectCalls += 1
        if connectResult {
            connectionState = .ready
        }
        return connectResult
    }

    func disconnect() {
        disconnectCalls += 1
        connectionState = .disconnected
    }

    func sendAudio(data: Data) {
        sendAudioCalls += 1
    }

    func sendVideoFrame(image: UIImage) {
        sendVideoFrameCalls += 1
    }

    func sendToolResponse(_ response: [String: Any]) {
        toolResponseCalls += 1
    }

    func sendClientContent(turns: [ConversationTurn]) {
        sendClientContentCalls += 1
        lastClientContentTurns = turns
    }

    func triggerDisconnected(reason: String?) {
        onDisconnected?(reason)
    }

    private(set) var clearSessionCalls = 0

    func clearSession() {
        clearSessionCalls += 1
    }

    // Mock implementation for repair mode
    func enableRepairMateMode(domain: String, procedure: String?) {
        enableRepairMateModeCalls.append((domain: domain, procedure: procedure))
    }

    func disableRepairMateMode() {
        disableRepairMateModeCalled = true
    }

    func analyzeImage(_ frame: Data, prompt: String) async -> String {
        return "{}"
    }
}

private final class MockAudioManager: AudioManaging {
    var onAudioCaptured: ((Data) -> Void)?

    var setupError: Error?
    var startCaptureError: Error?

    private(set) var setupModes: [Bool] = []
    private(set) var startCaptureCalls = 0
    private(set) var playAudioCalls = 0
    private(set) var stopPlaybackCalls = 0
    private(set) var stopCaptureCalls = 0

    func setupAudioSession(useIPhoneMode: Bool) throws {
        setupModes.append(useIPhoneMode)
        if let setupError { throw setupError }
    }

    func startCapture() throws {
        startCaptureCalls += 1
        if let startCaptureError { throw startCaptureError }
    }

    func playAudio(data: Data) {
        playAudioCalls += 1
    }

    func stopPlayback() {
        stopPlaybackCalls += 1
    }

    func stopCapture() {
        stopCaptureCalls += 1
    }

    func emitCapturedAudio(_ data: Data) {
        onAudioCaptured?(data)
    }
}

private struct MockGeminiError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class GeminiSessionViewModelTests: XCTestCase {
    private func waitUntil(
        timeout: TimeInterval = 1.0,
        pollInterval: UInt64 = 10_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return false
    }

    func testStartSessionWhenNotConfiguredSetsErrorAndDoesNotActivate() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { false }
        )

        await sut.startSession()

        XCTAssertFalse(sut.isGeminiActive)
        XCTAssertEqual(sut.errorMessage, "Gemini API key not configured. Open Developer Settings to add your key from https://aistudio.google.com/apikey")
        XCTAssertEqual(gemini.connectCalls, 0)
        XCTAssertEqual(audio.setupModes.count, 0)
    }

    func testStartSessionAudioSetupFailureStopsBeforeConnect() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        audio.setupError = MockGeminiError(message: "audio setup failed")
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        await sut.startSession()

        XCTAssertFalse(sut.isGeminiActive)
        XCTAssertEqual(gemini.connectCalls, 0)
        XCTAssertEqual(sut.errorMessage, "Audio setup failed: audio setup failed")
    }

    func testStartSessionConnectFailureUsesServiceErrorAndResetsState() async {
        let gemini = MockGeminiService()
        gemini.connectResult = false
        gemini.connectionState = .error("service connect failed")
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        await sut.startSession()

        XCTAssertFalse(sut.isGeminiActive)
        XCTAssertEqual(sut.errorMessage, "service connect failed")
        XCTAssertEqual(gemini.disconnectCalls, 1)
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertEqual(audio.startCaptureCalls, 0)
    }

    func testStartSessionCaptureFailureDisconnectsAndResetsState() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        audio.startCaptureError = MockGeminiError(message: "mic start failed")
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        await sut.startSession()

        XCTAssertFalse(sut.isGeminiActive)
        XCTAssertEqual(gemini.disconnectCalls, 1)
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertEqual(sut.errorMessage, "Mic capture failed: mic start failed")
    }

    func testStopSessionResetsStateAndStopsDependencies() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        sut.isGeminiActive = true
        sut.connectionState = .ready
        sut.isModelSpeaking = true
        sut.userTranscript = "hello"
        sut.aiTranscript = "world"
        sut.toolCallStatus = .executing("execute")

        sut.stopSession()

        XCTAssertFalse(sut.isGeminiActive)
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertFalse(sut.isModelSpeaking)
        XCTAssertEqual(sut.userTranscript, "")
        XCTAssertEqual(sut.aiTranscript, "")
        XCTAssertEqual(sut.toolCallStatus, .idle)
        XCTAssertEqual(gemini.disconnectCalls, 1)
        XCTAssertEqual(audio.stopCaptureCalls, 1)
    }

    func testSendVideoFrameIfThrottledHonorsConnectionStateAndInterval() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var currentTime = t0

        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true },
            now: { currentTime },
            videoFrameInterval: 1.0
        )

        // Not active -> no send
        sut.connectionState = .ready
        sut.sendVideoFrameIfThrottled(image: UIImage())
        XCTAssertEqual(gemini.sendVideoFrameCalls, 0)

        sut.isGeminiActive = true
        sut.sendVideoFrameIfThrottled(image: UIImage())
        XCTAssertEqual(gemini.sendVideoFrameCalls, 1)

        currentTime = t0.addingTimeInterval(0.3)
        sut.sendVideoFrameIfThrottled(image: UIImage())
        XCTAssertEqual(gemini.sendVideoFrameCalls, 1)

        currentTime = t0.addingTimeInterval(1.3)
        sut.sendVideoFrameIfThrottled(image: UIImage())
        XCTAssertEqual(gemini.sendVideoFrameCalls, 2)
    }

    func testAudioCaptureIsMutedInIPhoneModeWhileModelSpeaking() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )
        sut.streamingMode = .iPhone

        await sut.startSession()
        XCTAssertTrue(sut.isGeminiActive)

        gemini.isModelSpeaking = true
        audio.emitCapturedAudio(Data([1, 2, 3]))
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(gemini.sendAudioCalls, 0)

        gemini.isModelSpeaking = false
        audio.emitCapturedAudio(Data([1, 2, 3]))
        let didSend = await waitUntil { gemini.sendAudioCalls == 1 }
        XCTAssertTrue(didSend)

        sut.stopSession()
    }

    func testOnDisconnectedTriggersReconnectWhenActive() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true },
            reconnectSleep: { _ in }
        )

        await sut.startSession()
        XCTAssertTrue(sut.isGeminiActive)
        XCTAssertEqual(gemini.connectCalls, 1)

        gemini.triggerDisconnected(reason: "network dropped")

        let didReconnect = await waitUntil {
            gemini.connectCalls >= 2 && audio.stopCaptureCalls >= 1
        }
        XCTAssertTrue(didReconnect)

        sut.stopSession()
    }

    func testReconnectStartsFreshEmptySession() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true },
            reconnectSleep: { _ in }
        )

        await sut.startSession()
        XCTAssertTrue(sut.isGeminiActive)

        // Trigger disconnect and wait for reconnect
        gemini.triggerDisconnected(reason: "network dropped")

        let didReconnect = await waitUntil {
            gemini.connectCalls >= 2
        }
        XCTAssertTrue(didReconnect)
        // Gemini Live API doesn't support clientContent replay.
        XCTAssertEqual(gemini.sendClientContentCalls, 0)

        sut.stopSession()
    }

    func testStopSessionClearsResumptionToken() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true },
            reconnectSleep: { _ in }
        )

        await sut.startSession()
        XCTAssertTrue(sut.isGeminiActive)
        
        XCTAssertEqual(gemini.clearSessionCalls, 0)
        sut.stopSession()
        XCTAssertEqual(gemini.clearSessionCalls, 1)
    }


    // MARK: - Repair Domain Tests

    func testRepairDomainSetsSystemPromptAndStartsSafety() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Initially no system prompt
        XCTAssertNil(gemini.systemInstructionOverride)
        XCTAssertFalse(gemini.disableRepairMateModeCalled)

        // Set repair domain
        sut.repairDomain = .auto

        // System prompt should be set
        XCTAssertNotNil(gemini.systemInstructionOverride)
        XCTAssertTrue(gemini.systemInstructionOverride!.contains("RepairMate"))
        XCTAssertTrue(gemini.systemInstructionOverride!.contains("ASE-certified mechanic"))

        // Repair mode should be enabled
        XCTAssertEqual(gemini.enableRepairMateModeCalls.count, 1)
        XCTAssertEqual(gemini.enableRepairMateModeCalls[0].domain, "Auto Repair")
        XCTAssertFalse(gemini.disableRepairMateModeCalled)
    }

    func testRepairDomainChangeUpdatesSystemPrompt() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Set to auto domain
        sut.repairDomain = .auto
        let autoPrompt = gemini.systemInstructionOverride
        XCTAssertTrue(autoPrompt!.contains("ASE-certified mechanic"))

        // Change to electronics domain
        sut.repairDomain = .electronics
        XCTAssertNotEqual(gemini.systemInstructionOverride, autoPrompt)
        XCTAssertTrue(gemini.systemInstructionOverride!.contains("ESD"))
    }

    func testStopSafetyAnalysisPreservesSystemPrompt() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Set repair domain
        sut.repairDomain = .auto
        let prompt = gemini.systemInstructionOverride
        XCTAssertNotNil(prompt)
        XCTAssertFalse(gemini.disableRepairMateModeCalled)

        // Stop safety analysis (simulates streaming stop)
        sut.stopSafetyAnalysis()

        // System prompt should be preserved
        XCTAssertEqual(gemini.systemInstructionOverride, prompt)
        XCTAssertTrue(gemini.systemInstructionOverride!.contains("RepairMate"))

        // Repair mode should be disabled
        XCTAssertTrue(gemini.disableRepairMateModeCalled)
    }

    func testClearRepairDomainRemovesSystemPrompt() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Set repair domain
        sut.repairDomain = .auto
        XCTAssertNotNil(gemini.systemInstructionOverride)

        // Clear repair domain
        sut.repairDomain = nil

        // System prompt should be cleared
        XCTAssertNil(gemini.systemInstructionOverride)

        // Repair mode should be disabled
        XCTAssertTrue(gemini.disableRepairMateModeCalled)
    }

    func testStopSafetyAnalysisWhenNoDomainDoesNotCrash() {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Should not crash when no domain is set
        sut.stopSafetyAnalysis()

        // No system prompt to preserve
        XCTAssertNil(gemini.systemInstructionOverride)
        XCTAssertTrue(gemini.disableRepairMateModeCalled)
    }

    func testRepairDomainAllFourDomainsHaveSystemPrompts() {
        for domain in RepairDomain.allCases {
            let gemini = MockGeminiService()
            let audio = MockAudioManager()
            let sut = GeminiSessionViewModel(
                geminiService: gemini,
                audioManager: audio,
                isGeminiConfigured: { true }
            )

            sut.repairDomain = domain

            XCTAssertNotNil(gemini.systemInstructionOverride, "\(domain) should have a system prompt")
            XCTAssertEqual(gemini.enableRepairMateModeCalls.count, 1, "\(domain) should enable repair mode")
            XCTAssertEqual(gemini.enableRepairMateModeCalls[0].domain, domain.rawValue, "\(domain) domain should match")
        }
    }

    func testStartSessionReappliesRepairDomainOnReconnect() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Set repair domain first
        sut.repairDomain = .auto
        XCTAssertEqual(gemini.enableRepairMateModeCalls.count, 1)
        let firstPrompt = gemini.systemInstructionOverride
        XCTAssertNotNil(firstPrompt)

        // Simulate streaming stop (stopSafetyAnalysis preserves prompt)
        sut.stopSafetyAnalysis()
        XCTAssertTrue(gemini.disableRepairMateModeCalled)
        // System prompt should still be set after stopSafetyAnalysis
        XCTAssertEqual(gemini.systemInstructionOverride, firstPrompt)

        // Start session again - repair domain should be re-applied
        await sut.startSession()

        // Verify repair domain was re-applied
        XCTAssertEqual(gemini.enableRepairMateModeCalls.count, 2, "Repair domain should be re-applied on startSession")
        XCTAssertEqual(gemini.enableRepairMateModeCalls[1].domain, "Auto Repair")
        XCTAssertEqual(gemini.systemInstructionOverride, firstPrompt, "System prompt should be the same")

        sut.stopSession()
    }

    func testStartSessionWithoutRepairDomainDoesNotReapply() async {
        let gemini = MockGeminiService()
        let audio = MockAudioManager()
        let sut = GeminiSessionViewModel(
            geminiService: gemini,
            audioManager: audio,
            isGeminiConfigured: { true }
        )

        // Start session without setting repair domain
        await sut.startSession()

        XCTAssertEqual(gemini.enableRepairMateModeCalls.count, 0, "Repair mode should not be enabled without domain")

        sut.stopSession()
    }
}
