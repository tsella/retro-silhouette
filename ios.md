# iOS library

[← Back to the README](./README.md)

**RetroSilhouetteKit** is a zero-dependency, real-time video and audio processing library for iOS 15+. The whole implementation is one file, `ios/Sources/RetroSilhouetteKit/RetroSilhouetteKit.swift`.

## Features

- **Live camera or custom video input.** The built-in `AVCaptureSession` manager starts with `startCamera()`. You can also feed `CMSampleBuffer` or `CVPixelBuffer` frames from `AVPlayer`, ReplayKit, or WebRTC. Input frames can be BGRA or bi-planar YUV 4:2:0 (`420f`, `420v`; the Y plane is the luma).
- **Built-in 90s Eurodance synth or external audio tap.** A procedural 138 BPM, 64-step `AVAudioEngine` synthesizer drives the bass cuts and the layer scaling. External `AVAudioPCMBuffer` streams work the same way.
- **Full configuration API.** Set the pixel resolution, the trail count, the frame delay between trails, the luma threshold, mask inversion, horizontal mirroring, dynamic zoom cuts, and blocky gradient artifacts.
- **Real-time output streams.** Receive processed `CVPixelBuffer` and `CGImage` frames through delegate callbacks, closures, or Combine `@Published` properties. Use them for `AVAssetWriter` recording, streaming, or custom drawing.
- **Drop-in SwiftUI and UIKit views.** `RetroSilhouetteView` includes an optional floating music button and settings drawer. `RetroSilhouetteUIView` is the plain `UIView` form.

## Installation

### Option 1: Swift Package Manager

Add the repository in Xcode (`File > Add Package Dependencies...`), or put it in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tsella/retro-silhouette.git", from: "1.0.0")
]
```

### Option 2: Direct source file

Copy `ios/Sources/RetroSilhouetteKit/RetroSilhouetteKit.swift` into your Xcode project.

### Camera permission

If you use `engine.startCamera()`, add `NSCameraUsageDescription` to your `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to generate real-time silhouette echo trails.</string>
```

## Usage

### Quick start with SwiftUI

`RetroSilhouetteView` draws nearest-neighbour pixelated silhouettes and adds an optional music toggle and a slide-up settings drawer:

```swift
import SwiftUI
import RetroSilhouetteKit

struct ContentView: View {
    @StateObject private var engine = RetroSilhouetteEngine()

    var body: some View {
        RetroSilhouetteView(engine: engine, showFloatingControls: true)
            .onAppear {
                engine.startCamera(position: .front)
            }
            .onDisappear {
                engine.stopCamera()
                engine.stopMusic()
            }
    }
}
```

### Quick start with UIKit

Use `RetroSilhouetteUIView` inside any `UIViewController`:

```swift
import UIKit
import RetroSilhouetteKit

class ViewController: UIViewController {
    private let engine = RetroSilhouetteEngine()
    private var silhouetteView: RetroSilhouetteUIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        silhouetteView = RetroSilhouetteUIView(engine: engine)
        silhouetteView.frame = view.bounds
        silhouetteView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(silhouetteView)

        engine.startCamera(position: .front)
        try? engine.startMusic()
    }
}
```

### Configuration

All visual and audio-reactive parameters live in `engine.configuration`:

```swift
var config = RetroSilhouetteConfiguration()
config.baseResolution = 160            // Shortest-edge pixel grid (64...320)
config.baseTrailCount = 4              // Echo trails when audio scaling is off (2...8)
config.minAudioTrailCount = 2          // Minimum layers at low amplitude
config.maxAudioTrailCount = 8          // Maximum layers at peak amplitude
config.trailDelayFrames = 4            // Frame offset between echo layers (1...12)
config.lumaThreshold = 128             // Foreground/background luma cutoff (0...255)
config.invertMask = false              // Invert subject and background
config.mirrorHorizontally = true       // Mirror the front camera
config.attachToSound = true            // Cut palettes on bass, scale layers on amplitude
config.autoCyclePalettes = true        // Cycle palettes when the audio is off
config.dynamicCameraZoomCuts = true    // Hard-cut camera zooms on the beat
config.blockyGradientArtifacts = true  // Macroblock noise on gradient backgrounds
config.bassCutSensitivity = 0.62       // External audio bass threshold (0.0...1.0)

let engine = RetroSilhouetteEngine(configuration: config)
```

### Music inside an app that owns the audio session

The built-in synth sets the shared `AVAudioSession` to `.playback`. That cuts the microphone of an app that runs in `.playAndRecord`. Such an app can pull the music and mix it into its own audio instead:

```swift
engine.audioController.managesAudioSession = false   // never touch AVAudioSession
engine.startExternalMusic(sampleRate: 48_000)        // no audio engine of its own

// In the app's audio callback, for each block of `frames` samples:
engine.renderMusic(into: monoFloatSamples, frameCount: frames)   // -1...1, silence when off

engine.stopMusic()
```

The beat cuts and the amplitude-scaled trail layers follow the pulled music, the same as with the internal synth.

## Tests

```bash
xcodebuild test -scheme RetroSilhouetteKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The test target covers the external synth.
