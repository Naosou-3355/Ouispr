import XCTest
@testable import OuisprCore

final class FrenchElisionTests: XCTestCase {

    func testAuditCase() {
        XCTAssertEqual(FrenchElision.apply("Le écoute et les secondes"), "L'écoute et les secondes")
    }

    func testEachElidableWord() {
        XCTAssertEqual(FrenchElision.apply("la histoire de autres que il je ai ne a se est me a te aime"),
                       "l'histoire d'autres qu'il j'ai n'a s'est m'a t'aime")
    }

    func testCapitalsAreKept() {
        XCTAssertEqual(FrenchElision.apply("Que il vienne. Je arrive."), "Qu'il vienne. J'arrive.")
    }

    func testAspiratedHAndExceptionsAreKept() {
        XCTAssertEqual(FrenchElision.apply("le héros de la hauteur le onze le yaourt"),
                       "le héros de la hauteur le onze le yaourt")
    }

    func testSilentHIsElided() {
        XCTAssertEqual(FrenchElision.apply("le homme de hier"), "l'homme d'hier")
    }

    func testYAlone() {
        XCTAssertEqual(FrenchElision.apply("je y vais"), "j'y vais")
    }

    func testImperativePronounIsKept() {
        XCTAssertEqual(FrenchElision.apply("laisse-le entrer, puis-je avoir"), "laisse-le entrer, puis-je avoir")
    }

    func testConsonantsAndPunctuationAreKept() {
        XCTAssertEqual(FrenchElision.apply("le chat, le, et de un"), "le chat, le, et d'un")
    }

    func testUrlsEmailsAndCodeAreNeverTouched() {
        XCTAssertEqual(FrenchElision.apply("de alex@ouispr.app le https://example.fr la a_b"),
                       "de alex@ouispr.app le https://example.fr la a_b")
        XCTAssertEqual(FrenchElision.apply("tape `le ls -a` puis le écran"), "tape `le ls -a` puis l'écran")
    }

    func testSpacingIsPreserved() {
        XCTAssertEqual(FrenchElision.apply("  le  écoute\n"), "  l'écoute\n")
    }

    func testPostpassAppliesItInFrenchOnly() {
        XCTAssertEqual(PolishPostpass.decodeFromEngine("le écoute", language: .french), "l'écoute")
        XCTAssertEqual(PolishPostpass.decodeFromEngine("le écoute", language: .english), "le écoute")
    }
}
