import AVFoundation
import XCTest
@testable import RetroSilhouetteKit

final class ExternalSynthTests: XCTestCase {
    private func render(_ engine: RetroSilhouetteEngine, frames: Int) -> [Float] {
        var out = [Float](repeating: 1, count: frames)
        out.withUnsafeMutableBufferPointer { engine.renderMusic(into: $0.baseAddress!, frameCount: frames) }
        return out
    }

    func testSilenceWhenTheExternalSynthIsOff() {
        let engine = RetroSilhouetteEngine()
        XCTAssertEqual(render(engine, frames: 480), [Float](repeating: 0, count: 480))
    }

    func testTheExternalSynthPlaysMusicInRangeAndStops() {
        let engine = RetroSilhouetteEngine()
        engine.startExternalMusic(sampleRate: 48_000)
        XCTAssertTrue(engine.isAudioPlaying)
        // 1 s in 10 ms frames, as a call's audio callback pulls it.
        var all: [Float] = []
        for _ in 0..<100 { all += render(engine, frames: 480) }
        XCTAssertGreaterThan(all.map { $0 * $0 }.reduce(0, +) / Float(all.count), 0.001, "the music is not silence")
        XCTAssertLessThanOrEqual(all.map(abs).max() ?? 0, 0.98)
        engine.stopMusic()
        XCTAssertFalse(engine.isAudioPlaying)
        XCTAssertEqual(render(engine, frames: 480), [Float](repeating: 0, count: 480))
    }

    func testTheExternalSynthLeavesTheAudioSessionAlone() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat)
        let engine = RetroSilhouetteEngine()
        engine.audioController.managesAudioSession = false
        engine.startExternalMusic(sampleRate: 48_000)
        try engine.audioController.configureAudioSession()
        XCTAssertEqual(session.category, .playAndRecord)
        engine.stopMusic()
    }
}
