import Foundation
import SwiftUI

@MainActor
protocol GeminiLiveServicing: AnyObject {
  var connectionState: GeminiConnectionState { get set }
  var isModelSpeaking: Bool { get }
  var systemInstructionOverride: String? { get set }

  var onAudioReceived: ((Data) -> Void)? { get set }
  var onTurnComplete: (() -> Void)? { get set }
  var onInterrupted: (() -> Void)? { get set }
  var onDisconnected: ((String?) -> Void)? { get set }
  var onInputTranscription: ((String) -> Void)? { get set }
  var onOutputTranscription: ((String) -> Void)? { get set }
  var onToolCall: ((GeminiToolCall) -> Void)? { get set }
  var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)? { get set }

  func connect() async -> Bool
  func disconnect()
  func sendAudio(data: Data)
  func sendVideoFrame(image: UIImage)
  func sendToolResponse(_ response: [String: Any])
  func sendClientContent(turns: [ConversationTurn])
  func analyzeImage(_ frame: Data, prompt: String) async -> String

  // RepairMate mode control
  func enableRepairMateMode(domain: String, procedure: String?)
  func disableRepairMateMode()
  func clearSession()
}

protocol AudioManaging: AnyObject {
  var onAudioCaptured: ((Data) -> Void)? { get set }
  func setupAudioSession(useIPhoneMode: Bool) throws
  func startCapture() throws
  func playAudio(data: Data)
  func stopPlayback()
  func stopCapture()
}

@MainActor
protocol ToolCallRouting: AnyObject {
  func handleToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  )
  func cancelToolCalls(ids: [String])
  func cancelAll()
}

