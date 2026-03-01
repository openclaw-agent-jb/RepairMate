/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import UIKit
import XCTest

@testable import RepairMate

final class PixelBufferUtilsTests: XCTestCase {
    // MARK: - Create Pixel Buffer Tests

    func testCreatePixelBufferFromImage() {
        // Create a test image using SF Symbols (guaranteed to be available)
        let image = UIImage(systemName: "star.fill")!
        let buffer = PixelBufferUtils.createPixelBuffer(from: image)

        XCTAssertNotNil(buffer, "Should create pixel buffer from valid image")

        // Verify dimensions match the image's CGImage dimensions
        guard let cgImage = image.cgImage else {
            XCTFail("Should have CGImage")
            return
        }

        XCTAssertEqual(CVPixelBufferGetWidth(buffer!), cgImage.width, "Buffer width should match image width")
        XCTAssertEqual(CVPixelBufferGetHeight(buffer!), cgImage.height, "Buffer height should match image height")
    }

    func testCreatePixelBufferFromNilCGImage() {
        // Create an empty UIImage that has no CGImage backing
        let emptyImage = UIImage()

        // This should return nil since there's no CGImage
        let buffer = PixelBufferUtils.createPixelBuffer(from: emptyImage)
        XCTAssertNil(buffer, "Should return nil for image without CGImage backing")
    }

    // MARK: - Scale Tests

    func testScalePixelBuffer() {
        // Create a test image with known dimensions
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        // Scale to a different size
        let targetSize = CGSize(width: 100, height: 100)
        let scaledBuffer = PixelBufferUtils.scale(sourceBuffer, to: targetSize)

        XCTAssertNotNil(scaledBuffer, "Should create scaled buffer")
        XCTAssertEqual(CVPixelBufferGetWidth(scaledBuffer!), 100, "Scaled width should be 100")
        XCTAssertEqual(CVPixelBufferGetHeight(scaledBuffer!), 100, "Scaled height should be 100")

        // Original dimensions should be different
        XCTAssertNotEqual(sourceWidth, 100, "Source width should differ from target")
        XCTAssertNotEqual(sourceHeight, 100, "Source height should differ from target")
    }

    func testScalePixelBufferSameSize() {
        // Create a test image
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        // Scale to the same size (should return original buffer)
        let targetSize = CGSize(width: sourceWidth, height: sourceHeight)
        let scaledBuffer = PixelBufferUtils.scale(sourceBuffer, to: targetSize)

        XCTAssertNotNil(scaledBuffer, "Should return buffer for same size scaling")
        XCTAssertEqual(CVPixelBufferGetWidth(scaledBuffer!), sourceWidth, "Width should remain unchanged")
        XCTAssertEqual(CVPixelBufferGetHeight(scaledBuffer!), sourceHeight, "Height should remain unchanged")
    }

    // MARK: - Rotation Tests

    func testRotatePixelBuffer90Degrees() {
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        let rotatedBuffer = PixelBufferUtils.rotate(sourceBuffer, degrees: 90)

        XCTAssertNotNil(rotatedBuffer, "Should create rotated buffer")
        // 90° rotation swaps width and height
        XCTAssertEqual(CVPixelBufferGetWidth(rotatedBuffer!), sourceHeight, "Width should be original height after 90° rotation")
        XCTAssertEqual(CVPixelBufferGetHeight(rotatedBuffer!), sourceWidth, "Height should be original width after 90° rotation")
    }

    func testRotatePixelBuffer180Degrees() {
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        let rotatedBuffer = PixelBufferUtils.rotate(sourceBuffer, degrees: 180)

        XCTAssertNotNil(rotatedBuffer, "Should create rotated buffer")
        // 180° rotation keeps same dimensions
        XCTAssertEqual(CVPixelBufferGetWidth(rotatedBuffer!), sourceWidth, "Width should remain unchanged after 180° rotation")
        XCTAssertEqual(CVPixelBufferGetHeight(rotatedBuffer!), sourceHeight, "Height should remain unchanged after 180° rotation")
    }

    func testRotatePixelBuffer270Degrees() {
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        let rotatedBuffer = PixelBufferUtils.rotate(sourceBuffer, degrees: 270)

        XCTAssertNotNil(rotatedBuffer, "Should create rotated buffer")
        // 270° rotation swaps width and height
        XCTAssertEqual(CVPixelBufferGetWidth(rotatedBuffer!), sourceHeight, "Width should be original height after 270° rotation")
        XCTAssertEqual(CVPixelBufferGetHeight(rotatedBuffer!), sourceWidth, "Height should be original width after 270° rotation")
    }

