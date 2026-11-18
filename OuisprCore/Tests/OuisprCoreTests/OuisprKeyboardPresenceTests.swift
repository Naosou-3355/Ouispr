// OuisprCore/Tests/OuisprCoreTests/OuisprKeyboardPresenceTests.swift
// Reading the Ouispr keyboard's presence from the keyboard list (#713).
import XCTest
@testable import OuisprCore

final class OuisprKeyboardPresenceTests: XCTestCase {

    func testOuisprInTheListIsListedUnderItsIdentifier() {
        let presence = OuisprKeyboardPresence(inputModeIdentifiers: [
            "fr_FR@sw=AZERTY-French;hw=Automatic",
            "com.pivi.dictus.keyboard",
            "emoji@sw=Emoji"
        ])
        XCTAssertEqual(presence, .listed(identifier: "com.pivi.dictus.keyboard"))
        XCTAssertTrue(presence.isListed)
    }

    /// The measured case of #713: three keyboards left, Ouispr removed.
    func testAListWithoutOuisprIsNotListed() {
        let presence = OuisprKeyboardPresence(inputModeIdentifiers: [
            "fr_FR@sw=AZERTY-French;hw=Automatic",
            "en_US@sw=QWERTY;hw=Automatic",
            "emoji@sw=Emoji"
        ])
        XCTAssertEqual(presence, .notListed)
        XCTAssertFalse(presence.isListed)
    }

    /// iOS never lets the last keyboard go, so an empty list says nothing about Ouispr and
    /// must not revert the onboarding step.
    func testAnEmptyListIsUnreadableNotAbsent() {
        let presence = OuisprKeyboardPresence(inputModeIdentifiers: [])
        XCTAssertEqual(presence, .unreadable)
        XCTAssertFalse(presence.isListed)
    }

    func testAnotherAppsKeyboardIsNotTakenForOuispr() {
        XCTAssertEqual(
            OuisprKeyboardPresence(inputModeIdentifiers: ["com.example.dictation.keyboard"]),
            .notListed
        )
    }
}
