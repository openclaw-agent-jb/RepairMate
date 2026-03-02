/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import RepairMate

final class ToolCallModelsTests: XCTestCase {

  // MARK: - GeminiToolCall Tests

  func testGeminiToolCallParsingValid() {
    let json: [String: Any] = [
      "toolCall": [
        "functionCalls": [
          [
            "id": "call-123",
            "name": "execute",
            "args": [
              "task": "search for something"
            ]
          ],
          [
            "id": "call-456",
            "name": "lookup_torque_spec",
            "args": [
              "make": "Honda",
              "model": "Civic",
              "component": "alternator"
            ]
          ]
        ]
      ]
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNotNil(toolCall)
    XCTAssertEqual(toolCall?.functionCalls.count, 2)

    let firstCall = toolCall?.functionCalls[0]
    XCTAssertEqual(firstCall?.id, "call-123")
    XCTAssertEqual(firstCall?.name, "execute")
    XCTAssertEqual(firstCall?.args["task"] as? String, "search for something")

    let secondCall = toolCall?.functionCalls[1]
    XCTAssertEqual(secondCall?.id, "call-456")
    XCTAssertEqual(secondCall?.name, "lookup_torque_spec")
    XCTAssertEqual(secondCall?.args["make"] as? String, "Honda")
  }

  func testGeminiToolCallParsingMissingToolCall() {
    let json: [String: Any] = [
      "otherKey": "value"
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNil(toolCall)
  }

  func testGeminiToolCallParsingMissingFunctionCalls() {
    let json: [String: Any] = [
      "toolCall": [
        "otherKey": "value"
      ]
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNil(toolCall)
  }

  func testGeminiToolCallParsingEmptyFunctionCalls() {
    let json: [String: Any] = [
      "toolCall": [
        "functionCalls": []
      ]
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNotNil(toolCall)
    XCTAssertEqual(toolCall?.functionCalls.count, 0)
  }

  func testGeminiFunctionCallMissingId() {
    let json: [String: Any] = [
      "toolCall": [
        "functionCalls": [
          [
            "name": "execute",
            "args": [:]
          ]
        ]
      ]
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNotNil(toolCall)
    XCTAssertEqual(toolCall?.functionCalls.count, 0) // Should skip invalid calls
  }

  func testGeminiFunctionCallMissingName() {
    let json: [String: Any] = [
      "toolCall": [
        "functionCalls": [
          [
            "id": "call-123",
            "args": [:]
          ]
        ]
      ]
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNotNil(toolCall)
    XCTAssertEqual(toolCall?.functionCalls.count, 0) // Should skip invalid calls
  }

  func testGeminiFunctionCallDefaultArgs() {
    let json: [String: Any] = [
      "toolCall": [
        "functionCalls": [
          [
            "id": "call-123",
            "name": "execute"
            // No args key
          ]
        ]
      ]
    ]

    let toolCall = GeminiToolCall(json: json)
    XCTAssertNotNil(toolCall)
    XCTAssertEqual(toolCall?.functionCalls.count, 1)
    XCTAssertEqual(toolCall?.functionCalls[0].args.count, 0) // Empty dictionary as default
  }

  // MARK: - GeminiToolCallCancellation Tests

  func testGeminiToolCallCancellationParsing() {
    let json: [String: Any] = [
      "toolCallCancellation": [
        "ids": ["call-123", "call-456", "call-789"]
      ]
    ]

    let cancellation = GeminiToolCallCancellation(json: json)
    XCTAssertNotNil(cancellation)
    XCTAssertEqual(cancellation?.ids.count, 3)
    XCTAssertEqual(cancellation?.ids, ["call-123", "call-456", "call-789"])
  }

  func testGeminiToolCallCancellationMissingCancellation() {
    let json: [String: Any] = [
      "otherKey": "value"
    ]

    let cancellation = GeminiToolCallCancellation(json: json)
    XCTAssertNil(cancellation)
  }

  func testGeminiToolCallCancellationMissingIds() {
    let json: [String: Any] = [
      "toolCallCancellation": [
        "otherKey": "value"
      ]
    ]

    let cancellation = GeminiToolCallCancellation(json: json)
    XCTAssertNil(cancellation)
  }

  func testGeminiToolCallCancellationEmptyIds() {
    let json: [String: Any] = [
      "toolCallCancellation": [
        "ids": []
      ]
    ]

    let cancellation = GeminiToolCallCancellation(json: json)
    XCTAssertNotNil(cancellation)
    XCTAssertEqual(cancellation?.ids.count, 0)
  }

  // MARK: - ToolResult Tests

  func testToolResultSuccess() {
    let result = ToolResult.success("Task completed successfully")

    switch result {
    case .success(let message):
      XCTAssertEqual(message, "Task completed successfully")
    default:
      XCTFail("Expected success case")
    }
  }

  func testToolResultFailure() {
    let result = ToolResult.failure("Network error")

    switch result {
    case .failure(let error):
      XCTAssertEqual(error, "Network error")
    default:
      XCTFail("Expected failure case")
    }
  }

  func testToolResultResponseValueSuccess() {
    let result = ToolResult.success("Operation completed")
    let response = result.responseValue

    XCTAssertEqual(response["result"] as? String, "Operation completed")
    XCTAssertNil(response["error"])
  }

  func testToolResultResponseValueFailure() {
    let result = ToolResult.failure("Something went wrong")
    let response = result.responseValue

    XCTAssertEqual(response["error"] as? String, "Something went wrong")
    XCTAssertNil(response["result"])
  }

  // MARK: - ToolCallStatus Tests

  func testToolCallStatusIdle() {
    let status: ToolCallStatus = .idle
    XCTAssertEqual(status.displayText, "")
    XCTAssertFalse(status.isActive)
  }

  func testToolCallStatusExecuting() {
    let status: ToolCallStatus = .executing("execute")
    XCTAssertEqual(status.displayText, "Running: execute...")
    XCTAssertTrue(status.isActive)
  }

  func testToolCallStatusCompleted() {
    let status: ToolCallStatus = .completed("lookup_torque_spec")
    XCTAssertEqual(status.displayText, "Done: lookup_torque_spec")
    XCTAssertFalse(status.isActive)
  }

  func testToolCallStatusFailed() {
    let status: ToolCallStatus = .failed("search", "Timeout")
    XCTAssertEqual(status.displayText, "Failed: search - Timeout")
    XCTAssertFalse(status.isActive)
  }

  func testToolCallStatusCancelled() {
    let status: ToolCallStatus = .cancelled("execute")
    XCTAssertEqual(status.displayText, "Cancelled: execute")
    XCTAssertFalse(status.isActive)
  }

  func testToolCallStatusEquality() {
    XCTAssertEqual(ToolCallStatus.idle, ToolCallStatus.idle)
    XCTAssertEqual(ToolCallStatus.executing("test"), ToolCallStatus.executing("test"))
    XCTAssertEqual(ToolCallStatus.completed("test"), ToolCallStatus.completed("test"))
    XCTAssertEqual(ToolCallStatus.failed("test", "error"), ToolCallStatus.failed("test", "error"))
    XCTAssertEqual(ToolCallStatus.cancelled("test"), ToolCallStatus.cancelled("test"))

    XCTAssertNotEqual(ToolCallStatus.idle, ToolCallStatus.executing("test"))
    XCTAssertNotEqual(ToolCallStatus.executing("a"), ToolCallStatus.executing("b"))
    XCTAssertNotEqual(ToolCallStatus.failed("test", "a"), ToolCallStatus.failed("test", "b"))
  }

  // MARK: - ToolDeclarations Tests

  func testToolDeclarationsExecuteExists() {
    let execute = ToolDeclarations.execute
    XCTAssertEqual(execute["name"] as? String, "execute")
    XCTAssertNotNil(execute["description"])
    XCTAssertNotNil(execute["parameters"])
    XCTAssertEqual(execute["behavior"] as? String, "BLOCKING")
  }

  func testToolDeclarationsAllDeclarationsWithoutRepairMate() {
    let declarations = ToolDeclarations.allDeclarations(includeRepairMateTools: false)
    XCTAssertEqual(declarations.count, 1)
    XCTAssertEqual(declarations[0]["name"] as? String, "execute")
  }

  func testToolDeclarationsAllDeclarationsWithRepairMate() {
    let declarations = ToolDeclarations.allDeclarations(includeRepairMateTools: true)
    XCTAssertEqual(declarations.count, 4) // execute + 3 repairmate tools

    let names = declarations.compactMap { $0["name"] as? String }
    XCTAssertTrue(names.contains("execute"))
    XCTAssertTrue(names.contains("lookup_torque_spec"))
    XCTAssertTrue(names.contains("lookup_wiring_diagram"))
    XCTAssertTrue(names.contains("check_part_compatibility"))
  }

  func testExecuteParametersStructure() {
    let execute = ToolDeclarations.execute
    let params = execute["parameters"] as? [String: Any]
    XCTAssertNotNil(params)
    XCTAssertEqual(params?["type"] as? String, "object")
    XCTAssertNotNil(params?["properties"])

    let properties = params?["properties"] as? [String: Any]
    XCTAssertNotNil(properties?["task"])

    let taskParam = properties?["task"] as? [String: Any]
    XCTAssertEqual(taskParam?["type"] as? String, "string")
    XCTAssertNotNil(taskParam?["description"])

    let required = params?["required"] as? [String]
    XCTAssertEqual(required, ["task"])
  }
}
