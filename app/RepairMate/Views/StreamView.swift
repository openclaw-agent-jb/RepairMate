/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and Gemini Live AI integration.
//

import MWDATCore
import SwiftUI

// Teal accent sampled from the BackgroundImage robot glow
private let brandTeal = Color(red: 0.0, green: 0.76, blue: 0.88)

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @State private var showDeveloperConfig = false
  @State private var showTranscriptLog = false
  @AppStorage("com.repairmate.autoSaveTranscripts") private var autoSaveTranscripts = false
  var selectedDomain: RepairDomain?
  var procedureName: String?

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop
      if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundColor(.white)
      }

      // Gemini AI overlay (transcript, speaking indicator)
      if geminiVM.isGeminiActive {
        VStack {
          Spacer()
          VStack(spacing: 8) {
            if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
              TranscriptView(userText: geminiVM.userTranscript, aiText: geminiVM.aiTranscript)
            }
            if geminiVM.toolCallStatus != .idle {
              ToolCallStatusView(status: geminiVM.toolCallStatus)
            }
            if geminiVM.isModelSpeaking {
              SpeakingIndicator()
            }
          }
          .padding(.bottom, 160)
        }
        .padding(.all, 24)
      }

      // Safety alert banner — appears at top when WARNING or STOP is detected
      if let alert = geminiVM.safetyAlert {
        VStack {
          HStack(spacing: 10) {
            Image(systemName: alert.requiresImmediateStop ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
              .font(.title2)
              .foregroundColor(alert.requiresImmediateStop ? .red : .yellow)
            VStack(alignment: .leading, spacing: 2) {
              Text(alert.requiresImmediateStop ? "STOP" : "WARNING")
                .font(.headline).bold()
              Text(alert.reason)
                .font(.caption)
              Text(alert.action)
                .font(.caption).italic()
            }
            Spacer()
          }
          .padding(12)
          .background(alert.requiresImmediateStop ? Color.red.opacity(0.9) : Color.orange.opacity(0.9))
          .foregroundColor(.white)
          .cornerRadius(12)
          .padding(.horizontal, 16)
          .padding(.top, 60)
          .onTapGesture {
            withAnimation(.easeOut(duration: 0.3)) {
              geminiVM.safetyAlert = nil
            }
          }
          Spacer()
        }
      }


      // Floating Gemini AI button (centered vertically, right edge)
      HStack {
        Spacer()
        VStack(spacing: 12) {
          Button(action: {
            if !GeminiConfig.isConfigured {
              showDeveloperConfig = true
            } else {
              Task {
                if geminiVM.isGeminiActive {
                  geminiVM.stopSession()
                } else {
                  await geminiVM.startSession()
                }
              }
            }
          }) {
            ZStack {
              Circle()
                .fill(brandTeal.opacity(0.25))
                .frame(width: 36, height: 36)
                .overlay(
                  Circle()
                    .stroke(geminiVM.isGeminiActive ? Color.blue : Color.clear, lineWidth: 2)
                )

              Image("gemini")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            }
            .shadow(radius: 4)
          }
        }
        .padding(.trailing)
      }

      // Bottom controls layer
      VStack(spacing: 16) {
        Spacer()

        HStack(spacing: 8) {
          CircleButton(icon: "text.bubble", text: nil) {
            withAnimation(.easeInOut(duration: 0.25)) {
              showTranscriptLog.toggle()
            }
          }

          // Photo capture button
          CircleButton(icon: "camera", text: nil) {
            viewModel.capturePhoto()
          }

          // Stop streaming button
          CircleButton(icon: "rectangle.portrait.and.arrow.right", text: nil) {
            Task {
              await viewModel.stopSession()
            }
          }
        }

        // Status pills row
        HStack(spacing: 8) {
          DomainStatusBar(domain: selectedDomain)
          if geminiVM.isGeminiActive {
            GeminiStatusBar(geminiVM: geminiVM)
          }
        }
      }
      .padding(.bottom, 40)
      .padding(.horizontal, 24)

      // Transcript log overlay
      if showTranscriptLog {
        TranscriptLogView(
          geminiVM: geminiVM,
          domain: selectedDomain,
          procedureName: procedureName,
          autoSaveEnabled: autoSaveTranscripts,
          onDismiss: {
            withAnimation(.easeInOut(duration: 0.25)) {
              showTranscriptLog = false
            }
          }
        )
        .transition(.opacity)
      }
    }
    .onAppear {
      Task {
        await geminiVM.startSession()
      }
    }
    .onDisappear {
      Task {
        if geminiVM.isGeminiActive {
          geminiVM.stopSession()
        }
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    .toast(message: $geminiVM.errorMessage, icon: "exclamationmark.triangle.fill", duration: 5.0)
    .sheet(isPresented: $showDeveloperConfig, onDismiss: {
      if GeminiConfig.isConfigured && !geminiVM.isGeminiActive {
        Task {
          await geminiVM.startSession()
        }
      }
    }) {
      DeveloperConfigView()
    }
  }

}
