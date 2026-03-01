/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Welcome screen that guides users through the DAT SDK registration process.
// This view is displayed when the app is not yet registered.
//

import MWDATCore
import SwiftUI

private let sheetDismissalDelay: TimeInterval = 0.5
private let brandTeal = Color(red: 0.0, green: 0.76, blue: 0.88)

struct HomeScreenView: View {
  @ObservedObject var viewModel: WearablesViewModel
  // Domain/procedure plumbing – supplied by StreamSessionView so
  // "Start on iPhone" goes through the same selector flow as NonStreamView.
  @Binding var selectedDomain: RepairDomain?
  var repairManager: RepairMateSessionManager
  var onDomainSelected: ((RepairDomain) -> Void)?
  var onProcedureComplete: ((RepairDomain, RepairProcedure?) -> Void)?
  /// Called after domain+procedure are selected to actually start the iPhone session.
  var onStartIPhone: (() -> Void)?

  @State private var contentOpacity: Double = 0
  @State private var imageScale: CGFloat = 0.8
  @State private var showDeveloperConfig = false
  @State private var showTranscripts = false
  @State private var showIPhoneWarning = false
  @State private var showDomainSelector = false
  @State private var showProcedureSelector = false
  @State private var isProcessingAction = false
  @State private var isDomainSelectedProgrammatically = false
  @State private var isProcedureDismissedProgrammatically = false

  var body: some View {
    ZStack {
      // Background: SplashImage with full coverage
      Image("BackgroundImage")
        .resizable()
        .aspectRatio(contentMode: .fill)
        .edgesIgnoringSafeArea(.all)
        .scaleEffect(1.05)

      // Dark gradient overlay for readability
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
        // Header with settings menu
        HStack {
          Spacer()
          Menu {
            Button {
              showDeveloperConfig = true
            } label: {
              Label("Dev Settings", systemImage: "gear")
            }

            Button {
              showTranscripts = true
            } label: {
              Label("Transcripts", systemImage: "text.bubble")
            }
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

        // Bottom action section
        VStack(spacing: 12) {
          Text("You'll be redirected to the Meta AI app\nto confirm your connection.")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)

          CustomButton(
            title: viewModel.registrationState == .registering ? "Connecting..." : "Connect My Glasses",
            style: .primary,
            isDisabled: viewModel.registrationState == .registering
          ) {
            Task { await viewModel.connectGlasses() }
          }
          .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)

          // iPhone streaming – available even without glasses, opens domain selector first
          if onStartIPhone != nil {
            CustomButton(
              title: "Stream on iPhone",
              style: .secondary,
              isDisabled: isProcessingAction
            ) {
              guard !isProcessingAction else { return }
              showIPhoneWarning = true
            }
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
          }

          #if targetEnvironment(simulator)
          Text("SIMULATOR PREVIEW")
            .font(.system(size: 10, weight: .bold))
            .tracking(1.5)
            .foregroundColor(.yellow.opacity(0.85))

          CustomButton(
            title: "Skip – Simulator Preview",
            style: .destructive,
            isDisabled: false
          ) {
            viewModel.simulatorBypassActive = true
          }
          .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
          #endif
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .opacity(contentOpacity)
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
    // Safety warning before iPhone streaming
    .alert("Use with Caution", isPresented: $showIPhoneWarning) {
      Button("Continue", role: .destructive) {
        isProcessingAction = true
        showDomainSelector = true
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Streaming on iPhone works best when your phone is secured in a mount or stand. Holding or balancing your device while doing hands-free repair is unsafe.")
    }
    // Domain selector sheet
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
              cancelAction()
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
          if let domain = selectedDomain {
            onProcedureComplete?(domain, procedure)
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + sheetDismissalDelay) {
            onStartIPhone?()
            isProcessingAction = false
          }
        }
      )
      .presentationDetents([.large])
    }
    .onChange(of: showDomainSelector) { isPresented in
      if !isPresented {
        if isDomainSelectedProgrammatically {
          isDomainSelectedProgrammatically = false
        } else {
          cancelAction()
        }
      }
    }
    .onChange(of: showProcedureSelector) { isPresented in
      if !isPresented {
        if isProcedureDismissedProgrammatically {
          isProcedureDismissedProgrammatically = false
        } else {
          cancelAction()
        }
      }
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
        contentOpacity = 1.0
      }
      withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
        imageScale = 1.0
      }
    }
  }

  private func cancelAction() {
    isProcessingAction = false
  }
}


struct HomeTipItemView: View {
  let resource: ImageResource
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.white)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.white)

        Text(text)
          .font(.system(size: 14))
          .foregroundColor(.white.opacity(0.8))
          .lineSpacing(2)
      }
      Spacer()
    }
  }
}
