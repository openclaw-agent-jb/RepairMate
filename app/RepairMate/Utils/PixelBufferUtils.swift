/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PixelBufferUtils.swift
//
// Utilities for working with CVPixelBuffer and video frame processing.
//

import Accelerate
import CoreMedia
import CoreVideo
import Foundation
import UIKit

/// Utilities for CVPixelBuffer manipulation and video frame processing
enum PixelBufferUtils {
    // MARK: - Pixel Buffer Creation

    /// Create a CVPixelBuffer from a UIImage
    /// - Parameter image: Source UIImage
    /// - Returns: CVPixelBuffer or nil if creation fails
    static func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    // MARK: - Scaling

    /// Scale a CVPixelBuffer to a target size
    /// - Parameters:
    ///   - sourceBuffer: Source pixel buffer
    ///   - targetSize: Target dimensions
    /// - Returns: Scaled pixel buffer or nil if scaling fails
    static func scale(_ sourceBuffer: CVPixelBuffer, to targetSize: CGSize) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)

        // Skip if already correct size
        if sourceWidth == targetWidth && sourceHeight == targetHeight {
            return sourceBuffer
        }

        // Create destination buffer
        var destinationBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            CVPixelBufferGetPixelFormatType(sourceBuffer),
            attrs as CFDictionary,
            &destinationBuffer
        )

        guard status == kCVReturnSuccess, let destBuffer = destinationBuffer else {
            return nil
        }

        // Lock buffers
        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(destBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(destBuffer, [])
        }

        // Create vImage buffers
        var sourceVImage = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(sourceBuffer),
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(sourceBuffer)
        )

        var destVImage = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(destBuffer),
            height: vImagePixelCount(targetHeight),
            width: vImagePixelCount(targetWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(destBuffer)
        )

        // Scale using Accelerate
        let scaleError = vImageScale_ARGB8888(&sourceVImage, &destVImage, nil, vImage_Flags(kvImageHighQualityResampling))

        guard scaleError == kvImageNoError else {
            return nil
        }

        return destBuffer
    }

    // MARK: - Rotation

    /// Rotate a CVPixelBuffer by the specified angle
    /// - Parameters:
    ///   - sourceBuffer: Source pixel buffer
    ///   - rotation: Rotation angle (0, 90, 180, 270)
    /// - Returns: Rotated pixel buffer or original if no rotation needed
    static func rotate(_ sourceBuffer: CVPixelBuffer, degrees rotation: Int) -> CVPixelBuffer? {
        let normalizedRotation = ((rotation % 360) + 360) % 360

        guard normalizedRotation != 0 else {
            return sourceBuffer
        }

        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)

        // Determine output dimensions
        let (destWidth, destHeight): (Int, Int)
        switch normalizedRotation {
        case 90, 270:
            destWidth = sourceHeight
            destHeight = sourceWidth
        default:
            destWidth = sourceWidth
            destHeight = sourceHeight
        }

        // Create destination buffer
        var destinationBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            destWidth,
            destHeight,
            CVPixelBufferGetPixelFormatType(sourceBuffer),
            attrs as CFDictionary,
            &destinationBuffer
        )

        guard status == kCVReturnSuccess, let destBuffer = destinationBuffer else {
            return nil
        }

        // Lock buffers
        CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(destBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(destBuffer, [])
        }

        // Create vImage buffers
        var sourceVImage = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(sourceBuffer),
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(sourceBuffer)
        )

        var destVImage = vImage_Buffer(
            data: CVPixelBufferGetBaseAddress(destBuffer),
            height: vImagePixelCount(destHeight),
            width: vImagePixelCount(destWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(destBuffer)
        )

        // Determine rotation constant
        let rotationConstant: UInt8
        switch normalizedRotation {
        case 90:
            rotationConstant = UInt8(kRotate90DegreesClockwise)
        case 180:
            rotationConstant = UInt8(kRotate180DegreesClockwise)
        case 270:
            rotationConstant = UInt8(kRotate270DegreesClockwise)
        default:
            return sourceBuffer
        }

        // Rotate using Accelerate
        let backgroundColor: [UInt8] = [0, 0, 0, 255]
        let rotateError = vImageRotate90_ARGB8888(&sourceVImage, &destVImage, rotationConstant, backgroundColor, vImage_Flags(kvImageNoFlags))

        guard rotateError == kvImageNoError else {
            return nil
        }

        return destBuffer
    }

    // MARK: - Buffer Information

    /// Get the dimensions of a pixel buffer
    static func dimensions(of buffer: CVPixelBuffer) -> CGSize {
        CGSize(
            width: CGFloat(CVPixelBufferGetWidth(buffer)),
            height: CGFloat(CVPixelBufferGetHeight(buffer))
        )
    }

    /// Get the pixel format type of a buffer
    static func formatType(of buffer: CVPixelBuffer) -> OSType {
        CVPixelBufferGetPixelFormatType(buffer)
    }

    /// Check if a buffer is in a format suitable for RTMP streaming
    static func isSuitableForStreaming(_ buffer: CVPixelBuffer) -> Bool {
        let format = formatType(of: buffer)
        // Common formats that work well with VideoToolbox
        return format == kCVPixelFormatType_32BGRA
            || format == kCVPixelFormatType_32ARGB
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }
}

// MARK: - Rotation Constants

private let kRotate90DegreesClockwise: Int = 1
private let kRotate180DegreesClockwise: Int = 2
private let kRotate270DegreesClockwise: Int = 3
