import AVFoundation
import Foundation

class AudioManager {
  var onAudioCaptured: ((Data) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var isCapturing = false
  private var engineConfigObserver: NSObjectProtocol?
  private var interruptionObserver: NSObjectProtocol?

  private let outputFormat: AVAudioFormat

  // Accumulate resampled PCM into ~100ms chunks before sending
  private let sendQueue = DispatchQueue(label: "audio.accumulator")
  private var accumulatedData = Data()
  private let minSendBytes = 3200  // 100ms at 16kHz mono Int16 = 1600 frames * 2 bytes

  init() {
    self.outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: true
    )!
  }

  func setupAudioSession(useIPhoneMode: Bool = false) throws {
    let session = AVAudioSession.sharedInstance()
    // iPhone mode: voiceChat for aggressive echo cancellation (mic + speaker co-located)
    // Glasses mode: videoChat for mild AEC (mic is on glasses, speaker is on phone)
    let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat
    try session.setCategory(
      .playAndRecord,
      mode: mode,
      options: [.defaultToSpeaker, .allowBluetooth]
    )
    try session.setPreferredSampleRate(GeminiConfig.inputAudioSampleRate)
    try session.setPreferredIOBufferDuration(0.064)
    try session.setActive(true)
    NSLog("[Audio] Session mode: %@", useIPhoneMode ? "voiceChat (iPhone)" : "videoChat (glasses)")
  }

  func startCapture() throws {
    guard !isCapturing else { return }

    audioEngine.attach(playerNode)
    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

    sendQueue.async { self.accumulatedData = Data() }
    try installTapAndStart()
    playerNode.play()
    isCapturing = true

    // Restart the tap automatically if another component (e.g. RTMP) reconfigures the
    // shared AVAudioSession — that fires AVAudioEngineConfigurationChange and stops our engine.
    engineConfigObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: audioEngine,
      queue: .main
    ) { [weak self] _ in
      guard let self, self.isCapturing else { return }
      NSLog("[Audio] Engine configuration changed — restarting tap")
      try? AVAudioSession.sharedInstance().setActive(true)
      try? self.installTapAndStart()
      if !self.playerNode.isPlaying { self.playerNode.play() }
    }

    // Resume after phone calls, Siri, or other system interruptions end.
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      guard let self, self.isCapturing else { return }
      guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue),
            type == .ended else { return }
      NSLog("[Audio] Session interruption ended — restarting tap")
      try? AVAudioSession.sharedInstance().setActive(true)
      try? self.installTapAndStart()
      if !self.playerNode.isPlaying { self.playerNode.play() }
    }
  }

  /// Installs the microphone tap and starts the engine. Safe to call again after a
  /// configuration change (removes any existing tap first).
  private func installTapAndStart() throws {
    let inputNode = audioEngine.inputNode
    let inputNativeFormat = inputNode.outputFormat(forBus: 0)

    NSLog("[Audio] Native input format: %@ sampleRate=%.0f channels=%d",
          inputNativeFormat.commonFormat == .pcmFormatFloat32 ? "Float32" :
          inputNativeFormat.commonFormat == .pcmFormatInt16 ? "Int16" : "Other",
          inputNativeFormat.sampleRate, inputNativeFormat.channelCount)

    // Always tap in native format (Float32) and convert to Int16 PCM manually.
    // AVAudioEngine taps don't reliably convert between sample formats inline.
    let needsResample = inputNativeFormat.sampleRate != GeminiConfig.inputAudioSampleRate
        || inputNativeFormat.channelCount != GeminiConfig.audioChannels

    NSLog("[Audio] Needs resample: %@", needsResample ? "YES" : "NO")

    var converter: AVAudioConverter?
    if needsResample {
      let resampleFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: GeminiConfig.inputAudioSampleRate,
        channels: GeminiConfig.audioChannels,
        interleaved: false
      )!
      converter = AVAudioConverter(from: inputNativeFormat, to: resampleFormat)
    }

    var tapCount = 0
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNativeFormat) { [weak self] buffer, _ in
      guard let self else { return }

      tapCount += 1
      let pcmData: Data

      if let converter {
        let resampleFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: GeminiConfig.inputAudioSampleRate,
          channels: GeminiConfig.audioChannels,
          interleaved: false
        )!
        guard let resampled = self.convertBuffer(buffer, using: converter, targetFormat: resampleFormat) else {
          if tapCount <= 3 { NSLog("[Audio] Resample failed for tap #%d", tapCount) }
          return
        }
        pcmData = self.float32BufferToInt16Data(resampled)
      } else {
        pcmData = self.float32BufferToInt16Data(buffer)
      }

      // Accumulate into ~100ms chunks before sending to Gemini
      self.sendQueue.async {
        self.accumulatedData.append(pcmData)
        if self.accumulatedData.count >= self.minSendBytes {
          let chunk = self.accumulatedData
          self.accumulatedData = Data()
          self.onAudioCaptured?(chunk)
        }
      }
    }

    audioEngine.prepare()
    try audioEngine.start()
  }

  func playAudio(data: Data) {
    guard isCapturing, !data.isEmpty else { return }

    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!

    let frameCount = UInt32(data.count) / (GeminiConfig.audioBitsPerSample / 8 * GeminiConfig.audioChannels)
    guard frameCount > 0 else { return }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frameCount) else { return }
    buffer.frameLength = frameCount

    guard let floatData = buffer.floatChannelData else { return }
    data.withUnsafeBytes { rawBuffer in
      guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0..<Int(frameCount) {
        floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
      }
    }

    playerNode.scheduleBuffer(buffer)
    if !playerNode.isPlaying {
      playerNode.play()
    }
  }

  func stopPlayback() {
    playerNode.stop()
    playerNode.play()
  }

  func stopCapture() {
    guard isCapturing else { return }
    if let observer = engineConfigObserver {
      NotificationCenter.default.removeObserver(observer)
      engineConfigObserver = nil
    }
    if let observer = interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      interruptionObserver = nil
    }
    audioEngine.inputNode.removeTap(onBus: 0)
    playerNode.stop()
    audioEngine.stop()
    audioEngine.detach(playerNode)
    isCapturing = false
    // Flush any remaining accumulated audio
    sendQueue.async {
      if !self.accumulatedData.isEmpty {
        let chunk = self.accumulatedData
        self.accumulatedData = Data()
        self.onAudioCaptured?(chunk)
      }
    }
  }

  // MARK: - Private helpers

  private func float32BufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0, let floatData = buffer.floatChannelData else { return Data() }
    var int16Array = [Int16](repeating: 0, count: frameCount)
    for i in 0..<frameCount {
      let sample = max(-1.0, min(1.0, floatData[0][i]))
      int16Array[i] = Int16(sample * Float(Int16.max))
    }
    return int16Array.withUnsafeBufferPointer { ptr in
      Data(buffer: ptr)
    }
  }

  private func convertBuffer(
    _ inputBuffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    targetFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let outputFrameCount = UInt32(Double(inputBuffer.frameLength) * ratio)
    guard outputFrameCount > 0 else { return nil }

    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
      return nil
    }

    var error: NSError?
    var consumed = false
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return inputBuffer
    }

    if error != nil {
      return nil
    }

    return outputBuffer
  }
}
