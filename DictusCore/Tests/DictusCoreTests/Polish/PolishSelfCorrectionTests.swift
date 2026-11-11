// DictusCore/Tests/DictusCoreTests/Polish/PolishSelfCorrectionTests.swift
import XCTest
@testable import DictusCore

/// Rule 10 of the French Natural prompt: a spoken self-correction keeps only the
/// right version. The prompt asks for it; the lost-word check has to let the
/// retracted words go, and only those.
final class PolishSelfCorrectionTests: XCTestCase {

    private func lost(_ raw: String, _ polished: String) -> [String] {
        PolishLostWords.lostWords(polished: polished, raw: raw, languageCode: "fr")
    }

    // MARK: - Prompt

    func testPromptAsksToKeepOnlyTheRightVersion() {
        let prompt = PolishNaturalPromptFR.instructions()
        XCTAssertTrue(prompt.contains("10. Spoken self-corrections"))
        XCTAssertTrue(prompt.contains("keep ONLY the right version"))
        XCTAssertTrue(prompt.contains("OUTPUT: Je vais aller au cinéma samedi à 17h."))
        // The licence list still names the original rules, so parity holds.
        XCTAssertTrue(prompt.contains("Rules 4, 6 and 7 are the only licence to remove a word"))
        XCTAssertTrue(prompt.contains("plus rule 10, which removes what the speaker took back aloud"))
    }

    // MARK: - Lost-word check

    /// The dictation the rule exists for.
    func testRetractedDayAndTimeMayGo() {
        let raw = "Je vais aller au cinéma dimanche à 15h. Ah en fait non, c'est samedi à 17h."
        XCTAssertEqual(lost(raw, "Je vais aller au cinéma samedi à 17h."), [])
    }

    /// The right version, after the cue, stays protected.
    func testCorrectedVersionStaysProtected() {
        let raw = "Je vais aller au cinéma dimanche à 15h. Ah en fait non, c'est samedi à 17h."
        XCTAssertEqual(lost(raw, "Je vais aller au cinéma dimanche à 15h."), ["17", "samedi"])
    }

    /// Without a cue, a dropped word is still a loss.
    func testNoCueStillRefusesADroppedWord() {
        XCTAssertEqual(lost("On va au cinéma dimanche et samedi.", "On va au cinéma samedi."), ["dimanche"])
    }

    /// A word further back than the window stays protected.
    func testWordOutsideTheWindowStaysProtected() {
        let raw = "Dis à Julie que le dossier Martin est prêt depuis lundi matin "
            + "et que je vais aller au cinéma dimanche ah non samedi."
        let polished = "Dis que le dossier Martin est prêt depuis lundi matin "
            + "et que je vais aller au cinéma samedi."
        XCTAssertEqual(lost(raw, polished), ["julie"])
    }

    /// A bare `non` answering a question opens no window.
    func testBareNonIsNotACue() {
        let keys = PolishLostWords.keys(in: "Tu viens dimanche ? Non, samedi.")
        XCTAssertEqual(PolishLostWords.retractedWords(in: keys,
                                                      cues: PolishLostWordsLexicon.french.selfCorrectionCues),
                       [:])
    }
}
