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
}
