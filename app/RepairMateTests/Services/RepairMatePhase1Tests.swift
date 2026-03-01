import Foundation
import XCTest

@testable import RepairMate

// MARK: - RepairDomain Tests

@MainActor
final class RepairDomainTests: XCTestCase {

  func testAllCasesContainsFourDomains() {
    XCTAssertEqual(RepairDomain.allCases.count, 4)
  }

  func testEachDomainHasAnIcon() {
    for domain in RepairDomain.allCases {
      XCTAssertFalse(domain.icon.isEmpty, "\(domain.rawValue) should have an icon")
    }
  }

  func testEachDomainHasASystemPrompt() {
    for domain in RepairDomain.allCases {
      XCTAssertFalse(domain.systemPrompt.isEmpty, "\(domain.rawValue) should have a system prompt")
    }
  }

  func testAutoPromptContainsSafetyContent() {
    let prompt = RepairDomain.auto.systemPrompt
    XCTAssertTrue(prompt.contains("battery"), "Auto prompt should mention battery safety")
    XCTAssertTrue(prompt.contains("jack stands"), "Auto prompt should mention jack stands")
  }

  func testElectronicsPromptContainsESD() {
    let prompt = RepairDomain.electronics.systemPrompt
    XCTAssertTrue(prompt.contains("ESD"), "Electronics prompt should mention ESD precautions")
    XCTAssertTrue(prompt.contains("capacitor"), "Electronics prompt should mention capacitors")
  }

  func testAppliancesPromptContainsWaterWarning() {
    let prompt = RepairDomain.appliances.systemPrompt
    XCTAssertTrue(prompt.contains("water"), "Appliances prompt should mention water safety")
    XCTAssertTrue(prompt.contains("unplugged") || prompt.contains("Unplug"),
                  "Appliances prompt should mention unplugging")
  }

  func testHVACPromptContainsRefrigerant() {
    let prompt = RepairDomain.hvac.systemPrompt
    XCTAssertTrue(prompt.contains("refrigerant"), "HVAC prompt should mention refrigerant")
    XCTAssertTrue(prompt.contains("EPA"), "HVAC prompt should mention EPA certification")
  }

  func testDomainRawValues() {
    XCTAssertEqual(RepairDomain.auto.rawValue, "Auto Repair")
    XCTAssertEqual(RepairDomain.electronics.rawValue, "Electronics")
    XCTAssertEqual(RepairDomain.appliances.rawValue, "Appliances")
    XCTAssertEqual(RepairDomain.hvac.rawValue, "HVAC")
  }
}

// MARK: - RepairMateSessionManager Tests

@MainActor
final class RepairMateSessionManagerTests: XCTestCase {

  func testStartSessionSetsCurrentDomain() {
    let sut = RepairMateSessionManager()

    sut.startSession(domain: .auto)

    XCTAssertEqual(sut.currentDomain, .auto)
    XCTAssertEqual(sut.currentStep, 0)
    XCTAssertNotNil(sut.workflowState)
  }

  func testStartSessionWithProcedureSetsCurrentProcedure() {
    let sut = RepairMateSessionManager()
    let procedure = makeTestProcedure()

    sut.startSession(domain: .auto, procedure: procedure)

    XCTAssertEqual(sut.currentDomain, .auto)
    XCTAssertEqual(sut.currentProcedure?.id, procedure.id)
    XCTAssertEqual(sut.workflowState?.totalSteps, procedure.steps.count)
  }

  func testBuildSystemPromptReturnsEmptyWhenNoDomain() {
    let sut = RepairMateSessionManager()

    let prompt = sut.buildSystemPrompt()

    XCTAssertTrue(prompt.isEmpty)
  }

  func testBuildSystemPromptContainsDomainContent() {
    let sut = RepairMateSessionManager()
    sut.startSession(domain: .electronics)

    let prompt = sut.buildSystemPrompt()

    XCTAssertTrue(prompt.contains("ESD"), "Prompt should contain electronics safety rules")
    XCTAssertTrue(prompt.contains("RepairMate"), "Prompt should identify as RepairMate")
  }

  func testBuildSystemPromptIncludesProcedureDetails() {
    let sut = RepairMateSessionManager()
    let procedure = makeTestProcedure()
    sut.startSession(domain: .auto, procedure: procedure)

    let prompt = sut.buildSystemPrompt()

    XCTAssertTrue(prompt.contains("Test Alternator Replacement"))
    XCTAssertTrue(prompt.contains("10mm socket"))
    XCTAssertTrue(prompt.contains("Disconnect battery"))
  }

  func testAdvanceStepIncrementsCurrentStep() {
    let sut = RepairMateSessionManager()
    sut.startSession(domain: .auto)

    sut.advanceStep()

    XCTAssertEqual(sut.currentStep, 1)
    XCTAssertEqual(sut.workflowState?.currentStep, 1)
  }

  func testRecordSafetyAcknowledgementAppendsRule() {
    let sut = RepairMateSessionManager()
    sut.startSession(domain: .auto)

    sut.recordSafetyAcknowledgement("Battery disconnected")

    XCTAssertEqual(sut.workflowState?.safetyAcknowledged, ["Battery disconnected"])
  }

  func testSaveNoteAppendsToNotes() {
    let sut = RepairMateSessionManager()
    sut.startSession(domain: .auto)

    sut.saveNote("Bolt was rusted")
    sut.saveNote("Used penetrating oil")

    XCTAssertEqual(sut.workflowState?.notes, ["Bolt was rusted", "Used penetrating oil"])
  }