    func testRotatePixelBufferZeroDegrees() {
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        let rotatedBuffer = PixelBufferUtils.rotate(sourceBuffer, degrees: 0)

        XCTAssertNotNil(rotatedBuffer, "Should return buffer for 0° rotation")
        // 0° should return original without modification
        XCTAssertEqual(CVPixelBufferGetWidth(rotatedBuffer!), sourceWidth, "Width should remain unchanged for 0° rotation")
        XCTAssertEqual(CVPixelBufferGetHeight(rotatedBuffer!), sourceHeight, "Height should remain unchanged for 0° rotation")
    }

    func testRotatePixelBufferNegativeDegrees() {
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        _ = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        // -90° should normalize to 270° (swaps dimensions)
        let rotatedBuffer = PixelBufferUtils.rotate(sourceBuffer, degrees: -90)

        XCTAssertNotNil(rotatedBuffer, "Should handle negative rotation")
        XCTAssertEqual(CVPixelBufferGetWidth(rotatedBuffer!), sourceHeight, "Negative rotation should normalize correctly")
    }

    func testRotatePixelBufferLargeDegrees() {
        let image = UIImage(systemName: "star.fill")!
        guard let sourceBuffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create source buffer")
            return
        }

        _ = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        // 450° should normalize to 90° (swaps dimensions)
        let rotatedBuffer = PixelBufferUtils.rotate(sourceBuffer, degrees: 450)

        XCTAssertNotNil(rotatedBuffer, "Should handle large rotation values")
        XCTAssertEqual(CVPixelBufferGetWidth(rotatedBuffer!), sourceHeight, "Large rotation should normalize correctly")
    }

    // MARK: - Buffer Information Tests

    func testDimensionsOfBuffer() {
        let image = UIImage(systemName: "star.fill")!
        guard let buffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create buffer")
            return
        }

        guard let cgImage = image.cgImage else {
            XCTFail("Should have CGImage")
            return
        }

        let dimensions = PixelBufferUtils.dimensions(of: buffer)

        XCTAssertEqual(dimensions.width, CGFloat(cgImage.width), "Dimensions width should match image width")
        XCTAssertEqual(dimensions.height, CGFloat(cgImage.height), "Dimensions height should match image height")
    }

    func testFormatTypeOfBuffer() {
        let image = UIImage(systemName: "star.fill")!
        guard let buffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create buffer")
            return
        }

        let formatType = PixelBufferUtils.formatType(of: buffer)

        // createPixelBuffer uses kCVPixelFormatType_32BGRA
        XCTAssertEqual(formatType, kCVPixelFormatType_32BGRA, "Buffer should be BGRA format")
    }

    func testIsSuitableForStreaming_BGRA() {
        let image = UIImage(systemName: "star.fill")!
        guard let buffer = PixelBufferUtils.createPixelBuffer(from: image) else {
            XCTFail("Failed to create buffer")
            return
        }

        // BGRA is suitable for streaming
        XCTAssertTrue(PixelBufferUtils.isSuitableForStreaming(buffer), "BGRA format should be suitable for streaming")
    }

    func testIsSuitableForStreaming_ARGB() {
        // Create a buffer with ARGB format
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            100,
            100,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            XCTFail("Failed to create ARGB buffer")
            return
        }

        XCTAssertTrue(PixelBufferUtils.isSuitableForStreaming(buffer), "ARGB format should be suitable for streaming")
    }

    func testIsSuitableForStreaming_YUV() {
        // Create a buffer with YUV format (420YpCbCr8BiPlanarVideoRange)
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: false,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            100,
            100,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            XCTFail("Failed to create YUV buffer")
            return
        }

        XCTAssertTrue(PixelBufferUtils.isSuitableForStreaming(buffer), "YUV format should be suitable for streaming")
    }

    func testIsSuitableForStreaming_YUVFullRange() {
        // Create a buffer with YUV full range format
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: false,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            100,
            100,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            XCTFail("Failed to create YUV full range buffer")
            return
        }

        XCTAssertTrue(PixelBufferUtils.isSuitableForStreaming(buffer), "YUV full range format should be suitable for streaming")
    }

    func testIsSuitableForStreaming_UnsuitableFormat() {
        // Create a buffer with an unsupported format (16BE555)
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [:]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            100,
            100,
            kCVPixelFormatType_16BE555,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            XCTFail("Failed to create 16BE555 buffer")
            return
        }

        XCTAssertFalse(PixelBufferUtils.isSuitableForStreaming(buffer), "16BE555 format should not be suitable for streaming")
    }
}
