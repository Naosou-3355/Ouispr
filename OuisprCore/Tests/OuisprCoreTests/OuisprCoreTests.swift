// OuisprCore/Tests/OuisprCoreTests/OuisprCoreTests.swift
import XCTest
@testable import OuisprCore

final class OuisprCoreTests: XCTestCase {

    func testAppGroupIdentifier() {
        XCTAssertEqual(AppGroup.identifier, "group.solutions.pivi.dictus")
    }

    func testDictationStatusRawValues() {
        // Verify raw values match what we write to UserDefaults
        XCTAssertEqual(DictationStatus.idle.rawValue, "idle")
        XCTAssertEqual(DictationStatus.requested.rawValue, "requested")
        XCTAssertEqual(DictationStatus.recording.rawValue, "recording")
        XCTAssertEqual(DictationStatus.transcribing.rawValue, "transcribing")
        XCTAssertEqual(DictationStatus.processing.rawValue, "processing")
        XCTAssertEqual(DictationStatus.ready.rawValue, "ready")
        XCTAssertEqual(DictationStatus.failed.rawValue, "failed")
    }

    func testDictationStatusCodable() throws {
        let status = DictationStatus.recording
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DictationStatus.self, from: data)
        XCTAssertEqual(decoded, status)
    }

    func testSharedKeysAreUnique() {
        let keys = [
            SharedKeys.dictationStatus,
            SharedKeys.lastTranscription,
            SharedKeys.lastTranscriptionTimestamp,
            SharedKeys.lastError,
        ]
        XCTAssertEqual(keys.count, Set(keys).count, "SharedKeys must be unique")
    }

    func testSharedKeysPrefix() {
        // All keys should use ouispr. prefix to avoid collisions
        XCTAssertTrue(SharedKeys.dictationStatus.hasPrefix("ouispr."))
        XCTAssertTrue(SharedKeys.lastTranscription.hasPrefix("ouispr."))
        XCTAssertTrue(SharedKeys.lastTranscriptionTimestamp.hasPrefix("ouispr."))
        XCTAssertTrue(SharedKeys.lastError.hasPrefix("ouispr."))
    }

    func testAppGroupDiagnosticRun() {
        // Note: This test works in simulator where App Group may not be
        // configured. It verifies the function runs without crashing.
        // On device with correct entitlements, canWrite/canRead should be true.
        let result = AppGroupDiagnostic.run()
        XCTAssertEqual(result.appGroupID, AppGroup.identifier)
        // containerExists may be false in test environment — that's OK
    }
}
