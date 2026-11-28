// OuisprApp/Views/ProSheen.swift
// The Ouispr Pro signature: an iridescent sheen that passes once (Pro bench V1.1, 25 Nov 2026).
import SwiftUI
import OuisprCore

/// One pass of an iridescent light across a view, each time it appears.
///
/// WHY once and not a loop: the signature has to stay "elegant, sober and bare"
/// (Alex, bench V1.1). A shimmer that repeats is a loading state in every iOS app;
/// a single pass reads as a finish. It plays on appearance, so the Pro window's
/// button shows it once per opening and the Settings row once per visit.
///
/// WHY nothing under Reduce Motion: the sheen is decoration with no information in
/// it, the case Apple's guidance on Reduce Motion asks to drop rather than replace.
private struct ProSheen: ViewModifier {
    /// Under the content rather than over it: the band never crosses the words.
    var behindContent = false
    /// Whether the pass has played, kept by the screen: the pass then plays once per
    /// screen rather than at each appearance of the view (a List row reappears on every
    /// scroll).
    var played: Binding<Bool>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 before the pass, 1 after it. Reset on each appearance.
    @State private var progress: CGFloat = 0

    /// The band's colours: the pastel blue, lilac and mint of the "irisée" direction,
    /// light enough to read as a reflection on the ink and not as a colour.
    private static let band: [Color] = [
        .clear,
        Color(red: 0.72, green: 0.84, blue: 1.0).opacity(0.55),
        Color(red: 0.90, green: 0.78, blue: 1.0).opacity(0.50),
        Color(red: 0.76, green: 1.0, blue: 0.90).opacity(0.45),
        .clear
    ]

    func body(content: Content) -> some View {
        if behindContent {
            content.background { band }
                .onAppear(perform: start)
        } else {
            content.overlay { band }
                .onAppear(perform: start)
        }
    }

    private var band: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            LinearGradient(colors: Self.band, startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.6)
                .rotationEffect(.degrees(14))
                // From fully left of the view to fully right of it.
                .offset(x: -width * 0.7 + progress * width * 1.7)
        }
        .opacity(reduceMotion || (played?.wrappedValue == true && progress == 0) ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func start() {
        if let played {
            guard !played.wrappedValue else { return }
            played.wrappedValue = true
        }
        progress = 0
        guard !reduceMotion else { return }
        // A short wait, so the pass is seen after the screen has landed.
        withAnimation(.easeInOut(duration: 1.1).delay(0.35)) {
            progress = 1
        }
    }
}

extension View {
    /// The Pro signature. Apply it before the view's `clipShape`, which keeps the band
    /// inside the button's corners.
    func proSheen(behindContent: Bool = false, played: Binding<Bool>? = nil) -> some View {
        modifier(ProSheen(behindContent: behindContent, played: played))
    }
}
