//
//  RetroSilhouetteKit.swift
//  RetroSilhouetteKit
//
//  Inspired by the 1992 Amiga demo "State of the Art" by Spaceballs:
//  https://www.youtube.com/watch?v=89wq5EoXy-0
//
//  A self-contained, real-time retro silhouette echo-trail engine for iOS.
//  Supports live AVCaptureSession camera input, external CMSampleBuffer/CVPixelBuffer video feed,
//  procedural 90s Eurodance audio synthesis, external AVAudioPCMBuffer tap reactivity,
//  and real-time CVPixelBuffer / UIImage / SwiftUI View output.
//

import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import UIKit
import SwiftUI
import Combine
import Accelerate

// MARK: - Public Color & Palette Models

/// Represents an RGBA color normalized to 0.0 ... 1.0 for fast pixel buffer compositing.
public struct SilhouetteColor: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        if cleaned.count == 6 {
            self.r = UInt8((rgb & 0xFF0000) >> 16)
            self.g = UInt8((rgb & 0x00FF00) >> 8)
            self.b = UInt8(rgb & 0x0000FF)
            self.a = 255
        } else {
            self.r = 0; self.g = 0; self.b = 0; self.a = 255
        }
    }

    public var uiColor: UIColor {
        UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}

/// Background style for a silhouette palette.
public enum SilhouetteBackgroundStyle: Equatable, Sendable {
    case solid(SilhouetteColor)
    case gradient([SilhouetteColor])
}

/// Defines a complete color theme for the background and echo trail layers.
public struct SilhouettePalette: Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var background: SilhouetteBackgroundStyle
    /// Trail colors ordered from oldest echo (index 0) to newest live silhouette (last index).
    public var trailColors: [SilhouetteColor]

    public init(
        id: String = UUID().uuidString,
        name: String,
        background: SilhouetteBackgroundStyle,
        trailColors: [SilhouetteColor]
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.trailColors = trailColors
    }

    // Authentic Video Presets
    public static let heatwave = SilhouettePalette(
        id: "heatwave",
        name: "HEATWAVE",
        background: .solid(SilhouetteColor(hex: "#FFFFFF")),
        trailColors: [
            SilhouetteColor(hex: "#F3A867"),
            SilhouetteColor(hex: "#DC6E2A"),
            SilhouetteColor(hex: "#9C2C10"),
            SilhouetteColor(hex: "#6D0E04"),
            SilhouetteColor(hex: "#380000")
        ]
    )

    public static let cyberIce = SilhouettePalette(
        id: "cyber_ice",
        name: "CYBER ICE",
        background: .solid(SilhouetteColor(hex: "#000000")),
        trailColors: [
            SilhouetteColor(hex: "#003566"),
            SilhouetteColor(hex: "#00509D"),
            SilhouetteColor(hex: "#0096C7"),
            SilhouetteColor(hex: "#48CAE4"),
            SilhouetteColor(hex: "#D8FFFF")
        ]
    )

    public static let monoAsh = SilhouettePalette(
        id: "mono_ash",
        name: "MONO ASH",
        background: .solid(SilhouetteColor(hex: "#B5B5B5")),
        trailColors: [
            SilhouetteColor(hex: "#9E9E9E"),
            SilhouetteColor(hex: "#7C7C7C"),
            SilhouetteColor(hex: "#525252"),
            SilhouetteColor(hex: "#262626"),
            SilhouetteColor(hex: "#000000")
        ]
    )

    public static let acidLime = SilhouettePalette(
        id: "acid_lime",
        name: "ACID LIME",
        background: .gradient([
            SilhouetteColor(hex: "#48FF48"),
            SilhouetteColor(hex: "#D4FF66"),
            SilhouetteColor(hex: "#FFFF77")
        ]),
        trailColors: [
            SilhouetteColor(hex: "#B8D8A0"),
            SilhouetteColor(hex: "#8FA8BE"),
            SilhouetteColor(hex: "#636EC2"),
            SilhouetteColor(hex: "#2B2D6E"),
            SilhouetteColor(hex: "#000000")
        ]
    )

    public static let ipodPop = SilhouettePalette(
        id: "ipod_pop",
        name: "IPOD POP",
        background: .solid(SilhouetteColor(hex: "#140024")),
        trailColors: [
            SilhouetteColor(hex: "#5A189A"),
            SilhouetteColor(hex: "#9D4EDD"),
            SilhouetteColor(hex: "#F72585"),
            SilhouetteColor(hex: "#FF9E00"),
            SilhouetteColor(hex: "#FFEA00")
        ]
    )

    public static let allPresets: [SilhouettePalette] = [
        .heatwave, .cyberIce, .monoAsh, .acidLime, .ipodPop
    ]

    /// Generates a randomized high-contrast retro palette.
    public static func random() -> SilhouettePalette {
        let baseHue = CGFloat.random(in: 0...1)
        let darkBg = Bool.random()
        let bg = darkBg ? SilhouetteColor(hex: "#050508") : SilhouetteColor(hex: "#F8FAFC")

        var trails: [SilhouetteColor] = []
        for i in 0..<4 {
            let hue = (baseHue + CGFloat(i) * 0.08).truncatingRemainder(dividingBy: 1.0)
            let brightness: CGFloat = darkBg
                ? (0.35 + CGFloat(i) * 0.18)
                : (0.85 - CGFloat(i) * 0.18)
            let color = UIColor(hue: hue, saturation: 0.9, brightness: brightness, alpha: 1.0)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            trails.append(SilhouetteColor(
                r: UInt8(clamping: Int(r * 255)),
                g: UInt8(clamping: Int(g * 255)),
                b: UInt8(clamping: Int(b * 255))
            ))
        }
        trails.append(darkBg ? SilhouetteColor(hex: "#FFFFFF") : SilhouetteColor(hex: "#09090B"))

        return SilhouettePalette(
            name: "CUSTOM #\(Int.random(in: 10...99))",
            background: .solid(bg),
            trailColors: trails
        )
    }
}

