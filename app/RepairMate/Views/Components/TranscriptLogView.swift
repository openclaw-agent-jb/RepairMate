import SwiftUI

/// A scrollable, semi-transparent overlay showing a conversation transcript.
/// Supports two modes:
/// - **Live mode**: Pass `geminiVM` to show the active conversation with auto-scroll.
///   Uses dark overlay colors (designed for on-top-of-video-feed).
/// - **Read-only mode**: Pass `savedTurns` to display a previously saved transcript.
///   Uses system theme-aware colors (adapts to Dark/Light mode).
struct TranscriptLogView: View {
  // Live mode
  var geminiVM: GeminiSessionViewModel?

  // Read-only mode
  var savedTurns: [SavedTranscript.SavedTurn]?

  // Context for saving
  var domain: RepairDomain?
  var procedureName: String?
  var autoSaveEnabled: Bool = false

  let onDismiss: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var showSavedConfirmation = false

  private var isReadOnly: Bool { savedTurns != nil }

  // MARK: - Theme-aware colors

  private var backgroundColor: Color {
    isReadOnly
      ? Color(UIColor.systemBackground)
      : Color.black.opacity(0.85)
  }

  private var primaryTextColor: Color {
    isReadOnly ? Color(UIColor.label) : .white
  }

  private var secondaryTextColor: Color {
    isReadOnly ? Color(UIColor.secondaryLabel) : .white.opacity(0.7)
  }

  private var dividerColor: Color {
    isReadOnly ? Color(UIColor.separator) : Color.white.opacity(0.2)
  }

  var body: some View {
    ZStack {
      // Backdrop
      backgroundColor
        .edgesIgnoringSafeArea(.all)
        .onTapGesture {
          if !isReadOnly { onDismiss() }
        }

      VStack(spacing: 0) {
        // Header bar
        HStack {
          Text("Transcript")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(primaryTextColor)

          if showSavedConfirmation {
            Text("Saved ✓")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.green)
              .transition(.opacity)
          }

          Spacer()

          // Manual save button (live mode only, hidden when auto-save is on)
          if !isReadOnly && !autoSaveEnabled {
            Button(action: saveTranscript) {
              Image(systemName: "square.and.arrow.down")
                .font(.system(size: 18))
                .foregroundColor(secondaryTextColor)
            }
            .disabled(isTranscriptEmpty)
            .opacity(isTranscriptEmpty ? 0.3 : 1.0)
            .padding(.trailing, 8)
          }

          Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 24))
              .foregroundColor(secondaryTextColor)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)

        Divider()
          .background(dividerColor)

        // Scrollable transcript
        if isReadOnly {
          readOnlyContent
        } else {
          liveContent
        }

        // Empty state
        if isEmpty {
          emptyState
        }
      }
      .padding(.top, isReadOnly ? 0 : 50)
    }
  }

  // MARK: - Live Content (observes geminiVM)

  @ViewBuilder
  private var liveContent: some View {
    if let vm = geminiVM {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(Array(vm.conversationHistory.enumerated()), id: \.offset) { index, turn in
              TranscriptBubble(
                text: turn.text,
                isUser: turn.role == "user",
                isLive: false,
                useThemeColors: false
              )
              .id("turn-\(index)")
            }

            if !vm.currentTurnUserText.isEmpty {
              TranscriptBubble(
                text: vm.currentTurnUserText,
                isUser: true,
                isLive: true,
                useThemeColors: false
              )
              .id("live-user")
            }

            if !vm.currentTurnModelText.isEmpty {
              TranscriptBubble(
                text: vm.currentTurnModelText,
                isUser: false,
                isLive: true,
                useThemeColors: false
              )
              .id("live-model")
            }

            Color.clear
              .frame(height: 1)
              .id("bottom")
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
        .onChange(of: vm.conversationHistory.count) { _ in
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }
        .onChange(of: vm.currentTurnUserText) { _ in
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }
        .onChange(of: vm.currentTurnModelText) { _ in
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }
      }
    }
  }

  // MARK: - Read-Only Content (saved transcript, theme-aware)

  @ViewBuilder
  private var readOnlyContent: some View {
    if let turns = savedTurns {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
            TranscriptBubble(
              text: turn.text,
              isUser: turn.role == "user",
              isLive: false,
              useThemeColors: true
            )
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }
    }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "text.bubble")
        .font(.system(size: 36))
        .foregroundColor(secondaryTextColor.opacity(0.4))
      Text("No transcript yet")
        .font(.system(size: 14))
        .foregroundColor(secondaryTextColor.opacity(0.6))
      Text("Start speaking to see the conversation here")
        .font(.system(size: 12))
        .foregroundColor(secondaryTextColor.opacity(0.4))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helpers

  private var isEmpty: Bool {
    if isReadOnly {
      return savedTurns?.isEmpty ?? true
    }
    guard let vm = geminiVM else { return true }
    return vm.conversationHistory.isEmpty
        && vm.currentTurnUserText.isEmpty
        && vm.currentTurnModelText.isEmpty
  }

  private var isTranscriptEmpty: Bool {
    guard let vm = geminiVM else { return true }
    return vm.conversationHistory.isEmpty
  }

  private func saveTranscript() {
    guard let vm = geminiVM, !vm.conversationHistory.isEmpty else { return }
    let result = TranscriptStore.shared.save(
      turns: vm.conversationHistory,
      domain: domain?.shortLabel,
      procedure: procedureName
    )
    if result != nil {
      withAnimation { showSavedConfirmation = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        withAnimation { showSavedConfirmation = false }
      }
    }
  }
}

// MARK: - Chat Bubble

struct TranscriptBubble: View {
  let text: String
  let isUser: Bool
  let isLive: Bool
  var useThemeColors: Bool = false

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack {
      if isUser { Spacer(minLength: 60) }

      VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
        // Role label
        HStack(spacing: 4) {
          Image(systemName: isUser ? "person.fill" : "sparkles")
            .font(.system(size: 9, weight: .semibold))
          Text(isUser ? "You" : "AI")
            .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(isUser ? Color.blue.opacity(0.8) : Color.green.opacity(0.8))

        // Message text
        Text(text)
          .font(.system(size: 14))
          .foregroundColor(textColor)
          .italic(isLive)
          .multilineTextAlignment(isUser ? .trailing : .leading)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(bubbleBackground)
      )

      if !isUser { Spacer(minLength: 60) }
    }
  }

  private var textColor: Color {
    if useThemeColors {
      return Color(UIColor.label).opacity(isLive ? 0.5 : 1.0)
    }
    return .white.opacity(isLive ? 0.6 : 0.95)
  }

  private var bubbleBackground: Color {
    if useThemeColors {
      if isUser {
        return Color.blue.opacity(isLive ? 0.08 : 0.15)
      } else {
        return Color(UIColor.secondarySystemBackground)
      }
    }
    // Dark overlay style for live mode
    if isUser {
      return Color.blue.opacity(isLive ? 0.15 : 0.25)
    } else {
      return Color.white.opacity(isLive ? 0.05 : 0.1)
    }
  }
}
