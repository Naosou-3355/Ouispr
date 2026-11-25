// OuisprCore/Tests/OuisprCoreTests/ProHomeCardTests.swift
// The Home Pro card (#216 decision 16): visible in every state, calm once paid.
import XCTest
@testable import OuisprCore

final class ProHomeCardTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func content(paywallVisible: Bool = true,
                         promotion: ProPromotionEntry = .upgrade,
                         isPaid: Bool = false,
                         isEntitled: Bool = false,
                         trial: ProTrialState = .neverStarted,
                         activeFeatures: Int = 4) -> ProHomeCardContent {
        ProHomeCard.content(paywallVisible: paywallVisible, promotion: promotion, isPaid: isPaid,
                            isEntitled: isEntitled, trial: trial, activeFeatures: activeFeatures)
    }

    func testTheHomeScreenOnlyKeepsTheTrialsLastDaysReminder() {
        // Pro offer of 25 Nov 2026: Pro lives in Settings and opens where a Pro
        // feature is touched. The reminder stays, because the Pro window's trial
        // timeline promises it.
        XCTAssertEqual(content(promotion: .trialEnding(daysLeft: 2), isEntitled: true,
                               trial: .running(endsAt: now.addingTimeInterval(86_400))), .trialEnding(daysLeft: 2))
    }

    func testNoUpgradeCardAndNoMemberCardAnyMore() {
        XCTAssertEqual(content(promotion: .upgrade), .hidden)
        XCTAssertEqual(content(promotion: .hidden), .hidden)
        XCTAssertEqual(content(promotion: .hidden, isEntitled: true,
                               trial: .running(endsAt: now.addingTimeInterval(10 * 86_400))), .hidden)
        XCTAssertEqual(content(promotion: .hidden, isPaid: true, isEntitled: true, activeFeatures: 3), .hidden)
    }

    func testNothingWithThePaywallHidden() {
        XCTAssertEqual(content(paywallVisible: false, promotion: .trialEnding(daysLeft: 1)), .hidden)
        XCTAssertEqual(content(paywallVisible: false, promotion: .upgrade, isPaid: true, isEntitled: true), .hidden)
    }
}