  func testEndSessionClearsAllState() {
    let sut = RepairMateSessionManager()
    sut.startSession(domain: .auto, procedure: makeTestProcedure())
    sut.advanceStep()

    sut.endSession()

    XCTAssertNil(sut.currentDomain)
    XCTAssertNil(sut.currentProcedure)
    XCTAssertEqual(sut.currentStep, 0)
    XCTAssertNil(sut.workflowState)
  }

  func testWorkflowStateSessionIdIsUnique() {
    let sut = RepairMateSessionManager()

    sut.startSession(domain: .auto)
    let firstId = sut.workflowState?.sessionId

    sut.startSession(domain: .electronics)
    let secondId = sut.workflowState?.sessionId

    XCTAssertNotNil(firstId)
    XCTAssertNotNil(secondId)
    XCTAssertNotEqual(firstId, secondId)
  }

  // MARK: - Helpers

  private func makeTestProcedure() -> RepairProcedure {
    RepairProcedure(
      id: "test-alternator-001",
      name: "Test Alternator Replacement",
      domain: "auto",
      difficulty: "intermediate",
      estimatedTime: "45-60 minutes",
      tools: ["10mm socket", "12mm socket", "ratchet"],
      steps: [
        RepairStep(
          number: 1,
          title: "Safety Preparation",
          action: "Disconnect battery",
          visualCues: "Black cable, minus sign",
          safetyWarning: "Prevents short circuits",
          torqueSpec: nil
        ),
        RepairStep(
          number: 2,
          title: "Access",
          action: "Remove engine cover",
          visualCues: "Plastic clips",
          safetyWarning: nil,
          torqueSpec: nil
        ),
      ],
      safetyWarnings: ["Disconnect battery before starting", "Engine may be hot"]
    )
  }
}

// MARK: - SafetyClassifier Tests

@MainActor
final class SafetyClassifierTests: XCTestCase {

  // Minimal mock conforming to GeminiLiveServicing for SafetyClassifier tests.
  private final class MockSafetyGeminiService: GeminiLiveServicing {
    var connectionState: GeminiConnectionState = .disconnected
    var isModelSpeaking: Bool = false
    var systemInstructionOverride: String?
    var onAudioReceived: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?
    var onInputTranscription: ((String) -> Void)?
    var onOutputTranscription: ((String) -> Void)?
    var onToolCall: ((GeminiToolCall) -> Void)?
    var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)?
    func connect() async -> Bool { true }
    func disconnect() {}
    func sendAudio(data: Data) {}
    func sendVideoFrame(image: UIImage) {}
    func sendToolResponse(_ response: [String: Any]) {}
    func sendClientContent(turns: [ConversationTurn]) {}
    func analyzeImage(_ frame: Data, prompt: String) async -> String { "" }
    func enableRepairMateMode(domain: String, procedure: String?) {}
    func disableRepairMateMode() {}
    func clearSession() {}
  }

  func testParseSafetyResultWithValidJSON() {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let json = """
      {"level": "WARNING", "reason": "Battery still connected", "action": "Disconnect negative terminal"}
      """
    let result = sut.parseSafetyResult(json)

    XCTAssertEqual(result.level, .warning)
    XCTAssertEqual(result.reason, "Battery still connected")
    XCTAssertEqual(result.action, "Disconnect negative terminal")
    XCTAssertFalse(result.requiresImmediateStop)
  }

  func testParseSafetyResultWithStopLevel() {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let json = """
      {"level": "STOP", "reason": "Vehicle unsupported", "action": "Place on jack stands immediately"}
      """
    let result = sut.parseSafetyResult(json)

    XCTAssertEqual(result.level, .stop)
    XCTAssertTrue(result.requiresImmediateStop)
  }

  func testParseSafetyResultWithSafeLevel() {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let json = """
      {"level": "SAFE", "reason": "No hazards detected", "action": "Continue"}
      """
    let result = sut.parseSafetyResult(json)

    XCTAssertEqual(result.level, .safe)
    XCTAssertFalse(result.requiresImmediateStop)
  }

  func testParseSafetyResultWithInvalidJSONReturnsUnknown() {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let result = sut.parseSafetyResult("not valid json at all")

    XCTAssertEqual(result.level, .warning)
    XCTAssertTrue(result.reason.contains("Unable to assess"))
  }

  func testBuildSafetyPromptIncludesCurrentStep() {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let prompt = sut.buildSafetyPrompt(currentStep: "Removing alternator bolts")

    XCTAssertTrue(prompt.contains("Removing alternator bolts"))
    XCTAssertTrue(prompt.contains("SAFE"))
    XCTAssertTrue(prompt.contains("WARNING"))
    XCTAssertTrue(prompt.contains("STOP"))
  }

  func testBuildSafetyPromptWithNilStepUsesUnknown() {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let prompt = sut.buildSafetyPrompt(currentStep: nil)

    XCTAssertTrue(prompt.contains("Unknown"))
  }

  func testAnalyzeFrameReturnsDefaultSafeAssessment() async {
    let service = MockSafetyGeminiService()
    let sut = SafetyClassifier(geminiService: service)

    let result = await sut.analyzeFrame(Data([0xFF, 0xD8]), currentStep: "Test step")

    XCTAssertEqual(result.level, .safe)
    XCTAssertFalse(result.requiresImmediateStop)
  }
}
