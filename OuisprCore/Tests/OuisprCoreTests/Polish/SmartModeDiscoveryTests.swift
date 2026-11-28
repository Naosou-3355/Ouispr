// OuisprCore/Tests/OuisprCoreTests/Polish/SmartModeDiscoveryTests.swift
// When the toolbar still teaches the long-press gesture (issues #79, #460).
//
// These tests mutate the real App Group suite, so setUp/tearDown remove the key.
import XCTest
@testable import OuisprCore

final class SmartModeDiscoveryTests: XCTestCase {

    private var defaults: UserDefaults { AppGroup.defaults }

    override func setUp() {
        super.setUp()
        defaults.removeObject(forKey: SharedKeys.smartModeGestureUsed)
        defaults.removeObject(forKey: SharedKeys.smartModeHintShownCount)
    }

    override func tearDown() {
        defaults.removeObject(forKey: SharedKeys.smartModeGestureUsed)
        defaults.removeObject(forKey: SharedKeys.smartModeHintShownCount)
        super.tearDown()
    }

    func testTheHintIsOfferedToSomeoneWhoHasNeverUsedTheGesture() {
        XCTAssertTrue(SmartModeDiscovery.offersHint(deviceCanRunModes: true, fanIsReachable: true, displaysBeforeThisOpening: 0))
    }

    /// It taught what it had to teach.
    func testTheHintRetiresOnceTheGestureHasBeenUsed() {
        SmartModeDiscovery.noteGestureUsed()
        XCTAssertTrue(SmartModeDiscovery.hasUsedGesture)
        XCTAssertFalse(SmartModeDiscovery.offersHint(deviceCanRunModes: true, fanIsReachable: true, displaysBeforeThisOpening: 0))
    }

    /// Most of the installed base cannot run Smart Modes at all, and teaching them a
    /// gesture whose every outcome is a disabled row is worse than silence.
    func testTheHintNeverAppearsOnADeviceThatCannotRunModes() {
        XCTAssertFalse(SmartModeDiscovery.offersHint(deviceCanRunModes: false, fanIsReachable: true, displaysBeforeThisOpening: 0))
    }

    /// #460: with the paywall hidden, the long press opens nothing. An instruction for a
    /// gesture with no outcome is worse than the advertisement the fan used to show —
    /// it is an instruction that appears not to work.
    func testTheHintIsWithheldWhenTheFanCannotBeOpened() {
        XCTAssertFalse(SmartModeDiscovery.offersHint(deviceCanRunModes: true, fanIsReachable: false, displaysBeforeThisOpening: 0))
    }

    // MARK: - Display cap (lot 1.7)

    /// TipKit's MaxDisplayCount: five openings, then the hint retires used or not.
    func testTheHintRetiresAfterFiveOpeningsThatShowedIt() {
        for opening in 0..<SmartModeDiscovery.maxDisplayCount {
            let before = SmartModeDiscovery.displayCount
            XCTAssertEqual(before, opening)
            XCTAssertTrue(SmartModeDiscovery.offersHint(
                deviceCanRunModes: true, fanIsReachable: true, displaysBeforeThisOpening: before
            ), "opening \(opening + 1) still shows it")
            SmartModeDiscovery.noteHintShown()
        }
        XCTAssertEqual(SmartModeDiscovery.displayCount, 5)
        XCTAssertFalse(SmartModeDiscovery.offersHint(
            deviceCanRunModes: true, fanIsReachable: true,
            displaysBeforeThisOpening: SmartModeDiscovery.displayCount
        ))
    }

    /// The fifth opening counts itself at its start and keeps the hint to its end.
    func testTheOpeningThatReachesTheCapKeepsTheHint() {
        for _ in 0..<4 { SmartModeDiscovery.noteHintShown() }
        let before = SmartModeDiscovery.displayCount
        SmartModeDiscovery.noteHintShown()
        XCTAssertTrue(SmartModeDiscovery.offersHint(
            deviceCanRunModes: true, fanIsReachable: true, displaysBeforeThisOpening: before
        ))
    }

    func testTheCounterStopsAtTheCap() {
        for _ in 0..<12 { SmartModeDiscovery.noteHintShown() }
        XCTAssertEqual(SmartModeDiscovery.displayCount, SmartModeDiscovery.maxDisplayCount)
    }

    /// Using the gesture still retires it at once, whatever the count.
    func testUsingTheGestureRetiresItBeforeTheCap() {
        SmartModeDiscovery.noteHintShown()
        SmartModeDiscovery.noteGestureUsed()
        XCTAssertFalse(SmartModeDiscovery.offersHint(
            deviceCanRunModes: true, fanIsReachable: true, displaysBeforeThisOpening: 1
        ))
    }
}
