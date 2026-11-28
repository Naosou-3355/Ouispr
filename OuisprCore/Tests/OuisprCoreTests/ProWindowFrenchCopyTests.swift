// OuisprCore/Tests/OuisprCoreTests/ProWindowFrenchCopyTests.swift
// Every string of the Ouispr Pro window has a French value in the app's catalogue (Pro offer, 25 Nov 2026).

import XCTest
@testable import OuisprCore

/// The window's strings are English keys built in OuisprCore, which ships no
/// catalogue, and translated in OuisprApp's. A key with no French value reaches a
/// French iPhone in English (#792), and OuisprApp has no test bundle, so this reads
/// the repo, the way `SettingsFrenchCopyTests` does.
final class ProWindowFrenchCopyTests: XCTestCase {

    private static let catalogue = "OuisprApp/Localizable.xcstrings"

    /// The keys the views write literally: hero, timeline, trial button, history row.
    private static let viewKeys = [
        "Ouispr learns from you",
        "Also included",
        "Try %lld days free",
        "Then subscribe if you wish.",
        "See the plans",
        "Today",
        "Day %lld",
        "%lld older dictations match",
        "Search your whole history with Ouispr Pro",
        "Preview the free version",
        "Relaunch Ouispr to apply."
    ]

    /// The keys OuisprCore builds: every feature's name, description and focus copy,
    /// and the timeline's details.
    private static var coreKeys: [String] {
        ProFeature.allCases.flatMap {
            [$0.displayName, $0.paywallDescription, $0.focusTitle, $0.focusLine]
        } + ProTrialTimeline.steps().map(\.detail)
    }

    func testEveryWindowKeyHasAFrenchValue() throws {
        let strings = try catalogueStrings()
        for key in Self.viewKeys + Self.coreKeys {
            let entry = try XCTUnwrap(strings[key], "the catalogue has no entry for \(key)")
            let values = frenchValues(of: entry)
            XCTAssertFalse(values.isEmpty, "no French value for \(key)")
            for value in values {
                XCTAssertFalse(value.contains("—"), "no em dashes in user-facing copy: \(value)")
                for placeholder in ["%@", "%lld"] where key.contains(placeholder) {
                    XCTAssertTrue(value.contains(placeholder), "\(value) drops \(placeholder)")
                }
            }
        }
    }

    /// The French of the window, as validated on the Pro bench (25 Nov 2026).
    func testTheBenchWordingIsKept() throws {
        let strings = try catalogueStrings()
        let expected = [
            "Also included": "Inclus aussi",
            "Try %lld days free": "Essayer %lld jours gratuitement",
            "Then subscribe if you wish.": "Ensuite, abonnez-vous si vous le souhaitez.",
            "Ouispr learns from you": "Ouispr apprend de vous",
            "The modes": "Les modes",
            "All your history": "Tout votre historique"
        ]
        for (key, french) in expected {
            XCTAssertEqual(frenchValues(of: try XCTUnwrap(strings[key])), [french], key)
        }
    }

    // MARK: - Reading the repo

    private func frenchValues(of entry: [String: Any]) -> [String] {
        guard let localizations = entry["localizations"] as? [String: Any],
              let french = localizations["fr"] as? [String: Any] else { return [] }
        if let unit = french["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        let plural = (french["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        return plural.values.compactMap {
            (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }

    private func catalogueStrings() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent(Self.catalogue))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["strings"] as? [String: [String: Any]]) ?? [:]
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // OuisprCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // OuisprCore
            .deletingLastPathComponent()  // repo root
    }
}
