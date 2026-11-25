// OuisprCore/Tests/OuisprCoreTests/TranscriptionStyleTests.swift
// The transcription style: capitals and punctuation only, storage and fallback.
import XCTest
@testable import OuisprCore

final class TranscriptionStyleTests: XCTestCase {

    // A throwaway suite, not the App Group: `swift test` must never touch the
    // group container (#560).
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TranscriptionStyleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Storage

    func testTheThreeStylesInPickerOrder() {
        XCTAssertEqual(TranscriptionStyle.allCases, [.formal, .casual, .veryCasual])
    }

    /// The raw values are the stored format: renaming one loses the user's choice.
    func testRawValuesAreTheStoredFormat() {
        XCTAssertEqual(TranscriptionStyle.formal.rawValue, "formal")
        XCTAssertEqual(TranscriptionStyle.casual.rawValue, "casual")
        XCTAssertEqual(TranscriptionStyle.veryCasual.rawValue, "veryCasual")
    }

    func testNothingStoredMeansCasual() {
        XCTAssertEqual(TranscriptionStyle.current(in: defaults), .casual)
    }

    func testTheStoredStyleIsRead() {
        defaults.set("veryCasual", forKey: SharedKeys.transcriptionStyle)
        XCTAssertEqual(TranscriptionStyle.current(in: defaults), .veryCasual)
        defaults.set("formal", forKey: SharedKeys.transcriptionStyle)
        XCTAssertEqual(TranscriptionStyle.current(in: defaults), .formal)
    }

    func testAnUnknownStoredValueFallsBackToCasual() {
        defaults.set("excited", forKey: SharedKeys.transcriptionStyle)
        XCTAssertEqual(TranscriptionStyle.current(in: defaults), .casual)
    }

    // MARK: - Formal

    func testFormalChangesNothing() {
        let text = "Salut Marc, à samedi. Tu viens\u{202F}?"
        XCTAssertEqual(TranscriptionStyle.formal.apply(to: text), text)
    }

    // MARK: - Casual

    func testCasualRemovesTheFinalPeriod() {
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Salut Marc, à samedi."), "Salut Marc, à samedi")
    }

    func testCasualKeepsEveryPeriodButTheLast() {
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Première phrase. Deuxième."), "Première phrase. Deuxième")
    }

    func testCasualIgnoresTrailingWhitespace() {
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Bon.\n"), "Bon\n")
    }

    func testCasualKeepsQuestionAndExclamationMarks() {
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Tu viens\u{202F}?"), "Tu viens\u{202F}?")
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Génial\u{202F}!"), "Génial\u{202F}!")
    }

    func testCasualKeepsAnEllipsis() {
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Et voilà..."), "Et voilà...")
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "Et voilà…"), "Et voilà…")
    }

    func testCasualKeepsThePeriodOfEtc() {
        let text = "Des pommes, des poires, etc."
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: text), text)
    }

    func testCasualOnEmptyText() {
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: ""), "")
        XCTAssertEqual(TranscriptionStyle.casual.apply(to: "  "), "  ")
    }

    // MARK: - Very casual

    func testVeryCasualDropsCapitalsCommasAndPeriods() {
        XCTAssertEqual(
            TranscriptionStyle.veryCasual.apply(
                to: "Salut Marc, pour samedi on dit 17h. Tu prends la glace\u{202F}? Merci."
            ),
            "salut Marc pour samedi on dit 17h tu prends la glace\u{202F}? merci"
        )
    }

    func testVeryCasualKeepsDecimals() {
        XCTAssertEqual(TranscriptionStyle.veryCasual.apply(to: "Il fait 3,5 degrés."), "il fait 3,5 degrés")
    }

    func testVeryCasualKeepsAcronymsAndInnerCapitals() {
        XCTAssertEqual(TranscriptionStyle.veryCasual.apply(to: "La PR est prête. OK pour moi."),
                       "la PR est prête OK pour moi")
        XCTAssertEqual(TranscriptionStyle.veryCasual.apply(to: "L'iPhone est là."), "l'iPhone est là")
    }

    func testVeryCasualLowercasesAccentedCapitals() {
        XCTAssertEqual(TranscriptionStyle.veryCasual.apply(to: "À demain."), "à demain")
    }

    func testVeryCasualKeepsAnEllipsis() {
        XCTAssertEqual(TranscriptionStyle.veryCasual.apply(to: "J'arrive... Attends."), "j'arrive... attends")
    }

    func testVeryCasualLowercasesEachListLine() {
        XCTAssertEqual(
            TranscriptionStyle.veryCasual.apply(to: "Samedi\u{202F}:\n- Prendre les boissons\n- Moi\u{202F}: le gâteau"),
            "samedi\u{202F}:\n- prendre les boissons\n- moi\u{202F}: le gâteau"
        )
    }

    /// A style changes the form, never the words: same words, same order.
    func testNoStyleChangesAWord() {
        let text = "Salut Marc, pour samedi on avait dit chez toi à 17h. Léa viendra en retard."
        func words(_ value: String) -> [String] {
            value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        for style in TranscriptionStyle.allCases {
            XCTAssertEqual(words(style.apply(to: text)), words(text), "\(style)")
        }
    }
}
