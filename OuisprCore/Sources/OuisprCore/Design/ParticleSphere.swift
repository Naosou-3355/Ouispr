// OuisprCore/Sources/OuisprCore/Design/ParticleSphere.swift
// The character's mood: one per stage of a dictation.
import Foundation

/// What the character is saying. One per stage of a dictation.
///
/// The name is the particle sphere's, which the ink character replaced (Beta 45); the
/// sphere's simulation and renderers were removed once nothing drew them, and the mood
/// is what the ink character kept of it.
public enum ParticleSphereMood: Equatable, Sendable {
    /// Nothing is happening: the character rests.
    case resting
    /// The microphone is open: the line follows the voice.
    case listening
    /// The text is being transcribed or cleaned up: one crest breathes.
    case working
    /// The text is ready: a drop, then laughing eyes.
    case done
}
