import XCTest
@testable import OuisprCore

final class LinkLikeTokenTests: XCTestCase {

    func testURLsAreLinkLike() {
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "regarde https://exemple.com/pagge"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "http://exemple"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "va sur www.exemple"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "exemple.com/articles/bonjoru"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "le site exemple.fr"))
    }

    func testEmailsAndPathsAreLinkLike() {
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "écris à nom@exemple"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "nom.prenom@exemple.fr"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "ouvre ~/Documents/rapoprt"))
        XCTAssertTrue(LinkLikeToken.isAtCursor(context: "le fichier index.html"))
    }

    func testOrdinaryWordsAreNot() {
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: ""))
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: "bonjour"))
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: "je vais bien. Bonjoru"))
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: "c'est l'heure"))
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: "fin."))
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: "salut @pseudo"))
        XCTAssertFalse(LinkLikeToken.isAtCursor(context: "lien https://exemple.com puis bonjoru"))
    }
}
