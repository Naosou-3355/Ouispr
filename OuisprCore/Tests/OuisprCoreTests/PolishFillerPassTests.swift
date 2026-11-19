// OuisprCore/Tests/OuisprCoreTests/PolishFillerPassTests.swift
import XCTest
@testable import OuisprCore

final class PolishFillerPassTests: XCTestCase {

    private func pass(_ text: String, _ language: SupportedLanguage = .french) -> String {
        PolishFillerPass.apply(text, language: language)
    }

    func testHesitationsInsideASentenceGo() {
        XCTAssertEqual(pass("La tuile qui propose euh une adresse."), "La tuile qui propose une adresse.")
        XCTAssertEqual(pass("Je pense, euh, que oui."), "Je pense, que oui.")
        XCTAssertEqual(pass("disparaissent laisse-les apparents Uh Lorsqu'on referme"), "disparaissent laisse-les apparents Lorsqu'on referme")
    }

    func testASentenceOpeningHesitationGivesItsCapitalToTheNextWord() {
        XCTAssertEqual(pass("Euh, je sais pas trop."), "Je sais pas trop.")
        XCTAssertEqual(pass("En minutes. Euh. La petite pastille."), "En minutes. La petite pastille.")
        XCTAssertEqual(pass("euh on y va"), "On y va")
    }

    func testWordsThatOnlyContainASoundStay() {
        for text in ["Il a humé le café.", "Une heure de route.", "Le umami du plat.", "Bah oui, bon, quoi."] {
            XCTAssertEqual(pass(text), text)
        }
    }

    func testEnglishAndPrepassIntegration() {
        XCTAssertEqual(pass("So um I think uh we should go.", .english), "So I think we should go.")
        XCTAssertEqual(VerbalPunctuationPrepass.apply("euh je arrive virgule attends", language: .french),
                       VerbalPunctuationPrepass.apply("je arrive virgule attends", language: .french).prefix(1).uppercased()
                       + VerbalPunctuationPrepass.apply("je arrive virgule attends", language: .french).dropFirst())
    }
}
