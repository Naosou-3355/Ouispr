#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/OuisprTypography.swift
// Typography system: SF Pro for headings and body.
import SwiftUI

/// Typography scale for Ouispr.
///
/// WHY system text styles instead of fixed sizes:
/// System text styles (`.title`, `.body`, `.caption`) automatically scale with
/// Dynamic Type -- Apple's accessibility feature that lets users set their preferred
/// text size. Using these styles means Ouispr respects the user's accessibility
/// preferences without any extra code.
///
/// WHY plain SF Pro for headings (design V2, bench 1):
/// The rounded design read as friendly but not as sober. The straight SF Pro in
/// semibold is the system's own voice, which is what a very plain interface wants.
public extension Font {
    /// Large heading -- SF Pro Semibold
    static let ouisprHeading: Font = .system(.title, design: .default, weight: .semibold)

    /// Section subheading -- SF Pro Semibold
    static let ouisprSubheading: Font = .system(.title3, design: .default, weight: .semibold)

    /// Body text -- SF Pro Text (system default)
    static let ouisprBody: Font = .system(.body)

    /// Caption text -- SF Pro Text small
    static let ouisprCaption: Font = .system(.caption)

    /// The dictated text on the recording screen: 28 pt at the default text size
    /// (bench 3), and it follows Dynamic Type.
    static let ouisprDictation: Font = .system(.title, design: .default, weight: .regular)

    /// A stage label ("Listening", "Cleaning up"): 15 pt at the default text size.
    static let ouisprStageLabel: Font = .system(.subheadline)
}
#endif
