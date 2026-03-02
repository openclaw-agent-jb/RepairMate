/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

@testable import RepairMate

final class TranscriptStoreTests: XCTestCase {

  var sut: TranscriptStore!
  var testDirectory: URL!

  override func setUp() {
    super.setUp()

    // Create a temporary directory for testing
    let tempDir = FileManager.default.temporaryDirectory
    testDirectory = tempDir.appendingPathComponent("TranscriptStoreTests-\(UUID().uuidString)")

    // Create a testable instance that uses our temp directory
    sut = TestableTranscriptStore.create(directoryURL: testDirectory)
  }

  override func tearDown() {
    // Clean up test directory
    try? FileManager.default.removeItem(at: testDirectory)
    sut = nil
    super.tearDown()
  }

  // MARK: - Title Generation Tests

  func testGenerateTitleWithDomainAndProcedure() {
    let title = TranscriptStore.generateTitle(domain: "Automobile", procedure: "Spark Plugs")
    XCTAssertEqual(title, "Automobile_Spark_Plugs")
  }

  func testGenerateTitleWithOnlyDomain() {
    let title = TranscriptStore.generateTitle(domain: "Electronics", procedure: nil)
    XCTAssertEqual(title, "Electronics")
  }

  func testGenerateTitleWithEmptyProcedure() {
    let title = TranscriptStore.generateTitle(domain: "HVAC", procedure: "")
    XCTAssertEqual(title, "HVAC")
  }

  func testGenerateTitleWithNilDomain() {
    let title = TranscriptStore.generateTitle(domain: nil, procedure: "Repair")
    XCTAssertEqual(title, "Session_Repair")
  }

  func testGenerateTitleWithBothNil() {
    let title = TranscriptStore.generateTitle(domain: nil, procedure: nil)
    XCTAssertEqual(title, "Session")
  }

  func testGenerateTitleNormalizesSpaces() {
    let title = TranscriptStore.generateTitle(domain: "Auto Mobile", procedure: "Oil Change")
    XCTAssertEqual(title, "Auto_Mobile_Oil_Change")
  }

  func testGenerateTitleNormalizesHyphens() {
    let title = TranscriptStore.generateTitle(domain: "Auto-Mobile", procedure: "Oil-Change")
    XCTAssertEqual(title, "Auto_Mobile_Oil_Change")
  }

  func testGenerateTitleStripsDiacritics() {
    let title = TranscriptStore.generateTitle(domain: "Café", procedure: "Résumé")
    XCTAssertEqual(title, "Cafe_Resume")
  }

  func testGenerateTitleStripsSpecialCharacters() {
    let title = TranscriptStore.generateTitle(domain: "Auto@#$%", procedure: "Repair!!!")
    XCTAssertEqual(title, "Auto_Repair")
  }

  // MARK: - Save Tests

  func testSaveTranscript() {
    let turns: [ConversationTurn] = [
      ConversationTurn(role: "user", text: "Hello"),
      ConversationTurn(role: "model", text: "Hi there!")
    ]

    let result = sut.save(turns: turns, domain: "Test", procedure: "Save")

    XCTAssertNotNil(result)
    XCTAssertEqual(result?.title, "Test_Save")
    XCTAssertEqual(result?.turns.count, 2)
    XCTAssertEqual(result?.turns[0].role, "user")
    XCTAssertEqual(result?.turns[0].text, "Hello")
  }

  func testSaveEmptyTurnsReturnsNil() {
    let result = sut.save(turns: [], domain: "Test", procedure: "Empty")
    XCTAssertNil(result)
  }

  func testSaveGeneratesUniqueIds() {
    let turns = [ConversationTurn(role: "user", text: "Test")]

    let transcript1 = sut.save(turns: turns, domain: "Test", procedure: "1")
    let transcript2 = sut.save(turns: turns, domain: "Test", procedure: "2")

    XCTAssertNotEqual(transcript1?.id, transcript2?.id)
  }