/// Full configuration options exposed by `RetroSilhouetteEngine`.
public struct RetroSilhouetteConfiguration: Equatable, Sendable {
    public var baseResolution: Int = 160
    public var baseTrailCount: Int = 4
    public var minAudioTrailCount: Int = 2
    public var maxAudioTrailCount: Int = 8
    public var trailDelayFrames: Int = 4
    public var lumaThreshold: UInt8 = 128
    public var invertMask: Bool = false
    public var mirrorHorizontally: Bool = true
    public var attachToSound: Bool = true
    public var autoCyclePalettes: Bool = true
    public var dynamicCameraZoomCuts: Bool = true
    public var blockyGradientArtifacts: Bool = true
    public var bassCutSensitivity: Float = 0.62

    public init() {}
}

/// Real-time telemetry and output frame delegate for integrating into custom pipelines.
public protocol RetroSilhouetteEngineDelegate: AnyObject {
    func silhouetteEngine(
        _ engine: RetroSilhouetteEngine,
        didOutputPixelBuffer pixelBuffer: CVPixelBuffer,
        cgImage: CGImage,
        timestamp: CMTime
    )

    func silhouetteEngine(
        _ engine: RetroSilhouetteEngine,
        didTriggerBeatCut palette: SilhouettePalette,
        cameraZoom: CGFloat
    )

    func silhouetteEngine(
        _ engine: RetroSilhouetteEngine,
        didUpdateAudioAmplitude amplitude: Float,
        bassEnergy: Float,
        activeTrailLayers: Int
    )
}

public extension RetroSilhouetteEngineDelegate {
    func silhouetteEngine(_ engine: RetroSilhouetteEngine, didTriggerBeatCut palette: SilhouettePalette, cameraZoom: CGFloat) {}
    func silhouetteEngine(_ engine: RetroSilhouetteEngine, didUpdateAudioAmplitude amplitude: Float, bassEnergy: Float, activeTrailLayers: Int) {}
}

// MARK: - Procedural 90s Eurodance Synthesizer & External Audio Analyzer

public final class RetroEurodanceAudioController {
    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    public private(set) var isPlaying: Bool = false
    public var bpm: Double = 138.0

    public var onBassBeatTrigger: (() -> Void)?
    public var onAmplitudeUpdate: ((_ amplitude: Float, _ bassEnergy: Float) -> Void)?

    private var sampleRate: Double = 44100.0
    private var sampleCounter: Int64 = 0
    private var lastTriggeredStep: Int = -1
    private var kickPhase: Double = 0
    private var bassPhase: Double = 0
    private var leadPhase1: Double = 0
    private var leadPhase2: Double = 0
    private var lastBassCutTime: TimeInterval = 0
    private var samplesSinceUpdate = 0

    private let bassSteps: [Int?] = [
        33, 45, 33, 45, 33, 45, 33, 45,
        29, 41, 29, 41, 31, 43, 31, 43,
        36, 48, 36, 48, 31, 43, 31, 43,
        38, 50, 38, 50, 40, 52, 40, 52,
        33, 45, 36, 48, 38, 50, 40, 52,
        29, 41, 38, 50, 40, 52, 40, 44,
        33, nil, 45, 45, 31, nil, 43, 43,
        29, 41, 31, 43, 33, 40, 45, 57
    ]

    private let leadSteps: [[Int]?] = [
        [69, 76], nil, [76], [69, 74], [72, 76], nil, [71, 74], [67, 71],
        [65, 72], nil, [72], [65, 71], [67, 74], nil, [71, 79], nil,
        [72, 79], nil, [79], [76, 81], [67, 74], nil, [74], [71, 76],
        [62, 69], [69], [74], [77], [64, 71], nil, [76, 80], [83],
        [69, 76], [72], [76], [81], [79], [76], [72], [69],
        [65, 72], [69], [72], [77], [64, 71], [68], [71], [76],
        [69, 76], nil, [69, 76], nil, [67, 74], nil, [67, 74], nil,
        [65, 72], [67, 74], [69, 76], [71, 79], [72, 81], [72, 81], [76, 84], nil
    ]

    /// When false, the controller never changes the shared `AVAudioSession`. Set it to false in an app that owns
    /// the session, for example a call app in `.playAndRecord`: `.playback` would cut its mic.
    public var managesAudioSession: Bool = true

