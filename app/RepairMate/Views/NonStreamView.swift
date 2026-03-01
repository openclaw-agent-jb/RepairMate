/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NonStreamView.swift
//
// Default screen to show getting started tips after app connection
// Initiates streaming
//

import MWDATCore
import SwiftUI

private let sheetDismissalDelay: TimeInterval = 0.5
// Teal accent sampled from the BackgroundImage robot glow
private let brandTeal = Color(red: 0.0, green: 0.76, blue: 0.88)

enum PendingStreamAction {
  case iphone
  case glasses
}

struct NonStreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var repairManager: RepairMateSessionManager
  @Binding var selectedDomain: RepairDomain?
  var onDomainSelected: ((RepairDomain) -> Void)?
  var onProcedureComplete: ((RepairDomain, RepairProcedure?) -> Void)?
  @State private var sheetHeight: CGFloat = 300
  @State private var showDeveloperConfig = false
  @State private var showDomainSelector = false
  @State private var showProcedureSelector = false
  @State private var pendingAction: PendingStreamAction? = nil
  @State private var isProcessingAction: Bool = false
  @State private var toastMessage: String? = nil
  @State private var isDomainSelectedProgrammatically: Bool = false
  @State private var isProcedureDismissedProgrammatically: Bool = false
  @State private var contentOpacity: Double = 0
  @State private var imageScale: CGFloat = 0.8
  @State private var showTranscripts = false

  var body: some View {
    ZStack {
      // Background: SplashImage with full coverage
      Image("BackgroundImage")
        .resizable()
        .aspectRatio(contentMode: .fill)
        .edgesIgnoringSafeArea(.all)
        .scaleEffect(1.05) // Slight overscale for parallax feel

      // Dark gradient overlay for readability (bottom-heavy)
      LinearGradient(
        gradient: Gradient(stops: [
          .init(color: .black.opacity(0.3), location: 0.0),
          .init(color: .black.opacity(0.5), location: 0.4),
          .init(color: .black.opacity(0.85), location: 1.0)
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
      .edgesIgnoringSafeArea(.all)

      VStack(spacing: 0) {
        // Header with settings
        HStack {
          Spacer()
          Menu {


            // AI assistant configuration
            Button {
              showDeveloperConfig = true
            } label: {
              Label("Dev Settings", systemImage: "gear")
            }

            // Saved transcripts
            Button {
              showTranscripts = true
            } label: {
              Label("Transcripts", systemImage: "text.bubble")
            }

            Divider()

            Button("Disconnect", role: .destructive) {
              Task { await wearablesVM.disconnectGlasses() }
            }
            .disabled(wearablesVM.registrationState != .registered)
          } label: {
            ZStack {
              Circle()
                .fill(brandTeal.opacity(0.25))
                .frame(width: 44, height: 44)

              Image(systemName: "gearshape")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)

        Spacer()

        // Status indicator with animation
        HStack(spacing: 10) {
          Image(systemName: "hourglass")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.white.opacity(0.8))
            .frame(width: 16, height: 16)
            .symbolEffect(.pulse, options: .repeating, value: viewModel.hasActiveDevice)

          Text(viewModel.hasActiveDevice ? "Device connected" : "Waiting for device...")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
          Capsule()
            .fill(Color.white.opacity(0.1))
        )
        .opacity(viewModel.hasActiveDevice ? contentOpacity : contentOpacity * 0.9)
        .animation(.easeInOut(duration: 0.3), value: viewModel.hasActiveDevice)
        .padding(.bottom, 12)

        // Main content card with glassmorphism - appears directly below status indicator
        VStack(spacing: 20) {
          VStack(spacing: 12) {
            Text(viewModel.hasActiveDevice && viewModel.connectedDeviceName != nil
                 ? viewModel.connectedDeviceName!
                 : "Connect Your Glasses")
              .font(.system(size: viewModel.hasActiveDevice ? 24 : 28, weight: .bold, design: .rounded))
              .foregroundColor(.white)
              .multilineTextAlignment(.center)
              .lineLimit(2)
              .minimumScaleFactor(0.8)
              .animation(.easeInOut(duration: 0.3), value: viewModel.connectedDeviceName)

            Text(viewModel.hasActiveDevice
                 ? "Ready to stream.\nTap 'Start Streaming' to begin."
                 : "Stream live video from your AI Glasses or\n use your iPhone camera to get started.")
              .font(.system(size: 16, weight: .medium))
              .multilineTextAlignment(.center)
              .foregroundColor(.white.opacity(0.85))
              .lineSpacing(4)
              .padding(.horizontal, 8)
              .animation(.easeInOut(duration: 0.3), value: viewModel.hasActiveDevice)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
          RoundedRectangle(cornerRadius: 24)
            .fill(brandTeal.opacity(0.18))
            .overlay(
              RoundedRectangle(cornerRadius: 24)
                .stroke(brandTeal.opacity(0.5), lineWidth: 1)
            )
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .opacity(contentOpacity * 0.7)
        .offset(y: imageScale == 1.0 ? 0 : 20)
        .padding(.bottom, 20)

        // Action buttons
        VStack(spacing: 12) {
          CustomButton(
            title: "Start on iPhone",
            style: .primary,
            isDisabled: isProcessingAction
          ) {
            handleStreamAction(.iphone)
          }
          .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)

          CustomButton(
            title: "Start Streaming",
            style: .primary,
            isDisabled: !viewModel.hasActiveDevice || isProcessingAction
          ) {
            handleStreamAction(.glasses)
          }
          .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
    }
    .sheet(isPresented: $wearablesVM.showGettingStartedSheet) {
      if #available(iOS 16.0, *) {
        GettingStartedSheetView(height: $sheetHeight)
          .presentationDetents([.height(sheetHeight)])
          .presentationDragIndicator(.visible)
      } else {
        GettingStartedSheetView(height: $sheetHeight)
      }
    }
    // Developer config sheet
    .sheet(isPresented: $showDeveloperConfig) {
      DeveloperConfigView()
    }
    // Saved transcripts sheet
    .sheet(isPresented: $showTranscripts) {
      SavedTranscriptsView()
    }
    // RepairMate domain selector sheet
    .sheet(isPresented: $showDomainSelector) {
      NavigationView {
        DomainSelectorView(
          selectedDomain: $selectedDomain,
          onDomainSelected: { domain in
            onDomainSelected?(domain)
            isDomainSelectedProgrammatically = true
            showDomainSelector = false
            DispatchQueue.main.asyncAfter(deadline: .now() + sheetDismissalDelay) {
              showProcedureSelector = true
            }
          }
        )
        .padding()
        .navigationTitle("RepairMate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
              showDomainSelector = false
              cancelPendingAction()
            }
          }
        }
      }
      .presentationDetents([.medium])
    }
    // Procedure selector sheet
    .sheet(isPresented: $showProcedureSelector) {
      ProcedureSelectorView(
        sessionManager: repairManager,
        onProcedureSelected: { procedure in
          isProcedureDismissedProgrammatically = true
          showProcedureSelector = false
          // Only trigger repairDomain (which starts SafetyAnalysisService) if there's a pending stream action
          if pendingAction != nil, let domain = selectedDomain {
            onProcedureComplete?(domain, procedure)
          }
          executePendingAction()
        }
      )
      .presentationDetents([.large])
    }
    .onChange(of: showDomainSelector) { isPresented in
      if !isPresented {
        if isDomainSelectedProgrammatically {
          isDomainSelectedProgrammatically = false
        } else if pendingAction != nil {
          cancelPendingAction()
        }
      }
    }
    .onChange(of: showProcedureSelector) { isPresented in
      if !isPresented {
        if isProcedureDismissedProgrammatically {
          isProcedureDismissedProgrammatically = false
        } else if pendingAction != nil {
          cancelPendingAction()
        }
      }
    }
    .toast(message: $toastMessage)
    .onAppear {
      withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
        contentOpacity = 1.0
      }
      withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
        imageScale = 1.0
      }
    }
  }

  private func handleStreamAction(_ action: PendingStreamAction) {
    guard !isProcessingAction else { return }
    isProcessingAction = true
    pendingAction = action
    showDomainSelector = true
  }

  private func executePendingAction() {
    guard let action = pendingAction else {
      isProcessingAction = false
      return
    }
    pendingAction = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + sheetDismissalDelay) {
      startStream(action)
    }
  }

  private func startStream(_ action: PendingStreamAction) {
    Task {
      defer { isProcessingAction = false }
      switch action {
      case .iphone:
        await viewModel.handleStartIPhone()
      case .glasses:
        await viewModel.handleStartStreaming()
      }
    }
  }

  private func cancelPendingAction() {
    guard let action = pendingAction else {
      isProcessingAction = false
      return
    }
    pendingAction = nil
    isProcessingAction = false
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
      switch action {
      case .iphone:
        toastMessage = "iPhone stream cancelled"
      case .glasses:
        toastMessage = "Glasses stream cancelled"
      }
    }
  }
}

struct GettingStartedSheetView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var height: CGFloat

  var body: some View {
    VStack(spacing: 24) {
      Text("Getting started")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.primary)

      VStack(spacing: 12) {
        TipItemView(
          resource: .videoIcon,
          text: "First, Camera Access needs permission to use your glasses camera."
        )
        TipItemView(
          resource: .tapIcon,
          text: "Capture photos by tapping the camera button."
        )
        TipItemView(
          resource: .smartGlassesIcon,
          text: "The capture LED lets others know when you're capturing content or going live."
        )
      }
      .padding(.bottom, 16)

      CustomButton(
        title: "Continue",
        style: .primary,
        isDisabled: false
      ) {
        dismiss()
      }
    }
    .padding(.all, 24)
    .background(
      GeometryReader { geo -> Color in
        DispatchQueue.main.async {
          height = geo.size.height
        }
        return Color.clear
      }
    )
  }
}

struct TipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.primary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundColor(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