  func testSavePersistsToDisk() {
    let turns = [
      ConversationTurn(role: "user", text: "Hello"),
      ConversationTurn(role: "model", text: "World")
    ]

    let saved = sut.save(turns: turns, domain: "Persist", procedure: "Test")

    // Verify file exists
    let fileURL = testDirectory.appendingPathComponent("\(saved!.id).json")
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

    // Verify file content
    let data = try? Data(contentsOf: fileURL)
    XCTAssertNotNil(data)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let loaded = try? decoder.decode(SavedTranscript.self, from: data!)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.title, "Persist_Test")
  }

  // MARK: - Load Tests

  func testLoadAllReturnsEmptyArrayWhenNoTranscripts() {
    let transcripts = sut.loadAll()
    XCTAssertEqual(transcripts.count, 0)
  }

  func testLoadAllReturnsSavedTranscripts() {
    let turns = [ConversationTurn(role: "user", text: "Test")]

    _ = sut.save(turns: turns, domain: "First", procedure: nil)
    _ = sut.save(turns: turns, domain: "Second", procedure: nil)

    let loaded = sut.loadAll()
    XCTAssertEqual(loaded.count, 2)
  }

  func testLoadAllReturnsSortedByDateDescending() {
    // This test verifies sorting - most recent first
    let turns = [ConversationTurn(role: "user", text: "Test")]

    let first = sut.save(turns: turns, domain: "First", procedure: nil)
    Thread.sleep(forTimeInterval: 0.1) // Ensure different timestamps
    let second = sut.save(turns: turns, domain: "Second", procedure: nil)

    let loaded = sut.loadAll()
    XCTAssertEqual(loaded.count, 2)
    XCTAssertEqual(loaded[0].id, second?.id) // Most recent first
    XCTAssertEqual(loaded[1].id, first?.id)
  }

  func testLoadAllIgnoresInvalidFiles() {
    // Create an invalid JSON file
    let invalidData = "not json".data(using: .utf8)!
    let invalidFile = testDirectory.appendingPathComponent("invalid.json")
    try? invalidData.write(to: invalidFile)

    let turns = [ConversationTurn(role: "user", text: "Valid")]
    _ = sut.save(turns: turns, domain: "Valid", procedure: nil)

    let loaded = sut.loadAll()
    XCTAssertEqual(loaded.count, 1)
    XCTAssertEqual(loaded[0].title, "Valid")
  }

  func testLoadAllIgnoresNonJsonFiles() {
    let textFile = testDirectory.appendingPathComponent("readme.txt")
    try? "Hello".write(to: textFile, atomically: true, encoding: .utf8)

    let turns = [ConversationTurn(role: "user", text: "Test")]
    _ = sut.save(turns: turns, domain: "Test", procedure: nil)

    let loaded = sut.loadAll()
    XCTAssertEqual(loaded.count, 1)
  }

  // MARK: - Delete Tests

  func testDeleteRemovesTranscript() {
    let turns = [ConversationTurn(role: "user", text: "To Delete")]
    let saved = sut.save(turns: turns, domain: "Delete", procedure: "Me")

    let beforeDelete = sut.loadAll()
    XCTAssertEqual(beforeDelete.count, 1)

    sut.delete(id: saved!.id)

    let afterDelete = sut.loadAll()
    XCTAssertEqual(afterDelete.count, 0)
  }

  func testDeleteNonexistentIdDoesNotCrash() {
    sut.delete(id: "nonexistent-id")
    // Should not crash
  }

  func testDeleteOnlyRemovesSpecifiedTranscript() {
    let turns = [ConversationTurn(role: "user", text: "Test")]

    let keep = sut.save(turns: turns, domain: "Keep", procedure: nil)
    let remove = sut.save(turns: turns, domain: "Remove", procedure: nil)

    sut.delete(id: remove!.id)

    let remaining = sut.loadAll()
    XCTAssertEqual(remaining.count, 1)
    XCTAssertEqual(remaining[0].id, keep?.id)
  }

  // MARK: - Auto Save Tests

  func testAutoSaveWhenEnabled() {
    UserDefaults.standard.set(true, forKey: "com.repairmate.autoSaveTranscripts")

    let turns = [ConversationTurn(role: "user", text: "Auto")]
    let result = sut.autoSaveIfEnabled(turns: turns, domain: "Auto", procedure: "Save")

    XCTAssertNotNil(result)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "com.repairmate.autoSaveTranscripts")
  }

  func testAutoSaveWhenDisabled() {
    UserDefaults.standard.set(false, forKey: "com.repairmate.autoSaveTranscripts")

    let turns = [ConversationTurn(role: "user", text: "No Auto")]
    let result = sut.autoSaveIfEnabled(turns: turns, domain: "No", procedure: "Auto")

    XCTAssertNil(result)

    // Clean up
    UserDefaults.standard.removeObject(forKey: "com.repairmate.autoSaveTranscripts")
  }

  func testAutoSaveWhenNotConfigured() {
    UserDefaults.standard.removeObject(forKey: "com.repairmate.autoSaveTranscripts")

    let turns = [ConversationTurn(role: "user", text: "Not Set")]
    let result = sut.autoSaveIfEnabled(turns: turns, domain: "Not", procedure: "Set")

    XCTAssertNil(result)
  }

  // MARK: - SavedTranscript Model Tests

  func testSavedTranscriptCodable() {
    let turn = SavedTranscript.SavedTurn(role: "user", text: "Hello")
    let transcript = SavedTranscript(
      id: "test-id",
      title: "Test_Title",
      turns: [turn],
      createdAt: Date()
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    guard let data = try? encoder.encode(transcript),
          let decoded = try? decoder.decode(SavedTranscript.self, from: data) else {
      XCTFail("Failed to encode/decode")
      return
    }

    XCTAssertEqual(decoded.id, "test-id")
    XCTAssertEqual(decoded.title, "Test_Title")
    XCTAssertEqual(decoded.turns.count, 1)
    XCTAssertEqual(decoded.turns[0].role, "user")
    XCTAssertEqual(decoded.turns[0].text, "Hello")
  }
}

// MARK: - Test Helper

private class TestableTranscriptStore: TranscriptStore {
  private let customDirectory: URL

  init(directoryURL: URL) {
    self.customDirectory = directoryURL
    // Don't call super.init() since it's private - use the shared instance approach
    // Instead, we'll use a static factory method
  }

  static func create(directoryURL: URL) -> TestableTranscriptStore {
    let store = TestableTranscriptStore(directoryURL: directoryURL)
    // Create the directory
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return store
  }

  override var transcriptsDirectory: URL {
    return customDirectory
  }
}
