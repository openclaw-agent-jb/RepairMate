/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import RepairMate

@MainActor
final class RepairMateToolsTests: XCTestCase {

  // MARK: - Tool Declaration Tests

  func testLookupTorqueSpecDeclaration() {
    let declaration = RepairMateToolDeclarations.lookupTorqueSpec
    
    XCTAssertEqual(declaration["name"] as? String, "lookup_torque_spec")
    XCTAssertNotNil(declaration["description"])
    XCTAssertEqual(declaration["behavior"] as? String, "BLOCKING")
    
    let params = declaration["parameters"] as? [String: Any]
    XCTAssertNotNil(params)
    XCTAssertEqual(params?["type"] as? String, "object")
    
    let properties = params?["properties"] as? [String: Any]
    XCTAssertNotNil(properties?["make"])
    XCTAssertNotNil(properties?["model"])
    XCTAssertNotNil(properties?["component"])
    XCTAssertNotNil(properties?["year"])
    XCTAssertNotNil(properties?["bolt_location"])
    
    let required = params?["required"] as? [String]
    XCTAssertEqual(required, ["make", "model", "component"])
  }

  func testLookupWiringDiagramDeclaration() {
    let declaration = RepairMateToolDeclarations.lookupWiringDiagram
    
    XCTAssertEqual(declaration["name"] as? String, "lookup_wiring_diagram")
    XCTAssertNotNil(declaration["description"])
    XCTAssertEqual(declaration["behavior"] as? String, "BLOCKING")
    
    let params = declaration["parameters"] as? [String: Any]
    let properties = params?["properties"] as? [String: Any]
    XCTAssertNotNil(properties?["system"])
    XCTAssertNotNil(properties?["make"])
    XCTAssertNotNil(properties?["model"])
    XCTAssertNotNil(properties?["year"])
    
    let required = params?["required"] as? [String]
    XCTAssertEqual(required, ["system", "make", "model"])
  }

  func testCheckPartCompatibilityDeclaration() {
    let declaration = RepairMateToolDeclarations.checkPartCompatibility
    
    XCTAssertEqual(declaration["name"] as? String, "check_part_compatibility")
    XCTAssertNotNil(declaration["description"])
    XCTAssertEqual(declaration["behavior"] as? String, "BLOCKING")
    
    let params = declaration["parameters"] as? [String: Any]
    let properties = params?["properties"] as? [String: Any]
    XCTAssertNotNil(properties?["part_number"])
    XCTAssertNotNil(properties?["make"])
    XCTAssertNotNil(properties?["model"])
    XCTAssertNotNil(properties?["year"])
    
    let required = params?["required"] as? [String]
    XCTAssertEqual(required, ["make", "model"])
  }

  func testAllDeclarationsArray() {
    let all = RepairMateToolDeclarations.all
    
    XCTAssertEqual(all.count, 3)
    
    let names = all.compactMap { $0["name"] as? String }
    XCTAssertTrue(names.contains("lookup_torque_spec"))
    XCTAssertTrue(names.contains("lookup_wiring_diagram"))
    XCTAssertTrue(names.contains("check_part_compatibility"))
  }

  func testToolNamesSet() {
    let names = RepairMateToolDeclarations.names
    
    XCTAssertEqual(names.count, 3)
    XCTAssertTrue(names.contains("lookup_torque_spec"))
    XCTAssertTrue(names.contains("lookup_wiring_diagram"))
    XCTAssertTrue(names.contains("check_part_compatibility"))
  }

  // MARK: - RepairMateToolHandler Tests

  func testCanHandleReturnsTrueForKnownTools() {
    XCTAssertTrue(RepairMateToolHandler.canHandle("lookup_torque_spec"))
    XCTAssertTrue(RepairMateToolHandler.canHandle("lookup_wiring_diagram"))
    XCTAssertTrue(RepairMateToolHandler.canHandle("check_part_compatibility"))
  }

  func testCanHandleReturnsFalseForUnknownTools() {
    XCTAssertFalse(RepairMateToolHandler.canHandle("execute"))
    XCTAssertFalse(RepairMateToolHandler.canHandle("unknown_tool"))
    XCTAssertFalse(RepairMateToolHandler.canHandle(""))
  }

  // MARK: - Task Building Tests (via integration)

  // These tests verify the task description builders work correctly
  // by checking that the handler properly delegates to the bridge

