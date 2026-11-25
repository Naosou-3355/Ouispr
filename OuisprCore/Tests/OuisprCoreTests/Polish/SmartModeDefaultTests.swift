// OuisprCore/Tests/OuisprCoreTests/Polish/SmartModeDefaultTests.swift
// The mode the app returns to after a dictation.
//
// These tests mutate the real App Group suite, so setUp/tearDown remove the keys.
import XCTest
@testable import OuisprCore

final class SmartModeDefaultTests: XCTestCase {

    private let keys = [SharedKeys.smartModeArmed, SharedKeys.smartModeDefault, SharedKeys.smartModeSkipAnnounced]

    override func setUp() {
        super.setUp()
        keys.forEach { AppGroup.defaults.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { AppGroup.defaults.removeObject(forKey: $0) }
        super.tearDown()
    }

    func testNormalIsTheDefaultDefault() {
        XCTAssertNil(SmartModeDefault.identifier)
        XCTAssertNil(SmartModeDefault.mode)
    }

    func testReturningWithoutADefaultDisarms() {
        SmartModeStore.arm(SmartModeCatalogue.notes)
        SmartModeDefault.returnToDefault()
        XCTAssertNil(SmartModeStore.armedIdentifier)
    }

    func testReturningArmsTheDefault() {
        SmartModeDefault.set(SmartModeCatalogue.notes)
        SmartModeStore.arm(SmartModeCatalogue.translate(to: .english))
        SmartModeDefault.returnToDefault()
        XCTAssertEqual(SmartModeStore.armedIdentifier, "notes")
    }

    func testSettingNormalClearsTheDefault() {
        SmartModeDefault.set(SmartModeCatalogue.notes)
        SmartModeDefault.set(nil)
        XCTAssertNil(SmartModeDefault.identifier)
    }

    func testAnUnknownIdentifierReadsAsNormalWithoutBeingCleared() {
        AppGroup.defaults.set("gone.mode", forKey: SharedKeys.smartModeDefault)
        XCTAssertNil(SmartModeDefault.mode)
        XCTAssertEqual(SmartModeDefault.identifier, "gone.mode")
        SmartModeDefault.returnToDefault()
        XCTAssertNil(SmartModeStore.armedIdentifier)
    }
}
