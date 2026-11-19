// OuisprCore/Tests/OuisprCoreTests/PolishCleanInputTests.swift
import XCTest
@testable import OuisprCore

final class PolishCleanInputTests: XCTestCase {

    private func clean(_ text: String, _ language: SupportedLanguage = .french) -> Bool {
        PolishCleanInput.isClean(text, language: language)
    }

    func testShortPunctuatedSentencesAreClean() {
        XCTAssertTrue(clean("Je te rappelle dès que je sors de ma réunion."))
        XCTAssertTrue(clean("Salut, tu peux m'envoyer le document avant midi ?"))
        XCTAssertTrue(clean("On se retrouve à 18h30 devant la gare. Ça te va ?"))
        XCTAssertTrue(clean("I'll call you back after the meeting.", .english))
    }

    func testEveryPromptRuleKeepsTheModel() {
        // rules 1–2: capitals and final punctuation
        XCTAssertFalse(clean("je te rappelle dès que je sors."))
        XCTAssertFalse(clean("Je te rappelle dès que je sors"))
        XCTAssertFalse(clean("Je te rappelle. on se voit demain."))
        // rule 3: spelled-out numbers
        XCTAssertFalse(clean("On se retrouve à dix-huit heures."))
        // rule 4: verbal punctuation left over
        XCTAssertFalse(clean("Liste de point, pain, œufs."))
        // rule 5: line breaks
        XCTAssertFalse(clean("Bonjour,<<NL>>À demain."))
        // rule 6: stutter
        XCTAssertFalse(clean("Je je sais pas trop."))
        // rule 7: fillers
        XCTAssertFalse(clean("Euh, je sais pas trop."))
        XCTAssertFalse(clean("C'est pas grave, tu vois."))
        // rule 10: self-corrections
        XCTAssertFalse(clean("On se voit samedi, non pardon, dimanche."))
        XCTAssertFalse(clean("Je passe demain, en fait jeudi."))
        XCTAssertFalse(clean("Call me tomorrow, I mean Friday.", .english))
    }

    func testLongDictationsKeepTheModel() {
        // Distinct words, so no stutter rule fires: "a b a b …".
        func sentence(_ count: Int) -> String {
            "Un" + (1..<count).map { $0 % 2 == 0 ? " mot" : " beau" }.joined() + "."
        }
        XCTAssertTrue(clean(sentence(PolishCleanInput.maximumWords)))
        XCTAssertFalse(clean(sentence(PolishCleanInput.maximumWords + 1)))
    }

    func testLanguagesWithoutWordListsKeepTheModel() {
        XCTAssertFalse(clean("Te llamo después de la reunión.", .spanish))
        XCTAssertFalse(clean("Ich rufe dich nach dem Meeting an.", .german))
    }

    func testGateNeverSkipsASmartModeAMixedOrAnOffLanguageTranscript() {
        let text = "Je te rappelle dès que je sors de ma réunion."
        XCTAssertTrue(PolishGatePolicy.skipsForCleanInput(text, language: .french, isMixed: false, task: .natural))
        XCTAssertFalse(PolishGatePolicy.skipsForCleanInput(text, language: nil, isMixed: false, task: .natural))
        XCTAssertFalse(PolishGatePolicy.skipsForCleanInput(text, language: .french, isMixed: true, task: .natural))
        let smart = PolishTask.smart(SmartModeCatalogue.notes)
        XCTAssertFalse(PolishGatePolicy.skipsForCleanInput(text, language: .french, isMixed: false, task: smart))
    }
}
