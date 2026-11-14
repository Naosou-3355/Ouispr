import XCTest
@testable import DictusCore

/// AltStore re-signs a sideloaded app into `<group>.<TEAMID>`; the app and its
/// extensions must all land on that same group.
final class AppGroupResolveTests: XCTestCase {
    private let base = "group.solutions.pivi.dictus"

    func testWithoutAltStoreKeepsBase() {
        XCTAssertEqual(AppGroup.resolve(base: base, altAppGroups: nil), base)
        XCTAssertEqual(AppGroup.resolve(base: base, altAppGroups: []), base)
    }

    func testPicksTeamSuffixedGroup() {
        let groups = ["group.com.rileytestut.AltStore.ABCDE12345", "group.solutions.pivi.dictus.ABCDE12345"]
        XCTAssertEqual(AppGroup.resolve(base: base, altAppGroups: groups), "group.solutions.pivi.dictus.ABCDE12345")
    }

    func testIgnoresGroupsThatOnlyShareAPrefix() {
        let groups = ["group.solutions.pivi.dictusbeta.ABCDE12345"]
        XCTAssertEqual(AppGroup.resolve(base: base, altAppGroups: groups), base)
    }

    func testShortestMatchWins() {
        let groups = ["group.solutions.pivi.dictus.extra.ABCDE12345", "group.solutions.pivi.dictus.ABCDE12345"]
        XCTAssertEqual(AppGroup.resolve(base: base, altAppGroups: groups), "group.solutions.pivi.dictus.ABCDE12345")
    }
}
