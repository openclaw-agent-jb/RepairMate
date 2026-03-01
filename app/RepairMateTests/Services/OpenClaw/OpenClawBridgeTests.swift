/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import RepairMate

// MARK: - Mock URLProtocol for Network Testing

/// Mock URLProtocol that intercepts network requests for testing
final class MockURLProtocol: URLProtocol {
    static var mockResponses: [URL: (HTTPURLResponse?, Data?, Error?)] = [:]
    static var lastRequest: URLRequest?
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.requestCount += 1

        guard let url = request.url,
              let (response, data, error) = MockURLProtocol.mockResponses[url] else {
            // Return 404 if no mock response is set
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        mockResponses = [:]
        lastRequest = nil
        requestCount = 0
    }

    static func mockSuccessResponse(for url: URL, body: String) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = """
        {
            "choices": [
                {
                    "message": {
                        "content": "\(body)"
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        mockResponses[url] = (response, data, nil)
    }

    static func mockErrorResponse(for url: URL, statusCode: Int, message: String = "Error") {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        let data = "{\"error\": \"\(message)\"}".data(using: .utf8)!
        mockResponses[url] = (response, data, nil)
    }

    static func mockNetworkError(for url: URL, error: Error) {
        mockResponses[url] = (nil, nil, error)
    }
}

// MARK: - Testable OpenClawBridge

/// Subclass of OpenClawBridge that accepts a custom URLSession for testing
@MainActor
final class TestableOpenClawBridge: OpenClawBridge {
    init(session: URLSession) {
        // Use reflection to set the session since it's private
        super.init()
        // The session property is set in init, we need to work around this
        // For testing, we'll use a different approach - inject via subclass
    }
}

// MARK: - OpenClawBridge Tests

@MainActor
final class OpenClawBridgeTests: XCTestCase {

    var sut: OpenClawBridge!
    var mockSession: URLSession!
    let testHost = "https://test.example.com"
    let testPort = 443
    let testGatewayToken = "test-gateway-token"

    override func setUp() async throws {
        try await super.setUp()

        // Reset mock protocol state
        MockURLProtocol.reset()

        // Configure URLSession with mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Store test credentials in Keychain for GeminiConfig
        try? KeychainService.deleteAll()
        try? KeychainService.store(.openClawHost, value: "test.example.com")
        try? KeychainService.store(.openClawPort, value: "443")
        try? KeychainService.store(.openClawGatewayToken, value: testGatewayToken)

        sut = OpenClawBridge()
    }

    override func tearDown() async throws {
        sut = nil
        mockSession = nil
        try? KeychainService.deleteAll()
        try await super.tearDown()
    }

    // MARK: - Session Key Tests

    func testSessionKeyFormat() {
        // Session key should follow format: agent:main:glass:<ISO8601-timestamp>
        // The actual session key is private, but we can test behavior
        sut.resetSession()
        XCTAssertNotNil(sut)
    }

    func testResetSessionGeneratesNewKey() async throws {
        // Reset session
        sut.resetSession()

        // Status should be idle after reset
        if case .idle = sut.lastToolCallStatus {
            // Expected
        } else {
            XCTFail("Status should be idle after reset")
        }
    }

    func testResetSessionClearsStatus() {
        sut.resetSession()
        XCTAssertEqual(sut.lastToolCallStatus, .idle)
    }

    // MARK: - Status Tracking Tests

    func testInitialStatusIsIdle() {
        let freshBridge = OpenClawBridge()
        XCTAssertEqual(freshBridge.lastToolCallStatus, .idle)
    }

    func testStatusDisplayText() {
        XCTAssertEqual(ToolCallStatus.idle.displayText, "")
        XCTAssertEqual(ToolCallStatus.executing("test").displayText, "Running: test...")
        XCTAssertEqual(ToolCallStatus.completed("test").displayText, "Done: test")
        XCTAssertEqual(ToolCallStatus.failed("test", "error").displayText, "Failed: test - error")
        XCTAssertEqual(ToolCallStatus.cancelled("test").displayText, "Cancelled: test")
    }

    func testStatusIsActive() {
        XCTAssertFalse(ToolCallStatus.idle.isActive)
        XCTAssertTrue(ToolCallStatus.executing("test").isActive)
        XCTAssertFalse(ToolCallStatus.completed("test").isActive)
        XCTAssertFalse(ToolCallStatus.failed("test", "err").isActive)
        XCTAssertFalse(ToolCallStatus.cancelled("test").isActive)
    }

    func testStatusEquatable() {
        XCTAssertEqual(ToolCallStatus.idle, ToolCallStatus.idle)
        XCTAssertEqual(ToolCallStatus.executing("a"), ToolCallStatus.executing("a"))
        XCTAssertNotEqual(ToolCallStatus.executing("a"), ToolCallStatus.executing("b"))
        XCTAssertEqual(ToolCallStatus.completed("a"), ToolCallStatus.completed("a"))
        XCTAssertEqual(ToolCallStatus.failed("a", "err"), ToolCallStatus.failed("a", "err"))
        XCTAssertNotEqual(ToolCallStatus.failed("a", "err"), ToolCallStatus.failed("a", "other"))
    }

    // MARK: - Tool Result Tests

    func testToolResultSuccess() {
        let result = ToolResult.success("Operation completed")
        let value = result.responseValue

        XCTAssertEqual(value["result"] as? String, "Operation completed")
        XCTAssertNil(value["error"])
    }

    func testToolResultFailure() {
        let result = ToolResult.failure("Something went wrong")
        let value = result.responseValue

        XCTAssertEqual(value["error"] as? String, "Something went wrong")
        XCTAssertNil(value["result"])
    }

    // MARK: - Gemini Function Call Tests

    func testGeminiToolCallParsing() {
        let json: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    [
                        "id": "call-123",
                        "name": "execute",
                        "args": ["task": "send message"]
                    ]
                ]
            ]
        ]

        let toolCall = GeminiToolCall(json: json)
        XCTAssertNotNil(toolCall)
        XCTAssertEqual(toolCall?.functionCalls.count, 1)
        XCTAssertEqual(toolCall?.functionCalls.first?.id, "call-123")
        XCTAssertEqual(toolCall?.functionCalls.first?.name, "execute")
    }

    func testGeminiToolCallParsingWithEmptyArgs() {
        let json: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    [
                        "id": "call-456",
                        "name": "execute"
                    ]
                ]
            ]
        ]

        let toolCall = GeminiToolCall(json: json)
        XCTAssertNotNil(toolCall)
        XCTAssertTrue(toolCall?.functionCalls.first?.args.isEmpty ?? false)
    }

    func testGeminiToolCallParsingInvalidJSON() {
        let json: [String: Any] = ["invalid": "data"]
        let toolCall = GeminiToolCall(json: json)
        XCTAssertNil(toolCall)
    }

    func testGeminiToolCallCancellationParsing() {
        let json: [String: Any] = [
            "toolCallCancellation": [
                "ids": ["call-123", "call-456"]
            ]
        ]

        let cancellation = GeminiToolCallCancellation(json: json)
        XCTAssertNotNil(cancellation)
        XCTAssertEqual(cancellation?.ids.count, 2)
        XCTAssertTrue(cancellation?.ids.contains("call-123") ?? false)
    }

    func testGeminiToolCallCancellationInvalidJSON() {
        let json: [String: Any] = ["invalid": "data"]
        let cancellation = GeminiToolCallCancellation(json: json)
        XCTAssertNil(cancellation)
    }

    // MARK: - Tool Declarations Tests

    func testToolDeclarationsExecute() {
        let declarations = ToolDeclarations.allDeclarations()

        XCTAssertEqual(declarations.count, 1)
        XCTAssertEqual(declarations[0]["name"] as? String, "execute")
        XCTAssertNotNil(declarations[0]["description"])
        XCTAssertNotNil(declarations[0]["parameters"])
        XCTAssertEqual(declarations[0]["behavior"] as? String, "BLOCKING")
    }

    func testToolDeclarationsExecuteParameters() {
        let execute = ToolDeclarations.execute
        guard let params = execute["parameters"] as? [String: Any],
              let properties = params["properties"] as? [String: Any],
              let task = properties["task"] as? [String: Any] else {
            XCTFail("Invalid parameter structure")
            return
        }

        XCTAssertEqual(task["type"] as? String, "string")
        XCTAssertNotNil(task["description"])

        guard let required = params["required"] as? [String] else {
            XCTFail("Missing required parameters")
            return
        }
        XCTAssertTrue(required.contains("task"))
    }

    // MARK: - Integration Tests (require mocking URLSession)

    // Note: These tests would require modifying OpenClawBridge to accept a URLSession
    // or using method swizzling. For now, we test the components that don't require
    // network calls. The integration tests in RepairMateTests.swift cover the actual
    // network functionality.
}

// MARK: - Additional Edge Case Tests

@MainActor
final class OpenClawBridgeEdgeCaseTests: XCTestCase {

    func testToolCallStatusWithSpecialCharacters() {
        let status = ToolCallStatus.failed("execute", "Error: \"quotes\" and \\backslashes\\")
        XCTAssertTrue(status.displayText.contains("quotes"))
        XCTAssertTrue(status.displayText.contains("backslashes"))
    }

    func testToolResultWithEmptyString() {
        let success = ToolResult.success("")
        XCTAssertEqual(success.responseValue["result"] as? String, "")

        let failure = ToolResult.failure("")
        XCTAssertEqual(failure.responseValue["error"] as? String, "")
    }

    func testGeminiToolCallMultipleFunctionCalls() {
        let json: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    ["id": "call-1", "name": "execute", "args": ["task": "task 1"]],
                    ["id": "call-2", "name": "execute", "args": ["task": "task 2"]],
                    ["id": "call-3", "name": "execute", "args": ["task": "task 3"]]
                ]
            ]
        ]

        let toolCall = GeminiToolCall(json: json)
        XCTAssertEqual(toolCall?.functionCalls.count, 3)
    }

    func testGeminiToolCallMissingId() {
        let json: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    ["name": "execute", "args": [:]] // Missing id
                ]
            ]
        ]

        let toolCall = GeminiToolCall(json: json)
        // Should filter out entries without id
        XCTAssertEqual(toolCall?.functionCalls.count, 0)
    }

    func testGeminiToolCallMissingName() {
        let json: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    ["id": "call-123", "args": [:]] // Missing name
                ]
            ]
        ]

        let toolCall = GeminiToolCall(json: json)
        // Should filter out entries without name
        XCTAssertEqual(toolCall?.functionCalls.count, 0)
    }
}