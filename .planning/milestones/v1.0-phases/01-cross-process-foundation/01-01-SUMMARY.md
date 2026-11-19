# Summary: Plan 1.1 — Project Scaffold

**Status:** Completed
**Date:** 2026-03-05
**Commits:** 7 atomic commits

---

## What Was Built

### OuisprCore SPM Package (`OuisprCore/`)
A local Swift Package providing all cross-process foundation types shared between OuisprApp and OuisprKeyboard.

**Files created:**
- `OuisprCore/Package.swift` — Swift 5.9 package manifest, iOS 16.0 minimum, test target included
- `OuisprCore/Sources/OuisprCore/AppGroup.swift` — Single source of truth for App Group identifier (`group.com.pivi.dictus`) and shared UserDefaults/container access
- `OuisprCore/Sources/OuisprCore/DictationStatus.swift` — `Codable` enum (idle/requested/recording/transcribing/ready/failed) written to shared UserDefaults
- `OuisprCore/Sources/OuisprCore/SharedKeys.swift` — Centralized UserDefaults key constants with `ouispr.` prefix
- `OuisprCore/Sources/OuisprCore/DarwinNotifications.swift` — Cross-process Darwin notification helper; fixed C function pointer capture with module-level registry
- `OuisprCore/Sources/OuisprCore/AppGroupDiagnostic.swift` — Health check returning `DiagnosticResult` (canRead/canWrite/containerExists)
- `OuisprCore/Sources/OuisprCore/Logger.swift` — `OuisprLogger` with `@available(iOS 14.0, macOS 11.0, *)` guard
- `OuisprCore/Tests/OuisprCoreTests/OuisprCoreTests.swift` — 6 unit tests, all passing via `swift test`

### OuisprApp Target
- `OuisprApp/OuisprApp.swift` — `@main` SwiftUI App; runs `AppGroupDiagnostic.run()` in `init()`
- `OuisprApp/ContentView.swift` — Runs diagnostics via `.task {}`, renders `DiagnosticView` with green/red SF Symbol indicators
- `OuisprApp/OuisprApp.entitlements` — App Group `group.com.pivi.dictus`
- `OuisprApp/Info.plist` — `NSMicrophoneUsageDescription` set for Phase 2 prep

### OuisprKeyboard Extension Target
- `OuisprKeyboard/KeyboardViewController.swift` — `UIInputViewController` subclass using `UIHostingController` to host SwiftUI; runs diagnostic in `#if DEBUG viewDidLoad()`
- `OuisprKeyboard/KeyboardRootView.swift` — Placeholder view (216pt height, "Next Keyboard" button); full AZERTY layout deferred to Plan 1.3
- `OuisprKeyboard/OuisprKeyboard.entitlements` — App Group `group.com.pivi.dictus`
- `OuisprKeyboard/Info.plist` — `RequestsOpenAccess=true`, `PrimaryLanguage=fr-FR`, `IsASCIICapable=true`, `NSExtensionPrincipalClass=KeyboardViewController`

### Xcode Project (`Ouispr.xcodeproj/project.pbxproj`)
- Two `PBXNativeTarget` entries: `OuisprApp` (`.application`) and `OuisprKeyboard` (`.app-extension`)
- `APPLICATION_EXTENSION_API_ONLY = YES` on OuisprKeyboard (equivalent to `EXTENSION_SAFE_API_ONLY`)
- Both targets at iOS 16.0 minimum deployment target
- `XCLocalSwiftPackageReference` linking `OuisprCore` to both targets via `XCSwiftPackageProductDependency`
- Both `OuisprApp` (com.pivi.dictus) and `OuisprKeyboard` (com.pivi.dictus.keyboard) bundle IDs configured

---

## Verification Results

| Check | Result |
|-------|--------|
| `xcodebuild -scheme OuisprApp … build` | BUILD SUCCEEDED |
| `xcodebuild -scheme OuisprKeyboard … build` | BUILD SUCCEEDED |
| `swift test` in OuisprCore/ | 6/6 tests passed |
| No extension-unsafe API warnings | Confirmed |
| Both entitlements contain `group.com.pivi.dictus` | Confirmed |
| `RequestsOpenAccess = true` in keyboard Info.plist | Confirmed |
| `PrimaryLanguage = fr-FR` in keyboard Info.plist | Confirmed |
| iOS 16.0 minimum deployment target | Confirmed |

---

## Key Decisions

**DarwinNotifications C callback pattern:** `CFNotificationCenterAddObserver` requires a C function pointer that cannot capture Swift context. Solved with a module-level `_darwinCallbacks` dictionary protected by `NSLock`, and a `let _darwinCallback: CFNotificationCallback` at module scope. This is the correct Swift pattern for Darwin notification centers.

**`Logger` availability guard:** `os.log.Logger` requires `@available(iOS 14.0, macOS 11.0, *)`. Since OuisprCore's minimum is iOS 16.0, the guard is technically redundant for device builds but required for `swift test` (macOS) compatibility. `AppGroupDiagnostic` uses `os_log()` (available iOS 10+) to avoid the availability dance in the hot path.

**`APPLICATION_EXTENSION_API_ONLY`:** Xcode's extension targets use `APPLICATION_EXTENSION_API_ONLY = YES` in `project.pbxproj` (the old `EXTENSION_SAFE_API_ONLY` name is deprecated). Both settings enforce the same constraint — no `UIApplication.shared` usage in the extension.

**No Xcode workspace:** The project uses a single `.xcodeproj` with a local package reference. No workspace file is needed because OuisprCore is a local package, not a shared framework.

---

## What's Next

- **Plan 1.2:** Cross-process signaling — `ouispr://dictate` URL scheme, `DictationStatus` round-trip via App Group, Darwin notification round-trip smoke test
- **Plan 1.3:** Keyboard shell — full AZERTY layout replacing `KeyboardRootView` placeholder, graceful Full Access degradation

---

## Commits

1. `feat(core)`: create OuisprCore local SPM package with foundation types
2. `test(core)`: add OuisprCoreTests covering AppGroup, DictationStatus, SharedKeys
3. `feat(app)`: create OuisprApp SwiftUI entry point and ContentView with diagnostic display
4. `feat(keyboard)`: create OuisprKeyboard extension with UIHostingController pattern
5. `feat(config)`: add App Group entitlements group.com.pivi.dictus to both targets
6. `feat(config)`: configure Info.plist for both targets
7. `feat(project)`: create Xcode project with OuisprApp + OuisprKeyboard targets