    /// True while a caller pulls the synth's samples (`startExternalSynth`), with no audio engine of its own.
    public private(set) var isRenderingExternally: Bool = false

    public init() {}

    public func configureAudioSession() throws {
        guard managesAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    /// Starts the synth with no audio engine: the caller pulls mono samples with `renderExternalSynth` at
    /// `sampleRate` (for example from a call's audio callback, to mix the music into the call). It never touches
    /// the audio session. The beat and amplitude callbacks run as with the internal synth.
    public func startExternalSynth(sampleRate: Double) {
        if isPlaying { return }
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000.0
        sampleCounter = 0
        lastTriggeredStep = -1
        isRenderingExternally = true
        isPlaying = true
    }

    /// Writes the next `frameCount` mono samples (-1...1) to `samples`. Silence when the external synth is off.
    /// Call it from one thread at a time (an audio callback).
    public func renderExternalSynth(into samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard isRenderingExternally, frameCount > 0 else {
            samples.update(repeating: 0, count: max(0, frameCount))
            return
        }
        renderMono(into: samples, frameCount: frameCount)
    }

    public func stopExternalSynth() {
        guard isRenderingExternally else { return }
        isRenderingExternally = false
        isPlaying = false
        DispatchQueue.main.async { [weak self] in
            self?.onAmplitudeUpdate?(0.0, 0.0)
        }
    }

    public func startInternalSynth() throws {
        if isPlaying { return }
        try configureAudioSession()

        let format = audioEngine.outputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100.0
        sampleCounter = 0
        lastTriggeredStep = -1

        if sourceNode == nil {
            let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self = self else { return noErr }
                return self.renderSynthFrames(frameCount: frameCount, audioBufferList: audioBufferList)
            }
            sourceNode = node
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        isPlaying = true
    }

    public func stopInternalSynth() {
        guard isPlaying, !isRenderingExternally else { return }
        audioEngine.stop()
        isPlaying = false
        DispatchQueue.main.async { [weak self] in
            self?.onAmplitudeUpdate?(0.0, 0.0)
        }
    }

    public func toggleInternalSynth() throws {
        if isPlaying {
            stopInternalSynth()
        } else {
            try startInternalSynth()
        }
    }

    public func processExternalAudioBuffer(_ buffer: AVAudioPCMBuffer, bassSensitivity: Float = 0.62) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let normalizedAmp = min(1.0, max(0.0, rms * 3.8))

        var lowPassAccumulator: Float = 0
        var bassSqSum: Float = 0
        let alpha: Float = 0.08
        for i in 0..<frameLength {
            lowPassAccumulator = alpha * channelData[i] + (1.0 - alpha) * lowPassAccumulator
            bassSqSum += lowPassAccumulator * lowPassAccumulator
        }
        let bassRms = sqrt(bassSqSum / Float(frameLength))
        let normalizedBass = min(1.0, max(0.0, bassRms * 5.2))

        let now = CACurrentMediaTime()
        let shouldTriggerCut = normalizedBass >= bassSensitivity && (now - lastBassCutTime) > 0.22
        if shouldTriggerCut {
            lastBassCutTime = now
        }

        DispatchQueue.main.async { [weak self] in
            if shouldTriggerCut {
                self?.onBassBeatTrigger?()
            }
            self?.onAmplitudeUpdate?(normalizedAmp, normalizedBass)
        }
    }

