// OuisprCore/Sources/OuisprCore/Polish/SmartModeDefault.swift
// The mode Home's next dictation goes back to once a dictation has run.
import Foundation

/// The default mode of the app's mode button (Home, top left).
///
/// Chosen on the « bouton mode » bench (Alex, 24-25 Nov 2026): a mode is picked for the
/// next dictation only, and once one has run the button goes back to Normal, or to the
/// mode the user marked as the default (a long press in the menu, or the Settings row).
///
/// WHY on top of the armed mode rather than a second "next mode" key: the dictation
/// already reads one value, `SmartModeStore.resolveArmedMode()`, in the same process the
/// keyboard writes it from. Picking a mode arms it, and returning to the default arms the
/// default; nothing downstream changes.
///
/// The return happens for the app's own dictations only. The keyboard's armed mode stays
/// sticky (#79) until an app dictation runs, which then puts it back to the default too:
/// there is one armed mode for both surfaces.
public enum SmartModeDefault {

    private static var defaults: UserDefaults { AppGroup.defaults }

    /// Identifier of the default mode, or nil for Normal.
    public static var identifier: String? {
        defaults.string(forKey: SharedKeys.smartModeDefault)
    }

    /// The default mode as a record, or nil for Normal (and for an identifier this
    /// build does not ship, which reads as Normal without touching what is stored).
    public static var mode: SmartMode? {
        identifier.flatMap(SmartModeCatalogue.mode(withIdentifier:))
    }

    /// Make `mode` the default, or Normal with nil.
    public static func set(_ mode: SmartMode?) {
        if let mode {
            defaults.set(mode.id, forKey: SharedKeys.smartModeDefault)
        } else {
            defaults.removeObject(forKey: SharedKeys.smartModeDefault)
        }
        defaults.synchronize()
    }

    /// Arm the default, or disarm when it is Normal: what follows an app dictation.
    public static func returnToDefault() {
        if let mode {
            SmartModeStore.arm(mode)
        } else {
            SmartModeStore.disarm()
        }
    }
}
