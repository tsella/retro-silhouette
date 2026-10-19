# RetroSilhouetteKit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A real-time, audio-reactive retro silhouette motion-trail engine. The iOS/Swift implementation lives under [`ios/`](./ios) and runs on iOS 15+ through Swift Package Manager. The layout leaves room for further platforms (Android, macOS, WebGL).

---

## 🌟 Inspiration & Credits

This project is directly inspired by the legendary **1992 Amiga demoscene production *"State of the Art"* by Spaceballs**, which pioneered real-time rotoscoped dancer silhouettes, layered strobe echo trails, hard-cut camera zooms, and high-contrast color palette flashes synchronized to an electronic beat.

* 📺 **Watch the original 1992 Amiga Demo:** [Spaceballs - State of the Art - Amiga Demo (HD 50fps) on YouTube](https://www.youtube.com/watch?v=89wq5EoXy-0)

---

## 📁 Repository Structure

```text
.
├── README.md                  # Project documentation, credits, and API usage guide
├── LICENSE                    # MIT License
├── Package.swift              # Swift Package Manager manifest pointing to ./ios
├── .gitignore                 # Build artifacts and editor state
└── ios/
    └── Sources/
        └── RetroSilhouetteKit/
            └── RetroSilhouetteKit.swift   # Self-contained iOS Swift library (SwiftUI + UIKit + CoreVideo)
    └── Tests/
        └── RetroSilhouetteKitTests/       # XCTest: the external synth
```

*(Future platform implementations such as `android/`, `web/`, or `desktop/` can be added cleanly at the root level alongside `ios/`.)*

---

## 📱 iOS Library (`RetroSilhouetteKit`)

Located in `ios/Sources/RetroSilhouetteKit/RetroSilhouetteKit.swift`, **RetroSilhouetteKit** is a zero-dependency, real-time video and audio processing library for iOS 15+.

### Features
* **Live Camera or Custom Video Input:** Use the built-in `AVCaptureSession` camera manager (`startCamera()`) or feed custom `CMSampleBuffer` / `CVPixelBuffer` streams from `AVPlayer`, ReplayKit, or WebRTC.
* **Built-In 90s Eurodance Synth or External Audio Tap:** Includes a procedural 138 BPM 64-step `AVAudioEngine` synthesizer, or accepts external `AVAudioPCMBuffer` streams to drive bass cuts and amplitude layer scaling.
* **Full Configuration API:** Programmatically control pixel resolution, echo trail count, frame delay offsets, luma threshold cutoff, mask inversion, horizontal mirroring, dynamic camera zoom cuts, and MPEG blocky gradient artifacts.
* **Real-Time Output Streams:** Receive processed `CVPixelBuffer` and `CGImage` frames via delegate callbacks, closures, or Combine `@Published` properties for recording (`AVAssetWriter`), streaming, or custom rendering.
* **Drop-In SwiftUI & UIKit Views:** Includes `RetroSilhouetteView` (with optional floating music and settings drawer controls) and `RetroSilhouetteUIView`.

---

## 🚀 Installation

### Option 1: Swift Package Manager (SPM)
Add this repository to your Xcode project (`File > Add Package Dependencies...`) or include it in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tsella/retro-silhouette.git", from: "1.0.0")
]
```

### Option 2: Direct Source File
Copy `ios/Sources/RetroSilhouetteKit/RetroSilhouetteKit.swift` directly into your Xcode project.

> **Important (`Info.plist`):** If you use the built-in camera (`engine.startCamera()`), add the `NSCameraUsageDescription` key to your app's `Info.plist`:
> ```xml
> <key>NSCameraUsageDescription</key>
> <string>Camera access is required to generate real-time silhouette echo trails.</string>
> ```

---

## 🛠 Usage Guide (iOS)

### 1. Quick Start with SwiftUI (`RetroSilhouetteView`)
Drop the full-screen studio view into any SwiftUI hierarchy. It automatically renders nearest-neighbor pixelated silhouettes and provides an optional top-right music toggle and slide-up settings drawer:

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

### 2. Quick Start with UIKit (`RetroSilhouetteUIView`)
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

### 3. Programmatic Configuration (`RetroSilhouetteConfiguration`)
All visual and audio-reactive parameters are exposed via `engine.configuration`:

```swift
var config = RetroSilhouetteConfiguration()
config.baseResolution = 160            // Shortest-edge pixel grid resolution (64...320)
config.baseTrailCount = 4              // Echo trail count when sound scaling is off (2...8)
config.minAudioTrailCount = 2          // Minimum layers at low audio amplitude
config.maxAudioTrailCount = 8          // Maximum layers at peak audio amplitude
config.trailDelayFrames = 4            // Frame offset between echo layers (1...12)
config.lumaThreshold = 128             // Foreground/background luma cutoff (0...255)
config.invertMask = false              // Invert subject vs background
config.mirrorHorizontally = true       // Mirror front camera
config.attachToSound = true            // Cut palettes on bass & scale layers on amplitude
config.autoCyclePalettes = true        // Auto-flash palettes when audio is off
config.dynamicCameraZoomCuts = true    // 90s/00s hard-cut camera zooms on beat
config.blockyGradientArtifacts = true  // Macroblock noise on gradient backgrounds
config.bassCutSensitivity = 0.62       // External audio bass threshold (0.0...1.0)

let engine = RetroSilhouetteEngine(configuration: config)
```

### 4. Music inside an app that owns the audio session (for example a call app)

The built-in synth sets the shared `AVAudioSession` to `.playback`, which cuts the mic of an app in `.playAndRecord`. Such an app can pull the music instead and mix it into its own audio:

```swift
engine.audioController.managesAudioSession = false   // never touch AVAudioSession
engine.startExternalMusic(sampleRate: 48_000)        // no audio engine of its own

// In the app's audio callback, for each block of `frames` samples:
engine.renderMusic(into: monoFloatSamples, frameCount: frames)   // -1...1; silence when the music is off

engine.stopMusic()
```

The beat cuts and the amplitude-scaled trail layers follow the pulled music, as with the internal synth.

### Tests

```bash
xcodebuild test -scheme RetroSilhouetteKit -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## 📄 License

This project is licensed under the **MIT License** — Copyright (c) 2026 Tom Sella. See the [LICENSE](./LICENSE) file for full details.
