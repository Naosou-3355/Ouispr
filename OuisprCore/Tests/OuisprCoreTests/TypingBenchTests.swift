// OuisprCore/Tests/OuisprCoreTests/TypingBenchTests.swift
// The typing bench's numbers: speed, word accuracy, character errors, and the store.
import XCTest
@testable import OuisprCore

final class TypingBenchTests: XCTestCase {

    func testNormalizeForgivesTypography() {
        XCTAssertEqual(
            TypingBenchScoring.normalize("  J\u{2019}ai\u{00A0}oublié   mes clés "),
            "J'ai oublié mes clés"
        )
    }

    func testNormalizeKeepsAccentsAndCase() {
        XCTAssertNotEqual(TypingBenchScoring.normalize("cle"), TypingBenchScoring.normalize("clé"))
        XCTAssertNotEqual(TypingBenchScoring.normalize("je"), TypingBenchScoring.normalize("Je"))
    }

    func testEditDistance() {
        XCTAssertEqual(TypingBenchScoring.editDistance(Array("chat"), Array("chat")), 0)
        XCTAssertEqual(TypingBenchScoring.editDistance(Array("chat"), Array("chas")), 1)
        XCTAssertEqual(TypingBenchScoring.editDistance(Array("chat"), Array("")), 4)
        XCTAssertEqual(TypingBenchScoring.editDistance(Array("kitten"), Array("sitting")), 3)
    }

    func testPerfectPhrase() throws {
        // 11 characters typed in 2 s: (11 - 1) / 5 words over 1/30 min = 60 wpm.
        let trial = TypingBenchTrial(target: "Bonjour toi", typed: "Bonjour toi", seconds: 2)
        let score = try XCTUnwrap(TypingBenchScoring.score([trial]))
        XCTAssertEqual(score.wordsPerMinute, 10.0 / 5 / (2.0 / 60), accuracy: 0.001)
        XCTAssertEqual(score.wordAccuracy, 1)
        XCTAssertEqual(score.characterErrorRate, 0)
    }

    func testOneWrongWordOutOfFour() throws {
        let trial = TypingBenchTrial(target: "je vais au cinéma", typed: "je fais au cinéma", seconds: 3)
        let score = try XCTUnwrap(TypingBenchScoring.score([trial]))
        XCTAssertEqual(score.wordAccuracy, 0.75, accuracy: 0.0001)
        XCTAssertEqual(score.characterErrorRate, 1.0 / 17, accuracy: 0.0001)
    }

    func testMissingAndExtraWordsCount() throws {
        let missing = TypingBenchTrial(target: "il fait beau", typed: "il beau", seconds: 1)
        XCTAssertEqual(try XCTUnwrap(TypingBenchScoring.score([missing])).wordAccuracy, 2.0 / 3, accuracy: 0.0001)
        let garbage = TypingBenchTrial(target: "oui", typed: "a b c d e", seconds: 1)
        // Accuracy floors at zero for a phrase, it never goes negative.
        XCTAssertEqual(try XCTUnwrap(TypingBenchScoring.score([garbage])).wordAccuracy, 0)
    }

    func testTrialsAreSummedNotAveraged() throws {
        let short = TypingBenchTrial(target: "oui", typed: "non", seconds: 1)
        let long = TypingBenchTrial(target: "a b c d e f g h i", typed: "a b c d e f g h i", seconds: 4)
        let score = try XCTUnwrap(TypingBenchScoring.score([short, long]))
        // 1 wrong word out of 10, not the average of 0 % and 100 %.
        XCTAssertEqual(score.wordAccuracy, 0.9, accuracy: 0.0001)
        XCTAssertEqual(score.trialCount, 2)
    }

    func testEmptyOrUntimedTrialAddsNoSpeed() throws {
        let empty = TypingBenchTrial(target: "bonjour", typed: "", seconds: 0)
        let score = try XCTUnwrap(TypingBenchScoring.score([empty]))
        XCTAssertEqual(score.wordsPerMinute, 0)
        XCTAssertEqual(score.wordAccuracy, 0)
        XCTAssertEqual(score.characterErrorRate, 1)
        XCTAssertNil(TypingBenchScoring.score([]))
    }

    func testScorePerKeyboard() throws {
        let apple = TypingBenchSession(keyboard: "Apple", trials: [TypingBenchTrial(target: "oui", typed: "oui", seconds: 1)])
        let ouispr = TypingBenchSession(keyboard: "Ouispr", trials: [TypingBenchTrial(target: "oui", typed: "ouo", seconds: 1)])
        XCTAssertEqual(try XCTUnwrap(TypingBenchScoring.score(keyboard: "Apple", in: [apple, ouispr])).wordAccuracy, 1)
        XCTAssertEqual(try XCTUnwrap(TypingBenchScoring.score(keyboard: "Ouispr", in: [apple, ouispr])).wordAccuracy, 0)
        XCTAssertNil(TypingBenchScoring.score(keyboard: "Gboard", in: [apple, ouispr]))
    }

    func testPhrasesAreCleanAndUnique() {
        let phrases = TypingBenchPhrases.french
        XCTAssertEqual(phrases.count, 20)
        XCTAssertEqual(Set(phrases).count, phrases.count)
        for phrase in phrases {
            XCTAssertEqual(TypingBenchScoring.normalize(phrase), phrase, "not normalized: \(phrase)")
        }
    }

    func testStoreRoundTrip() {
        let suite = "TypingBenchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!  // swiftlint:disable:this force_unwrapping
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TypingBenchStore(defaults: defaults)
        XCTAssertEqual(store.all(), [])

        store.append(TypingBenchSession(keyboard: "Apple", trials: []))
        XCTAssertEqual(store.all(), [], "a session with no phrase is not kept")

        let first = TypingBenchSession(keyboard: "Apple", trials: [TypingBenchTrial(target: "a", typed: "a", seconds: 1)])
        let second = TypingBenchSession(keyboard: "Ouispr", trials: [TypingBenchTrial(target: "b", typed: "b", seconds: 1)])
        store.append(first)
        store.append(second)
        XCTAssertEqual(store.all(), [first, second])

        store.delete(id: first.id)
        XCTAssertEqual(store.all(), [second])
        store.deleteAll()
        XCTAssertEqual(store.all(), [])
    }

    func testReportNamesEachKeyboard() {
        let sessions = [
            TypingBenchSession(keyboard: "Apple", trials: [TypingBenchTrial(target: "oui", typed: "oui", seconds: 1)]),
            TypingBenchSession(keyboard: "Ouispr", trials: [TypingBenchTrial(target: "oui", typed: "oui", seconds: 1)])
        ]
        let text = TypingBenchReport.text(sessions: sessions, keyboards: ["Ouispr", "Apple"])
        XCTAssertTrue(text.contains("Ouispr (1 session(s), 1 phrases)"))
        XCTAssertTrue(text.contains("Apple (1 session(s), 1 phrases)"))
        XCTAssertTrue(text.contains("100.0 % de mots justes"))
    }
}