@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var safetyAlert: SafetyAssessment?
  private let geminiService: GeminiLiveServicing
  private let openClawBridge = OpenClawBridge()
  private var toolCallRouter: ToolCallRouting?
  private let audioManager: AudioManaging
  private var lastVideoFrameTime: Date = .distantPast
  private var stateObservation: Task<Void, Never>?
  private var displayClearTimer: Task<Void, Never>?
  private var reconnectAttempts = 0
  private let maxReconnectAttempts = 5
  private var reconnectTask: Task<Void, Never>?
  @Published private(set) var conversationHistory: [ConversationTurn] = []
  @Published private(set) var currentTurnUserText = ""
  @Published private(set) var currentTurnModelText = ""
  private let maxHistoryTurns = 20
  private let isGeminiConfigured: () -> Bool
  private let reconnectSleep: (UInt64) async -> Void
  private let now: () -> Date
  private let videoFrameInterval: TimeInterval
  private let toolCallRouterFactory: (OpenClawBridge) -> ToolCallRouting
  private var safetyService: SafetyAnalysisService?
  var streamingMode: StreamingMode = .glasses

  /// The active repair domain. When set, overrides the Gemini system prompt
  /// with domain-specific RepairMate instructions and activates safety analysis.
  var repairDomain: RepairDomain? {
    didSet {
      if let domain = repairDomain {
        applyRepairDomain(domain)
      } else {
        clearRepairDomain()
      }
    }
  }

  /// The name of the current procedure (set by StreamSessionView when a procedure is selected).
  /// Used for transcript title generation.
  var currentProcedureName: String?

  /// Applies the repair domain: sets system prompt and starts safety analysis.
  private func applyRepairDomain(_ domain: RepairDomain) {
    let manager = RepairMateSessionManager()
    manager.startSession(domain: domain)
    let prompt = manager.buildSystemPrompt()

    geminiService.systemInstructionOverride = prompt
    // Enable RepairMate mode so repair tools are included on next connect
    geminiService.enableRepairMateMode(
      domain: domain.rawValue,
      procedure: nil
    )
    // Start periodic safety analysis
    let safety = SafetyAnalysisService(geminiService: geminiService)
    safety.onSafetyAlert = { [weak self] assessment in
      guard let self else { return }
      NSLog("[RepairMate] Safety alert: %@ — %@",
            assessment.level.rawValue, assessment.reason)
      self.showSafetyAlert(assessment)
    }
    safety.start()
    safetyService = safety
  }

  /// Clears the repair domain: stops safety analysis but keeps system prompt.
  /// Use this when streaming stops but you want to preserve domain knowledge.
  func stopSafetyAnalysis() {
    safetyService?.stop()
    safetyService = nil
    geminiService.disableRepairMateMode()
  }

  /// Fully clears the repair domain: stops safety analysis AND removes system prompt.
  private func clearRepairDomain() {
    stopSafetyAnalysis()
    geminiService.systemInstructionOverride = nil
  }

  init(
    geminiService: GeminiLiveServicing? = nil,
    audioManager: AudioManaging = AudioManager(),
    isGeminiConfigured: @escaping () -> Bool = { GeminiConfig.isConfigured },
    reconnectSleep: @escaping (UInt64) async -> Void = { nanoseconds in
      try? await Task.sleep(nanoseconds: nanoseconds)
    },
    now: @escaping () -> Date = { Date() },
    videoFrameInterval: TimeInterval = GeminiConfig.videoFrameInterval,
    toolCallRouterFactory: ((OpenClawBridge) -> ToolCallRouting)? = nil
  ) {
    self.geminiService = geminiService ?? GeminiLiveService()
    self.audioManager = audioManager
    self.isGeminiConfigured = isGeminiConfigured
    self.reconnectSleep = reconnectSleep
    self.now = now
    self.videoFrameInterval = videoFrameInterval
    self.toolCallRouterFactory = toolCallRouterFactory ?? { bridge in
      ToolCallRouter(bridge: bridge)
    }
  }

  func startSession() async {
    guard !isGeminiActive else { return }

    // Re-apply repair domain if one was set (it may have been lost after disconnect)
    if let domain = repairDomain {
      applyRepairDomain(domain)
    }

    guard isGeminiConfigured() else {
      errorMessage = "Gemini API key not configured. Open Developer Settings to add your key from https://aistudio.google.com/apikey"
      return
    }

    isGeminiActive = true

    // Wire audio callbacks
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        // iPhone mode: mute mic while model speaks to prevent echo feedback
        // (loudspeaker + co-located mic overwhelms iOS echo cancellation)
        if self.streamingMode == .iPhone && self.geminiService.isModelSpeaking { return }
        self.geminiService.sendAudio(data: data)
      }
    }

    geminiService.onAudioReceived = { [weak self] data in
      self?.audioManager.playAudio(data: data)
    }

    geminiService.onInterrupted = { [weak self] in
      self?.audioManager.stopPlayback()
    }

    geminiService.onTurnComplete = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        // Check for safety warning using the FULL completed turn text
        // before it gets cleared — avoids partial-text banner (e.g. "The blue").
        if self.repairDomain != nil, self.safetyAlert == nil {
          self.checkForSafetyWarning(in: self.currentTurnModelText)
        }

        // Commit completed exchange to history before clearing UI state
        if !self.currentTurnUserText.isEmpty {
          self.conversationHistory.append(ConversationTurn(role: "user", text: self.currentTurnUserText))
        }
        if !self.currentTurnModelText.isEmpty {
          self.conversationHistory.append(ConversationTurn(role: "model", text: self.currentTurnModelText))
        }
        self.currentTurnUserText = ""
        self.currentTurnModelText = ""
        if self.conversationHistory.count > self.maxHistoryTurns {
          self.conversationHistory = Array(self.conversationHistory.suffix(self.maxHistoryTurns))
        }
        // Clear user transcript when AI finishes responding
        self.userTranscript = ""
        self.resetDisplayClearTimer()
      }
    }

    geminiService.onInputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.userTranscript += text
        self.aiTranscript = ""
        self.currentTurnUserText += text
        self.resetDisplayClearTimer()
      }
    }

    geminiService.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.aiTranscript += text
        self.currentTurnModelText += text
        self.resetDisplayClearTimer()
      }
    }

    // Handle unexpected disconnection — auto-reconnect silently
    geminiService.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }
        self.reconnectTask?.cancel()
        NSLog("[Gemini] Connection lost (%@), starting reconnect",
              reason ?? "unknown")
        self.reconnectTask = Task { await self.reconnect() }
      }
    }

    // New OpenClaw session per Gemini session (fresh context, no stale memory)
    openClawBridge.resetSession()

    // Wire tool call handling
    toolCallRouter = toolCallRouterFactory(openClawBridge)

    geminiService.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        for call in toolCall.functionCalls {
          self.toolCallRouter?.handleToolCall(call) { [weak self] response in
            self?.geminiService.sendToolResponse(response)
          }
        }
      }
    }

    geminiService.onToolCallCancellation = { [weak self] cancellation in
      guard let self else { return }
      Task { @MainActor in
        self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
      }
    }

    // Observe service state
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled else { break }
        self.connectionState = self.geminiService.connectionState
        self.isModelSpeaking = self.geminiService.isModelSpeaking
        let newToolStatus = self.openClawBridge.lastToolCallStatus
        if newToolStatus != self.toolCallStatus {
          self.toolCallStatus = newToolStatus
          if newToolStatus != .idle {
            self.resetDisplayClearTimer()
          }
        }
      }
    }

    // Setup audio — iPhone mode uses aggressive AEC (.voiceChat), glasses uses mild AEC (.videoChat)
    do {
      try audioManager.setupAudioSession(useIPhoneMode: streamingMode == .iPhone)
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      isGeminiActive = false
      return
    }

    // Connect to Gemini and wait for setupComplete
    reconnectAttempts = 0
    let setupOk = await geminiService.connect()

    if !setupOk {
      let msg: String
      if case .error(let err) = geminiService.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to Gemini (state: \(geminiService.connectionState))"
      }
      errorMessage = msg
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }
  }

  func stopSession() {
    safetyService?.stop()
    safetyService = nil
    reconnectTask?.cancel()
    reconnectTask = nil
    // Auto-save transcript before clearing history
    TranscriptStore.shared.autoSaveIfEnabled(
      turns: conversationHistory,
      domain: repairDomain?.shortLabel,
      procedure: currentProcedureName
    )
    conversationHistory = []
    currentTurnUserText = ""
    currentTurnModelText = ""
    toolCallRouter?.cancelAll()
    toolCallRouter = nil
    audioManager.stopCapture()
    geminiService.clearSession()
    geminiService.disconnect()
    stateObservation?.cancel()
    stateObservation = nil
    displayClearTimer?.cancel()
    displayClearTimer = nil
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
  }


  private func reconnect() async {
    geminiService.disconnect()
    audioManager.stopCapture()
    currentTurnUserText = ""
    currentTurnModelText = ""

    // Retry loop with exponential backoff (handleConnectionLost does NOT fire
    // onDisconnected during connect(), so we must drive retries ourselves).
    while reconnectAttempts < maxReconnectAttempts {
      reconnectAttempts += 1
      let backoffNs = UInt64(1_000_000_000) * UInt64(1 << (reconnectAttempts - 1)) // 1s, 2s, 4s, 8s, 16s
      NSLog("[Gemini] Reconnect attempt %d/%d (backoff %dms)",
            reconnectAttempts, maxReconnectAttempts, backoffNs / 1_000_000)
      await reconnectSleep(backoffNs)

      guard !Task.isCancelled else { return }

      let setupOk = await geminiService.connect()
      if setupOk {
        // Note: clientContent history replay removed — the native audio model
        // rejects it with 1007 "invalid argument". Reconnects start fresh.
        do {
          try audioManager.startCapture()
          NSLog("[Gemini] Reconnect succeeded on attempt %d", reconnectAttempts)
          reconnectAttempts = 0
          return // Success — exit retry loop
        } catch {
          stopSession()
          errorMessage = "Mic capture failed on reconnect"
          return
        }
      }
      // connect() failed — clean up before next attempt
      geminiService.disconnect()
    }

    // All attempts exhausted for session resumption.
    // Fall back to a fresh connection without session resumption.
    NSLog("[Gemini] Resumption failed after %d attempts. Falling back to fresh session.", maxReconnectAttempts)
    errorMessage = "Session could not be resumed. Starting a fresh connection..."
    geminiService.clearSession()

    // Brief pause before the fallback attempt
    await reconnectSleep(1_000_000_000)

    guard !Task.isCancelled else { return }

    let fallbackSetupOk = await geminiService.connect()
    if fallbackSetupOk {
      do {
        try audioManager.startCapture()
        NSLog("[Gemini] Fallback fresh connection succeeded")
        return
      } catch {
        stopSession()
        errorMessage = "Mic capture failed on fresh connection"
        return
      }
    }

    // Fallback failed
    stopSession()
    errorMessage = "Reconnection failed completely."
  }

  private func resetDisplayClearTimer() {
    displayClearTimer?.cancel()
    displayClearTimer = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
      guard !Task.isCancelled, let self else { return }
      self.userTranscript = ""
      self.aiTranscript = ""
      self.toolCallStatus = .idle
      // Keep source-of-truth in sync so stateObservation doesn't re-hydrate stale status.
      self.openClawBridge.lastToolCallStatus = .idle
    }
  }

  func sendVideoFrameIfThrottled(image: UIImage) {
    guard isGeminiActive, connectionState == .ready else { return }
    let timestamp = now()
    guard timestamp.timeIntervalSince(lastVideoFrameTime) >= videoFrameInterval else { return }
    lastVideoFrameTime = timestamp
    FrameStore.shared.latestFrame = image   // Safety analysis reads from here
    geminiService.sendVideoFrame(image: image)
  }

  /// Display a safety alert banner. It must be manually dismissed by tapping.
  /// Call this from both real safety events and the debug test button.
  func showSafetyAlert(_ assessment: SafetyAssessment) {
    withAnimation(.spring()) {
      safetyAlert = assessment
    }
  }

  /// Detect "SAFETY WARNING:" in Gemini's spoken output and surface it as a banner.
  /// Gemini is instructed by the system prompt to prefix hazard warnings with this keyword.
  private func checkForSafetyWarning(in text: String) {
    let keyword = "SAFETY WARNING:"
    guard let range = text.range(of: keyword, options: .caseInsensitive) else { return }

    // Extract everything after the keyword
    let body = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard !body.isEmpty else { return }

    // Split into reason + action on a sentence boundary if possible
    let sentences = body.components(separatedBy: ". ")
    let reason = sentences.first ?? body
    let action = sentences.count > 1 ? sentences.dropFirst().joined(separator: ". ") : "Stop and assess the situation carefully."

    // Determine level: "STOP" or "IMMEDIATE" in the text escalates to stop
    let isStop = body.localizedCaseInsensitiveContains("stop immediately")
                  || body.localizedCaseInsensitiveContains("do not proceed")
    let level: SafetyAssessment.SafetyLevel = isStop ? .stop : .warning

    let assessment = SafetyAssessment(level: level, reason: reason, action: action)
    NSLog("[SafetyDetect] Keyword detected → level: %@, reason: %@", level.rawValue, reason)
    showSafetyAlert(assessment)
  }

}

extension GeminiLiveService: GeminiLiveServicing {}
extension AudioManager: AudioManaging {}
extension ToolCallRouter: ToolCallRouting {}