    private func midiToFreq(_ midi: Int) -> Double {
        return 440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// The internal engine's node: one mono render, copied to each output buffer (channel).
    private func renderSynthFrames(frameCount: UInt32, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let count = Int(frameCount)
        guard let first = ablPointer.first, let firstData = first.mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        let firstCount = min(count, Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        renderMono(into: firstData, frameCount: firstCount)
        for buffer in ablPointer.dropFirst() {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let n = min(firstCount, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            data.update(from: firstData, count: n)
        }
        return noErr
    }

    /// The synth: `frameCount` mono samples into `samples`, and the beat and amplitude callbacks (main thread).
    private func renderMono(into samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        let eighthNoteDuration = (60.0 / bpm) * 0.5
        let samplesPerStep = max(1, Int64(sampleRate * eighthNoteDuration))

        var rmsSum: Float = 0
        var bassTriggerOccurred = false

        for frame in 0..<frameCount {
            let currentSample = sampleCounter
            sampleCounter += 1

            let totalSteps = Int(currentSample / samplesPerStep)
            let stepIndex = totalSteps % 64
            let stepSampleOffset = currentSample % samplesPerStep
            let stepProgress = Double(stepSampleOffset) / Double(samplesPerStep)

            if stepIndex != lastTriggeredStep {
                lastTriggeredStep = stepIndex
                let isKickStep = (stepIndex % 2 == 0) || stepIndex == 61 || stepIndex == 63
                if isKickStep {
                    kickPhase = 0
                    bassTriggerOccurred = true
                }
            }

            var kickSample: Double = 0
            let isKickActive = (stepIndex % 2 == 0) || stepIndex == 61 || stepIndex == 63
            if isKickActive && stepProgress < 0.85 {
                let env = exp(-stepProgress * 6.5)
                let freq = 48.0 + 130.0 * exp(-stepProgress * 22.0)
                kickPhase += freq / sampleRate
                kickSample = sin(kickPhase * 2.0 * .pi) * env * 0.65
            }

            var hatSample: Double = 0
            if stepIndex % 2 == 1 && stepProgress < 0.35 {
                let env = exp(-stepProgress * 18.0)
                let whiteNoise = Double.random(in: -1.0...1.0)
                hatSample = whiteNoise * env * 0.14
            }

            var bassSample: Double = 0
            if let bassNote = bassSteps[stepIndex] {
                let freq = midiToFreq(bassNote)
                bassPhase = (bassPhase + freq / sampleRate).truncatingRemainder(dividingBy: 1.0)
                let saw = (bassPhase * 2.0) - 1.0
                let env = exp(-stepProgress * 4.2)
                bassSample = saw * env * 0.28
            }

            var leadSample: Double = 0
            if let chord = leadSteps[stepIndex], !chord.isEmpty {
                let f1 = midiToFreq(chord[0])
                let f2 = midiToFreq(chord.last ?? chord[0])
                leadPhase1 = (leadPhase1 + f1 / sampleRate).truncatingRemainder(dividingBy: 1.0)
                leadPhase2 = (leadPhase2 + f2 / sampleRate).truncatingRemainder(dividingBy: 1.0)
                let saw1 = (leadPhase1 * 2.0) - 1.0
                let saw2 = (leadPhase2 * 2.0) - 1.0
                let env = exp(-stepProgress * 3.2)
                leadSample = (saw1 + saw2) * 0.5 * env * 0.22
            }

            let mixed = Float(max(-0.98, min(0.98, kickSample + hatSample + bassSample + leadSample)))
            rmsSum += mixed * mixed

            samples[frame] = mixed
        }

        let rms = sqrt(rmsSum / Float(max(1, frameCount)))
        let normAmp = min(1.0, max(0.0, rms * 2.6))
        let bassEnergy: Float = bassTriggerOccurred ? 0.95 : normAmp * 0.7

        // The callbacks drive the picture (about 30 to 60 frames per second): send them on each beat and at most
        // every 20 ms, not on each audio block (a call's audio thread pulls 100 blocks per second).
        samplesSinceUpdate += frameCount
        guard bassTriggerOccurred || Double(samplesSinceUpdate) >= sampleRate * 0.02 else { return }
        samplesSinceUpdate = 0
        DispatchQueue.main.async { [weak self] in
            if bassTriggerOccurred {
                self?.onBassBeatTrigger?()
            }
            self?.onAmplitudeUpdate?(normAmp, bassEnergy)
        }
    }
}

// MARK: - Core RetroSilhouetteEngine

public final class RetroSilhouetteEngine: NSObject, ObservableObject {

    @Published public var configuration: RetroSilhouetteConfiguration {
        didSet {
            if !configuration.attachToSound {
                activeTrailCount = configuration.baseTrailCount
            }
            if !configuration.dynamicCameraZoomCuts {
                cameraZoom = 1.0
                cameraPan = .zero
            }
        }
    }

    @Published public private(set) var palettes: [SilhouettePalette] = SilhouettePalette.allPresets
    @Published public private(set) var activePaletteIndex: Int = 0
    @Published public private(set) var activeTrailCount: Int = 4
    @Published public private(set) var currentAudioAmplitude: Float = 0.0
    @Published public private(set) var currentBassEnergy: Float = 0.0
    @Published public private(set) var latestCGImage: CGImage?
    @Published public private(set) var isCameraRunning: Bool = false
    @Published public private(set) var isAudioPlaying: Bool = false
    @Published public private(set) var measuredFPS: Int = 0

    public var activePalette: SilhouettePalette {
        palettes[ max(0, min(activePaletteIndex, palettes.count - 1)) ]
    }

    public weak var delegate: RetroSilhouetteEngineDelegate?
    public var onFrameOutput: ((_ pixelBuffer: CVPixelBuffer, _ cgImage: CGImage) -> Void)?

    public let audioController = RetroEurodanceAudioController()

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.retrosilhouettekit.videoqueue", qos: .userInteractive)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    private var maskHistory: [[UInt8]] = []
    private var maskBufferWidth: Int = 0
    private var maskBufferHeight: Int = 0
    private var frameCounter: Int = 0

    public private(set) var cameraZoom: CGFloat = 1.0
    public private(set) var cameraPan: CGPoint = .zero

    private let videoTimelineSequence = [0, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 2, 3, 3, 4]
    private var timelineStep: Int = 0

    private var fpsFrameCount: Int = 0
    private var lastFPSTimestamp: TimeInterval = CACurrentMediaTime()

    public init(configuration: RetroSilhouetteConfiguration = RetroSilhouetteConfiguration()) {
        self.configuration = configuration
        self.activeTrailCount = configuration.baseTrailCount
        super.init()
        setupAudioBindings()
    }

    private func setupAudioBindings() {
        audioController.onBassBeatTrigger = { [weak self] in
            guard let self = self else { return }
            if self.configuration.attachToSound || self.configuration.autoCyclePalettes {
                self.triggerBeatCut()
            }
        }

        audioController.onAmplitudeUpdate = { [weak self] amp, bass in
            guard let self = self else { return }
            self.currentAudioAmplitude = amp
            self.currentBassEnergy = bass

            if self.configuration.attachToSound && (self.audioController.isPlaying || amp > 0.01) {
                let minL = Float(self.configuration.minAudioTrailCount)
                let maxL = Float(self.configuration.maxAudioTrailCount)
                let scaled = Int((minL + amp * (maxL - minL)).rounded())
                let clamped = max(self.configuration.minAudioTrailCount, min(self.configuration.maxAudioTrailCount, scaled))
                if clamped != self.activeTrailCount {
                    self.activeTrailCount = clamped
                }
            }

            self.delegate?.silhouetteEngine(
                self,
                didUpdateAudioAmplitude: amp,
                bassEnergy: bass,
                activeTrailLayers: self.activeTrailCount
            )
        }
    }

    public func triggerBeatCut(forcePaletteIndex: Int? = nil) {
        if let forced = forcePaletteIndex, forced >= 0, forced < palettes.count {
            activePaletteIndex = forced
        } else {
            timelineStep = (timelineStep + 1) % videoTimelineSequence.count
            let nextIdx = videoTimelineSequence[timelineStep]
            activePaletteIndex = min(nextIdx, palettes.count - 1)
        }

        if configuration.dynamicCameraZoomCuts {
            let roll = Double.random(in: 0...1)
            if roll < 0.22 {
                cameraZoom = 1.65
                cameraPan = CGPoint(x: CGFloat.random(in: -0.12...0.12), y: -0.18)
            } else if roll < 0.45 {
                cameraZoom = 1.25
                cameraPan = CGPoint(x: CGFloat.random(in: -0.08...0.08), y: -0.05)
            } else {
                cameraZoom = 1.0
                cameraPan = .zero
            }
        } else {
            cameraZoom = 1.0
            cameraPan = .zero
        }

        delegate?.silhouetteEngine(self, didTriggerBeatCut: activePalette, cameraZoom: cameraZoom)
    }

    public func selectPalette(at index: Int, disableAutoCycle: Bool = true) {
        guard index >= 0 && index < palettes.count else { return }
        if disableAutoCycle {
            configuration.autoCyclePalettes = false
        }
        triggerBeatCut(forcePaletteIndex: index)
    }

    @discardableResult
    public func selectRandomPalette() -> SilhouettePalette {
        let custom = SilhouettePalette.random()
        if palettes.count > 5 {
            palettes[5] = custom
        } else {
            palettes.append(custom)
        }
        configuration.autoCyclePalettes = false
        triggerBeatCut(forcePaletteIndex: palettes.count - 1)
        return custom
    }

    public func addCustomPalette(_ palette: SilhouettePalette, activateImmediately: Bool = true) {
        palettes.append(palette)
        if activateImmediately {
            triggerBeatCut(forcePaletteIndex: palettes.count - 1)
        }
    }

    public func startMusic() throws {
        try audioController.startInternalSynth()
        isAudioPlaying = audioController.isPlaying
    }

    /// The synth with no audio engine of its own: pull its samples with `renderMusic(into:frameCount:)`, for
    /// example to mix them into a call's outgoing audio. The audio session is not touched. `stopMusic()` ends it.
    public func startExternalMusic(sampleRate: Double) {
        audioController.startExternalSynth(sampleRate: sampleRate)
        isAudioPlaying = audioController.isPlaying
    }

    /// The next `frameCount` mono samples (-1...1) of the external synth, or silence. From one thread (an audio
    /// callback).
    public func renderMusic(into samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        audioController.renderExternalSynth(into: samples, frameCount: frameCount)
    }

    public func stopMusic() {
        audioController.stopExternalSynth()
        audioController.stopInternalSynth()
        isAudioPlaying = false
        activeTrailCount = configuration.baseTrailCount
    }

    public func toggleMusic() throws {
        try audioController.toggleInternalSynth()
        isAudioPlaying = audioController.isPlaying
        if !isAudioPlaying {
            activeTrailCount = configuration.baseTrailCount
        }
    }

    public func processExternalAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioController.processExternalAudioBuffer(buffer, bassSensitivity: configuration.bassCutSensitivity)
    }

    public func startCamera(position: AVCaptureDevice.Position = .front, completion: ((Bool) -> Void)? = nil) {
        currentCameraPosition = position
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartCaptureSession(position: position, completion: completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self, granted else {
                    DispatchQueue.main.async { completion?(false) }
                    return
                }
                self.configureAndStartCaptureSession(position: position, completion: completion)
            }
        default:
            DispatchQueue.main.async { completion?(false) }
        }
    }

    public func stopCamera() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            DispatchQueue.main.async {
                self.isCameraRunning = false
            }
        }
    }

    public func flipCamera() {
        let nextPosition: AVCaptureDevice.Position = (currentCameraPosition == .front) ? .back : .front
        configuration.mirrorHorizontally = (nextPosition == .front)
        startCamera(position: nextPosition)
    }

    private func configureAndStartCaptureSession(position: AVCaptureDevice.Position, completion: ((Bool) -> Void)?) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .vga640x480

            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { completion?(false) }
                return
            }
            self.captureSession.addInput(input)

            if !self.captureSession.outputs.contains(self.videoOutput) {
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.processingQueue)
                if self.captureSession.canAddOutput(self.videoOutput) {
                    self.captureSession.addOutput(self.videoOutput)
                }
            }

            if let connection = self.videoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                } else if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }

            self.captureSession.commitConfiguration()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            DispatchQueue.main.async {
                self.isCameraRunning = true
                completion?(true)
            }
        }
    }

    public func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        processVideoPixelBuffer(pixelBuffer, timestamp: timestamp)
    }

    public func processVideoPixelBuffer(_ inputPixelBuffer: CVPixelBuffer, timestamp: CMTime = .zero) {
        processingQueue.async { [weak self] in
            self?.renderSilhouetteFrame(from: inputPixelBuffer, timestamp: timestamp)
        }
    }

    private func renderSilhouetteFrame(from inputPixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        frameCounter += 1
        fpsFrameCount += 1

        let now = CACurrentMediaTime()
        if now - lastFPSTimestamp >= 1.0 {
            let currentFPS = fpsFrameCount
            fpsFrameCount = 0
            lastFPSTimestamp = now
            DispatchQueue.main.async { [weak self] in
                self?.measuredFPS = currentFPS
            }
        }

        let config = configuration
        let palette = activePalette
        let trailLayers = max(2, min(8, activeTrailCount))
        let delayFrames = max(1, config.trailDelayFrames)
        let zoom = cameraZoom
        let pan = cameraPan

        if config.autoCyclePalettes && !isAudioPlaying && (frameCounter % 48 == 0) {
            DispatchQueue.main.async { [weak self] in
                self?.triggerBeatCut()
            }
        }

        let srcWidth = CVPixelBufferGetWidth(inputPixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(inputPixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else { return }

        let aspect = Double(srcWidth) / Double(srcHeight)
        let targetW: Int
        let targetH: Int
        if aspect >= 1.0 {
            targetH = max(32, config.baseResolution)
            targetW = max(32, Int((Double(targetH) * aspect).rounded()))
        } else {
            targetW = max(32, config.baseResolution)
            targetH = max(32, Int((Double(targetW) / aspect).rounded()))
        }

        if targetW != maskBufferWidth || targetH != maskBufferHeight {
            maskBufferWidth = targetW
            maskBufferHeight = targetH
            maskHistory.removeAll()
        }

        let currentMask = extractLumaMask(
            from: inputPixelBuffer,
            targetWidth: targetW,
            targetHeight: targetH,
            threshold: config.lumaThreshold,
            invert: config.invertMask,
            mirror: config.mirrorHorizontally,
            zoom: zoom,
            pan: pan
        )

        maskHistory.insert(currentMask, at: 0)
        let maxBufferCount = 8 * delayFrames + 2
        if maskHistory.count > maxBufferCount {
            maskHistory.removeLast(maskHistory.count - maxBufferCount)
        }

        guard let outputBuffer = createOutputPixelBuffer(width: targetW, height: targetH) else { return }
        CVPixelBufferLockBaseAddress(outputBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(outputBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(outputBuffer)
        let dstPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        drawBackground(
            into: dstPtr,
            width: targetW,
            height: targetH,
            bytesPerRow: bytesPerRow,
            palette: palette,
            blockyGradient: config.blockyGradientArtifacts,
            frame: frameCounter
        )

        let sampledColors = sampleTrailColors(from: palette, count: trailLayers)

        for layer in 0..<trailLayers {
            let stepsBack = (trailLayers - 1 - layer) * delayFrames
            let historyIdx = min(stepsBack, maskHistory.count - 1)
            guard historyIdx >= 0, historyIdx < maskHistory.count else { continue }

            let mask = maskHistory[historyIdx]
            let color = sampledColors[layer]

            for y in 0..<targetH {
                let rowStart = y * bytesPerRow
                let maskRowStart = y * targetW
                for x in 0..<targetW {
                    if mask[maskRowStart + x] > 0 {
                        let px = rowStart + x * 4
                        dstPtr[px + 0] = color.b
                        dstPtr[px + 1] = color.g
                        dstPtr[px + 2] = color.r
                        dstPtr[px + 3] = 255
                    }
                }
            }
        }

        let ciImage = CIImage(cvPixelBuffer: outputBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: targetW, height: targetH)) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.latestCGImage = cgImage
            self.onFrameOutput?(outputBuffer, cgImage)
            self.delegate?.silhouetteEngine(
                self,
                didOutputPixelBuffer: outputBuffer,
                cgImage: cgImage,
                timestamp: timestamp
            )
        }
    }

    private func extractLumaMask(
        from pixelBuffer: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int,
        threshold: UInt8,
        invert: Bool,
        mirror: Bool,
        zoom: CGFloat,
        pan: CGPoint
    ) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        // BGRA (the built-in camera), or bi-planar YUV 4:2:0 (WebRTC, AVPlayer): the Y plane is the luma.
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isBiPlanarYUV = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let isVideoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let bytesPerRow = isBiPlanarYUV
            ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetBytesPerRow(pixelBuffer)
        let base = isBiPlanarYUV
            ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
            : CVPixelBufferGetBaseAddress(pixelBuffer)
        guard let baseAddr = base, isBiPlanarYUV || format == kCVPixelFormatType_32BGRA else {
            return [UInt8](repeating: 0, count: targetWidth * targetHeight)
        }
        let srcPtr = baseAddr.assumingMemoryBound(to: UInt8.self)

        var mask = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let invZoom = 1.0 / max(0.2, Double(zoom))
        let panX = Double(pan.x)
        let panY = Double(pan.y)
        let threshInt = Int(threshold)

        for y in 0..<targetHeight {
            let normY = (Double(y) / Double(targetHeight) - 0.5) * invZoom + 0.5 - panY
            let srcY = min(srcH - 1, max(0, Int(normY * Double(srcH))))
            let srcRow = srcY * bytesPerRow
            let maskRow = y * targetWidth

            for x in 0..<targetWidth {
                let rawNormX = (Double(x) / Double(targetWidth) - 0.5) * invZoom + 0.5 - panX
                let normX = mirror ? (1.0 - rawNormX) : rawNormX
                let srcX = min(srcW - 1, max(0, Int(normX * Double(srcW))))

                let luma: Int
                if isBiPlanarYUV {
                    let y = Int(srcPtr[srcRow + srcX])
                    // Video range is Y 16...235: stretch it to 0...255, as full range and BGRA are.
                    luma = isVideoRange ? min(255, max(0, (y - 16) * 255 / 219)) : y
                } else {
                    let px = srcRow + srcX * 4
                    let b = Int(srcPtr[px + 0])
                    let g = Int(srcPtr[px + 1])
                    let r = Int(srcPtr[px + 2])
                    luma = (77 * r + 150 * g + 29 * b) >> 8
                }
                let isForeground = invert ? (luma > threshInt) : (luma < threshInt)
                if isForeground {
                    mask[maskRow + x] = 255
                }
            }
        }
        return mask
    }

    private func drawBackground(
        into dstPtr: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        palette: SilhouettePalette,
        blockyGradient: Bool,
        frame: Int
    ) {
        switch palette.background {
        case .solid(let color):
            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width {
                    let px = row + x * 4
                    dstPtr[px + 0] = color.b
                    dstPtr[px + 1] = color.g
                    dstPtr[px + 2] = color.r
                    dstPtr[px + 3] = 255
                }
            }

        case .gradient(let colors):
            let c0 = colors.first ?? SilhouetteColor(hex: "#48FF48")
            let c1 = colors.count > 1 ? colors[1] : c0
            let c2 = colors.last ?? c1
            let blockSize = max(6, min(width, height) / 14)
            let timeSeed = Double(frame / 4)

            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width {
                    let t = min(1.0, max(0.0, (Double(x) / Double(width) * 0.55) + (Double(y) / Double(height) * 0.45)))
                    let r: Double
                    let g: Double
                    let b: Double
                    if t < 0.55 {
                        let localT = t / 0.55
                        r = Double(c0.r) + (Double(c1.r) - Double(c0.r)) * localT
                        g = Double(c0.g) + (Double(c1.g) - Double(c0.g)) * localT
                        b = Double(c0.b) + (Double(c1.b) - Double(c0.b)) * localT
                    } else {
                        let localT = (t - 0.55) / 0.45
                        r = Double(c1.r) + (Double(c2.r) - Double(c1.r)) * localT
                        g = Double(c1.g) + (Double(c2.g) - Double(c1.g)) * localT
                        b = Double(c1.b) + (Double(c2.b) - Double(c1.b)) * localT
                    }

                    var delta: Double = 0
                    if blockyGradient {
                        let bx = Double((x / blockSize) * blockSize)
                        let by = Double((y / blockSize) * blockSize)
                        let hash = sin(bx * 12.9898 + by * 78.233 + timeSeed) * 43758.5453
                        let fract = hash - floor(hash)
                        delta = fract > 0.5 ? 14.0 : -10.0
                    }

                    let px = row + x * 4
                    dstPtr[px + 0] = UInt8(clamping: Int(b + delta))
                    dstPtr[px + 1] = UInt8(clamping: Int(g + delta))
                    dstPtr[px + 2] = UInt8(clamping: Int(r + delta))
                    dstPtr[px + 3] = 255
                }
            }
        }
    }

    private func sampleTrailColors(from palette: SilhouettePalette, count: Int) -> [SilhouetteColor] {
        let src = palette.trailColors
        guard !src.isEmpty else {
            return Array(repeating: SilhouetteColor(hex: "#000000"), count: count)
        }
        let safeCount = max(2, count)
        var result: [SilhouetteColor] = []
        result.reserveCapacity(safeCount)
        for i in 0..<safeCount {
            let fraction = Double(i) / Double(safeCount - 1)
            let idx = Int((fraction * Double(src.count - 1)).rounded())
            result.append(src[max(0, min(src.count - 1, idx))])
        }
        return result
    }

    private func createOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        return pixelBuffer
    }
}

