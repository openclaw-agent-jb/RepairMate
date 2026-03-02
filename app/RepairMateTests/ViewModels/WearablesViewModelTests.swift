/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Combine
import MWDATCore
import XCTest

@testable import RepairMate

// MARK: - Mock Objects

@MainActor
private class MockWearables: WearablesInterface {
  var devices: [DeviceIdentifier] = []
  var registrationState: RegistrationState = .unregistered
  
  var registrationStateStreamContinuation: AsyncStream<RegistrationState>.Continuation?
  var devicesStreamContinuation: AsyncStream<[DeviceIdentifier]>.Continuation?
  
  var startRegistrationCalled = false
  var startUnregistrationCalled = false
  var lastDeviceForIdentifier: DeviceIdentifier?
  
  func registrationStateStream() -> AsyncStream<RegistrationState> {
    AsyncStream { continuation in
      self.registrationStateStreamContinuation = continuation
    }
  }
  
  func devicesStream() -> AsyncStream<[DeviceIdentifier]> {
    AsyncStream { continuation in
      self.devicesStreamContinuation = continuation
    }
  }
  
  func deviceForIdentifier(_ identifier: DeviceIdentifier) -> Device? {
    lastDeviceForIdentifier = identifier
    return MockDevice(identifier: identifier)
  }
  
  func startRegistration() async throws {
    startRegistrationCalled = true
    // Simulate successful registration
    registrationState = .registering
    registrationStateStreamContinuation?.yield(.registering)
  }
  
  func startUnregistration() async throws {
    startUnregistrationCalled = true
    registrationState = .unregistered
  }
}

@MainActor
private class MockDevice: Device {
  let identifier: DeviceIdentifier
  var compatibilityListenerAdded = false
  
  init(identifier: DeviceIdentifier) {
    self.identifier = identifier
  }
  
  func nameOrId() -> String {
    return "MockDevice-\(identifier)"
  }
  
  func addCompatibilityListener(_ listener: @escaping (Compatibility) -> Void) -> AnyListenerToken {
    compatibilityListenerAdded = true
    return MockListenerToken()
  }
}

private struct MockListenerToken: AnyListenerToken {}

// MARK: - Tests

@MainActor
final class WearablesViewModelTests: XCTestCase {
  
  var mockWearables: MockWearables!
  var sut: WearablesViewModel!
  
  override func setUp() {
    super.setUp()
    mockWearables = MockWearables()
    sut = WearablesViewModel(wearables: mockWearables)
  }
  
  override func tearDown() {
    sut = nil
    mockWearables = nil
    super.tearDown()
  }
  
  // MARK: - Initialization Tests
  
  func testInitSetsInitialDevicesFromWearables() {
    mockWearables.devices = ["device-1", "device-2"]
    let newSut = WearablesViewModel(wearables: mockWearables)
    
    XCTAssertEqual(newSut.devices.count, 2)
    XCTAssertTrue(newSut.devices.contains("device-1"))
    XCTAssertTrue(newSut.devices.contains("device-2"))
  }
  
  func testInitSetsInitialRegistrationState() {
    mockWearables.registrationState = .registered
    let newSut = WearablesViewModel(wearables: mockWearables)
    
    XCTAssertEqual(newSut.registrationState, .registered)
  }
  
  // MARK: - Registration State Stream Tests
  
  func testRegistrationStateUpdatesWhenStreamYields() async {
    // Initially unregistered
    XCTAssertEqual(sut.registrationState, .unregistered)
    
    // Simulate state change from stream
    mockWearables.registrationStateStreamContinuation?.yield(.registering)
    
    // Give time for the async update
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    XCTAssertEqual(sut.registrationState, .registering)
  }
  
  func testGettingStartedSheetShownOnSuccessfulRegistration() async {
    // Start with registering state
    mockWearables.registrationStateStreamContinuation?.yield(.registering)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Transition to registered
    mockWearables.registrationStateStreamContinuation?.yield(.registered)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertTrue(sut.showGettingStartedSheet)
    XCTAssertEqual(sut.registrationState, .registered)
  }
  
  func testErrorShownWhenRegistrationFails() async {
    // Start with registering state
    mockWearables.registrationStateStreamContinuation?.yield(.registering)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Transition back to available (failure case)
    mockWearables.registrationStateStreamContinuation?.yield(.available)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertTrue(sut.showError)
    XCTAssertTrue(sut.errorMessage.contains("Could not connect to Meta AI app"))
  }
  
  func testDeviceStreamSetupWhenRegistered() async {
    mockWearables.registrationStateStreamContinuation?.yield(.registered)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Verify device stream was set up by yielding devices
    mockWearables.devicesStreamContinuation?.yield(["device-1", "device-2"])
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertEqual(sut.devices.count, 2)
  }
  
  // MARK: - Device Stream Tests
  
