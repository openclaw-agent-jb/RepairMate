/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// ToastView.swift
//
// Reusable toast notification component with glassmorphism styling and auto-dismiss.
//

import SwiftUI

struct ToastView: View {
  let message: String
  let icon: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.white.opacity(0.9))
      Text(message)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.white.opacity(0.9))
        .lineLimit(2)
        .minimumScaleFactor(0.85)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 16)
    .background(
      Capsule()
        .fill(.ultraThinMaterial)
        .overlay(
          Capsule()
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    )
    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
  }
}

private struct ToastModifier: ViewModifier {
  @Binding var message: String?
  let icon: String
  let duration: TimeInterval
  @State private var dismissID = UUID()

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        if let text = message {
          ToastView(message: text, icon: icon)
            .onTapGesture {
              withAnimation(.easeOut(duration: 0.3)) {
                message = nil
              }
            }
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .onChange(of: message) { newValue in
        guard newValue != nil else { return }
        let id = UUID()
        dismissID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
          if dismissID == id {
            withAnimation(.easeOut(duration: 0.3)) {
              message = nil
            }
          }
        }
      }
  }
}

extension View {
  func toast(
    message: Binding<String?>,
    icon: String = "xmark.circle.fill",
    duration: TimeInterval = 2.5
  ) -> some View {
    modifier(ToastModifier(message: message, icon: icon, duration: duration))
  }
}
