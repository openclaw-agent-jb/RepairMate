/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CustomButton.swift
//
// Reusable button component used throughout the RepairMate app for consistent styling.
//

import SwiftUI

struct CustomButton: View {
  let title: String
  let style: ButtonStyle
  let isDisabled: Bool
  let action: () -> Void

  enum ButtonStyle {
    case primary, secondary, destructive

    var backgroundColor: Color {
      switch self {
      case .primary:
        return .appPrimary
      case .secondary:
        return Color(white: 0.30)
      case .destructive:
        return .destructiveBackground
      }
    }

    var foregroundColor: Color {
      switch self {
      case .primary, .secondary:
        return .white
      case .destructive:
        return .destructiveForeground
      }
    }

    /// Gradient used instead of flat colour for `.primary` buttons.
    var gradient: LinearGradient? {
      switch self {
      case .primary:
        return LinearGradient(
          colors: [
            Color(red: 0.031, green: 0.420, blue: 0.451), // #087273  deep teal
            Color(red: 0.094, green: 0.596, blue: 0.608), // #189899  teal
            Color(red: 0.216, green: 0.780, blue: 0.776)  // #37C7C6  bright cyan-teal
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      case .secondary, .destructive:
        return nil
      }
    }
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(style.foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
          Group {
            if let gradient = style.gradient {
              RoundedRectangle(cornerRadius: 30)
                .fill(gradient)
            } else {
              RoundedRectangle(cornerRadius: 30)
                .fill(style.backgroundColor)
            }
          }
        )
    }
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.6 : 1.0)
  }
}
