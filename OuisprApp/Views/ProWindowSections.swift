// OuisprApp/Views/ProWindowSections.swift
// The Ouispr Pro window's pieces for someone being sold Pro: features, trial, ink button (Pro offer, 25 Nov 2026).
import SwiftUI
import OuisprCore

/// The touched feature in its own block with its sentence, then "Also included"
/// over one grouped card of the others; from Settings, the four in that card.
///
/// The caller passes `.settings` at the end of the trial: that screen says what
/// was lost, all of it, and was opened by the app rather than by a feature.
struct ProWindowFeatureList: View {
    let layout: ProWindowLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let focus = layout.focus {
                focusBlock(focus)
                Text("Also included")
                    .font(.ouisprCaption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                ForEach(Array(layout.rows.enumerated()), id: \.element) { index, feature in
                    if index > 0 {
                        Divider().padding(.leading, 52)
                    }
                    featureCard(feature)
                }
            }
            .ouisprGlass()
        }
    }

    /// The feature the user just touched, with what it does in one sentence.
    private func focusBlock(_ feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title2)
                .foregroundColor(iconColor(for: feature))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(feature.focusTitle))
                    .font(.ouisprSubheading)
                Text(LocalizedStringKey(feature.focusLine))
                    .font(.ouisprBody)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !feature.isSupportedByThisDevice {
                    unsupportedNotice
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .ouisprGlass()
        .accessibilityElement(children: .combine)
    }

    /// A row of the grouped card: icon, title, description.
    /// Non-interactive (informational only per UI-SPEC). Compact metrics so
    /// the plan cards stay above the fold on a 6.1-inch screen.
    private func featureCard(_ feature: ProFeature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundColor(iconColor(for: feature))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(feature.displayName))
                    .font(.ouisprBody.weight(.semibold))
                Text(LocalizedStringKey(feature.paywallDescription))
                    .font(.ouisprCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                if !feature.isSupportedByThisDevice {
                    unsupportedNotice
                }
            }

            Spacer()
        }
        .padding(12)
        // Dimmed, not hidden, and not disabled: the card is still a truthful part of
        // what Pro contains, and the sentence under it is the point.
        .opacity(feature.isSupportedByThisDevice ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: feature))
    }

    /// The line that makes a paywall honest on a device that cannot run the feature
    /// (#79).
    ///
    /// **This is a review risk before it is a UX one.** Apple Foundation Models needs
    /// an iPhone 15 Pro or later on iOS 26; Ouispr supports iOS 17 up, so most of the
    /// installed base is in this state permanently, and #268 closed the only
    /// alternative backend `wontfix`. A reviewer on a device without Apple
    /// Intelligence, facing a paywall that advertises a feature their hardware cannot
    /// deliver, is a rejection for misleading metadata — and the App Review device on
    /// #207 was an iPad Air.
    ///
    /// WHY the card is marked rather than removed, which #79 left open: a paywall
    /// that silently contains different things on different phones is one nobody can
    /// screenshot for review or reason about in a support thread, and a user who
    /// upgrades their iPhone would never learn the feature had been there all along.
    /// Marking says the same true thing to everyone. Pro still sells on History and
    /// Vocabulary, which is exactly what #79 decided.
    private var unsupportedNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))

            Text("Requires Apple Intelligence (iPhone 15 Pro or later, iOS 26)")
                .font(.ouisprCaption)
                .lineLimit(2)
        }
        .foregroundColor(.secondary)
        .padding(.top, 2)
    }

    /// Each part goes through the catalog first (#279): `ProFeature`'s strings are
    /// English keys, and `accessibilityLabel(_:)` reads a `String` verbatim, so the
    /// combined label was the one English line on a French paywall.
    private func accessibilityLabel(for feature: ProFeature) -> String {
        let name = String(localized: String.LocalizationValue(feature.displayName))
        let description = String(localized: String.LocalizationValue(feature.paywallDescription))
        guard let notice = feature.unsupportedNotice else {
            return "\(name): \(description)"
        }
        return "\(name): \(description). \(String(localized: String.LocalizationValue(notice)))"
    }

    /// Icon color per feature (Smart Mode = accent, others = accent highlight; #789).
    private func iconColor(for feature: ProFeature) -> Color {
        switch feature {
        case .smartMode: return .ouisprAccent
        case .history, .vocabulary, .voiceNotes: return .ouisprAccentHighlight
        }
    }
}

/// The reverse trial as the window's one call to action (Pro bench V1): today, the
/// reminder, the end; then the button that starts it.
///
/// WHY the trial leads and the plans wait behind a link: nothing is charged at the
/// end, so the trial is a decision without risk, and Apple's guidelines ask for one
/// clear call to action on a subscription screen.
struct ProTrialOfferSection: View {
    /// Set by "See the plans": the paywall shows its plans under this section.
    @Binding var showsPlans: Bool

    /// Starts the trial (`ProStatusManager.startTrialIfEligible`).
    let start: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProTrialTimelineView(steps: ProTrialTimeline.steps())
                .padding(16)
                .ouisprGlass()

            Button {
                start()
            } label: {
                Text("Try \(ProTrial.durationDays) days free")
                    .font(.ouisprSubheading)
                    .inkCTALabel()
            }
            .buttonStyle(GlassPressStyle())

            Text("Then subscribe if you wish.")
                .font(.ouisprCaption)
                .foregroundColor(.secondary)

            if !showsPlans {
                Button {
                    withAnimation(.easeInOut(duration: Motion.standard)) {
                        showsPlans = true
                    }
                } label: {
                    Text("See the plans")
                        .font(.ouisprCaption.weight(.semibold))
                        .foregroundColor(.ouisprAccent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Ink call to action

extension View {
    /// The Pro window's main button: ink, like every main action since the design
    /// refresh, with the Pro signature passing once over it (Pro bench V1.1).
    func inkCTALabel() -> some View {
        frame(maxWidth: .infinity, minHeight: 24)
            .padding()
            .background(Color.ouisprInk)
            .foregroundColor(Color.ouisprSurface)
            .proSheen()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The reverse trial in three dated steps (Pro bench V1): a dot per step on one line,
/// the day above the dot, what happens under it.
private struct ProTrialTimelineView: View {
    let steps: [ProTrialTimeline.Step]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 6) {
                    dayTitle(step)
                        .font(.ouisprCaption.weight(.semibold))
                        .foregroundColor(.primary)
                    ZStack {
                        // The line runs between the dots, so none sticks out at the ends.
                        HStack(spacing: 0) {
                            Rectangle().fill(index == 0 ? Color.clear : Color.secondary.opacity(0.3))
                            Rectangle().fill(index == steps.count - 1 ? Color.clear : Color.secondary.opacity(0.3))
                        }
                        .frame(height: 1.5)
                        Circle()
                            .fill(index == 0 ? Color.ouisprInk : Color.ouisprBackground)
                            .overlay(Circle().stroke(Color.ouisprInk, lineWidth: 1.5))
                            .frame(width: 10, height: 10)
                    }
                    Text(LocalizedStringKey(step.detail))
                        .font(.ouisprCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "Today", or "Day 12": the number is a format argument so the catalogue
    /// translates one sentence rather than one per day.
    private func dayTitle(_ step: ProTrialTimeline.Step) -> Text {
        step.day == 0 ? Text("Today") : Text("Day \(step.day)")
    }
}
