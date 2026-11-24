// OuisprCore/Tests/OuisprCoreTests/OuisprVariantTests.swift
import XCTest
@testable import OuisprCore

final class OuisprVariantTests: XCTestCase {
    func testEverydayIdentifiersAreStandard() {
        for identifier in [nil, "com.pivi.dictus", "com.pivi.dictus.keyboard", "com.pivi.dictus.ABCDE.keyboard",
                           "com.apple.dt.xctest.tool"] {
            XCTAssertEqual(OuisprVariant.resolve(bundleIdentifier: identifier), .standard)
        }
    }

    func testBetaIdentifiersAreBeta() {
        for identifier in ["com.pivi.ouisprbeta", "com.pivi.ouisprbeta.keyboard", "com.pivi.ouisprbeta.ABCDE",
                           "com.pivi.ouisprbeta.ABCDE.keyboard"] {
            XCTAssertEqual(OuisprVariant.resolve(bundleIdentifier: identifier), .beta)
        }
    }

    func testAnIdentifierThatOnlyStartsLikeTheBetaIsNotTheBeta() {
        XCTAssertEqual(OuisprVariant.resolve(bundleIdentifier: "com.pivi.ouisprbetatest"), .standard)
    }

    /// The whole point of the Beta: no name of one variant may reach the other.
    func testTheTwoVariantsShareNoName() {
        let standard = OuisprVariant.standard
        let beta = OuisprVariant.beta
        XCTAssertNotEqual(standard.appGroupBase, beta.appGroupBase)
        XCTAssertNotEqual(standard.urlScheme, beta.urlScheme)
        XCTAssertNotEqual(standard.notificationPrefix, beta.notificationPrefix)
        XCTAssertNotEqual(standard.bundlePrefix, beta.bundlePrefix)
    }

    /// The tests elsewhere use prefix and containment checks, so neither name may sit
    /// inside the other: a keyboard of one variant would otherwise pass for the other's.
    func testNeitherBundlePrefixContainsTheOther() {
        let standard = OuisprVariant.standard.bundlePrefix
        let beta = OuisprVariant.beta.bundlePrefix
        XCTAssertFalse(standard.contains(beta))
        XCTAssertFalse(beta.contains(standard))
        XCTAssertFalse(OuisprVariant.beta.appGroupBase.hasPrefix(OuisprVariant.standard.appGroupBase + "."))
        XCTAssertFalse(OuisprVariant.standard.appGroupBase.hasPrefix(OuisprVariant.beta.appGroupBase + "."))
    }

    func testTheTestHostIsTheStandardApp() {
        XCTAssertEqual(OuisprVariant.current, .standard)
        XCTAssertEqual(AppGroup.baseIdentifier, "group.solutions.pivi.dictus")
    }
}
