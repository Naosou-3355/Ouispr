// OuisprKeyboard/TouchHandling/SpatialTyping.swift
// Keeps where each letter of the current word was tapped, and resizes letter keys
// invisibly from the letters already typed.
import CoreGraphics
import Foundation

/// The two touch-aware typing features, on the Swift side.
///
/// 1. **Hidden key resizing.** A tap near the border of two keys goes to the one the
///    dictionary expects next ("bonj" + a tap between `o` and `u` gives `o`). The keys
///    never change on screen and a tap well inside a key always produces that key: only
///    the outer quarter of a key can be reassigned. Same idea as Apple's adjustable hit
///    regions (US patent 8,232,973).
/// 2. **Touch-aware correction.** The autocorrect scorer prices each letter of the word
///    from where the finger landed instead of from the key it produced, like Gboard's
///    spatial model ("The Machine Intelligence Behind Gboard", Google Research, 2017).
///
/// The maths live in C++ (`ouispr_spatial.cpp`); parameters and their measured effect
/// are in `tools/typing-bench/README.md`.
///
/// WHY a shared object: the touch is seen by `GiellaKeyboardView`, the character is
/// inserted by `OuisprKeyboardBridge`, and the correction runs in `AOSPTrieEngine`,
/// sometimes on the suggestion queue. They meet here, behind a lock.
final class SpatialTyping {

    static let shared = SpatialTyping()

    /// One letter of the current word and where it was tapped, in key widths.
    /// NaN coordinates: the letter was not tapped (long-press accent, swipe alternate).
    private struct Tap {
        let letter: Character
        let x: Float
        let y: Float
    }

    /// The letter keys as installed in the engine, used to convert points to key units.
    struct Geometry: Equatable {
        /// Horizontal distance between two neighbouring letter keys, in points.
        let pitch: CGFloat
        /// Lowercased letter and centre in the keyboard view, in points.
        let centers: [Character: CGPoint]
        /// Vertical distance between two letter rows, in points.
        let rowPitch: CGFloat
    }

    private let lock = NSLock()
    private var trail: [Tap] = []
    private var pendingTap: (letter: Character, point: CGPoint)?
    private var geometry: Geometry?

    /// Longest word whose taps are kept. Past it the trail stops growing; the content
    /// check in `taps(for:)` then simply finds no match.
    private static let maxTrailLength = 48

    /// Whether touches may be reassigned right now (autocorrect on, host field allows
    /// it). Set by the bridge; read on the main thread at each touch.
    var isResolutionEnabled: () -> Bool = { false }

    /// Text before the cursor, read from the host on the main thread. Set by the bridge.
    var contextBeforeCursor: () -> String? = { nil }

    private init() {}

    // MARK: - Geometry

    /// Install the letter keys as they are laid out now. Cheap when nothing changed.
    func install(_ newGeometry: Geometry, engine: TextPredictionEngine = .shared) {
        lock.lock()
        let changed = newGeometry != geometry
        if changed { geometry = newGeometry }
        lock.unlock()
        guard changed, newGeometry.pitch > 0, newGeometry.rowPitch > 0 else { return }

        var characters: [UInt16] = []
        var xs: [Float] = []
        var ys: [Float] = []
        for (letter, center) in newGeometry.centers {
            guard let unit = letter.spatialCodeUnit else { continue }
            characters.append(unit)
            xs.append(Float(center.x / newGeometry.pitch))
            ys.append(Float(center.y / newGeometry.pitch))
        }
        engine.setSpatialKeys(
            characters: characters, centerX: xs, centerY: ys,
            keyWidth: 1.0, keyHeight: Float(newGeometry.rowPitch / newGeometry.pitch)
        )
    }

    private func units(_ point: CGPoint) -> (Float, Float)? {
        lock.lock()
        defer { lock.unlock() }
        guard let pitch = geometry?.pitch, pitch > 0 else { return nil }
        return (Float(point.x / pitch), Float(point.y / pitch))
    }

    // MARK: - Hidden key resizing

    /// The letter a touch on `geometricLetter` most probably meant. Returns
    /// `geometricLetter` (lowercased) when resizing is off or nothing beats it.
    func resolve(_ geometricLetter: Character, at point: CGPoint,
                 engine: TextPredictionEngine = .shared) -> Character {
        let lowered = geometricLetter.lowercased().first ?? geometricLetter
        guard isResolutionEnabled(),
              let unit = lowered.spatialCodeUnit,
              let (x, y) = units(point) else { return lowered }
        let context = contextBeforeCursor()
        let prefix = Self.wordPrefix(in: context)
        let resolved = engine.resolveTouch(
            x: x, y: y, geometricKey: unit, prefix: prefix, previousWord: Self.previousWord(in: context)
        )
        guard let scalar = Unicode.Scalar(resolved) else { return lowered }
        return Character(scalar)
    }

