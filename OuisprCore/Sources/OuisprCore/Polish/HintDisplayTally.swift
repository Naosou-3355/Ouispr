// OuisprCore/Sources/OuisprCore/Polish/HintDisplayTally.swift
// Counts the Smart Mode hint once per keyboard opening that drew it (lot 1.7).
import Foundation

/// The per-opening half of the hint's display cap (`SmartModeDiscovery.maxDisplayCount`).
///
/// A display is counted when the hint was actually drawn in the centre slot, not when the
/// policy merely offered it: the slot's priority table gives it the room only after the
/// error, undo, suggestions, armed mode and ☰ panel hint, so an opening that offered it
/// can still have shown something else. And it is counted once per opening, however many
/// times the bar is redrawn and however many of the keyboard's root views report it.
///
/// Lives in OuisprCore, not in the keyboard, because the keyboard target has no tests.
public struct HintDisplayTally: Equatable, Sendable {
    /// `SmartModeDiscovery.displayCount` as it stood when the keyboard last opened: the
    /// cap is judged against it, so the opening that reaches the cap keeps its hint.
    public private(set) var displaysBeforeThisOpening: Int
    /// Whether this opening has already been counted.
    public private(set) var countedThisOpening = false

    public init(displayCount: Int) {
        displaysBeforeThisOpening = max(0, displayCount)
    }

    /// A new opening of the keyboard (`KeyboardOwnership.opensKeyboard(appearingAfter:)`).
    public mutating func keyboardOpened(displayCount: Int) {
        displaysBeforeThisOpening = max(0, displayCount)
        countedThisOpening = false
    }

    /// The hint was drawn. Returns true when this is the opening's first drawing, which
    /// is the one to record with `SmartModeDiscovery.noteHintShown()`.
    public mutating func hintDrawn() -> Bool {
        guard !countedThisOpening else { return false }
        countedThisOpening = true
        return true
    }
}

public extension KeyboardOwnership {
    /// Whether a controller appearing (`appearing(controllerID:)`, iOS bringing a keyboard
    /// on screen) turned `previous` into this state as a new opening: owned after nobody
    /// visibly owned it. From `.awaitingReclaim` it counts too: that is the successor iOS
    /// builds after the user switched apps, measured on the simulator (28 Nov 2026) as
    /// the usual way a keyboard comes back. Only call it for an appearance: a reclaim by a
    /// controller already on screen (`claiming`, #260) continues the same opening.
    func opensKeyboard(appearingAfter previous: KeyboardOwnership) -> Bool {
        !previous.isVisible && isVisible
    }
}
