// OuisprCore/Tests/OuisprCoreTests/AppGroupLegacyKeyMigrationTests.swift
import XCTest
@testable import OuisprCore

final class AppGroupLegacyKeyMigrationTests: XCTestCase {
    private let suiteName = "ouispr.tests.legacyKeyMigration"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMovesLegacyValuesToTheNewKeys() {
        defaults.set(true, forKey: "dictus.hasCompletedOnboarding")
        defaults.set("fr", forKey: "dictus.language")

        AppGroup.migrateLegacyKeys(in: defaults)

        XCTAssertTrue(defaults.bool(forKey: SharedKeys.hasCompletedOnboarding))
        XCTAssertEqual(defaults.string(forKey: SharedKeys.language), "fr")
        XCTAssertNil(defaults.object(forKey: "dictus.hasCompletedOnboarding"))
        XCTAssertNil(defaults.object(forKey: "dictus.language"))
    }

    func testKeepsAValueAlreadyUnderTheNewKey() {
        defaults.set("en", forKey: "dictus.language")
        defaults.set("de", forKey: SharedKeys.language)

        AppGroup.migrateLegacyKeys(in: defaults)

        XCTAssertEqual(defaults.string(forKey: SharedKeys.language), "de")
        XCTAssertNil(defaults.object(forKey: "dictus.language"))
    }

    func testLeavesOtherKeysAlone() {
        defaults.set(3, forKey: "recentEmojis")

        AppGroup.migrateLegacyKeys(in: defaults)

        XCTAssertEqual(defaults.integer(forKey: "recentEmojis"), 3)
    }
}
