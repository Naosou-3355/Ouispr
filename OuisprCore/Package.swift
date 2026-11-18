// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OuisprCore",
    platforms: [.iOS(.v17), .macOS("26.0")],
    products: [
        .library(name: "OuisprCore", targets: ["OuisprCore"]),
        .executable(name: "polish-harness", targets: ["polish-harness"])
    ],
    targets: [
        .target(name: "OuisprCore", path: "Sources/OuisprCore"),
        // The #570 / #581 fidelity scorers: proposition recall, person and stance,
        // order, and speaker-state fabrication. Deterministic and model-free.
        //
        // WHY its own target rather than a folder in OuisprCore or a file in the
        // harness. It is measurement code, not product code, so it has no business
        // shipping inside the keyboard extension's ~50 MB — but the harness is a
        // macOS-only executable and a test target cannot import one without breaking
        // the iOS Simulator destination `swift test` also runs on (#301). A plain
        // library both can depend on is the only shape that is testable AND absent
        // from the app. Nothing links it into OuisprApp or OuisprKeyboard.
        .target(name: "PolishFidelity", dependencies: ["OuisprCore"], path: "Sources/PolishFidelity"),
        // Off-device polish eval harness (macOS only — needs Apple Intelligence).
        // Runs the REAL pipeline (PolishPipeline + AppleFoundationModelsPolishEngine)
        // on text fixtures, sharing one source of truth with the app. Not built by
        // the iOS app. `swift test` (and so CI, #534) compiles it but never runs it;
        // run it locally on a Mac with Apple Intelligence enabled.
        .executableTarget(
            name: "polish-harness",
            dependencies: ["OuisprCore", "PolishFidelity"],
            path: "Sources/polish-harness",
            // Undeclared, SwiftPM warns "unhandled file" and that warning is the
            // first line of every committed capture in docs/research/.
            exclude: ["README.md"],
            resources: [.copy("fixtures")]
        ),
        .testTarget(
            name: "OuisprCoreTests",
            dependencies: ["OuisprCore", "PolishFidelity"],
            path: "Tests/OuisprCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
