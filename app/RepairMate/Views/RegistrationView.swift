/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// RegistrationView.swift
//
// Background view that handles callbacks from the Meta AI mobile app during
// DAT SDK registration and permission flows. This invisible view processes deep links
// that complete the OAuth authorization process initiated by the DAT SDK.
//

import MWDATCore
import SwiftUI

struct RegistrationView: View {
  @ObservedObject var viewModel: WearablesViewModel

  var body: some View {
    EmptyView()
      // Handle callback URLs from the Meta mobile app
      // This is essential for completing DAT SDK registration and permission flows
      .onOpenURL { url in
        NSLog("[RepairMate] RegistrationView onOpenURL: \(url.absoluteString)")

        let isFacemateScheme = url.scheme?.lowercased() == "repairmate"
        let hasWearablesAction: Bool = {
          guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
          }
          return components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        }()

        NSLog("[RepairMate] isFacemateScheme: \(isFacemateScheme), hasWearablesAction: \(hasWearablesAction)")

        // Process URLs that are either repairmate:// scheme OR have metaWearablesAction param
        guard isFacemateScheme || hasWearablesAction else {
          NSLog("[RepairMate] Ignoring non-DAT URL callback")
          return
        }

        Task {
          do {
            // Pass the callback URL to the DAT SDK for processing
            // This handles registration completion and permission grant responses
            NSLog("[RepairMate] Calling Wearables.handleUrl...")
            _ = try await Wearables.shared.handleUrl(url)
            NSLog("[RepairMate] Wearables.handleUrl succeeded")
          } catch let error as RegistrationError {
            NSLog("[RepairMate] RegistrationError: \(error.description)")
            viewModel.showError(error.description)
          } catch {
            NSLog("[RepairMate] Unknown error: \(error.localizedDescription)")
            viewModel.showError("Unknown error: \(error.localizedDescription)")
          }
        }
      }
  }
}
