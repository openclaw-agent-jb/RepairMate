/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import Combine
import MWDATCamera
import MWDATCore
import SwiftUI

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

enum StreamingMode {
  case glasses
  case iPhone
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false
  @Published var connectedDeviceName: String? = nil

  // Gemini Live integration
  var geminiSessionVM: GeminiSessionViewModel?

  // iPhone camera mode
  @Published var streamingMode: StreamingMode = .glasses
  private var iPhoneCameraManager: IPhoneCameraManager?

  var isStreaming: Bool {
    streamingStatus != .stopped
  }

  // Timer properties
  @Published var remainingTime: TimeInterval = 0

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  private var timerTask: Task<Void, Never>?
  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession?
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface?
  private let deviceSelector: AutoDeviceSelector?
  private var deviceMonitorTask: Task<Void, Never>?

  private var permissionStatusProvider: (Permission) async throws -> PermissionStatus
  private var permissionRequestProvider: (Permission) async throws -> PermissionStatus
  private var streamStartAction: () async -> Void
  private var streamStopAction: () async -> Void
  private var streamCapturePhotoAction: () -> Void
  private var iPhoneStopAction: (() -> Void)?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    let selector = AutoDeviceSelector(wearables: wearables)
    self.deviceSelector = selector
    // Configure for streaming: high resolution at 30fps
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.high,
      frameRate: 30)
    let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
    streamSession = session

    permissionStatusProvider = { permission in
      try await wearables.checkPermissionStatus(permission)
    }
    permissionRequestProvider = { permission in
      try await wearables.requestPermission(permission)
    }
    streamStartAction = { [session] in
      await session.start()
    }
    streamStopAction = { [session] in
      await session.stop()
    }
    streamCapturePhotoAction = { [session] in
      session.capturePhoto(format: .jpeg)
    }
    iPhoneStopAction = nil

    // Monitor device availability and capture device name
    deviceMonitorTask = Task { @MainActor in
      for await deviceId in selector.activeDeviceStream() {
        self.hasActiveDevice = deviceId != nil
        if let id = deviceId, let device = wearables.deviceForIdentifier(id) {
          self.connectedDeviceName = Self.displayName(for: device)
        } else {
          self.connectedDeviceName = nil
        }
      }
    }

    // Subscribe to session state changes using the DAT SDK listener pattern
    stateListenerToken = session.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    videoFrameListenerToken = session.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }

        if let image = videoFrame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            self.hasReceivedFirstFrame = true
          }
        }

        // Forward video frames to Gemini Live (throttled internally to ~1fps)
        if let frame = self.currentVideoFrame {
          self.geminiSessionVM?.sendVideoFrameIfThrottled(image: frame)
        }
      }
    }

    // Subscribe to streaming errors
    errorListenerToken = session.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    updateStatusFromState(session.state)

    // Subscribe to photo capture events
    photoDataListenerToken = session.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage
          self.showPhotoPreview = true
        }
      }
    }
  }

  init(
    permissionStatusProvider: @escaping (Permission) async throws -> PermissionStatus,
    permissionRequestProvider: @escaping (Permission) async throws -> PermissionStatus,
    streamStartAction: @escaping () async -> Void = {},
    streamStopAction: @escaping () async -> Void = {},
    streamCapturePhotoAction: @escaping () -> Void = {},
    iPhoneStopAction: (() -> Void)? = nil
  ) {
    self.wearables = nil
    self.deviceSelector = nil
    self.streamSession = nil
    self.permissionStatusProvider = permissionStatusProvider
    self.permissionRequestProvider = permissionRequestProvider
    self.streamStartAction = streamStartAction
    self.streamStopAction = streamStopAction
    self.streamCapturePhotoAction = streamCapturePhotoAction
    self.iPhoneStopAction = iPhoneStopAction
  }

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      let status = try await permissionStatusProvider(permission)
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await permissionRequestProvider(permission)
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      showError("Permission error: \(error.localizedDescription)")
    }
  }

  func startSession() async {
    remainingTime = 0
    stopTimer()
    await streamStartAction()
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    stopTimer()
    if streamingMode == .iPhone {
      if let iPhoneStopAction {
        iPhoneStopAction()
      } else {
        stopIPhoneSession()
      }
      return
    }
    await streamStopAction()
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func capturePhoto() {
    if streamingMode == .iPhone {
      if let frame = currentVideoFrame {
        capturedPhoto = frame
        showPhotoPreview = true
      }
    } else {
      streamCapturePhotoAction()
    }
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  // MARK: - iPhone Camera Mode

  func handleStartIPhone() async {
    let granted = await IPhoneCameraManager.requestPermission()
    if granted {
      startIPhoneSession()
    } else {
      showError("Camera permission denied. Please grant access in Settings.")
    }
  }

  private func startIPhoneSession() {
    remainingTime = 0
    stopTimer()

    streamingMode = .iPhone
    let camera = IPhoneCameraManager()
    camera.onFrameCaptured = { [weak self] image in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.currentVideoFrame = image
        if !self.hasReceivedFirstFrame {
          self.hasReceivedFirstFrame = true
        }
        // Forward to Gemini (throttled ~1fps)
        self.geminiSessionVM?.sendVideoFrameIfThrottled(image: image)
      }
    }
    camera.start()
    iPhoneCameraManager = camera
    streamingStatus = .streaming
  }

  private func stopIPhoneSession() {
    iPhoneCameraManager?.stop()
    iPhoneCameraManager = nil
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    streamingStatus = .stopped
    streamingMode = .glasses
  }

  private func startTimer() {
    stopTimer()
    timerTask = Task { @MainActor [weak self] in
      while let self, remainingTime > 0 {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        guard !Task.isCancelled else { break }
        remainingTime -= 1
      }
      if let self, !Task.isCancelled {
        await stopSession()
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  private func updateStatusFromState(_ state: StreamSessionState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private static func displayName(for device: Device) -> String {
    switch device.deviceType() {
    case .rayBanMeta:
      return "Ray-Ban Meta"
    case .oakleyMetaHSTN:
      return "Oakley Meta HSTN"
    case .oakleyMetaVanguard:
      return "Oakley Meta Vanguard"
    case .metaRayBanDisplay:
      return "Meta Ray-Ban Display"
    case .unknown:
      return device.nameOrId()
    @unknown default:
      return device.nameOrId()
    }
  }

  private func formatStreamingError(_ error: StreamSessionError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}