  @MainActor
  func testHandleTorqueSpecCall() async {
    let mockBridge = MockOpenClawBridge()
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-1",
      name: "lookup_torque_spec",
      args: [
        "make": "Honda",
        "model": "Civic",
        "year": "2015",
        "component": "alternator",
        "bolt_location": "upper mounting bolt"
      ]
    )
    
    _ = await handler.handle(call)
    
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("torque specification"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Honda"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Civic"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("alternator"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("upper mounting bolt"), true)
    XCTAssertEqual(mockBridge.lastToolName, "lookup_torque_spec")
  }

  @MainActor
  func testHandleWiringDiagramCall() async {
    let mockBridge = MockOpenClawBridge()
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-2",
      name: "lookup_wiring_diagram",
      args: [
        "system": "charging system",
        "make": "Toyota",
        "model": "Camry",
        "year": "2020"
      ]
    )
    
    _ = await handler.handle(call)
    
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("wiring diagram"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("charging system"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Toyota"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Camry"), true)
    XCTAssertEqual(mockBridge.lastToolName, "lookup_wiring_diagram")
  }

  @MainActor
  func testHandlePartCompatibilityCallWithPartNumber() async {
    let mockBridge = MockOpenClawBridge()
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-3",
      name: "check_part_compatibility",
      args: [
        "part_number": "ABC123",
        "make": "Ford",
        "model": "F-150",
        "year": "2018"
      ]
    )
    
    _ = await handler.handle(call)
    
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("ABC123"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Ford"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("F-150"), true)
    XCTAssertEqual(mockBridge.lastToolName, "check_part_compatibility")
  }

  @MainActor
  func testHandlePartCompatibilityCallWithoutPartNumber() async {
    let mockBridge = MockOpenClawBridge()
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-4",
      name: "check_part_compatibility",
      args: [
        "make": "Chevrolet",
        "model": "Silverado"
      ]
    )
    
    _ = await handler.handle(call)
    
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("compatible replacement parts"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Chevrolet"), true)
    XCTAssertEqual(mockBridge.lastDelegatedTask?.contains("Silverado"), true)
  }

  @MainActor
  func testHandleOmitsOptionalParametersWhenEmpty() async {
    let mockBridge = MockOpenClawBridge()
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-5",
      name: "lookup_torque_spec",
      args: [
        "make": "Honda",
        "model": "Accord",
        "component": "brake caliper"
        // No year, no bolt_location
      ]
    )
    
    _ = await handler.handle(call)
    
    let task = mockBridge.lastDelegatedTask ?? ""
    // Should contain the required fields
    XCTAssertTrue(task.contains("Honda"))
    XCTAssertTrue(task.contains("Accord"))
    XCTAssertTrue(task.contains("brake caliper"))
    // Should not contain empty optional fields in a malformed way
    XCTAssertFalse(task.contains("  ")) // No double spaces from empty values
  }

  @MainActor
  func testHandleReturnsSuccessResult() async {
    let mockBridge = MockOpenClawBridge()
    mockBridge.mockResult = .success("45 Nm (33 ft-lbs)")
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-6",
      name: "lookup_torque_spec",
      args: ["make": "Honda", "model": "Civic", "component": "alternator"]
    )
    
    let result = await handler.handle(call)
    
    if case .success(let message) = result {
      XCTAssertEqual(message, "45 Nm (33 ft-lbs)")
    } else {
      XCTFail("Expected success result")
    }
  }

  @MainActor
  func testHandleReturnsFailureResult() async {
    let mockBridge = MockOpenClawBridge()
    mockBridge.mockResult = .failure("Network timeout")
    let handler = RepairMateToolHandler(bridge: mockBridge)
    
    let call = GeminiFunctionCall(
      id: "call-7",
      name: "lookup_torque_spec",
      args: ["make": "Honda", "model": "Civic", "component": "alternator"]
    )
    
    let result = await handler.handle(call)
    
    if case .failure(let error) = result {
      XCTAssertEqual(error, "Network timeout")
    } else {
      XCTFail("Expected failure result")
    }
  }
}

// MARK: - Mock OpenClaw Bridge

@MainActor
private class MockOpenClawBridge: OpenClawBridge {
  var lastDelegatedTask: String?
  var lastToolName: String?
  var mockResult: ToolResult = .success("Mock result")
  
  override init() {
    // Call super.init() but we'll override the delegateTask method
    super.init()
  }
  
  override func delegateTask(task: String, toolName: String) async -> ToolResult {
    lastDelegatedTask = task
    lastToolName = toolName
    return mockResult
  }
}
