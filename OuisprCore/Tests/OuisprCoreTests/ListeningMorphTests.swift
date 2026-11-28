// OuisprCore/Tests/OuisprCoreTests/ListeningMorphTests.swift
// When the listening screen plays the mic's morph (lot 1.7).
//
// These tests mutate the real App Group suite, so setUp/tearDown remove the keys.
import XCTest
@testable import OuisprCore

final class ListeningMorphTests: XCTestCase {

    private let tap = Date(timeIntervalSince1970: 1_000_000)

    private func clear() {
        AppGroup.defaults.removeObject(forKey: SharedKeys.keyboardMicTappedAt)
        AppGroup.defaults.removeObject(forKey: SharedKeys.keyboardMorphPlayedForTap)
    }

    override func setUp() {
        super.setUp()
        clear()
    }

    override func tearDown() {
        clear()
        super.tearDown()
    }

    private func plays(_ status: DictationStatus, after seconds: TimeInterval, played: Date? = nil) -> Bool {
        ListeningMorph.playsMorph(status: status, lastMicTap: tap, playedForTap: played, now: tap.addingTimeInterval(seconds))
    }

    func testNoTapNoMorph() {
        XCTAssertNil(ListeningMorph.lastMicTap)
        XCTAssertFalse(ListeningMorph.claimMorph(status: .requested))
    }

    /// Alex's case: the tap opens the app, the user comes back, the screen opens in
    /// `.recording` a few seconds later. It still plays.
    func testAScreenOpeningAfterTheTripToTheAppStillPlays() {
        XCTAssertTrue(plays(.requested, after: 0))
        XCTAssertTrue(plays(.recording, after: 5))
        XCTAssertTrue(plays(.recording, after: ListeningMorph.window))
    }

    func testAScreenOpeningLongAfterTheTapDoesNotPlay() {
        XCTAssertFalse(plays(.recording, after: 30))
    }

    func testItNeverPlaysUnderTranscription() {
        XCTAssertFalse(plays(.transcribing, after: 1))
        XCTAssertFalse(plays(.processing, after: 1))
        XCTAssertFalse(plays(.idle, after: 1))
    }

    func testATapInTheFutureDoesNotCount() {
        XCTAssertFalse(plays(.requested, after: -1))
    }

    /// A screen rebuilt by a reclaim (#260) while the user speaks does not play it again.
    func testInRecordingItPlaysOncePerTap() {
        ListeningMorph.noteMicTap(at: tap)
        XCTAssertTrue(ListeningMorph.claimMorph(status: .recording, now: tap.addingTimeInterval(3)))
        XCTAssertFalse(ListeningMorph.claimMorph(status: .recording, now: tap.addingTimeInterval(4)))
        // A new tap plays again.
        let next = tap.addingTimeInterval(60)
        ListeningMorph.noteMicTap(at: next)
        XCTAssertTrue(ListeningMorph.claimMorph(status: .recording, now: next.addingTimeInterval(1)))
    }

    /// The screen of the tap itself does not use up the one played after the app.
    func testPlayingInRequestedLeavesTheRecordingOne() {
        ListeningMorph.noteMicTap(at: tap)
        XCTAssertTrue(ListeningMorph.claimMorph(status: .requested, now: tap))
        XCTAssertTrue(ListeningMorph.claimMorph(status: .recording, now: tap.addingTimeInterval(4)))
    }

    func testTheTapSurvivesInTheAppGroup() throws {
        ListeningMorph.noteMicTap(at: tap)
        XCTAssertEqual(try XCTUnwrap(ListeningMorph.lastMicTap).timeIntervalSince1970, 1_000_000, accuracy: 1e-6)
    }
}
