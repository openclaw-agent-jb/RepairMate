import SwiftUI

struct ProcedureSelectorView: View {
  @ObservedObject var sessionManager: RepairMateSessionManager
  var onProcedureSelected: (RepairProcedure?) -> Void
  @Environment(\.dismiss) var dismiss

  var body: some View {
    VStack(spacing: 20) {
      if sessionManager.isLoadingProcedures {
        Spacer()
        ProgressView("Loading procedures for \(sessionManager.currentDomain?.rawValue ?? "")...")
          .foregroundColor(.white)
        Spacer()
      } else if sessionManager.procedures.isEmpty {
        Spacer()
        Text("No specific procedures found.")
          .font(.headline)
          .foregroundColor(.white.opacity(0.8))
        Text("You can still use RepairMate as a general assistant.")
          .font(.subheadline)
          .foregroundColor(.white.opacity(0.6))
          .multilineTextAlignment(.center)
          .padding(.horizontal)
        
        CustomButton(
          title: "Continue without a procedure",
          style: .primary,
          isDisabled: false
        ) {
          onProcedureSelected(nil)
        }
        .padding(.top, 20)
        Spacer()
      } else {
        Text("Select a Procedure")
          .font(.title2)
          .fontWeight(.bold)
          .foregroundColor(.white)
          .padding(.top)

        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(sessionManager.procedures) { procedure in
              Button(action: {
                onProcedureSelected(procedure)
              }) {
                VStack(alignment: .leading, spacing: 6) {
                  Text(procedure.name)
                    .font(.headline)
                    .foregroundColor(.white)
                  
                  HStack {
                    Label(procedure.difficulty, systemImage: "speedometer")
                    Spacer()
                    Label(procedure.estimatedTime, systemImage: "clock")
                  }
                  .font(.subheadline)
                  .foregroundColor(.white.opacity(0.7))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                  RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
              }
              .buttonStyle(PlainButtonStyle())
            }
          }
          .padding(.horizontal)
        }
        
        CustomButton(
          title: "Skip Procedure (General Chat)",
          style: .primary,
          isDisabled: false
        ) {
          onProcedureSelected(nil)
        }
        .padding(.horizontal)
        .padding(.bottom)
      }
    }
    .background(Color.black.edgesIgnoringSafeArea(.all))
  }
}
