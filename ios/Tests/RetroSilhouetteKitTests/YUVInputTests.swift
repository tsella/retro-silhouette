import CoreVideo
import XCTest
@testable import RetroSilhouetteKit

/// WebRTC and AVPlayer give bi-planar YUV 4:2:0 frames, not BGRA: the engine reads their Y plane as the luma.
final class YUVInputTests: XCTestCase {
    /// A full-range 420f frame: Y = 0 (dark) on the left half, 255 (bright) on the right half.
    private func halfDarkFrame(width: Int = 64, height: Int = 48) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any]]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs as CFDictionary, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for row in 0..<height {
            for col in 0..<width { y[row * yRow + col] = col < width / 2 ? 0 : 255 }
        }
        let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let uvRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for i in 0..<(uvRow * height / 2) { uv[i] = 128 }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let p = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let at = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return [p[at], p[at + 1], p[at + 2]]
    }

    func testABiPlanarFrameGivesASilhouetteOfItsDarkHalf() {
        var config = RetroSilhouetteConfiguration()
        config.mirrorHorizontally = false
        config.dynamicCameraZoomCuts = false
        config.blockyGradientArtifacts = false
        let engine = RetroSilhouetteEngine(configuration: config)
        let done = expectation(description: "a frame")
        var output: CVPixelBuffer?
        engine.onFrameOutput = { buffer, _ in
            if output == nil {
                output = buffer
                done.fulfill()
            }
        }
        engine.processVideoPixelBuffer(halfDarkFrame())
        wait(for: [done], timeout: 5)
        let out = output!
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(out), kCVPixelFormatType_32BGRA)
        let w = CVPixelBufferGetWidth(out)
        let h = CVPixelBufferGetHeight(out)
        // The dark half is the subject (luma under the threshold), the bright half the background.
        XCTAssertNotEqual(pixel(out, x: w / 4, y: h / 2), pixel(out, x: 3 * w / 4, y: h / 2))
    }
}