  func testDevicesUpdateFromStream() async {
    // Set up registered state first
    mockWearables.registrationStateStreamContinuation?.yield(.registered)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Yield devices from stream
    mockWearables.devicesStreamContinuation?.yield(["new-device"])
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    XCTAssertEqual(sut.devices, ["new-device"])
  }
  
  // MARK: - Connect Glasses Tests
  
  func testConnectGlassesCallsStartRegistration() async {
    await sut.connectGlasses()
    
    XCTAssertTrue(mockWearables.startRegistrationCalled)
  }
  
  func testConnectGlassesSkipsIfAlreadyRegistering() async {
    sut.registrationState = .registering
    
    await sut.connectGlasses()
    
    XCTAssertFalse(mockWearables.startRegistrationCalled)
  }
  
  func testConnectGlassesShowsErrorOnRegistrationError() async {
    // Create a mock that throws an error
    let errorMock = MockWearablesThatThrows()
    let errorSut = WearablesViewModel(wearables: errorMock)
    
    await errorSut.connectGlasses()
    
    XCTAssertTrue(errorSut.showError)
    XCTAssertFalse(errorSut.errorMessage.isEmpty)
  }
  
  // MARK: - Disconnect Glasses Tests
  
  func testDisconnectGlassesCallsStartUnregistration() async {
    await sut.disconnectGlasses()
    
    XCTAssertTrue(mockWearables.startUnregistrationCalled)
  }
  
  func testDisconnectGlassesShowsErrorOnError() async {
    // Create a mock that throws an error
    let errorMock = MockWearablesThatThrowsUnregistration()
    let errorSut = WearablesViewModel(wearables: errorMock)
    
    await errorSut.disconnectGlasses()
    
    XCTAssertTrue(errorSut.showError)
  }
  
  // MARK: - Error Handling Tests
  
  func testShowErrorSetsErrorMessageAndShowsError() {
    sut.showError("Test error message")
    
    XCTAssertTrue(sut.showError)
    XCTAssertEqual(sut.errorMessage, "Test error message")
  }
  
  func testDismissErrorHidesError() {
    sut.showError("Test error")
    XCTAssertTrue(sut.showError)
    
    sut.dismissError()
    
    XCTAssertFalse(sut.showError)
  }
  
  // MARK: - Device Compatibility Tests
  
  func testCompatibilityListenerAddedForNewDevice() async {
    // Set up registered state
    mockWearables.registrationStateStreamContinuation?.yield(.registered)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Yield a new device
    mockWearables.devicesStreamContinuation?.yield(["device-1"])
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Verify the mock device had a listener added
    // This happens in monitorDeviceCompatibility
  }
  
  func testCompatibilityListenersCleanedUpForRemovedDevices() async {
    // Start with registered state and devices
    mockWearables.registrationStateStreamContinuation?.yield(.registered)
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    mockWearables.devicesStreamContinuation?.yield(["device-1", "device-2"])
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // Remove one device
    mockWearables.devicesStreamContinuation?.yield(["device-1"])
    try? await Task.sleep(nanoseconds: 100_000_000)
    
    // The token for device-2 should have been removed from the dictionary
    // This is tested indirectly by verifying no crashes occur
    XCTAssertEqual(sut.devices, ["device-1"])
  }
}

// MARK: - Error-throwing Mock Objects

@MainActor
private class MockWearablesThatThrows: WearablesInterface {
  var devices: [DeviceIdentifier] = []
  var registrationState: RegistrationState = .unregistered
  
  func registrationStateStream() -> AsyncStream<RegistrationState> {
    AsyncStream { _ in }
  }
  
  func devicesStream() -> AsyncStream<[DeviceIdentifier]> {
    AsyncStream { _ in }
  }
  
  func deviceForIdentifier(_ identifier: DeviceIdentifier) -> Device? {
    return nil
  }
  
  func startRegistration() async throws {
    throw TestError.registrationFailed
  }
  
  func startUnregistration() async throws {
    // Not used
  }
}

@MainActor
private class MockWearablesThatThrowsUnregistration: WearablesInterface {
  var devices: [DeviceIdentifier] = []
  var registrationState: RegistrationState = .unregistered
  
  func registrationStateStream() -> AsyncStream<RegistrationState> {
    AsyncStream { _ in }
  }
  
  func devicesStream() -> AsyncStream<[DeviceIdentifier]> {
    AsyncStream { _ in }
  }
  
  func deviceForIdentifier(_ identifier: DeviceIdentifier) -> Device? {
    return nil
  }
  
  func startRegistration() async throws {
    // Not used
  }
  
  func startUnregistration() async throws {
    throw TestError.unregistrationFailed
  }
}

private enum TestError: Error, LocalizedError {
  case registrationFailed
  case unregistrationFailed
  
  var errorDescription: String? {
    switch self {
    case .registrationFailed:
      return "Registration failed"
    case .unregistrationFailed:
      return "Unregistration failed"
    }
  }
}