extension RetroSilhouetteEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processVideoSampleBuffer(sampleBuffer)
    }
}

// MARK: - UIKit View Wrapper (RetroSilhouetteUIView)

public final class RetroSilhouetteUIView: UIView {
    public let engine: RetroSilhouetteEngine
    private var cancellable: AnyCancellable?

    public init(engine: RetroSilhouetteEngine) {
        self.engine = engine
        super.init(frame: .zero)
        backgroundColor = .black
        layer.magnificationFilter = .nearest
        layer.contentsGravity = .resizeAspectFill
        clipsToBounds = true

        cancellable = engine.$latestCGImage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cgImage in
                self?.layer.contents = cgImage
            }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleStageTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleStageTap() {
        engine.triggerBeatCut()
    }
}

// MARK: - SwiftUI View & Full-Screen Studio Experience (RetroSilhouetteView)

public struct RetroSilhouetteView: View {
    @ObservedObject public var engine: RetroSilhouetteEngine
    public var showFloatingControls: Bool

    @State private var isSettingsPresented: Bool = false

    public init(
        engine: RetroSilhouetteEngine = RetroSilhouetteEngine(),
        showFloatingControls: Bool = true
    ) {
        self.engine = engine
        self.showFloatingControls = showFloatingControls
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                if let cgImage = engine.latestCGImage {
                    Image(decorative: cgImage, scale: 1.0, orientation: .up)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            engine.triggerBeatCut()
                        }
                } else {
                    Color.black
                }
            }
            .ignoresSafeArea()

            if showFloatingControls {
                HStack(spacing: 10) {
                    Button {
                        try? engine.toggleMusic()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: engine.isAudioPlaying ? "speaker.wave.3.fill" : "speaker.slash.fill")
                                .foregroundColor(engine.isAudioPlaying ? .green : .cyan)
                            Text(engine.isAudioPlaying ? "Stop Music" : "Play Music")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            RetroSilhouetteSettingsSheet(engine: engine)
                .modifier(SettingsSheetDetents())
        }
    }
}

