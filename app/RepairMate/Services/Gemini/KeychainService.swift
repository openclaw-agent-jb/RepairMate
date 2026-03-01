/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// KeychainService.swift
//
// Secure storage for sensitive configuration values using iOS Keychain.
// Secrets are stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
// for maximum security — no iCloud backup and locked when device is locked.
//

import Foundation
import Security

enum KeychainService {
  // Service name for Keychain namespace isolation
  private static let service = "com.repairmate.secrets"

  enum Key: String, CaseIterable {
    case geminiAPIKey = "com.repairmate.gemini.apikey"
    case openClawHost = "com.repairmate.openclaw.host"
    case openClawPort = "com.repairmate.openclaw.port"
    case openClawGatewayToken = "com.repairmate.openclaw.gateway"

    var displayName: String {
      switch self {
      case .geminiAPIKey: return "Gemini API Key"
      case .openClawHost: return "OpenClaw Host"
      case .openClawPort: return "OpenClaw Port"
      case .openClawGatewayToken: return "OpenClaw Gateway Token"
      }
    }

    var placeholder: String {
      switch self {
      case .geminiAPIKey: return "AIzaSy..."
      case .openClawHost: return "your-machine.ts.net"
      case .openClawPort: return "443"
      case .openClawGatewayToken: return "your-gateway-token"
      }
    }
  }

  // MARK: - Store

  static func store(_ key: Key, value: String) throws {
    guard !value.isEmpty else {
      throw KeychainError.emptyValue
    }

    let data = Data(value.utf8)

    // Delete existing item first — use only identifying attributes,
    // NOT kSecValueData, otherwise the delete fails to match when
    // the stored value differs (i.e. on update).
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]

    let status = SecItemAdd(addQuery as CFDictionary, nil)

    guard status == errSecSuccess else {
      throw KeychainError.unhandledError(status: status)
    }
  }

  // MARK: - Retrieve

  static func retrieve(_ key: Key) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
      return nil
    }

    return value
  }

  // MARK: - Delete

  static func delete(_ key: Key) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unhandledError(status: status)
    }
  }

  // MARK: - Delete All (for testing/debug)

  static func deleteAll() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]

    let status = SecItemDelete(query as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unhandledError(status: status)
    }
  }

  // MARK: - Check Configuration Status

  static func isConfigured() -> Bool {
    // Check if at least Gemini API Key is configured
    guard let apiKey = retrieve(.geminiAPIKey), !apiKey.isEmpty else {
      return false
    }

    // Validate it's not a placeholder
    return apiKey != "YOUR_GEMINI_API_KEY"
  }

  static func isOpenClawConfigured() -> Bool {
    guard let gatewayToken = retrieve(.openClawGatewayToken), !gatewayToken.isEmpty,
          gatewayToken != "YOUR_OPENCLAW_GATEWAY_TOKEN" else {
      return false
    }

    guard let host = retrieve(.openClawHost), !host.isEmpty,
          host != "YOUR_MAC_HOSTNAME.local" else {
      return false
    }

    return true
  }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
  case emptyValue
  case unhandledError(status: OSStatus)

  var errorDescription: String? {
    switch self {
    case .emptyValue:
      return "Cannot store empty value in Keychain"
    case .unhandledError(let status):
      return "Keychain error with status: \(status)"
    }
  }
}
