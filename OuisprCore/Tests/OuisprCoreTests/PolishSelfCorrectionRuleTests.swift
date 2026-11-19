// OuisprCore/Tests/OuisprCoreTests/PolishSelfCorrectionRuleTests.swift
import XCTest
@testable import OuisprCore

final class PolishSelfCorrectionRuleTests: XCTestCase {

    private func fix(_ text: String) -> String {
        PolishSelfCorrection.apply(text, language: .french)
    }

    func testTheRetractedPartAndTheCueGo() {
        XCTAssertEqual(fix("Je t'attends devant la mairie, pardon, devant la gare."), "Je t'attends devant la gare.")
        XCTAssertEqual(fix("On se voit samedi non pardon dimanche devant le parc."), "On se voit dimanche devant le parc.")
        XCTAssertEqual(fix("La réunion est lundi matin, enfin non, mardi matin."), "La réunion est mardi matin.")
        XCTAssertEqual(fix("Envoie le devis à Léa ou plutôt à Hugo avant ce soir."),
                       "Envoie le devis à Hugo avant ce soir.")
        // Other cues inside a question still correct.
        XCTAssertEqual(fix("Tu peux envoyer le devis à Léa, non pardon, à Hugo ?"), "Tu peux envoyer le devis à Hugo ?")
        XCTAssertEqual(fix("J'ai oublié le dossier, je veux dire les clés, au bureau."), "J'ai oublié les clés, au bureau.")
        XCTAssertEqual(fix("Il part vivre à Lyon en fait non à Rennes en septembre."), "Il part vivre à Rennes en septembre.")
        // Weak cues, and the way Parakeet hears the strong ones.
        XCTAssertEqual(fix("Il part vivre à Marseille, non à Rennes en septembre."), "Il part vivre à Rennes en septembre.")
        XCTAssertEqual(fix("La réunion est samedi matin ou attend vendredi matin."), "La réunion est vendredi matin.")
        XCTAssertEqual(fix("Je t'attends devant la piscine en fin devant le parc."), "Je t'attends devant le parc.")
    }

    func testAnOrdinaryPardonOrNonRemovesNothing() {
        for text in [
            "Pardon, tu as l'heure ?",
            "Je lui ai demandé pardon pour hier.",
            "Non pardon, je ne voulais pas te vexer.",
            "Il a dit non, attends, on verra demain.",
            "Tu préfères la plage ou plutôt la montagne ?",
            "Elle a dit pardon à sa sœur.",
            "Non, je viens pas samedi.",
            "C'est plutôt bien, enfin je crois.",
            "Ce que je veux dire, c'est que ça marche.",
            "Je me suis trompé de bus ce matin.",
            "Je pense que non, je pense que oui.",
            "Tu viens samedi ou non ?",
            "Il a dit non à sa proposition.",
            "Enfin, la réunion est terminée.",
            "Il est enfin arrivé à la gare.",
            "J'attends le bus devant la gare.",
            "Non mais tu crois que je vais à la fête ?"
        ] {
            XCTAssertEqual(fix(text), text, text)
        }
    }

    func testEnglishIsLeftAlone() {
        let text = "See you Monday, sorry, Tuesday."
        XCTAssertEqual(PolishSelfCorrection.apply(text, language: .english), text)
    }
}
