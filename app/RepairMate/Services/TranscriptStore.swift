import Foundation

// MARK: - Saved Transcript Model

struct SavedTranscript: Codable, Identifiable {
  let id: String
  let title: String
  let turns: [SavedTurn]
  let createdAt: Date

  struct SavedTurn: Codable {
    let role: String  // "user" or "model"
    let text: String
  }
}

// MARK: - Transcript Store

/// Persists conversation transcripts as JSON files in Documents/Transcripts/.
class TranscriptStore {
  static let shared = TranscriptStore()

  private let directoryName = "Transcripts"
  private let fileManager = FileManager.default

  private var transcriptsDirectory: URL {
    let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent(directoryName)
  }

  private init() {
    // Ensure the Transcripts directory exists
    try? fileManager.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
  }

  // MARK: - Title Generation

  /// Generates a title like "Automobile_Spark_Plugs"
  static func generateTitle(domain: String?, procedure: String?, date: Date = Date()) -> String {
    let domainPart = normalize(domain) ?? "Session"
    let procedurePart = normalize(procedure)

    if let proc = procedurePart, !proc.isEmpty {
      return "\(domainPart)_\(proc)"
    } else {
      return domainPart
    }
  }

  /// Normalizes a string for use in a title: strips diacritics, replaces spaces/hyphens
  /// with underscores, and removes any remaining non-alphanumeric/underscore characters.
  private static func normalize(_ input: String?) -> String? {
    guard let input, !input.isEmpty else { return nil }
    return input
      .folding(options: .diacriticInsensitive, locale: .current)  // café → cafe
      .replacingOccurrences(of: " ", with: "_")
      .replacingOccurrences(of: "-", with: "_")
      .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
      .joined()
  }

  // MARK: - Save

  @discardableResult
  func save(turns: [ConversationTurn], domain: String?, procedure: String?) -> SavedTranscript? {
    guard !turns.isEmpty else { return nil }

    let now = Date()
    let transcript = SavedTranscript(
      id: UUID().uuidString,
      title: Self.generateTitle(domain: domain, procedure: procedure, date: now),
      turns: turns.map { SavedTranscript.SavedTurn(role: $0.role, text: $0.text) },
      createdAt: now
    )

    let fileURL = transcriptsDirectory.appendingPathComponent("\(transcript.id).json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted

    do {
      let data = try encoder.encode(transcript)
      try data.write(to: fileURL, options: .atomic)
      NSLog("[TranscriptStore] Saved transcript: %@", transcript.title)
      return transcript
    } catch {
      NSLog("[TranscriptStore] Failed to save: %@", error.localizedDescription)
      return nil
    }
  }

  /// Auto-saves if the AppStorage toggle is ON.
  @discardableResult
  func autoSaveIfEnabled(turns: [ConversationTurn], domain: String?, procedure: String?) -> SavedTranscript? {
    let autoSave = UserDefaults.standard.bool(forKey: "com.repairmate.autoSaveTranscripts")
    guard autoSave else { return nil }
    return save(turns: turns, domain: domain, procedure: procedure)
  }

  // MARK: - Load

  func loadAll() -> [SavedTranscript] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
      let files = try fileManager.contentsOfDirectory(at: transcriptsDirectory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }

      let transcripts: [SavedTranscript] = files.compactMap { url in
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SavedTranscript.self, from: data)
      }

      return transcripts.sorted { $0.createdAt > $1.createdAt }
    } catch {
      NSLog("[TranscriptStore] Failed to load: %@", error.localizedDescription)
      return []
    }
  }

  // MARK: - Delete

  func delete(id: String) {
    let fileURL = transcriptsDirectory.appendingPathComponent("\(id).json")
    do {
      try fileManager.removeItem(at: fileURL)
      NSLog("[TranscriptStore] Deleted transcript: %@", id)
    } catch {
      NSLog("[TranscriptStore] Failed to delete: %@", error.localizedDescription)
    }
  }
}
