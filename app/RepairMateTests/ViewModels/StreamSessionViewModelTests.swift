import XCTest
import MWDATCore

@testable import RepairMate

private actor InvocationCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

@MainActor
private final class MainActorCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct DummyPermissionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class StreamSessionViewModelTests: XCTestCase {
    func testHandleStartStreamingWhenAlreadyGrantedStartsSessionWithoutRequest() async {
        let startCounter = InvocationCounter()
        let requestCounter = InvocationCounter()

        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .granted },
            permissionRequestProvider: { _ in
                await requestCounter.increment()
                return .denied
            },
            streamStartAction: { await startCounter.increment() }
        )

        await sut.handleStartStreaming()

        let startCalls = await startCounter.value()
        let requestCalls = await requestCounter.value()
        XCTAssertEqual(startCalls, 1)
        XCTAssertEqual(requestCalls, 0)
        XCTAssertFalse(sut.showError)
        XCTAssertEqual(sut.errorMessage, "")
    }

    func testHandleStartStreamingRequestsPermissionAndStartsWhenGranted() async {
        let startCounter = InvocationCounter()
        let requestCounter = InvocationCounter()

        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .denied },
            permissionRequestProvider: { _ in
                await requestCounter.increment()
                return .granted
            },
            streamStartAction: { await startCounter.increment() }
        )

        await sut.handleStartStreaming()

        let startCalls = await startCounter.value()
        let requestCalls = await requestCounter.value()
        XCTAssertEqual(startCalls, 1)
        XCTAssertEqual(requestCalls, 1)
        XCTAssertFalse(sut.showError)
    }

    func testHandleStartStreamingShowsPermissionDeniedWhenRequestDenied() async {
        let startCounter = InvocationCounter()

        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .denied },
            permissionRequestProvider: { _ in .denied },
            streamStartAction: { await startCounter.increment() }
        )

        await sut.handleStartStreaming()

        let startCalls = await startCounter.value()
        XCTAssertEqual(startCalls, 0)
        XCTAssertTrue(sut.showError)
        XCTAssertEqual(sut.errorMessage, "Permission denied")
    }

    func testHandleStartStreamingPermissionCheckErrorShowsPermissionErrorMessage() async {
        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in
                throw DummyPermissionError(message: "boom")
            },
            permissionRequestProvider: { _ in .granted }
        )

        await sut.handleStartStreaming()

        XCTAssertTrue(sut.showError)
        XCTAssertTrue(sut.errorMessage.hasPrefix("Permission error:"))
    }

    func testStopSessionUsesIPhoneStopActionInIPhoneMode() async {
        let streamStopCounter = InvocationCounter()
        let iPhoneStopCounter = MainActorCounter()

        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .granted },
            permissionRequestProvider: { _ in .granted },
            streamStopAction: { await streamStopCounter.increment() },
            iPhoneStopAction: {
                iPhoneStopCounter.increment()
            }
        )
        sut.streamingMode = .iPhone

        await sut.stopSession()

        let streamStopCalls = await streamStopCounter.value()
        XCTAssertEqual(streamStopCalls, 0)
        XCTAssertEqual(iPhoneStopCounter.value, 1)
    }

    func testStopSessionUsesStreamStopActionInGlassesMode() async {
        let streamStopCounter = InvocationCounter()

        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .granted },
            permissionRequestProvider: { _ in .granted },
            streamStopAction: { await streamStopCounter.increment() }
        )
        sut.streamingMode = .glasses

        await sut.stopSession()

        let streamStopCalls = await streamStopCounter.value()
        XCTAssertEqual(streamStopCalls, 1)
    }

    func testCapturePhotoInGlassesModeUsesStreamCapturePhotoAction() async {
        let captureCounter = MainActorCounter()
        
        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .granted },
            permissionRequestProvider: { _ in .granted },
            streamCapturePhotoAction: { captureCounter.increment() }
        )
        sut.streamingMode = .glasses

        sut.capturePhoto()

        XCTAssertEqual(captureCounter.value, 1)
        XCTAssertFalse(sut.showPhotoPreview)
        XCTAssertNil(sut.capturedPhoto)
    }

    func testCapturePhotoInIPhoneModeUsesCurrentVideoFrame() async {
        let captureCounter = MainActorCounter()
        let testImage = UIImage()

        let sut = StreamSessionViewModel(
            permissionStatusProvider: { _ in .granted },
            permissionRequestProvider: { _ in .granted },
            streamCapturePhotoAction: { captureCounter.increment() }
        )
        sut.streamingMode = .iPhone
        sut.currentVideoFrame = testImage

        sut.capturePhoto()

        XCTAssertEqual(captureCounter.value, 0)
        XCTAssertTrue(sut.showPhotoPreview)
        XCTAssertEqual(sut.capturedPhoto, testImage)
    }
}
