import Foundation
import XCTest

@testable import RepairMate

// MARK: - Mock FirestoreService

@MainActor
private final class MockFirestoreService: FirestoreServicing {
    var proceduresToReturn: [RepairProcedure] = []
    var shouldThrow = false

    private(set) var fetchCallCount = 0
    private(set) var lastFetchedDomain: RepairDomain?

    private(set) var saveCallCount = 0
    private(set) var lastSavedWorkflow: WorkflowState?

    private(set) var logCallCount = 0
    private(set) var lastLoggedAssessment: SafetyAssessment?

    func fetchProcedures(domain: RepairDomain) async throws -> [RepairProcedure] {
        fetchCallCount += 1
        lastFetchedDomain = domain
        if shouldThrow { throw MockError.intentional }
        return proceduresToReturn
    }

    func saveWorkflow(_ workflow: WorkflowState) async throws {
        saveCallCount += 1
        lastSavedWorkflow = workflow
        if shouldThrow { throw MockError.intentional }
    }

    func logSafetyEvent(_ assessment: SafetyAssessment, sessionId: String) async throws {
        logCallCount += 1
        lastLoggedAssessment = assessment
        if shouldThrow { throw MockError.intentional }
    }

    enum MockError: Error { case intentional }
}

// MARK: - FirestoreService Integration Tests

/// Tests that RepairMateSessionManager correctly invokes FirestoreService.
/// All tests use MockFirestoreService — no live Firestore connection needed.
@MainActor
final class FirestoreServiceIntegrationTests: XCTestCase {

    // MARK: fetchProcedures

    func testStartSessionCallsFetchProcedures() async throws {
        let mock = MockFirestoreService()
        let sut = RepairMateSessionManager(firestoreService: mock)

        sut.startSession(domain: .auto)

        // Give the background Task a moment to execute
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        XCTAssertEqual(mock.fetchCallCount, 1)
        XCTAssertEqual(mock.lastFetchedDomain, .auto)
    }

    func testStartSessionFetchesCorrectDomain() async throws {
        let mock = MockFirestoreService()
        let sut = RepairMateSessionManager(firestoreService: mock)

        sut.startSession(domain: .electronics)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.lastFetchedDomain, .electronics)
    }

    func testStartSessionDoesNotCrashWhenFetchThrows() async throws {
        let mock = MockFirestoreService()
        mock.shouldThrow = true
        let sut = RepairMateSessionManager(firestoreService: mock)

        // Should not crash even when Firestore throws
        sut.startSession(domain: .hvac)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.fetchCallCount, 1)
    }

    // MARK: saveWorkflow

    func testAdvanceStepCallsSaveWorkflow() async throws {
        let mock = MockFirestoreService()
        let sut = RepairMateSessionManager(firestoreService: mock)
        sut.startSession(domain: .auto)

        sut.advanceStep()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.saveCallCount, 1)
        XCTAssertEqual(mock.lastSavedWorkflow?.currentStep, 1)
    }

    func testSaveWorkflowCarriesCorrectSessionId() async throws {
        let mock = MockFirestoreService()
        let sut = RepairMateSessionManager(firestoreService: mock)
        sut.startSession(domain: .appliances)
        let sessionId = sut.workflowState?.sessionId

        sut.advanceStep()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(mock.lastSavedWorkflow?.sessionId, sessionId)
    }

    func testAdvanceStepDoesNotCrashWhenSaveThrows() async throws {
        let mock = MockFirestoreService()
        mock.shouldThrow = true
        let sut = RepairMateSessionManager(firestoreService: mock)
        sut.startSession(domain: .auto)

        // NSLog will emit an error message — this should NOT crash
        sut.advanceStep()
        try await Task.sleep(nanoseconds: 50_000_000)

        // State is still updated locally despite Firestore failure
        XCTAssertEqual(sut.currentStep, 1)
    }

    // MARK: Nil Firestore (offline / Phase 1 compatibility)

    func testSessionManagerWorksWithoutFirestore() {
        let sut = RepairMateSessionManager()  // no firestoreService

        sut.startSession(domain: .auto)
        sut.advanceStep()
        sut.recordSafetyAcknowledgement("Battery disconnected")
        sut.saveNote("Used penetrating oil")
        sut.endSession()

        XCTAssertNil(sut.currentDomain)
        XCTAssertNil(sut.workflowState)
    }

}


// MARK: - Async test helper

func XCTAssertNoThrowAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
    } catch {
        XCTFail("Expression threw: \(error). \(message)", file: file, line: line)
    }
}