    /// The letters of the word being typed: the run of letters right before the cursor.
    /// Stops at an apostrophe, like the spell check does ("l'hom" → "hom").
    static func wordPrefix(in context: String?) -> String {
        guard let context else { return "" }
        var letters: [Character] = []
        for character in context.reversed() {
            guard character.isLetter else { break }
            letters.append(character)
            if letters.count >= 32 { break }
        }
        return String(letters.reversed()).lowercased()
    }

    /// The word before the one being typed, lowercased, as the n-grams store it ("l'ai"
    /// stays one token). Nil at the start of a sentence: only spaces may separate the two
    /// words, so "Fin. Je" gives no context to "Je".
    static func previousWord(in context: String?) -> String? {
        guard let context else { return nil }
        var index = context.endIndex
        while index > context.startIndex, context[context.index(before: index)].isLetter {
            index = context.index(before: index)
        }
        var sawSpace = false
        while index > context.startIndex, context[context.index(before: index)] == " " {
            index = context.index(before: index)
            sawSpace = true
        }
        guard sawSpace else { return nil }
        var letters: [Character] = []
        while index > context.startIndex, letters.count < 32 {
            let character = context[context.index(before: index)]
            guard character.isLetter || character == "'" || character == "’" || character == "-" else { break }
            letters.append(character == "’" ? "'" : character)
            index = context.index(before: index)
        }
        guard letters.contains(where: \.isLetter) else { return nil }
        return String(letters.reversed()).lowercased()
    }

    // MARK: - Tap trail (touch-aware correction)

    /// Called by the keyboard view right before it triggers a letter key.
    func notePendingTap(letter: Character, at point: CGPoint) {
        lock.lock()
        pendingTap = (letter.lowercased().first ?? letter, point)
        lock.unlock()
    }

    /// Called by the keyboard view right after the key was handled.
    func clearPendingTap() {
        lock.lock()
        pendingTap = nil
        lock.unlock()
    }

    /// Record what the keyboard just inserted. Letters extend the word, anything else
    /// (space, punctuation, apostrophe, digits) starts a new one.
    func recordInsertion(_ text: String) {
        let pending: (letter: Character, point: CGPoint)?
        lock.lock()
        pending = pendingTap
        pendingTap = nil
        lock.unlock()

        guard text.count == 1, let character = text.first, character.isLetter else {
            reset()
            return
        }
        let letter = character.lowercased().first ?? character
        var x = Float.nan
        var y = Float.nan
        if let pending, pending.letter == letter, let (ux, uy) = units(pending.point) {
            x = ux
            y = uy
        }
        lock.lock()
        if trail.count < Self.maxTrailLength {
            trail.append(Tap(letter: letter, x: x, y: y))
        }
        lock.unlock()
    }

    /// One character deleted before the cursor.
    func recordDeletion() {
        lock.lock()
        if !trail.isEmpty { trail.removeLast() }
        lock.unlock()
    }

    /// The word ended, or the document changed under us.
    func reset() {
        lock.lock()
        trail.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// Tap coordinates for `word`, one pair per UTF-16 code unit, or nil when the
    /// recorded letters do not spell exactly the end of the current word. That content
    /// check is what keeps a stale trail (cursor moved, text pasted, dictation) from
    /// pricing the wrong letters: on any doubt the correction runs as before.
    func taps(for word: String) -> (x: [Float], y: [Float])? {
        let letters = Array(word.lowercased())
        guard !letters.isEmpty, letters.count == word.utf16.count else { return nil }
        lock.lock()
        let recorded = trail
        lock.unlock()
        guard recorded.count >= letters.count else { return nil }
        let suffix = recorded.suffix(letters.count)
        guard zip(suffix, letters).allSatisfy({ $0.letter == $1 }) else { return nil }
        guard suffix.contains(where: { !$0.x.isNaN }) else { return nil }
        return (suffix.map(\.x), suffix.map(\.y))
    }
}

private extension Character {
    /// The single UTF-16 code unit of this character, or nil if it is not exactly one.
    /// (OuisprCore has the same helper, internal to that module.)
    var spatialCodeUnit: UInt16? {
        let scalars = unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first, scalar.value <= 0xFFFF else {
            return nil
        }
        return UInt16(scalar.value)
    }
}
