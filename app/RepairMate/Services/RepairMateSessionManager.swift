import Foundation

// MARK: - RepairMate Session Manager

/// Manages the active repair session: domain, procedure, step tracking, and workflow state.
/// FirestoreServicing is injected optionally — nil means offline/test mode.
@MainActor
class RepairMateSessionManager: ObservableObject {
  @Published var currentDomain: RepairDomain?
  @Published var currentProcedure: RepairProcedure?
  @Published var currentStep: Int = 0
  @Published var workflowState: WorkflowState?
  @Published var procedures: [RepairProcedure] = []
  @Published var isLoadingProcedures: Bool = false

  private let firestoreService: FirestoreServicing?

  init(firestoreService: FirestoreServicing? = nil) {
    self.firestoreService = firestoreService
  }

  /// Start a new repair session for the given domain and optional procedure.
  /// Also kicks off an async fetch of available procedures for the domain.
  func startSession(domain: RepairDomain, procedure: RepairProcedure? = nil) {
    currentDomain = domain
    currentProcedure = procedure
    currentStep = 0
    initializeWorkflow()
    loadDomainContext(domain)

    NSLog("[RepairMate] Session started — domain: %@, procedure: %@",
          domain.rawValue, procedure?.name ?? "none")
  }

  /// Build the full system prompt for the current session, combining domain expertise
  /// with procedure-specific context and safety rules.
  func buildSystemPrompt() -> String {
    guard let domain = currentDomain else {
      return ""
    }

    let basePrompt = domain.systemPrompt
    let safetyRules = getSafetyRules(for: domain)

    var prompt = """
      \(basePrompt)

      ADDITIONAL SAFETY RULES:
      \(safetyRules)

      VISUAL SAFETY MONITORING: You can see through the user's glasses camera. If you spot any safety hazard in the video — bare live wires, unsupported vehicle, connected battery during electrical work, charged capacitors, gas smell mentioned, hot surfaces, or missing PPE — immediately say "SAFETY WARNING:" followed by what you see and what to do. Do not wait to be asked.
      """

    if let procedure = currentProcedure {
      let stepDescriptions = procedure.steps.map { step in
        var desc = "Step \(step.number): \(step.title) — \(step.action)"
        if let warning = step.safetyWarning {
          desc += " ⚠️ \(warning)"
        }
        if let torque = step.torqueSpec {
          desc += " 🔧 Torque: \(torque)"
        }
        return desc
      }.joined(separator: "\n")

      prompt += """


        CURRENT PROCEDURE: \(procedure.name)
        Difficulty: \(procedure.difficulty)
        Estimated Time: \(procedure.estimatedTime)
        Tools Needed: \(procedure.tools.joined(separator: ", "))

        STEPS:
        \(stepDescriptions)

        SAFETY WARNINGS:
        \(procedure.safetyWarnings.joined(separator: "\n"))

        You are currently on step \(currentStep + 1) of \(procedure.steps.count).
        """
    }

    return prompt
  }

  /// Advance to the next step in the current procedure.
  func advanceStep() {
    currentStep += 1
    updateWorkflowState()
    NSLog("[RepairMate] Advanced to step %d", currentStep)
  }

  /// Record that the user acknowledged a safety warning.
  func recordSafetyAcknowledgement(_ rule: String) {
    workflowState?.safetyAcknowledged.append(rule)
  }

  /// Save a user note to the current workflow.
  func saveNote(_ note: String) {
    workflowState?.notes.append(note)
  }

  /// End the current session and clear all state.
  func endSession() {
    NSLog("[RepairMate] Session ended — domain: %@", currentDomain?.rawValue ?? "none")
    currentDomain = nil
    currentProcedure = nil
    currentStep = 0
    workflowState = nil
  }

  // MARK: - Private

  private func initializeWorkflow() {
    workflowState = WorkflowState(
      sessionId: UUID().uuidString,
      domain: currentDomain?.rawValue ?? "",
      procedure: currentProcedure?.name ?? "",
      currentStep: 0,
      totalSteps: currentProcedure?.steps.count ?? 0,
      startTime: Date(),
      safetyAcknowledged: [],
      notes: []
    )
  }

  /// Fetch available procedures for the domain from Firestore.
  /// Runs asynchronously — the session starts immediately without waiting for results.
  private func loadDomainContext(_ domain: RepairDomain) {
    guard let service = firestoreService else { return }
    isLoadingProcedures = true
    Task {
      do {
        let fetchedProcedures = try await service.fetchProcedures(domain: domain)
        NSLog("[RepairMate] Loaded %d procedure(s) for domain: %@", fetchedProcedures.count, domain.rawValue)
        await MainActor.run {
          self.procedures = fetchedProcedures
          self.isLoadingProcedures = false
        }
      } catch {
        NSLog("[RepairMate] Failed to load domain context: %@", error.localizedDescription)
        await MainActor.run {
          self.isLoadingProcedures = false
        }
      }
    }
  }


  private func updateWorkflowState() {
    workflowState?.currentStep = currentStep
    // Phase 2: Persist to Firestore
    guard let workflow = workflowState, let service = firestoreService else { return }
    Task {
      do {
        try await service.saveWorkflow(workflow)
      } catch {
        NSLog("[RepairMate] Failed to save workflow: %@", error.localizedDescription)
      }
    }
  }

  private func getSafetyRules(for domain: RepairDomain) -> String {
    switch domain {
    case .auto:
      return """
        - Disconnect battery before electrical work
        - Use jack stands — never work under a vehicle on a jack alone
        - Keep fire extinguisher nearby when working near fuel systems
        - Wear safety glasses and gloves
        """
    case .electronics:
      return """
        - Discharge all capacitors before touching components
        - Wear an ESD wrist strap connected to ground
        - Use proper ventilation when soldering
        - Never work on plugged-in devices
        """
    case .appliances:
      return """
        - Unplug appliance before any work
        - Shut off water supply for plumbing-connected appliances
        - Shut off gas for gas-connected appliances
        - Watch for sharp sheet metal edges
        """
    case .hvac:
      return """
        - Turn off breaker — verify with multimeter before touching
        - Discharge capacitors before handling
        - Never handle refrigerant without EPA certification
        - Check for gas leaks with soap solution
        """
    }
  }
}

// MARK: - Models

struct WorkflowState: Codable {
  let sessionId: String
  let domain: String
  let procedure: String
  var currentStep: Int
  let totalSteps: Int
  let startTime: Date
  var safetyAcknowledged: [String]
  var notes: [String]
}

struct RepairProcedure: Codable, Identifiable {
  let id: String
  let name: String
  let domain: String
  let difficulty: String
  let estimatedTime: String
  let tools: [String]
  let steps: [RepairStep]
  let safetyWarnings: [String]
}

struct RepairStep: Codable {
  let number: Int
  let title: String
  let action: String
  let visualCues: String?
  let safetyWarning: String?
  let torqueSpec: String?
}
