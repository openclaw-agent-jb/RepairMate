/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

@testable import RepairMate

final class KeychainServiceTests: XCTestCase {
    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Clean slate before each test
        try? KeychainService.deleteAll()
    }

    override func tearDown() async throws {
        // Clean up after each test
        try? KeychainService.deleteAll()
        try await super.tearDown()
    }

    // MARK: - Store and Retrieve

    func testStoreAndRetrieve() throws {
        try KeychainService.store(.geminiAPIKey, value: "test-api-key-123")

        let retrieved = KeychainService.retrieve(.geminiAPIKey)
        XCTAssertEqual(retrieved, "test-api-key-123", "Should retrieve the same value that was stored")
    }

    func testStoreOverwrites() throws {
        // Store initial value
        try KeychainService.store(.geminiAPIKey, value: "initial-value")
        XCTAssertEqual(KeychainService.retrieve(.geminiAPIKey), "initial-value")

        // Overwrite with new value
        try KeychainService.store(.geminiAPIKey, value: "new-value")
        XCTAssertEqual(KeychainService.retrieve(.geminiAPIKey), "new-value", "Should overwrite existing value")
    }

    func testRetrieveNonexistentKey() {
        // Ensure key doesn't exist
        try? KeychainService.delete(.geminiAPIKey)

        let retrieved = KeychainService.retrieve(.geminiAPIKey)
        XCTAssertNil(retrieved, "Retrieving nonexistent key should return nil")
    }

    func testDeleteKey() throws {
        // Store a value
        try KeychainService.store(.geminiAPIKey, value: "value-to-delete")
        XCTAssertNotNil(KeychainService.retrieve(.geminiAPIKey))

        // Delete it
        try KeychainService.delete(.geminiAPIKey)

        // Verify it's gone
        let retrieved = KeychainService.retrieve(.geminiAPIKey)
        XCTAssertNil(retrieved, "Deleted key should return nil")
    }

    func testDeleteNonexistentKey() {
        // Ensure key doesn't exist
        try? KeychainService.delete(.geminiAPIKey)

        // Deleting a nonexistent key should not throw
        XCTAssertNoThrow(try KeychainService.delete(.geminiAPIKey), "Deleting nonexistent key should not throw")
    }

    // MARK: - Error Handling

    func testStoreEmptyValueThrows() {
        XCTAssertThrowsError(try KeychainService.store(.geminiAPIKey, value: "")) { error in
            XCTAssertTrue(error is KeychainError, "Should throw KeychainError")
            XCTAssertEqual((error as? KeychainError)?.errorDescription, "Cannot store empty value in Keychain")
        }
    }

    // MARK: - Configuration Status

    func testIsConfiguredReturnsFalseInitially() {
        // Clean state
        try? KeychainService.delete(.geminiAPIKey)

        XCTAssertFalse(KeychainService.isConfigured(), "Should return false when no API key is stored")
    }

    func testIsConfiguredReturnsTrueAfterStoringAPIKey() throws {
        try KeychainService.store(.geminiAPIKey, value: "valid-api-key-12345")

        XCTAssertTrue(KeychainService.isConfigured(), "Should return true after storing valid API key")
    }

    func testIsConfiguredIgnoresPlaceholder() throws {
        // Store the placeholder value
        try KeychainService.store(.geminiAPIKey, value: "YOUR_GEMINI_API_KEY")

        XCTAssertFalse(KeychainService.isConfigured(), "Should return false for placeholder value")
    }

    func testIsOpenClawConfiguredReturnsFalseInitially() {
        // Clean state
        try? KeychainService.delete(.openClawHost)
        try? KeychainService.delete(.openClawGatewayToken)

        XCTAssertFalse(KeychainService.isOpenClawConfigured(), "Should return false when OpenClaw not configured")
    }

    func testIsOpenClawConfiguredReturnsTrueWhenConfigured() throws {
        try KeychainService.store(.openClawHost, value: "my-server.ts.net")
        try KeychainService.store(.openClawGatewayToken, value: "valid-gateway-token")

        XCTAssertTrue(KeychainService.isOpenClawConfigured(), "Should return true when properly configured")
    }

    func testIsOpenClawConfiguredIgnoresPlaceholderHost() throws {
        try KeychainService.store(.openClawHost, value: "YOUR_MAC_HOSTNAME.local")
        try KeychainService.store(.openClawGatewayToken, value: "valid-gateway-token")

        XCTAssertFalse(KeychainService.isOpenClawConfigured(), "Should return false for placeholder host")
    }

    func testIsOpenClawConfiguredIgnoresPlaceholderToken() throws {
        try KeychainService.store(.openClawHost, value: "my-server.ts.net")
        try KeychainService.store(.openClawGatewayToken, value: "YOUR_OPENCLAW_GATEWAY_TOKEN")

        XCTAssertFalse(KeychainService.isOpenClawConfigured(), "Should return false for placeholder gateway token")
    }

    // MARK: - Delete All

    func testDeleteAll() throws {
        // Store multiple values
        try KeychainService.store(.geminiAPIKey, value: "gemini-key")
        try KeychainService.store(.openClawHost, value: "host-value")
        try KeychainService.store(.openClawPort, value: "443")

        // Verify they exist
        XCTAssertNotNil(KeychainService.retrieve(.geminiAPIKey))
        XCTAssertNotNil(KeychainService.retrieve(.openClawHost))
        XCTAssertNotNil(KeychainService.retrieve(.openClawPort))

        // Delete all
        try KeychainService.deleteAll()

        // Verify all are gone
        XCTAssertNil(KeychainService.retrieve(.geminiAPIKey))
        XCTAssertNil(KeychainService.retrieve(.openClawHost))
        XCTAssertNil(KeychainService.retrieve(.openClawPort))
    }

    func testDeleteAllWhenEmpty() {
        // Ensure empty state
        try? KeychainService.deleteAll()

        // Should not throw when called on empty keychain
        XCTAssertNoThrow(try KeychainService.deleteAll(), "deleteAll should not throw on empty keychain")
    }

    // MARK: - All Keys Round Trip

    func testAllKeysRoundTrip() throws {
        // Test all Key enum cases
        try KeychainService.store(.geminiAPIKey, value: "test-gemini-key")
        try KeychainService.store(.openClawHost, value: "test-host.example.com")
        try KeychainService.store(.openClawPort, value: "443")
        try KeychainService.store(.openClawGatewayToken, value: "test-gateway-token")

        // Verify all can be retrieved
        XCTAssertEqual(KeychainService.retrieve(.geminiAPIKey), "test-gemini-key")
        XCTAssertEqual(KeychainService.retrieve(.openClawHost), "test-host.example.com")
        XCTAssertEqual(KeychainService.retrieve(.openClawPort), "443")
        XCTAssertEqual(KeychainService.retrieve(.openClawGatewayToken), "test-gateway-token")
    }

    func testKeyDisplayName() {
        XCTAssertEqual(KeychainService.Key.geminiAPIKey.displayName, "Gemini API Key")
        XCTAssertEqual(KeychainService.Key.openClawHost.displayName, "OpenClaw Host")
        XCTAssertEqual(KeychainService.Key.openClawPort.displayName, "OpenClaw Port")
        XCTAssertEqual(KeychainService.Key.openClawGatewayToken.displayName, "OpenClaw Gateway Token")
    }

    func testKeyPlaceholder() {
        XCTAssertEqual(KeychainService.Key.geminiAPIKey.placeholder, "AIzaSy...")
        XCTAssertEqual(KeychainService.Key.openClawHost.placeholder, "your-machine.ts.net")
        XCTAssertEqual(KeychainService.Key.openClawPort.placeholder, "443")
        XCTAssertEqual(KeychainService.Key.openClawGatewayToken.placeholder, "your-gateway-token")
    }

    func testKeyCaseIterable() {
        let allKeys = KeychainService.Key.allCases
        XCTAssertEqual(allKeys.count, 4, "Should have exactly 4 key types")
        XCTAssertTrue(allKeys.contains(.geminiAPIKey))
        XCTAssertTrue(allKeys.contains(.openClawHost))
        XCTAssertTrue(allKeys.contains(.openClawPort))
        XCTAssertTrue(allKeys.contains(.openClawGatewayToken))
    }

    // MARK: - KeychainError

    func testKeychainErrorDescriptions() {
        let emptyValueError = KeychainError.emptyValue
        XCTAssertEqual(emptyValueError.errorDescription, "Cannot store empty value in Keychain")

        let unhandledError = KeychainError.unhandledError(status: -25300)
        XCTAssertEqual(unhandledError.errorDescription, "Keychain error with status: -25300")
    }
}
