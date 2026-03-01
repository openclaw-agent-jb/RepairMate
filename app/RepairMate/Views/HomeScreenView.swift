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

struct HomeScreenView: View {
  @ObservedObject var viewModel: WearablesViewModel
  @State private var contentOpacity: Double = 0
  @State private var imageScale: CGFloat = 0.8

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
        Spacer()

        // Bottom action section
        VStack(spacing: 20) {
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
    .onAppear {
      withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
        contentOpacity = 1.0
      }
      withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2)) {
        imageScale = 1.0
      }
    }
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