/// The settings sheet's detents and drag indicator: iOS 16 API, so only there (the package supports iOS 15).
private struct SettingsSheetDetents: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

public struct RetroSilhouetteSettingsSheet: View {
    @ObservedObject public var engine: RetroSilhouetteEngine
    @Environment(\.dismiss) private var dismiss

    public init(engine: RetroSilhouetteEngine) {
        self.engine = engine
    }

    public var body: some View {
        NavigationView {
            Form {
                Section("Sound Reactivity") {
                    Toggle("Attach to Sound", isOn: $engine.configuration.attachToSound)
                    HStack {
                        Text("Live Amplitude")
                        Spacer()
                        Text("\(engine.activeTrailCount) Layers Active")
                            .font(.caption.monospaced())
                            .foregroundColor(.cyan)
                    }
                    ProgressView(value: Double(engine.currentAudioAmplitude), total: 1.0)
                        .tint(.cyan)
                }

                Section("Camera & Luma Mask") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Luma Threshold")
                            Spacer()
                            Text("\(engine.configuration.lumaThreshold)")
                                .font(.caption.monospaced())
                        }
                        Slider(
                            value: Binding(
                                get: { Double(engine.configuration.lumaThreshold) },
                                set: { engine.configuration.lumaThreshold = UInt8($0) }
                            ),
                            in: 20...235,
                            step: 1
                        )
                    }
                    Toggle("Invert Silhouette Mask", isOn: $engine.configuration.invertMask)
                    Toggle("Mirror Camera Horizontally", isOn: $engine.configuration.mirrorHorizontally)
                    Button("Flip Front / Back Camera") {
                        engine.flipCamera()
                    }
                }

