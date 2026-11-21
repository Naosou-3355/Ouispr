// OuisprCore/Tests/OuisprCoreTests/WordRevealPlanTests.swift
// The word-by-word reveal: how a text is cut, and that a long one never makes the
// user wait for it.
import XCTest
@testable import OuisprCore

final class WordRevealPlanTests: XCTestCase {

    func testAWordKeepsItsPunctuation() {
        let plan = WordRevealPlan(text: "Dis à Camille, vers dix-huit heures.")
        XCTAssertEqual(plan.tokens, [
            .word("Dis"), .word("à"), .word("Camille,"), .word("vers"), .word("dix-huit"), .word("heures.")
        ])
        XCTAssertEqual(plan.wordCount, 6)
    }

    func testRepeatedSpacesAndTabsAreOneGap() {
        let plan = WordRevealPlan(text: "  un   deux\ttrois ")
        XCTAssertEqual(plan.tokens, [.word("un"), .word("deux"), .word("trois")])
    }

    func testLineBreaksAreKeptAndTrailingOnesDropped() {
        let plan = WordRevealPlan(text: "Bonjour,\n\nà demain.\n")
        XCTAssertEqual(plan.tokens, [
            .word("Bonjour,"), .lineBreak, .lineBreak, .word("à"), .word("demain.")
        ])
        XCTAssertEqual(plan.wordCount, 3)
    }

    func testAWindowsLineBreakIsOneLineBreak() {
        let plan = WordRevealPlan(text: "un\r\ndeux")
        XCTAssertEqual(plan.tokens, [.word("un"), .lineBreak, .word("deux")])
    }

    func testAnEmptyTextHasNothingToAnimate() {
        for text in ["", "   ", "\n\n"] {
            let plan = WordRevealPlan(text: text)
            XCTAssertEqual(plan.wordCount, 0, "text: \(text.debugDescription)")
            XCTAssertTrue(plan.tokens.isEmpty, "text: \(text.debugDescription)")
            XCTAssertFalse(plan.animatesWordByWord)
            XCTAssertEqual(plan.totalDuration, 0)
        }
    }

    func testAShortTextRevealsAtTheBenchPace() {
        let plan = WordRevealPlan(text: "un deux trois quatre")
        XCTAssertTrue(plan.animatesWordByWord)
        XCTAssertEqual(plan.delay(forWordAt: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(plan.delay(forWordAt: 3), 0.1 + 3 * 0.11, accuracy: 1e-9)
    }

    func testASingleWordDoesNotDivideByZero() {
        let plan = WordRevealPlan(text: "Bonjour")
        XCTAssertEqual(plan.delay(forWordAt: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(plan.totalDuration, 0.45, accuracy: 1e-9)
    }

    func testALongTextSpeedsUpToFitTheCeiling() {
        let text = Array(repeating: "mot", count: 150).joined(separator: " ")
        let plan = WordRevealPlan(text: text)
        XCTAssertTrue(plan.animatesWordByWord)
        XCTAssertEqual(plan.delay(forWordAt: 149), 0.1 + 2.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(plan.totalDuration, 3.0)
        // Still in reading order.
        XCTAssertLessThan(plan.delay(forWordAt: 10), plan.delay(forWordAt: 11))
    }

    func testAVeryLongTextFadesInAtOnce() {
        let text = Array(repeating: "mot", count: 151).joined(separator: " ")
        XCTAssertFalse(WordRevealPlan(text: text).animatesWordByWord)
    }
}
