// DictusCore/Tests/DictusCoreTests/Ouispr/OuisprDefaultsTests.swift
import XCTest
@testable import DictusCore

/// A keychain with nothing in it, that keeps whatever is written for the test's life.
private final class NoTrialKeychain: ProTrialKeychain {
    var record: ProTrialRecord?
    func read() -> ProTrialKeychainRead { record.map(ProTrialKeychainRead.found) ?? .absent }
    func write(_ record: ProTrialRecord) -> Bool {
        self.record = record
        return true
    }
    func add(_ record: ProTrialRecord) -> Bool {
        guard self.record == nil else { return false }
        self.record = record
        return true
    }
    func delete() { record = nil }
}

/// What Ouispr changes from Dictus by default: the polish runs, rule 10's twin is in
/// the Auto prompt, and Pro is owned without a purchase.
final class OuisprDefaultsTests: XCTestCase {

    private let unlocked = FixedProtectedData(isProtectedDataAvailable: true)

    // MARK: - Polish on by default

    func testPolishIsOnForAUserWhoNeverTouchedTheToggle() {
        let store = LockableAppGroupStore(values: [:], isLocked: false)
        AppLaunchDefaults.writeMissingDefaults(to: store, protectedData: unlocked)
        XCTAssertEqual(store.object(forKey: SharedKeys.polishEnabled) as? Bool, true)
    }

    func testPolishStaysOffForAUserWhoSwitchedItOff() {
        let store = LockableAppGroupStore(values: [SharedKeys.polishEnabled: false], isLocked: false)
        AppLaunchDefaults.writeMissingDefaults(to: store, protectedData: unlocked)
        XCTAssertEqual(store.object(forKey: SharedKeys.polishEnabled) as? Bool, false)
    }

    // MARK: - Self-corrections in the Auto prompt

    func testAutoPromptKeepsOnlyTheRightVersionOfASelfCorrection() {
        let prompt = PolishAutoPrompt.instructions()
        XCTAssertTrue(prompt.contains("9. Spoken self-corrections"))
        XCTAssertTrue(prompt.contains("keep ONLY the right version"))
        XCTAssertTrue(prompt.contains("OUTPUT: Je vais aller au cinéma samedi à 17h."))
        XCTAssertTrue(prompt.contains("plus rule 9, which removes what the speaker took back aloud"))
    }

    // MARK: - Pro owned

    func testProIsUnlockedInThisBuild() {
        XCTAssertTrue(PremiumFlags.proUnlocked)
    }

    @MainActor
    func testAnUnlockedEnvironmentReadsAsPaidAndStartsNoTrial() throws {
        let suite = "ouispr.unlock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = ProTrialEnvironment(
            now: Date.init,
            deviceIsCapable: { true },
            paywallVisible: true,
            defaults: defaults,
            store: ProTrialStore(keychain: NoTrialKeychain(), defaults: defaults),
            proUnlocked: true
        )
        let manager = ProStatusManager(environment: environment)
        XCTAssertTrue(manager.isProActive)
        XCTAssertTrue(manager.isPaid)
        XCTAssertFalse(manager.mayStartTrial)
        XCTAssertFalse(manager.endOfTrialPaywallDue)
        XCTAssertNil(manager.trialBadgeDaysLeft)
    }
}
