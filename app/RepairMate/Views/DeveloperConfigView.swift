/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// DeveloperConfigView.swift
//
// Configuration UI for setting up API keys and secrets in the Keychain.
// This is shown on first launch or when secrets are missing.
// Hidden behind "Developer Mode" toggle to prevent user confusion.
//

import SwiftUI

struct DeveloperConfigView: View {
  @Environment(\.dismiss) private var dismiss
  var onDismiss: (() -> Void)? = nil

  // Developer Mode toggle
  @AppStorage("com.repairmate.developerMode") private var developerMode = true

  // Auto-save transcripts toggle
  @AppStorage("com.repairmate.autoSaveTranscripts") private var autoSaveTranscripts = false

  // Input fields
  @State private var geminiAPIKey = ""
  @State private var openClawHost = ""
  @State private var openClawGatewayToken = ""

  // State
  @State private var showingError = false
  @State private var errorMessage = ""
  @State private var showingSuccess = false

  var body: some View {
    NavigationView {
      Form {
        // Developer Mode Toggle
        Section {
          Toggle("Developer Mode", isOn: $developerMode)
            .onChange(of: developerMode) { _, _ in
              loadExistingConfig()
            }
        } footer: {
          Text("Enable to configure API keys and Advanced settings.")
        }

        // Auto-Save Transcripts
        Section {
          Toggle("Auto-Save Transcripts", isOn: $autoSaveTranscripts)
        } footer: {
          Text("Automatically save conversation transcripts when a session ends.")
        }

        // Configuration Status (always shown)
        Section {
          statusRow(title: "Gemini API Key", configured: KeychainService.isConfigured())
          statusRow(title: "OpenClaw", configured: KeychainService.isOpenClawConfigured())          
        } header: {
          Text("Configuration Status")
        }

        if developerMode {
          // Gemini Configuration
          Section {
            HStack {
              SecureField("Gemini API Key", text: $geminiAPIKey)
                .textContentType(.password)
              Button {
                if let s = UIPasteboard.general.string { geminiAPIKey = s }
              } label: {
                Image(systemName: "doc.on.clipboard")
              }
            }
          } header: {
            Text("Gemini Configuration")
          } footer: {
            Text("Your Google Gemini Live API key. Required for AI assistant functionality.")
          }

          // OpenClaw Configuration
          Section {
            TextField("Host (IP or hostname)", text: $openClawHost)
              .keyboardType(.default)
              .textInputAutocapitalization(.never)

            VStack(alignment: .leading, spacing: 4) {
              Text("Gateway Token")
                .font(.caption)
                .foregroundColor(.secondary)
              HStack {
                SecureField("Paste gateway token", text: $openClawGatewayToken)
                  .textContentType(.password)
                Button {
                  if let s = UIPasteboard.general.string { openClawGatewayToken = s }
                } label: {
                  Image(systemName: "doc.on.clipboard")
                }
              }
            }
          } header: {
            Text("OpenClaw Configuration")
          } footer: {
            Text("OpenClaw gateway settings for agentic task delegation. Optional.")
          }

          // Actions
          Section {
            Button(action: saveConfig) {
              Label("Save Configuration", systemImage: "checkmark.circle.fill")
            }
            .disabled(!isValidConfig)

            Button(role: .destructive, action: clearConfig) {
              Label("Clear All Secrets", systemImage: "trash")
            }
          }
        }
      }
      .navigationTitle("Developer Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if KeychainService.isConfigured() {
            Button("Close") {
              dismiss()
              onDismiss?()
            }
          }
        }
      }
      .alert("Error", isPresented: $showingError) {
        Button("OK") { }
      } message: {
        Text(errorMessage)
      }
      .alert("Success", isPresented: $showingSuccess) {
        Button("OK") {
          dismiss()
          onDismiss?()
        }
      } message: {
        Text("Configuration saved successfully")
      }
      .onAppear {
        loadExistingConfig()
      }
    }
  }

  // MARK: - Status Row

  private func statusRow(title: String, configured: Bool) -> some View {
    HStack {
      Text(title)
      Spacer()
      if configured {
        Label("Configured", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundColor(.green)
      } else {
        Label("Missing", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundColor(.orange)
      }
    }
  }

  // MARK: - Validation

  private var isValidConfig: Bool {
    // At least Gemini API key is required
    !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  // MARK: - Load Existing Config

  private func loadExistingConfig() {
    geminiAPIKey = KeychainService.retrieve(.geminiAPIKey) ?? ""
    openClawHost = KeychainService.retrieve(.openClawHost) ?? ""
    openClawGatewayToken = KeychainService.retrieve(.openClawGatewayToken) ?? ""
  }

  // MARK: - Save Config

  private func saveConfig() {
    do {
      let trimmedAPIKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedHost = openClawHost.trimmingCharacters(in: .whitespacesAndNewlines)

      try KeychainService.store(.geminiAPIKey, value: trimmedAPIKey)

      if !trimmedHost.isEmpty {
        try KeychainService.store(.openClawHost, value: trimmedHost)
      }

      let trimmedGatewayToken = openClawGatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedGatewayToken.isEmpty {
        try KeychainService.store(.openClawGatewayToken, value: trimmedGatewayToken)
      }

      showingSuccess = true
    } catch {
      errorMessage = "Failed to save configuration: \(error.localizedDescription)"
      showingError = true
    }
  }

  // MARK: - Clear Config

  private func clearConfig() {
    do {
      try KeychainService.deleteAll()

      // Clear text fields
      geminiAPIKey = ""
      openClawHost = ""
      openClawGatewayToken = ""
    } catch {
      errorMessage = "Failed to clear configuration: \(error.localizedDescription)"
      showingError = true
    }
  }
}
