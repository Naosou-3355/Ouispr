---
phase: 06-infrastructure-app-polish
plan: 01
subsystem: infra
tags: [design-system, swift, spm, xcassets, app-icon, coregraphics]

# Dependency graph
requires:
  - phase: v1.0
    provides: "OuisprCore SPM package, OuisprApp/Design/ and OuisprKeyboard/Design/ directories"
provides:
  - "Shared design system in OuisprCore/Sources/OuisprCore/Design/ with public access"
  - "App icon asset catalog with light/dark/tinted variants"
  - "Icon generation script (scripts/generate-app-icon.swift)"
affects: [06-02, 06-03, all-future-phases]

# Tech tracking
tech-stack:
  added: [CoreGraphics icon generation]
  patterns: [public extension for cross-module design tokens, xcassets iOS 18 format]

key-files:
  created:
    - OuisprCore/Sources/OuisprCore/Design/OuisprColors.swift
    - OuisprCore/Sources/OuisprCore/Design/OuisprTypography.swift
    - OuisprCore/Sources/OuisprCore/Design/GlassModifier.swift
    - OuisprCore/Sources/OuisprCore/Design/AnimatedMicButton.swift
    - OuisprCore/Sources/OuisprCore/Design/BrandWaveform.swift
    - OuisprCore/Sources/OuisprCore/Design/ProcessingAnimation.swift
    - OuisprCore/Sources/OuisprCore/Design/OuisprLogo.swift
    - OuisprApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
    - OuisprApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-dark.png
    - OuisprApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-tinted.png
    - scripts/generate-app-icon.swift
  modified:
    - Ouispr.xcodeproj/project.pbxproj
    - OuisprKeyboard/Views/RecordingOverlay.swift
    - OuisprKeyboard/Views/AccentPopup.swift
    - OuisprKeyboard/Views/FullAccessBanner.swift
    - OuisprApp/Onboarding/OnboardingView.swift
    - OuisprApp/Onboarding/WelcomePage.swift
    - OuisprApp/Onboarding/MicPermissionPage.swift
    - OuisprApp/Onboarding/KeyboardSetupPage.swift
    - OuisprApp/Views/LicensesView.swift

key-decisions:
  - "Used public extension pattern for Color/Font to expose design tokens across modules"
  - "Used CoreGraphics Swift script instead of manual PNG creation for reproducible icon generation"
  - "Scaled bars 1.2x from brand kit proportions for small-size readability"

patterns-established:
  - "Design tokens: all shared UI components live in OuisprCore/Sources/OuisprCore/Design/"
  - "public access: all cross-module symbols must be explicitly public in OuisprCore"
  - "Asset generation: scripts/ directory for build-time generation tools"

requirements-completed: [INFRA-01, INFRA-02]

# Metrics
duration: 9min
completed: 2026-03-07
---

# Phase 6 Plan 1: Design System Consolidation & App Icon Summary

**Consolidated 7 design files from OuisprApp/OuisprKeyboard duplicates into OuisprCore shared package with public access, and generated brand-kit app icon with light/dark/tinted variants**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-07T20:55:35Z
- **Completed:** 2026-03-07T21:04:21Z
- **Tasks:** 2
- **Files modified:** 22

## Accomplishments
- Eliminated 13 duplicate design files (7 in OuisprApp/Design/, 6 in OuisprKeyboard/Design/) into single source of truth
- All design symbols (colors, typography, glass modifier, views) now public in OuisprCore
- Generated app icon from brand kit at 1024x1024 with standard, dark, and tinted variants
- Both OuisprApp and OuisprKeyboard build successfully from shared design source

## Task Commits

Each task was committed atomically:

1. **Task 1: Move design files to OuisprCore and fix access control** - `93795ee` (feat)
2. **Task 2: Generate app icon from brand kit** - `ecaad09` (feat)

## Files Created/Modified
- `OuisprCore/Sources/OuisprCore/Design/*.swift` (7 files) - Shared design system with public access
- `OuisprApp/Assets.xcassets/AppIcon.appiconset/` - App icon with 3 variants + Contents.json
- `scripts/generate-app-icon.swift` - CoreGraphics icon generation script
- `Ouispr.xcodeproj/project.pbxproj` - Removed old design refs, added Assets.xcassets
- 8 Swift files - Added `import OuisprCore` where design symbols were used without it

## Decisions Made
- Used `public extension Color` / `public extension Font` pattern rather than standalone types, preserving the existing `Color.ouisprAccent` call syntax across both targets
- CoreGraphics-based Swift script for icon generation (reproducible, no external dependencies)
- Scaled bar dimensions 1.2x from brand kit for readability at small home screen sizes
- Bottom-aligned bars (matching the brand kit visual: bars grow upward from a shared baseline)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added missing `import OuisprCore` to 8 files**
- **Found during:** Task 1 (build verification)
- **Issue:** After moving design files to OuisprCore, 8 files that used design symbols (Color.ouisprAccent, .ouisprGlass(), BrandWaveform, etc.) had relied on them being compiled in the same target. They needed explicit `import OuisprCore`.
- **Fix:** Added `import OuisprCore` to RecordingOverlay.swift, AccentPopup.swift, FullAccessBanner.swift (OuisprKeyboard) and OnboardingView.swift, WelcomePage.swift, MicPermissionPage.swift, KeyboardSetupPage.swift, LicensesView.swift (OuisprApp)
- **Files modified:** 8 Swift files across both targets
- **Verification:** Both OuisprApp and OuisprKeyboard build successfully
- **Committed in:** 93795ee (Task 1 commit)

**2. [Rule 3 - Blocking] Added Assets.xcassets reference to Xcode project file**
- **Found during:** Task 2 (asset catalog integration)
- **Issue:** The Xcode project had no .xcassets directory. The new Assets.xcassets needed PBXFileReference, PBXGroup entry, and PBXResourcesBuildPhase entry to be recognized by Xcode.
- **Fix:** Added PBXBuildFile, PBXFileReference, and Resources build phase entries for Assets.xcassets
- **Files modified:** Ouispr.xcodeproj/project.pbxproj
- **Verification:** OuisprApp builds successfully with AppIcon in asset catalog
- **Committed in:** ecaad09 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both auto-fixes were necessary for the targets to compile. No scope creep.

## Issues Encountered
- iPhone 16 simulator not available (project uses Xcode 26 beta with iPhone 17 Pro simulators). Used `iPhone 17 Pro` destination instead. No impact on build verification.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Design system is now single-source in OuisprCore, ready for Plan 02 and 03 to build on
- App icon is set up for home screen display
- Both targets compile cleanly from shared design code

---
*Phase: 06-infrastructure-app-polish*
*Completed: 2026-03-07*
