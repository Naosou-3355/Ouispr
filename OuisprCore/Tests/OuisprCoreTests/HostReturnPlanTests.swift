// OuisprCore/Tests/OuisprCoreTests/HostReturnPlanTests.swift
// The order of the ways back to the host app (lot 1.8).
import XCTest
@testable import OuisprCore

final class HostReturnPlanTests: XCTestCase {

    /// Alex's capture: Claude has no scheme on purpose, so before lot 1.8 nothing
    /// happened. Now the system back link and the bundle come first.
    func testClaudeGoesBackWithoutAScheme() {
        XCTAssertEqual(HostReturnPlan.steps(hostId: "com.anthropic.claude"), [
            .systemBack, .openApplication(bundleId: "com.anthropic.claude"), .manual
        ])
    }

    func testSafariToo() {
        XCTAssertEqual(HostReturnPlan.steps(hostId: "com.apple.mobilesafari"), [
            .systemBack, .openApplication(bundleId: "com.apple.mobilesafari"), .manual
        ])
    }

    /// A mapped app keeps its scheme, but after the two that resume where the user was.
    func testAMappedAppTriesItsSchemeLast() throws {
        let host = "net.whatsapp.WhatsApp"
        let url = try XCTUnwrap(KnownAppSchemes.returnURL(forHostId: host), "fixture: a mapped host")
        XCTAssertEqual(HostReturnPlan.steps(hostId: host), [
            .systemBack, .openApplication(bundleId: host), .urlScheme(url), .manual
        ])
    }

    /// An unknown host still has the system back link.
    func testAnUnidentifiedHostStillTriesTheBackLink() {
        XCTAssertEqual(HostReturnPlan.steps(hostId: nil), [.systemBack, .manual])
        XCTAssertEqual(HostReturnPlan.steps(hostId: ""), [.systemBack, .manual])
    }

    /// View services and the home screen cannot be launched by identifier.
    func testViewServicesSkipTheBundleStep() {
        XCTAssertEqual(HostReturnPlan.steps(hostId: "com.apple.SafariViewService"), [.systemBack, .manual])
        XCTAssertEqual(HostReturnPlan.steps(hostId: "com.apple.springboard"), [.systemBack, .manual])
    }

    /// Dictating inside Ouispr itself: nowhere to go back to.
    func testOuisprItselfHasNowhereToGo() {
        for host in ["com.pivi.dictus", "com.pivi.ouisprbeta", "com.pivi.ouisprbeta.2TAS4PL5SA", "com.pivi.dictus.2TAS4PL5SA"] {
            XCTAssertEqual(HostReturnPlan.steps(hostId: host), [.manual], host)
        }
        XCTAssertNotEqual(HostReturnPlan.steps(hostId: "com.pivi.dictusother"), [.manual])
    }

    func testEveryPlanEndsWithTheGesture() {
        for host in [nil, "com.apple.mobilenotes", "com.apple.MobileSMS", "com.apple.reminders", "x"] {
            XCTAssertEqual(HostReturnPlan.steps(hostId: host).last, .manual)
        }
    }
}
