// OuisprCore/Tests/OuisprCoreTests/KeyboardModeTests.swift
// Tests for DefaultKeyboardLayer enum — shared contract for default layer selection.
import XCTest
@testable import OuisprCore

final class KeyboardModeTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    override func tearDown() {
        super.tearDown()
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        defaults?.removeObject(forKey: "ouispr.keyboardMode")
    }

    // MARK: - Cases

    func testEnumHasExactlyTwoCases() {
        XCTAssertEqual(DefaultKeyboardLayer.allCases.count, 2)
    }

    // MARK: - Raw Values

    func testRawValues() {
        XCTAssertEqual(DefaultKeyboardLayer.letters.rawValue, "letters")
        XCTAssertEqual(DefaultKeyboardLayer.numbers.rawValue, "numbers")
    }

    // MARK: - Display Names

    func testDisplayNameLetters() {
        XCTAssertEqual(DefaultKeyboardLayer.letters.displayName, "ABC")
    }

    func testDisplayNameNumbers() {
        XCTAssertEqual(DefaultKeyboardLayer.numbers.displayName, "123")
    }

    // MARK: - Active Property

    func testActiveDefaultsToLetters() {
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        XCTAssertEqual(DefaultKeyboardLayer.active, .letters)
    }

    func testActiveReadsStoredValue() {
        defaults?.set("numbers", forKey: SharedKeys.defaultKeyboardLayer)
        XCTAssertEqual(DefaultKeyboardLayer.active, .numbers)
    }

    func testActiveReturnsLettersForInvalidValue() {
        defaults?.set("invalid", forKey: SharedKeys.defaultKeyboardLayer)
        XCTAssertEqual(DefaultKeyboardLayer.active, .letters)
    }

    // MARK: - Migration

    func testMigrationMicroToNumbers() {
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        defaults?.set("micro", forKey: "ouispr.keyboardMode")

        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.defaultKeyboardLayer), "numbers")
        XCTAssertNil(defaults?.string(forKey: "ouispr.keyboardMode"))
    }

    func testMigrationFullToLetters() {
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        defaults?.set("full", forKey: "ouispr.keyboardMode")

        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.defaultKeyboardLayer), "letters")
        XCTAssertNil(defaults?.string(forKey: "ouispr.keyboardMode"))
    }

    func testMigrationEmojiMicroToLetters() {
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        defaults?.set("emojiMicro", forKey: "ouispr.keyboardMode")

        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.defaultKeyboardLayer), "letters")
        XCTAssertNil(defaults?.string(forKey: "ouispr.keyboardMode"))
    }

    func testMigrationIsIdempotent() {
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        defaults?.set("micro", forKey: "ouispr.keyboardMode")

        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()
        // Second call should be a no-op (new key already exists)
        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.defaultKeyboardLayer), "numbers")
    }

    func testMigrationNoOpWhenNoOldValue() {
        defaults?.removeObject(forKey: SharedKeys.defaultKeyboardLayer)
        defaults?.removeObject(forKey: "ouispr.keyboardMode")

        DefaultKeyboardLayer.migrateFromKeyboardModeIfNeeded()

        // No new key written — defaults will handle it
        XCTAssertNil(defaults?.string(forKey: SharedKeys.defaultKeyboardLayer))
    }

    // MARK: - SharedKeys

    func testSharedKeyValue() {
        XCTAssertEqual(SharedKeys.defaultKeyboardLayer, "ouispr.defaultKeyboardLayer")
    }
}
