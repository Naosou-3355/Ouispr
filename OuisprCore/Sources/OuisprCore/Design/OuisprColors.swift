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
    // MARK: - Brand Colors

    /// Primary accent blue: #2756D6 on light, #3D7EFF on dark.
    ///
    /// WHY two values (design V2, 20 Nov 2026): the app is light first, and #3D7EFF
    /// as text on the light background measures 3.7:1, under the 4.5:1 WCAG asks of
    /// body text. #2756D6 passes. On the dark background the brighter blue is the one
    /// that reads, so it stays there.
    static var ouisprAccent: Color {
        Color(light: Color(hex: 0x2756D6), dark: Color(hex: 0x3D7EFF))
    }

    /// Lighter accent highlight (#6BA3FF)
    static let ouisprAccentHighlight = Color(hex: 0x6BA3FF)

    /// Recording state red (#EF4444)
    static let ouisprRecording = Color(hex: 0xEF4444)

    /// Success state green (#22C55E)
    static let ouisprSuccess = Color(hex: 0x22C55E)

    // MARK: - Adaptive Colors (light/dark mode)

    /// Background color: off-white #F7F8FA light / anthracite #1C1D21 dark.
    /// Light first since design V2 (bench 1): the dark mode is derived from it.
    static var ouisprBackground: Color {
        Color(light: Color(hex: 0xF7F8FA), dark: Color(hex: 0x1C1D21))
    }

    /// Surface color for cards: white light / #26272C dark.
    static var ouisprSurface: Color {
        Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x26272C))
    }

    // MARK: - Text (design V2)

    /// Main text: #14161B light / #EDEFF3 dark.
    static var ouisprTextPrimary: Color {
        Color(light: Color(hex: 0x14161B), dark: Color(hex: 0xEDEFF3))
    }

    /// The ink character's stroke: navy #14161B light / #F4F6FB dark (bench of
    /// 24 Nov 2026). One ink, no shadow, no outline.
    static var ouisprInk: Color {
        Color(light: Color(hex: 0x14161B), dark: Color(hex: 0xF4F6FB))
    }

    /// Secondary text, such as a subtitle or a stage label: #4A4F5A light / #A8AFBD dark.
    static var ouisprTextSecondary: Color {
        Color(light: Color(hex: 0x4A4F5A), dark: Color(hex: 0xA8AFBD))
    }

    /// The quietest text that still passes 4.5:1 on the background, such as a hint
    /// or a time: #666C78 light / #8A91A0 dark.
    static var ouisprTextTertiary: Color {
        Color(light: Color(hex: 0x666C78), dark: Color(hex: 0x8A91A0))
    }

    // MARK: - Sphere (design V2)

    /// First colour of the particle sphere and of the main button (#2F6BFF).
    static let ouisprSphereStart = Color(hex: OuisprSphereGradient.startHex)

    /// Second colour of the particle sphere and of the main button (#7C5CFF).
    static let ouisprSphereEnd = Color(hex: OuisprSphereGradient.endHex)

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

/// The blue to blue-violet gradient the sphere, the main button and the waveform share.
public enum OuisprSphereGradient {
    static let startHex: UInt = 0x2F6BFF
    static let endHex: UInt = 0x7C5CFF

    /// The gradient as a fill, top leading to bottom trailing.
    public static var linear: LinearGradient {
        LinearGradient(
            colors: [.ouisprSphereStart, .ouisprSphereEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The colour `fraction` of the way from the first colour to the second.
    ///
    /// WHY by hand: a `Canvas` fills a path with one colour, and both the sphere and
    /// the waveforms draw hundreds of small paths, each at its own place on the
    /// gradient.
    public static func color(at fraction: Double, opacity: Double = 1) -> Color {
        let clamped = min(max(fraction, 0), 1)
        func channel(_ shift: UInt) -> Double {
            let start = Double((startHex >> shift) & 0xFF)
            let end = Double((endHex >> shift) & 0xFF)
            return (start + (end - start) * clamped) / 255.0
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0), opacity: opacity)
    }
}
#endif
