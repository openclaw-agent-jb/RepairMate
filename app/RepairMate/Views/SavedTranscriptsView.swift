import SwiftUI

/// Displays a list of saved transcripts with tap-to-view and swipe-to-delete.
struct SavedTranscriptsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var transcripts: [SavedTranscript] = []
  @State private var selectedTranscript: SavedTranscript?

  var body: some View {
    NavigationView {
      Group {
        if transcripts.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "text.bubble")
              .font(.system(size: 48))
              .foregroundColor(.secondary.opacity(0.4))
            Text("No Saved Transcripts")
              .font(.headline)
              .foregroundColor(.secondary)
            Text("Transcripts will appear here when saved manually or via auto-save.")
              .font(.caption)
              .foregroundColor(.secondary.opacity(0.7))
              .multilineTextAlignment(.center)
              .padding(.horizontal, 40)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List {
            ForEach(transcripts) { transcript in
              Button {
                selectedTranscript = transcript
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(transcript.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                  Text(formattedDate(transcript.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                  Text("\(transcript.turns.count) messages")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.vertical, 4)
              }
            }
            .onDelete(perform: deleteTranscripts)
          }
        }
      }
      .navigationTitle("Transcripts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .fullScreenCover(item: $selectedTranscript) { transcript in
        TranscriptLogView(
          savedTurns: transcript.turns,
          onDismiss: { selectedTranscript = nil }
        )
      }
    }
    .onAppear {
      transcripts = TranscriptStore.shared.loadAll()
    }
  }

  private func deleteTranscripts(at offsets: IndexSet) {
    for index in offsets {
      TranscriptStore.shared.delete(id: transcripts[index].id)
    }
    transcripts.remove(atOffsets: offsets)
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}
