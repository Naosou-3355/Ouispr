import XCTest
@testable import OuisprCore

/// The preparation screen's per-phase rules (#708).
final class ModelPreparationScreenTests: XCTestCase {

    // MARK: - The first frame (defect 1)

    /// A model whose files are all on disk opens on the optimization frame, never on the
    /// download, not even for the frame before the model manager moves.
    func testAModelOnDiskNeverOpensOnTheDownload() {
        XCTAssertEqual(
            ModelPreparationPhase.displayed(raw: .ready, hasSeenWorkPhase: false, filesOnDisk: true),
            .compiling
        )
    }

    /// A model that has to be fetched opens on the download, as before.
    func testAModelNotOnDiskOpensOnTheDownload() {
        XCTAssertEqual(
            ModelPreparationPhase.displayed(raw: .ready, hasSeenWorkPhase: false, filesOnDisk: false),
            .downloading
        )
    }

    /// Once real work has been seen, a resting state is the end of it, whatever the disk.
    func testAfterWorkTheRestingStateIsReady() {
        for filesOnDisk in [true, false] {
            XCTAssertEqual(
                ModelPreparationPhase.displayed(raw: .ready, hasSeenWorkPhase: true, filesOnDisk: filesOnDisk),
                .ready
            )
        }
    }

    /// A work phase is always drawn as itself: the mask only ever replaces `.ready`.
    func testWorkPhasesAreNeverMasked() {
        for raw in [ModelPreparationPhase.downloading, .compiling, .loading] {
            for seen in [true, false] {
                for filesOnDisk in [true, false] {
                    XCTAssertEqual(
                        ModelPreparationPhase.displayed(raw: raw, hasSeenWorkPhase: seen, filesOnDisk: filesOnDisk),
                        raw
                    )
                }
            }
        }
    }

    // MARK: - The language in the onboarding subtitle

    func testFrenchTakesTheArticle() {
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "français", interfaceLanguage: "fr"), "le français")
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "chinois", interfaceLanguage: "fr"), "le chinois")
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "allemand", interfaceLanguage: "fr"), "l'allemand")
    }

    /// "l'anglais", "l'espagnol", "l'italien", "l'ukrainien", "l'ourdou": the vowels,
    /// accented ones included ("l'écossais" would be one).
    func testFrenchElidesBeforeAVowel() {
        let expectations = [
            "anglais": "l'anglais",
            "espagnol": "l'espagnol",
            "italien": "l'italien",
            "ourdou": "l'ourdou",
            "ukrainien": "l'ukrainien",
            "écossais": "l'écossais"
        ]
        for (name, expected) in expectations {
            XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: name, interfaceLanguage: "fr"), expected)
        }
    }

    /// A y starts a consonant sound: "le yiddish", "le yoruba".
    func testFrenchDoesNotElideBeforeAY() {
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "yiddish", interfaceLanguage: "fr"), "le yiddish")
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "yoruba", interfaceLanguage: "fr"), "le yoruba")
    }

    /// Mute or aspirated h is a fact about each word: the fallback sentence rather than a guess.
    func testFrenchFallsBackBeforeAnH() {
        for name in ["hébreu", "hongrois", "hindi"] {
            XCTAssertNil(ModelPreparationLanguagePhrase.phrase(languageName: name, interfaceLanguage: "fr"), name)
        }
    }

    /// A capitalised name from a locale table still reads as a French noun in the sentence.
    func testFrenchLowercasesTheName() {
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "Français", interfaceLanguage: "fr"), "le français")
    }

    func testEnglishTakesTheBareName() {
        XCTAssertEqual(ModelPreparationLanguagePhrase.phrase(languageName: "French", interfaceLanguage: "en"), "French")
    }

    func testNoNameOrAnotherInterfaceLanguageFallsBack() {
        XCTAssertNil(ModelPreparationLanguagePhrase.phrase(languageName: nil, interfaceLanguage: "fr"))
        XCTAssertNil(ModelPreparationLanguagePhrase.phrase(languageName: "", interfaceLanguage: "en"))
        XCTAssertNil(ModelPreparationLanguagePhrase.phrase(languageName: "Französisch", interfaceLanguage: "de"))
    }
}
