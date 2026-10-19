// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetroSilhouetteKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "RetroSilhouetteKit",
            targets: ["RetroSilhouetteKit"]
        )
    ],
    targets: [
        .target(
            name: "RetroSilhouetteKit",
            path: "ios/Sources/RetroSilhouetteKit"
        ),
        .testTarget(
            name: "RetroSilhouetteKitTests",
            dependencies: ["RetroSilhouetteKit"],
            path: "ios/Tests/RetroSilhouetteKitTests"
        )
    ]
)
