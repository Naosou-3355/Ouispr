// swift-tools-version:5.10
// Parakeet v3 vs Parakeet Ultra on French dictation: accuracy (WER) and latency.
// Measurement only: the app does not depend on this package.
import PackageDescription

let package = Package(
    name: "ParakeetBench",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Ultra (`AsrModelVersion.ultra`) needs FluidAudio 0.18; the app is on 0.15.8.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3"),
    ],
    targets: [
        .executableTarget(
            name: "ParakeetBench",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/ParakeetBench"
        ),
    ]
)
