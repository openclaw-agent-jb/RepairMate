/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import RepairMate

final class GeminiConfigTests: XCTestCase {

  // MARK: - Configuration Constants Tests

  func testWebsocketBaseURL() {
    XCTAssertEqual(
      GeminiConfig.websocketBaseURL,
      "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    )
  }

  func testModel() {
    XCTAssertEqual(
      GeminiConfig.model,
      "models/gemini-2.5-flash-native-audio-preview-12-2025"
    )
  }

  func testAudioConfiguration() {
    XCTAssertEqual(GeminiConfig.inputAudioSampleRate, 16000)
    XCTAssertEqual(GeminiConfig.outputAudioSampleRate, 24000)
    XCTAssertEqual(GeminiConfig.audioChannels, 1)
    XCTAssertEqual(GeminiConfig.audioBitsPerSample, 16)
  }

  func testVideoConfiguration() {
    XCTAssertEqual(GeminiConfig.videoFrameInterval, 1.0)
    XCTAssertEqual(GeminiConfig.videoJPEGQuality, 0.5)
  }

  // MARK: - System Instruction Tests

  func testSystemInstructionNotEmpty() {
    XCTAssertFalse(GeminiConfig.systemInstruction.isEmpty)
    XCTAssertTrue(GeminiConfig.systemInstruction.contains("AI assistant"))
    XCTAssertTrue(GeminiConfig.systemInstruction.contains("execute"))
  }

  func testSystemInstructionContainsCriticalInstructions() {
    let instruction = GeminiConfig.systemInstruction
    XCTAssertTrue(instruction.contains("NO memory"))
    XCTAssertTrue(instruction.contains("NO storage"))
    XCTAssertTrue(instruction.contains("Meta Ray-Ban"))
  }

  func testSystemInstructionContainsToolInstructions() {
    let instruction = GeminiConfig.systemInstruction
    XCTAssertTrue(instruction.contains("send a message"))
    XCTAssertTrue(instruction.contains("search"))
    XCTAssertTrue(instruction.contains("acknowledgment"))
  }

  // MARK: - API Key Tests (Mock Keychain)

  func testApiKeyReturnsEmptyWhenNotConfigured() {
    // In a test environment with clean keychain, should return empty
    let apiKey = GeminiConfig.apiKey
    XCTAssertEqual(apiKey, "")
  }

  func testOpenClawHostReturnsHttpsPrefix() throws {
    // Store a test host
    try KeychainService.store(.openClawHost, value: "test-server.ts.net")
    
    let host = GeminiConfig.openClawHost
    XCTAssertTrue(host.hasPrefix("https://"))
    XCTAssertTrue(host.contains("test-server.ts.net"))
    
    // Clean up
    try? KeychainService.delete(.openClawHost)
  }

  func testOpenClawPortParsing() throws {
    // Store a test port
    try KeychainService.store(.openClawPort, value: "8080")
    
    let port = GeminiConfig.openClawPort
    XCTAssertEqual(port, 8080)
    
    // Clean up
    try? KeychainService.delete(.openClawPort)
  }

  func testOpenClawPortDefaultsTo443() {
    // Ensure no port is stored
    try? KeychainService.delete(.openClawPort)
    
    let port = GeminiConfig.openClawPort
    XCTAssertEqual(port, 443)
  }

  func testOpenClawGatewayToken() throws {
    // Store a test token
    try KeychainService.store(.openClawGatewayToken, value: "test-gateway-token")
    
    let token = GeminiConfig.openClawGatewayToken
    XCTAssertEqual(token, "test-gateway-token")
    
    // Clean up
    try? KeychainService.delete(.openClawGatewayToken)
  }

  // MARK: - Configuration Status Tests

  func testIsConfiguredReturnsFalseWhenNoApiKey() {
    // Ensure clean state
    try? KeychainService.delete(.geminiAPIKey)
    
    XCTAssertFalse(GeminiConfig.isConfigured)
  }

  func testIsConfiguredReturnsTrueWithValidApiKey() throws {
    try KeychainService.store(.geminiAPIKey, value: "test-api-key-123")
    
    XCTAssertTrue(GeminiConfig.isConfigured)
    
    // Clean up
    try? KeychainService.delete(.geminiAPIKey)
  }

  func testIsConfiguredIgnoresPlaceholder() throws {
    try KeychainService.store(.geminiAPIKey, value: "YOUR_GEMINI_API_KEY")
    
    XCTAssertFalse(GeminiConfig.isConfigured)
    
    // Clean up
    try? KeychainService.delete(.geminiAPIKey)
  }

  func testIsOpenClawConfiguredReturnsFalseWhenNotConfigured() {
    try? KeychainService.delete(.openClawHost)
    try? KeychainService.delete(.openClawGatewayToken)
    
    XCTAssertFalse(GeminiConfig.isOpenClawConfigured)
  }

  func testIsOpenClawConfiguredReturnsTrueWhenConfigured() throws {
    try KeychainService.store(.openClawHost, value: "test-host.ts.net")
    try KeychainService.store(.openClawGatewayToken, value: "test-token")
    
    XCTAssertTrue(GeminiConfig.isOpenClawConfigured)
    
    // Clean up
    try? KeychainService.delete(.openClawHost)
    try? KeychainService.delete(.openClawGatewayToken)
  }

  func testIsOpenClawConfiguredIgnoresPlaceholderHost() throws {
    try KeychainService.store(.openClawHost, value: "YOUR_MAC_HOSTNAME.local")
    try KeychainService.store(.openClawGatewayToken, value: "test-token")
    
    XCTAssertFalse(GeminiConfig.isOpenClawConfigured)
    
    // Clean up
    try? KeychainService.delete(.openClawHost)
    try? KeychainService.delete(.openClawGatewayToken)
  }

  func testIsOpenClawConfiguredIgnoresPlaceholderToken() throws {
    try KeychainService.store(.openClawHost, value: "test-host.ts.net")
    try KeychainService.store(.openClawGatewayToken, value: "YOUR_OPENCLAW_GATEWAY_TOKEN")
    
    XCTAssertFalse(GeminiConfig.isOpenClawConfigured)
    
    // Clean up
    try? KeychainService.delete(.openClawHost)
    try? KeychainService.delete(.openClawGatewayToken)
  }

  // MARK: - WebSocket URL Tests

  func testWebsocketURLReturnsNilWhenNotConfigured() {
    try? KeychainService.delete(.geminiAPIKey)
    
    let url = GeminiConfig.websocketURL()
    XCTAssertNil(url)
  }

  func testWebsocketURLReturnsValidURLWhenConfigured() throws {
    try KeychainService.store(.geminiAPIKey, value: "test-api-key-12345")
    
    let url = GeminiConfig.websocketURL()
    XCTAssertNotNil(url)
    XCTAssertEqual(url?.scheme, "wss")
    XCTAssertTrue(url?.absoluteString.contains("googleapis.com") ?? false)
    XCTAssertTrue(url?.absoluteString.contains("test-api-key-12345") ?? false)
    
    // Clean up
    try? KeychainService.delete(.geminiAPIKey)
  }

  func testWebsocketURLContainsCorrectPath() throws {
    try KeychainService.store(.geminiAPIKey, value: "my-api-key")
    
    let url = GeminiConfig.websocketURL()
    XCTAssertTrue(url?.absoluteString.contains("BidiGenerateContent") ?? false)
    
    // Clean up
    try? KeychainService.delete(.geminiAPIKey)
  }
}
