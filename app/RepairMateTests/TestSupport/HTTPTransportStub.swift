import Foundation

actor HTTPTransportStub {
    struct StubResponse {
        let statusCode: Int
        let body: Data
        let headers: [String: String]?
    }

    enum StubbedResult {
        case response(StubResponse)
        case error(Error)
    }

    private var queue: [StubbedResult] = []
    private var requests: [URLRequest] = []

    func enqueue(statusCode: Int, body: Data = Data(), headers: [String: String]? = nil) {
        queue.append(.response(.init(statusCode: statusCode, body: body, headers: headers)))
    }

    func enqueue(jsonObject: Any, statusCode: Int) throws {
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        enqueue(statusCode: statusCode, body: data, headers: ["Content-Type": "application/json"])
    }

    func enqueue(error: Error) {
        queue.append(.error(error))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queue.isEmpty else {
            throw NSError(domain: "HTTPTransportStub", code: -1, userInfo: [NSLocalizedDescriptionKey: "No stubbed response available"])
        }

        let next = queue.removeFirst()
        switch next {
        case .error(let error):
            throw error
        case .response(let response):
            let http = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: response.headers
            )!
            return (response.body, http)
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

enum TestHTTPError: Error {
    case simulated
}

