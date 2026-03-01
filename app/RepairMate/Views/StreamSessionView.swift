/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var viewModel: StreamSessionViewModel
  @StateObject private var geminiVM = GeminiSessionViewModel()
  @StateObject private var repairManager = RepairMateSessionManager(firestoreService: FirestoreService())
  @State private var selectedDomain: RepairDomain?

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming {
        // Full-screen video view with streaming controls
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM, selectedDomain: selectedDomain, procedureName: repairManager.currentProcedure?.name)
      } else {
        // Pre-streaming setup view with permissions and start button
        NonStreamView(
          viewModel: viewModel,
          wearablesVM: wearablesViewModel,
          repairManager: repairManager,
          selectedDomain: $selectedDomain,
          onDomainSelected: { domain in
            // Handle initial domain selection to start fetching domains
            repairManager.startSession(domain: domain)
            // Also update geminiVM.repairDomain so the new domain is used when streaming starts
            geminiVM.repairDomain = domain
          },
          onProcedureComplete: { domain, procedure in
            // When user finishes selecting a procedure, truly assign it
            geminiVM.repairDomain = domain
            geminiVM.currentProcedureName = procedure?.name
            if let proc = procedure {
              // re-start session with the procedure now that it is selected
              repairManager.startSession(domain: domain, procedure: proc)
            }
          }
        )
      }
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
    .task {
      viewModel.geminiSessionVM = geminiVM
      geminiVM.streamingMode = viewModel.streamingMode
    }
    .onChange(of: viewModel.streamingMode) { newMode in
      geminiVM.streamingMode = newMode
    }
    .onChange(of: viewModel.isStreaming) { isStreaming in
      // When streaming stops, stop safety analysis but preserve domain knowledge
      if !isStreaming {
        geminiVM.stopSafetyAnalysis()
      }
    }
  }
}
