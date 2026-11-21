#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/GlassModifier.swift
// Reusable glass effect modifier supporting iOS 26 Liquid Glass with graceful fallback.
import SwiftUI

/// Applies glass effect: `.glassEffect()` on iOS 26+, `.regularMaterial` on iOS 16-25.
///
/// WHY a custom modifier instead of applying material directly:
/// Centralizes the iOS version check. Every surface that should look "glassy" calls
/// `.ouisprGlass()` and automatically gets the best available effect for the device.
/// When iOS 26 ships, all surfaces upgrade to Liquid Glass without any code changes.
public struct GlassModifier<S: Shape>: ViewModifier {
    public let shape: S

    public init(shape: S) {
        self.shape = shape
    }

    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.regularMaterial))
        }
    }
}

/// Button style for every glass control: a slight scale-down under the finger.
///
/// WHY a custom ButtonStyle:
/// One place decides how a press feels, so a button on Home and a button on the
/// recording screen answer the finger the same way.
///
/// WHY 0.97 in 140 ms with no bounce (design V2, bench 4): the press has to confirm
/// the touch and get out of the way. The earlier 0.92 with a spring read as playful,
/// which is not what a sober interface wants. Call sites that pass their own scale
/// keep it.
public struct GlassPressStyle: ButtonStyle {
    /// Scale when finger is down.
    private let pressedScale: CGFloat

    /// Opacity when finger is down.
    private let pressedOpacity: Double

    public init(pressedScale: CGFloat = 0.97, pressedOpacity: Double = 0.85) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// Convenience View extension for applying glass effects.
public extension View {
    /// Apply glass effect with a custom shape (default: rounded rectangle with 16pt corners).
    ///
    /// - Parameter shape: The shape to use for the glass effect clipping.
    /// - Returns: View with glass effect applied.
    func ouisprGlass<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: 16)) -> some View {
        modifier(GlassModifier(shape: shape))
    }

    /// Apply glass effect optimized for toolbar/navigation bar surfaces.
    /// Uses Capsule shape for a pill-shaped glass background.
    func ouisprGlassBar() -> some View {
        modifier(GlassModifier(shape: Capsule()))
    }
}
#endif
