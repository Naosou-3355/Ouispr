// OuisprApp/Views/OpenedDictationCard.swift
// A dictation card lifted open: the whole text, and its copy, share and close pictograms.
import SwiftUI
import OuisprCore

// MARK: - Opened card

/// The card the user tapped, lifted out of its row and opened in place: same corners,
/// a uniform scale (no stretching), the cards' spring (0.32 s, damping 0.84). The full
/// text comes in word by word; copy and share are bare ink pictograms on 44 pt targets.
struct OpenedDictationCard: View {
    let record: TranscriptionRecord
    /// The card's frame in its row, in window coordinates, where it opens from.
    let origin: CGRect
    /// The history's way to the full screen of a record (a voice note's summary).
    var onShowDetail: (() -> Void)?
    let onClose: () -> Void

    @State private var open = false
    @State private var copied = false
    @State private var copiedReset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let spring = DictationCloudCard.spring

    var body: some View {
        GeometryReader { geo in
            let space = geo.frame(in: .global)
            let width = min(320, geo.size.width - 54)
            ZStack {
                // Tapping beside the card closes it.
                Color.black.opacity(open ? 0.06 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)

                content
                    .frame(width: width)
                    .background(
                        RoundedRectangle(cornerRadius: DictationCloudCard.cornerRadius, style: .continuous)
                            .fill(Color.ouisprSurface)
                            .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
                    )
                    .scaleEffect(open || reduceMotion ? 1 : origin.width / width)
                    .offset(open || reduceMotion ? .zero : CGSize(width: origin.midX - space.midX,
                                                                  height: origin.midY - space.midY))
                    .opacity(open ? 1 : 0)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: Motion.standard) : Self.spring) { open = true }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: DictationCloud.title(for: record.text))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ouisprTextPrimary)
                Spacer(minLength: 8)
                if copied {
                    // As visible as the title, not a caption in the date's place (n°15).
                    Label("Copied!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ouisprSuccess)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    Text(verbatim: record.shortDateLabel)
                        .font(.ouisprCaption)
                        .foregroundStyle(Color.ouisprTextSecondary)
                        .monospacedDigit()
                }
            }
            ScrollView {
                RevealingText(record.text, font: .system(size: 15), wordSpacing: 4)
                    .foregroundStyle(Color.ouisprTextPrimary)
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                if let onShowDetail {
                    pictogram("arrow.up.left.and.arrow.down.right", label: "Open", action: onShowDetail)
                }
                Spacer()
                pictogram("doc.on.doc", label: "Copy", action: copy)
                ShareLink(item: record.text) {
                    pictogramGlyph("square.and.arrow.up")
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, -10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func pictogram(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { pictogramGlyph(symbol) }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel(label)
    }

    private func pictogramGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.ouisprInk.opacity(0.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func copy() {
        UIPasteboard.general.string = record.text
        HapticFeedback.recordingStopped()
        withAnimation(.easeOut(duration: Motion.quick)) { copied = true }
        // Cancellable: a second copy restarts the 1.5 s rather than being cut short.
        copiedReset?.cancel()
        copiedReset = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Motion.quick)) { copied = false }
        }
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: Motion.standard) : Self.spring) {
            open = false
        } completion: {
            onClose()
        }
    }
}

/// A card open over a screen, and where it opened from.
struct OpenedCardState: Equatable {
    let record: TranscriptionRecord
    let origin: CGRect
}
