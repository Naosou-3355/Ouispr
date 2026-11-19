// OuisprCore/Tests/OuisprCoreTests/SharedKeysExtensionTests.swift
// Tests for SharedKeys extensions: language, hapticsEnabled, hasCompletedOnboarding.
import XCTest
@testable import OuisprCore

final class SharedKeysExtensionTests: XCTestCase {

    func testLanguageKeyExists() {
        XCTAssertEqual(SharedKeys.language, "ouispr.language")
    }

    func testHapticsEnabledKeyExists() {
        XCTAssertEqual(SharedKeys.hapticsEnabled, "ouispr.hapticsEnabled")
    }

    func testHasCompletedOnboardingKeyExists() {
        XCTAssertEqual(SharedKeys.hasCompletedOnboarding, "ouispr.hasCompletedOnboarding")
    }

    func testNewKeysAreUnique() {
        let newKeys = [
            SharedKeys.language,
            SharedKeys.hapticsEnabled,
            SharedKeys.hasCompletedOnboarding,
        ]
        XCTAssertEqual(newKeys.count, Set(newKeys).count, "SharedKeys must be unique")
    }

    func testNewKeysHaveOuisprPrefix() {
        XCTAssertTrue(SharedKeys.language.hasPrefix("ouispr."))
        XCTAssertTrue(SharedKeys.hapticsEnabled.hasPrefix("ouispr."))
        XCTAssertTrue(SharedKeys.hasCompletedOnboarding.hasPrefix("ouispr."))
    }
}
