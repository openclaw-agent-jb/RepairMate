import Foundation
import UIKit

enum GeminiConnectionState: Equatable {
  case disconnected
  case connecting
  case settingUp
  case ready
  case error(String)
}

struct ConversationTurn: Equatable {
  let role: String  // "user" or "model"
  let text: String
}

@MainActor
class GeminiLiveService: ObservableObject {
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false

  /// When set, overrides GeminiConfig.systemInstruction in the setup message.
  /// Used by RepairMate to inject domain-specific system prompts.
  var systemInstructionOverride: String?

  /// The token used to resume a disconnected session and restore conversation context.
  private(set) var resumptionToken: String?

  /// When true, RepairMate tool declarations are included in the Gemini setup message.
  private var repairMateMode: Bool = false

  /// Enable RepairMate mode — injects domain system prompt and registers repair tools.
  func enableRepairMateMode(domain: String, procedure: String?) {
    repairMateMode = true
    NSLog("[Gemini] RepairMate mode enabled — domain: %@", domain)
  }

  /// Disable RepairMate mode and restore the default system prompt.
  func disableRepairMateMode() {
    repairMateMode = false
    systemInstructionOverride = nil
    NSLog("[Gemini] RepairMate mode disabled")
  }

  var onAudioReceived: ((Data) -> Void)?
  var onTurnComplete: (() -> Void)?
  var onInterrupted: (() -> Void)?
  var onDisconnected: ((String?) -> Void)?
  var onInputTranscription: ((String) -> Void)?
  var onOutputTranscription: ((String) -> Void)?
  var onToolCall: ((GeminiToolCall) -> Void)?
  var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)?

  // Latency tracking
  private var lastUserSpeechEnd: Date?
  private var responseLatencyLogged = false

  private var webSocketTask: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var connectContinuation: CheckedContinuation<Bool, Never>?
  private var connectTimeoutTask: Task<Void, Never>?
  private var connectionLostFired = false
  private let delegate = WebSocketDelegate()
  private var urlSession: URLSession?
  private let sendQueue = DispatchQueue(label: "gemini.send", qos: .userInitiated)

  init() {}

  func connect() async -> Bool {
    guard connectContinuation == nil else {
      NSLog("[Gemini] connect() called while already connecting — ignored")
      return false
    }

    guard let url = GeminiConfig.websocketURL() else {
      connectionState = .error("No API key configured")
      return false
    }

    connectionState = .connecting
    connectionLostFired = false
    connectTimeoutTask?.cancel()
    connectTimeoutTask = nil

    // Fresh URLSession per connection — reusing a session after a WebSocket
    // failure leaves the TLS connection pool in a broken state, causing all
    // subsequent tasks to fail with "failed parent-flow".
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30
    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    self.urlSession = session

    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      self.connectContinuation = continuation

      self.delegate.onOpen = { [weak self] protocol_ in
        guard let self else { return }
        Task { @MainActor in
          self.connectionState = .settingUp
          self.sendSetupMessage()
          self.startReceiving()
        }
      }

      let wsTask = session.webSocketTask(with: url)
      self.webSocketTask = wsTask
      wsTask.resume()

      self.delegate.onClose = { [weak self] closedTask, code, reason in
        guard let self else { return }
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason"
        Task { @MainActor in
          // Ignore stale close events from a previous WebSocket connection
          guard closedTask === self.webSocketTask else { return }
          self.handleConnectionLost(reason: "Connection closed (code \(code.rawValue): \(reasonStr))")
        }
      }

      self.delegate.onError = { [weak self] errorTask, error in
        guard let self else { return }
        let msg = error?.localizedDescription ?? "Unknown error"
        Task { @MainActor in
          // Ignore stale errors from a previous WebSocket connection
          guard errorTask === self.webSocketTask else { return }
          self.handleConnectionLost(reason: msg)
        }
      }

      // Timeout after 15 seconds
      self.connectTimeoutTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        guard !Task.isCancelled, let self else { return }
        await MainActor.run {
          if self.connectionState == .connecting || self.connectionState == .settingUp {
            self.handleConnectionLost(reason: "Connection timed out")
          }
        }
      }
    }

    return result
  }

  func disconnect() {
    connectTimeoutTask?.cancel()
    connectTimeoutTask = nil
    receiveTask?.cancel()
    receiveTask = nil
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    delegate.onOpen = nil
    delegate.onClose = nil
    delegate.onError = nil
    // Note: onToolCall/onToolCallCancellation/resumptionToken are NOT cleared here —
    // they must survive reconnects to preserve context.
    connectionState = .disconnected
    isModelSpeaking = false
    resolveConnect(success: false)
  }

  func sendAudio(data: Data) {
    guard connectionState == .ready else { return }
    sendQueue.async { [weak self] in
      let base64 = data.base64EncodedString()
      let json: [String: Any] = [
        "realtimeInput": [
          "audio": [
            "mimeType": "audio/pcm;rate=16000",
            "data": base64
          ]
        ]
      ]
      self?.sendJSON(json)
    }
  }

  func sendVideoFrame(image: UIImage) {
    guard connectionState == .ready else { return }
    sendQueue.async { [weak self] in
      guard let jpegData = image.jpegData(compressionQuality: GeminiConfig.videoJPEGQuality) else { return }
      let base64 = jpegData.base64EncodedString()
      let json: [String: Any] = [
        "realtimeInput": [
          "video": [
            "mimeType": "image/jpeg",
            "data": base64
          ]
        ]
      ]
      self?.sendJSON(json)
    }
  }

  func sendToolResponse(_ response: [String: Any]) {
    guard connectionState == .ready else { return }
    sendQueue.async { [weak self] in
      self?.sendJSON(response)
    }
  }

  func sendClientContent(turns: [ConversationTurn]) {
    guard !turns.isEmpty else { return }
    let turnDicts: [[String: Any]] = turns.map { turn in
      ["role": turn.role, "parts": [["text": turn.text] as [String: Any]]]
    }
    let json: [String: Any] = [
      "clientContent": ["turns": turnDicts, "turnComplete": true] as [String: Any]
    ]
    sendQueue.async { [weak self] in
      self?.sendJSON(json)
    }
  }

  // MARK: - Private

  private func resolveConnect(success: Bool) {
    if let cont = connectContinuation {
      connectContinuation = nil
      cont.resume(returning: success)
    }
  }

  private func handleConnectionLost(reason: String?) {
    guard !connectionLostFired else { return }
    connectionLostFired = true
    connectTimeoutTask?.cancel()
    connectTimeoutTask = nil
    // If we're mid-connect, resolve the continuation as false.
    // Do NOT fire onDisconnected — the caller handles failure via the return value.
    // This prevents overlapping reconnect tasks when connect() fails.
    let wasConnecting = connectContinuation != nil
    resolveConnect(success: false)
    connectionState = .disconnected
    isModelSpeaking = false
    if !wasConnecting {
      onDisconnected?(reason)
    }
  }

  private func sendSetupMessage() {
    var setup: [String: Any] = [
      "model": GeminiConfig.model,
      "generationConfig": [
        "responseModalities": ["AUDIO"],
        "thinkingConfig": [
          "thinkingBudget": 0
        ]
      ],
      "realtimeInputConfig": [
        "automaticActivityDetection": [
          "disabled": false,
          "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
          "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
          "silenceDurationMs": 500,
          "prefixPaddingMs": 40
        ],
        "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
        "turnCoverage": "TURN_INCLUDES_ALL_INPUT"
      ],
      "inputAudioTranscription": [:] as [String: Any],
      "outputAudioTranscription": [:] as [String: Any]
    ]

    let instruction = systemInstructionOverride ?? GeminiConfig.systemInstruction
    setup["systemInstruction"] = [
      "parts": [
        ["text": instruction]
      ]
    ]
    setup["tools"] = [
      [
        "functionDeclarations": ToolDeclarations.allDeclarations(includeRepairMateTools: repairMateMode)
      ]
    ]

    // Instruct the server to send resumption tokens so context isn't lost on disconnect
    if let token = resumptionToken {
      setup["sessionResumption"] = ["handle": token]
    } else {
      setup["sessionResumption"] = [:] as [String: Any]
    }

    sendJSON(["setup": setup])
  }

  private func sendJSON(_ json: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let string = String(data: data, encoding: .utf8) else {
      return
    }
    guard let task = webSocketTask else { return }
    task.send(.string(string)) { error in
      if let error {
        NSLog("[Gemini] WebSocket send error: %@", error.localizedDescription)
      }
    }
  }

  private func startReceiving() {
    receiveTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        guard let task = self.webSocketTask else { break }
        do {
          let message = try await task.receive()
          switch message {
          case .string(let text):
            await self.handleMessage(text)
          case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
              await self.handleMessage(text)
            }
          @unknown default:
            break
          }
        } catch {
          if !Task.isCancelled {
            let reason = error.localizedDescription
            await MainActor.run {
              self.handleConnectionLost(reason: reason)
            }
          }
          break
        }
      }
    }
  }

  private func handleMessage(_ text: String) async {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return
    }

    // API-level error (quota exhausted, invalid key, etc.)
    if let apiError = json["error"] as? [String: Any] {
      let code    = apiError["code"]    as? Int    ?? -1
      let message = apiError["message"] as? String ?? "Unknown API error"
      let status  = apiError["status"]  as? String ?? ""
      let userMsg = code == 429
        ? "Gemini quota exceeded — check billing at aistudio.google.com"
        : "Gemini API error \(code)\(status.isEmpty ? "" : " (\(status))"): \(message)"
      connectionState = .error(userMsg)
      isModelSpeaking = false
      onDisconnected?(userMsg)
      return
    }

    // Setup complete
    if json["setupComplete"] != nil {
      NSLog("[Gemini] Setup complete — connection ready")
      connectionState = .ready
      resolveConnect(success: true)
      return
    }

    // Session resumption update
    if let resumption = json["sessionResumptionUpdate"] as? [String: Any],
       let resumable = resumption["resumable"] as? Bool, resumable,
       let newHandle = resumption["newHandle"] as? String {
      NSLog("[Gemini] Received new session resumption token")
      self.resumptionToken = newHandle
      return
    }

    // GoAway - server will close soon
    if let goAway = json["goAway"] as? [String: Any] {
      let timeLeft = goAway["timeLeft"] as? [String: Any]
      let seconds = timeLeft?["seconds"] as? Int ?? 0
      connectionState = .disconnected
      isModelSpeaking = false
      onDisconnected?("Server closing (time left: \(seconds)s)")
      return
    }

    // Tool call from model (top-level message, not inside serverContent)
    if let toolCall = GeminiToolCall(json: json) {
      NSLog("[Gemini] Tool call received: %d function(s)", toolCall.functionCalls.count)
      onToolCall?(toolCall)
      return
    }

    // Tool call cancellation (user interrupted during tool execution)
    if let cancellation = GeminiToolCallCancellation(json: json) {
      NSLog("[Gemini] Tool call cancellation: %@", cancellation.ids.joined(separator: ", "))
      onToolCallCancellation?(cancellation)
      return
    }

    // Server content
    if let serverContent = json["serverContent"] as? [String: Any] {
      if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
        isModelSpeaking = false
        onInterrupted?()
        return
      }

      if let modelTurn = serverContent["modelTurn"] as? [String: Any],
         let parts = modelTurn["parts"] as? [[String: Any]] {
        for part in parts {
          if let inlineData = part["inlineData"] as? [String: Any],
             let mimeType = inlineData["mimeType"] as? String,
             mimeType.hasPrefix("audio/pcm"),
             let base64Data = inlineData["data"] as? String,
             let audioData = Data(base64Encoded: base64Data) {
            if !isModelSpeaking {
              isModelSpeaking = true
              // Log latency: time from end of user speech to first audio response
              if let speechEnd = lastUserSpeechEnd, !responseLatencyLogged {
                let latency = Date().timeIntervalSince(speechEnd)
                NSLog("[Latency] %.0fms (user speech end -> first audio)", latency * 1000)
                responseLatencyLogged = true
              }
            }
            onAudioReceived?(audioData)
          } else if let text = part["text"] as? String {
            NSLog("[Gemini] %@", text)
          }
        }
      }

      if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
        isModelSpeaking = false
        responseLatencyLogged = false
        onTurnComplete?()
      }

      if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
         let text = inputTranscription["text"] as? String, !text.isEmpty {
        NSLog("[Gemini] You: %@", text)
        lastUserSpeechEnd = Date()
        responseLatencyLogged = false
        onInputTranscription?(text)
      }
      if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
         let text = outputTranscription["text"] as? String, !text.isEmpty {
        NSLog("[Gemini] AI: %@", text)
        onOutputTranscription?(text)
      }
      return
    }
  }

  func analyzeImage(_ frame: Data, prompt: String) async -> String {
    let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    guard let url = URL(string: urlString) else { return "" }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(GeminiConfig.apiKey, forHTTPHeaderField: "x-goog-api-key")

    let base64Image = frame.base64EncodedString()
    let payload: [String: Any] = [
      "contents": [
        [
          "parts": [
            ["text": prompt],
            [
              "inline_data": [
                "mime_type": "image/jpeg",
                "data": base64Image
              ]
            ]
          ]
        ]
      ],
      "generationConfig": [
        "responseMimeType": "application/json"
      ]
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: payload)
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        if let errorStr = String(data: data, encoding: .utf8) {
          NSLog("[Gemini] analyzeImage failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) response: \(errorStr)")
        }
        return ""
      }
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let candidates = json["candidates"] as? [[String: Any]],
         let first = candidates.first,
         let content = first["content"] as? [String: Any],
         let parts = content["parts"] as? [[String: Any]],
         let text = parts.first?["text"] as? String {
        return text
      }
    } catch {
      NSLog("[Gemini] analyzeImage error: \(error.localizedDescription)")
    }
    return ""
  }

  /// Manually clears the resumption token and conversation context
  func clearSession() {
    resumptionToken = nil
  }
}

// MARK: - WebSocket Delegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
  var onOpen: ((String?) -> Void)?
  var onClose: ((URLSessionWebSocketTask, URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
  var onError: ((URLSessionTask, Error?) -> Void)?

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onOpen?(`protocol`)
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onClose?(webSocketTask, closeCode, reason)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      onError?(task, error)
    }
  }
}