                Section("Color Palettes (\(engine.activePalette.name))") {
                    Toggle("Auto-Flash Palettes", isOn: $engine.configuration.autoCyclePalettes)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Array(engine.palettes.prefix(5).enumerated()), id: \.element.id) { idx, pal in
                            Button {
                                engine.selectPalette(at: idx)
                            } label: {
                                Text(pal.name)
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(engine.activePaletteIndex == idx ? Color.cyan.opacity(0.25) : Color.secondary.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            engine.selectRandomPalette()
                        } label: {
                            Text("🎲 Randomize")
                                .font(.caption.bold())
                                .foregroundColor(.cyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Trail & Pixel Parameters") {
                    Stepper(
                        "Base Echo Layers: \(engine.configuration.baseTrailCount)",
                        value: $engine.configuration.baseTrailCount,
                        in: 2...8
                    )
                    Stepper(
                        "Trail Delay: \(engine.configuration.trailDelayFrames) Frames",
                        value: $engine.configuration.trailDelayFrames,
                        in: 1...10
                    )
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Pixel Resolution")
                            Spacer()
                            Text("\(engine.configuration.baseResolution) px")
                                .font(.caption.monospaced())
                        }
                        Slider(
                            value: Binding(
                                get: { Double(engine.configuration.baseResolution) },
                                set: { engine.configuration.baseResolution = Int($0) }
                            ),
                            in: 64...320,
                            step: 16
                        )
                    }
                    Toggle("Dynamic 00s Camera Zoom Cuts", isOn: $engine.configuration.dynamicCameraZoomCuts)
                    Toggle("MPEG Blocky Gradient", isOn: $engine.configuration.blockyGradientArtifacts)
                }
            }
            .navigationTitle("Studio Settings (\(engine.measuredFPS) FPS)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("⚡ Beat Cut") {
                        engine.triggerBeatCut()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
