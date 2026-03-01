import Foundation
import FirebaseFirestore  // ← Step 1: uncomment after adding FirebaseFirestore via Swift Package Manager

// MARK: - FirestoreServicing Protocol

/// Abstraction over Firestore for testing.
/// All methods throw on network/auth failure so callers can degrade gracefully.
protocol FirestoreServicing: AnyObject {
    /// Fetch repair procedures for a specific domain, ordered by difficulty.
    func fetchProcedures(domain: RepairDomain) async throws -> [RepairProcedure]

    /// Upsert workflow state for the current session.
    func saveWorkflow(_ workflow: WorkflowState) async throws

    /// Append a WARNING or STOP safety event to the safetyLogs collection.
    func logSafetyEvent(_ assessment: SafetyAssessment, sessionId: String) async throws
}

// MARK: - FirestoreService

/// Concrete Firestore implementation backed by the Firebase iOS SDK.
///
/// **SDK note:** Requires the `FirebaseFirestore` package to be added in Xcode:
///   Product → Swift Packages → Add Package
///   URL: https://github.com/firebase/firebase-ios-sdk
///   Package: FirebaseFirestore
///
/// `GoogleService-Info.plist` must also be added to the RepairMate target.
final class FirestoreService: FirestoreServicing {

    // Step 2: uncomment after adding SDK
    private let db = Firestore.firestore()

    // MARK: - Init

    init() {
        NSLog("[FirestoreService] Initialized (SDK not yet linked — calls will no-op)")
    }

    // MARK: - FirestoreServicing

    func fetchProcedures(domain: RepairDomain) async throws -> [RepairProcedure] {
        // ── Replace this stub with the live implementation once SDK is linked ──
        //
        let snapshot = try await db
            .collection("procedures")
            .whereField("domain", isEqualTo: domain.firestoreKey)
            .order(by: "difficulty")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: RepairProcedure.self)
        }
    }

    func saveWorkflow(_ workflow: WorkflowState) async throws {
        // ── Replace this stub with the live implementation once SDK is linked ──
        //
        let data = try Firestore.Encoder().encode(workflow)
        try await db
            .collection("workflows")
            .document(workflow.sessionId)
            .setData(data.merging([
                "lastUpdated": FieldValue.serverTimestamp(),
                "status": "active"
            ]) { _, new in new })
    }

    func logSafetyEvent(_ assessment: SafetyAssessment, sessionId: String) async throws {
        guard assessment.requiresImmediateStop || assessment.level == .warning else {
            return  // Only log WARNING / STOP
        }

        // ── Replace this stub with the live implementation once SDK is linked ──
        //
        let data: [String: Any] = [
            "sessionId": sessionId,
            "timestamp": FieldValue.serverTimestamp(),
            "level": assessment.level.rawValue,
            "reason": assessment.reason,
            "action": assessment.action
        ]
        try await db.collection("safetyLogs").addDocument(data: data)
    }
}

// MARK: - Helpers

private extension RepairDomain {
    /// The lowercase key stored in Firestore documents.
    var firestoreKey: String {
        switch self {
        case .auto:        return "auto"
        case .electronics: return "electronics"
        case .appliances:  return "appliances"
        case .hvac:        return "hvac"
        }
    }
}
