// OuisprCore/Tests/OuisprCoreTests/PolishEditCheckTests.swift
import XCTest
@testable import OuisprCore

final class PolishEditCheckTests: XCTestCase {

    private func review(_ polished: String, _ input: String) -> String {
        PolishEditCheck.review(polished: polished, input: input, language: .french)
    }

    func testADroppedPronounComesBackAndTheGoodEditsStay() {
        XCTAssertEqual(
            review("Le bouton qui permet de recentrer la map sur ne fonctionne pas, tout simplement.",
                   "le bouton qui permet de recentrer la map sur nous ne fonctionne pas tout simplement"),
            "Le bouton qui permet de recentrer la map sur nous ne fonctionne pas, tout simplement."
        )
    }

    func testAnAddedNeIsUndone() {
        XCTAssertEqual(review("Ça la referme tout de suite, on ne peut pas la déplacer.",
                              "ça la referme tout de suite on peut pas la déplacer"),
                       "Ça la referme tout de suite, on peut pas la déplacer.")
        XCTAssertEqual(review("Il n’y a pas de souci.", "il y a pas de souci"), "Il y a pas de souci.")
    }

    func testTheSpeakersOwnDeletionsAreKept() {
        // Self-correction (rule 10): "nous" was taken back aloud.
        XCTAssertEqual(review("Vous venez samedi.", "nous venons non pardon vous venez samedi"), "Vous venez samedi.")
        // Stutter (rule 6).
        XCTAssertEqual(review("Je sais pas.", "je je sais pas"), "Je sais pas.")
        // A "ne" the speaker said stays.
        XCTAssertEqual(review("Je ne sais pas.", "je ne sais pas"), "Je ne sais pas.")
    }

    func testLayoutAndOtherLanguagesAreUntouched() {
        let laid = "Bonjour Marc,\n\nJe te confirme jeudi.\n\nCordialement,\nPaul"
        XCTAssertEqual(review(laid, "Bonjour Marc, je te confirme jeudi. Cordialement, Paul."), laid)
        XCTAssertEqual(PolishEditCheck.review(polished: "I can't go.", input: "I can not go", language: .english), "I can't go.")
    }
}
