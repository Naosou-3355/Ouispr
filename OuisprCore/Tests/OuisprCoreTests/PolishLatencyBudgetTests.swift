// OuisprCore/Tests/OuisprCoreTests/PolishLatencyBudgetTests.swift
import XCTest
@testable import OuisprCore

final class PolishLatencyBudgetTests: XCTestCase {

    private func words(_ count: Int) -> String {
        (0..<count).map { $0 % 2 == 0 ? "beau" : "mot" }.joined(separator: " ")
    }

    func testTheBudgetGrowsWithLengthAndStops() {
        XCTAssertEqual(PolishLatencyBudget.seconds(for: words(10), language: .french), 0)
        XCTAssertEqual(PolishLatencyBudget.seconds(for: words(15), language: .french), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PolishLatencyBudget.seconds(for: words(150), language: .french), 1.5, accuracy: 1e-9)
        XCTAssertEqual(PolishLatencyBudget.seconds(for: words(600), language: .french), 1.5, accuracy: 1e-9)
        XCTAssertLessThan(PolishLatencyBudget.seconds(for: words(60), language: .french), 1.5)
    }

    func testShortDictationsOnlyTheModelCanFixGetTheMessageBudget() {
        XCTAssertEqual(PolishLatencyBudget.seconds(for: "on se voit samedi non pardon dimanche", language: .french), 0.5)
        XCTAssertEqual(PolishLatencyBudget.seconds(for: "il m'a dit un truc de fou il sort avec Anne", language: .french), 0.5)
        XCTAssertEqual(PolishLatencyBudget.seconds(for: "je t'appelle ce soir", language: .french), 0)
    }

    func testAModelPastTheBudgetGivesWayToTheFloor() async {
        let job = PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false)
        let start = Date()
        let result = await PolishPipeline.transform(
            preprocessed: "je te rappelle ce soir", engine: SleepingEngine(seconds: 2),
            job: job, gate: PolishAvailabilityGate(), budget: 0.1
        )
        XCTAssertEqual(result.outcome, .overTimeBudget)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1, "the caller must not wait for the model")
        XCTAssertNotNil(PolishPipeline.resolvedOutput(result, preprocessed: "je te rappelle ce soir", job: job))
    }

    func testAModelInsideTheBudgetIsKeptAndZeroNeverCallsIt() async {
        let job = PolishJob(task: .natural, promptLanguage: .french, languageAgnosticPath: false)
        let fast = await PolishPipeline.transform(
            preprocessed: "je te rappelle ce soir", engine: SleepingEngine(seconds: 0),
            job: job, gate: PolishAvailabilityGate(), budget: 1
        )
        XCTAssertEqual(fast.outcome, .success)
        let none = await PolishPipeline.transform(
            preprocessed: "je te rappelle ce soir", engine: SleepingEngine(seconds: 0),
            job: job, gate: PolishAvailabilityGate(), budget: 0
        )
        XCTAssertEqual(none.outcome, .overTimeBudget)
        XCTAssertEqual(none.engineMs, 0)
    }
}

private struct SleepingEngine: PolishEngineProtocol {
    let seconds: Double
    let identifier = "sleeping-engine"

    func polish(raw: String, targetLanguage: SupportedLanguage, task: PolishTask) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return raw.prefix(1).uppercased() + raw.dropFirst() + "."
    }
}
