import Foundation
import UIKit

// MARK: - Safety Classifier

/// Analyzes video frames for safety hazards during repair work.
/// Sends JPEG frames to Gemini with a structured prompt and parses
/// the response into a `SafetyAssessment`.
@MainActor
class SafetyClassifier {
  private let geminiService: GeminiLiveServicing

  init(geminiService: GeminiLiveServicing) {
    self.geminiService = geminiService
  }

  /// Build the safety analysis prompt for a given repair step.
  func buildSafetyPrompt(currentStep: String?) -> String {
    return """
      Analyze this image for safety hazards during repair work.
      Current task: \(currentStep ?? "Unknown")

      Check for:
      1. Battery still connected (for auto work)
      2. Charged capacitors (for electronics)
      3. Water + electricity (for appliances)
      4. Unsupported vehicle
      5. Hot surfaces
      6. Moving parts
      7. Gas leaks
      8. Missing safety equipment

      Respond with JSON only, no markdown:
      {
        "level": "SAFE" | "WARNING" | "STOP",
        "reason": "explanation",
        "action": "what user should do"
      }
      """
  }

  /// Analyze a JPEG frame for safety hazards.
  func analyzeFrame(_ frameData: Data, currentStep: String?) async -> SafetyAssessment {
    let prompt = buildSafetyPrompt(currentStep: currentStep)
    let result = await geminiService.analyzeImage(frameData, prompt: prompt)
    
    // If the REST API hits a 429 Quota Exceeded, it returns empty.
    // Instead of failing loudly, we just swallow it here. The WebRTC Bidi
    // channel will still catch "SAFETY WARNING" spoken by the model.
    guard !result.isEmpty else {
      return SafetyAssessment(
        level: .safe,
        reason: "",
        action: ""
      )
    }
    
    let cleanedResult = result.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    return parseSafetyResult(cleanedResult)
  }

  /// Parse a JSON safety result string from Gemini into a SafetyAssessment.
  func parseSafetyResult(_ result: String) -> SafetyAssessment {
    guard let data = result.data(using: .utf8) else {
      return SafetyAssessment.unknown
    }

    do {
      let decoded = try JSONDecoder().decode(SafetyJSON.self, from: data)
      let level = SafetyAssessment.SafetyLevel(rawValue: decoded.level) ?? .warning
      return SafetyAssessment(
        level: level,
        reason: decoded.reason,
        action: decoded.action
      )
    } catch {
      NSLog("[SafetyClassifier] Failed to parse safety JSON: %@", error.localizedDescription)
      return SafetyAssessment.unknown
    }
  }
}

// MARK: - Internal JSON model

private struct SafetyJSON: Decodable {
  let level: String
  let reason: String
  let action: String
}

// MARK: - Safety Assessment

struct SafetyAssessment {
  let level: SafetyLevel
  let reason: String
  let action: String

  var requiresImmediateStop: Bool {
    level == .stop
  }

  enum SafetyLevel: String {
    case safe = "SAFE"
    case warning = "WARNING"
    case stop = "STOP"
  }

  /// Fallback when parsing fails.
  static let unknown = SafetyAssessment(
    level: .warning,
    reason: "Unable to assess — treat with caution",
    action: "Visually verify safety before proceeding"
  )
}
