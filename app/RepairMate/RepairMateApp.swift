/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// RepairMateApp.swift
//
// Main entry point for the RepairMate sample app demonstrating the Meta Wearables DAT SDK.
// This app shows how to connect to wearable devices (like Ray-Ban Meta smart glasses),
// stream live video from their cameras, and capture photos. It provides a complete example
// of DAT SDK integration including device registration, permissions, and media streaming.
//

import FirebaseCore
import Foundation
import MWDATCore
import SwiftUI

@main
struct RepairMateApp: App {
  private let wearables: WearablesInterface
  @StateObject private var wearablesViewModel: WearablesViewModel
  @State private var isReady = false

  init() {
    do {
      try Wearables.configure()
      NSLog("[RepairMate] Wearables.configure() succeeded")
    } catch {
      NSLog("[RepairMate] Wearables.configure() FAILED: \(error)")
    }
    let wearables = Wearables.shared
    self.wearables = wearables
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
    FirebaseApp.configure()
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if isReady {
          // Main app view with access to the shared Wearables SDK instance
          // The Wearables.shared singleton provides the core DAT API
          MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
            // Show error alerts for view model failures
            .alert("Error", isPresented: $wearablesViewModel.showError) {
              Button("OK") {
                wearablesViewModel.dismissError()
              }
            } message: {
              Text(wearablesViewModel.errorMessage)
            }
        } else {
          // Show the splash image while the app finishes initialising so
          // there is no blank gap — seamlessly bridges the system LaunchScreen.
          Image("SplashImage")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea()
        }
      }
      .task {
        // Guarantee the launch screen is visible for at least 1 second
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isReady = true
      }

      // Registration view handles the flow for connecting to the glasses via Meta AI
      RegistrationView(viewModel: wearablesViewModel)
    }
  }
}
