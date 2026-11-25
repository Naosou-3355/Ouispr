// OuisprApp/Views/GlassSegmentedBar.swift
// One glass capsule holding a few choices, the chosen one marked by a pill that slides.
import SwiftUI
import OuisprCore

/// A choice among a few, drawn as one material: a glass capsule and a soft pill that
/// slides to the chosen item (spring 0.32 s, damping 0.72; a fade under Reduce Motion).
///
/// The history's period bar and the style row at the foot of Home's mode menu are this
/// same control (validated sheet, 25 Nov 2026: « une seule matière, pastille qui
/// glisse »). WHY not a `Picker(.segmented)`: the system control draws its own opaque
/// track, a second material inside the glass.
struct GlassSegmentedBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> Text
    /// Each item's accessibility identifier, when the screen gives one.
    var identifier: ((Item) -> String)?
    var height: CGFloat = 52

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                segment(item)
            }
        }
        .padding(4)
        .frame(height: height)
        .ouisprGlass(in: Capsule())
    }

    private func segment(_ item: Item) -> some View {
        let selected = item == selection
        return Button {
            withAnimation(reduceMotion ? .easeOut(duration: Motion.quick)
                                       : .spring(response: 0.32, dampingFraction: 0.72)) {
                selection = item
            }
        } label: {
            title(item)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.ouisprTextPrimary : Color.ouisprTextSecondary)
                .lineLimit(1)
                // « Très décontracté » in a third of the 300 pt mode menu.
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier?(item) ?? "")
    }
}
