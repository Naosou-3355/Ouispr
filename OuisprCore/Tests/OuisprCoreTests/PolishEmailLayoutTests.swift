// OuisprCore/Tests/OuisprCoreTests/PolishEmailLayoutTests.swift
import XCTest
@testable import OuisprCore

final class PolishEmailLayoutTests: XCTestCase {

    private func layout(_ text: String, _ language: SupportedLanguage? = .french) -> String {
        PolishEmailLayout.apply(text, language: language)
    }

    func testGreetingBodyAndSignatureGoOnTheirOwnLines() {
        XCTAssertEqual(
            layout("Bonjour Marc, je te confirme notre réunion de jeudi. Je t’enverrai l’ordre du jour demain. Bonne journée Alex."),
            "Bonjour Marc,\n\nJe te confirme notre réunion de jeudi. Je t’enverrai l’ordre du jour demain.\n\nBonne journée,\nAlex"
        )
    }

    func testThanksBeforeASignOffIsItsOwnParagraph() {
        XCTAssertEqual(
            layout("Bonjour Madame Martin, la facture comporte une erreur. Pourriez-vous me renvoyer une version corrigée ? Merci d’avance cordialement, Paul Durand."),
            "Bonjour Madame Martin,\n\nLa facture comporte une erreur. Pourriez-vous me renvoyer une version corrigée ?\n\nMerci d’avance.\n\nCordialement,\nPaul Durand"
        )
    }

    func testTopicChangeStartsAParagraph() {
        XCTAssertEqual(
            layout("Bonjour Thomas, je t’envoie le devis. Par ailleurs, j’ai besoin de ta validation. N’hésite pas si tu as des questions. Cordialement, Paul."),
            "Bonjour Thomas,\n\nJe t’envoie le devis.\n\nPar ailleurs, j’ai besoin de ta validation.\n\nN’hésite pas si tu as des questions.\n\nCordialement,\nPaul"
        )
    }

    func testSignOffWithoutSignature() {
        XCTAssertEqual(
            layout("Bonjour à tous, la réunion est déplacée à vendredi. À bientôt."),
            "Bonjour à tous,\n\nLa réunion est déplacée à vendredi.\n\nÀ bientôt."
        )
    }

    func testTextMessagesStayOnOneLine() {
        let sms = "Salut Julie, merci pour ton message, je te redis demain. Bisous."
        XCTAssertEqual(layout(sms), sms)
    }

    func testOneEndAloneIsNotAnEmail() {
        for text in [
            "Bonjour, je voulais savoir si le devis était prêt.",
            "Je voulais savoir si le devis était prêt. Merci d’avance.",
            "Je te confirme la réunion de jeudi. Cordialement, Paul.",
            "Salut Manu, comment tu vas ?",
        ] {
            XCTAssertEqual(layout(text), text)
        }
    }

    func testSpeakersOwnLineBreaksAndOtherLanguagesAreLeftAlone() {
        let own = "Bonjour Marc,\nJe te confirme jeudi. Cordialement, Paul."
        XCTAssertEqual(layout(own), own)
        let english = "Hello Marc, see you Thursday. Best regards, Paul."
        XCTAssertEqual(layout(english, .english), english)
        let flat = "Bonjour Marc, je te confirme jeudi. Cordialement, Paul."
        XCTAssertEqual(layout(flat, nil), flat)
    }

    func testNoWordIsAddedOrLost() {
        let text = "Bonjour Thomas, suite à notre échange, je t’envoie le devis. Par ailleurs, j’ai besoin de ta validation avant lundi. Merci d’avance cordialement, Paul."
        let words: (String) -> [String] = { PolishCleanInput.words($0) }
        XCTAssertEqual(words(layout(text)), words(text))
    }
}
