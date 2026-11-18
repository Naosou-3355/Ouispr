#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/OuisprColors.swift
// Brand color system with hex initializer and light/dark mode support.
import SwiftUI

/// Brand color palette for Ouispr.
///
/// WHY Color(hex:) instead of Asset Catalog:
/// The project has no .xcassets directory yet for OuisprApp. Using hex initializers
/// provides exact brand colors from the brand kit without needing asset catalog setup.
/// Colors adapt to light/dark mode via the colorScheme-aware static properties.
///
/// WHY static computed properties returning adaptive colors:
/// SwiftUI re-evaluates computed properties when colorScheme changes, so the colors
/// automatically adapt to light/dark mode without manual observation.
public extension Color {
    // MARK: - Brand Colors (fixed, non-adaptive)

    /// Primary accent blue (#3D7EFF)
    static let ouisprAccent = Color(hex: 0x3D7EFF)

    /// Lighter accent highlight (#6BA3FF)
    static let ouisprAccentHighlight = Color(hex: 0x6BA3FF)

    /// Recording state red (#EF4444)
    static let ouisprRecording = Color(hex: 0xEF4444)

    /// Success state green (#22C55E)
    static let ouisprSuccess = Color(hex: 0x22C55E)

    // MARK: - Adaptive Colors (light/dark mode)

    /// Background color: #0A1628 dark / system background light
    static var ouisprBackground: Color {
        Color(light: Color(hex: 0xF2F2F7), dark: Color(hex: 0x0A1628))
    }

    /// Surface color for cards: #161C2C dark / secondary system background light
    static var ouisprSurface: Color {
        Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x161C2C))
    }

    // MARK: - Keyboard pill controls

    /// Icon tint for a secondary pill control in the keyboard area: the panel
    /// toggle and gear in `ToolbarView`, the cancel button in `RecordingOverlay`.
    ///
    /// WHY it is shared (#241): those pills sit in the same 52pt bar and swap
    /// places as the keyboard changes state, so a control that is black in one
    /// bar and grey in the next reads as two different systems. One token keeps
    /// them from drifting apart the next time either file is edited.
    ///
    /// WHY 50% rather than full strength: the glass pill is the affordance; the
    /// glyph only labels it. Full-strength icons compete with the mic and the
    /// validate button, which are the primary actions in their respective bars.
    static var ouisprPillIconSecondary: Color {
        Color(
            light: Color(white: 0.15).opacity(0.5),
            dark: Color.white.opacity(0.5)
        )
    }

    // MARK: - Gradient Colors (for BrandWaveform)

    /// Gradient start for center bar (#6BA3FF)
    static let ouisprGradientStart = Color(hex: 0x6BA3FF)

    /// Gradient end for center bar (#2563EB)
    static let ouisprGradientEnd = Color(hex: 0x2563EB)

    // MARK: - Hex Initializer

    /// Create a Color from a hex integer value (e.g., 0x3D7EFF).
    ///
    /// WHY UInt rather than String:
    /// Compile-time validation -- a typo in a hex literal causes a build error.
    /// String parsing would silently fail at runtime.
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Create an adaptive Color that switches between light and dark variants.
    ///
    /// WHY UIColor bridge:
    /// SwiftUI's Color doesn't have a built-in light/dark initializer on iOS 16.
    /// UIColor.init(dynamicProvider:) handles trait collection changes automatically,
    /// then we wrap it back in SwiftUI Color.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        self = dark
        #endif
    }
}
#endif
