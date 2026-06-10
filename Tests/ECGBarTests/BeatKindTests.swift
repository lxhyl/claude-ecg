import XCTest
@testable import ECGBar

final class BeatKindTests: XCTestCase {
    func testStopArmsFlatline() {
        let kind = BeatKind(event: "Stop")
        XCTAssertEqual(kind.waveform, .normal)
        XCTAssertEqual(kind.sound, .blip)
        XCTAssertEqual(kind.consequence, .armFlatline)
    }

    func testStopFailureArmsFlatlineWithInvertedSpike() {
        let kind = BeatKind(event: "StopFailure")
        XCTAssertEqual(kind.waveform, .inverted)
        XCTAssertEqual(kind.sound, .lowTone)
        XCTAssertEqual(kind.consequence, .armFlatline)
    }

    func testSessionEndFlatlinesImmediately() {
        let kind = BeatKind(event: "SessionEnd")
        XCTAssertEqual(kind.waveform, .normal)
        XCTAssertEqual(kind.consequence, .flatlineNow)
    }

    func testFailuresInvertTheSpike() {
        for event in ["PostToolUseFailure", "PermissionDenied"] {
            let kind = BeatKind(event: event)
            XCTAssertEqual(kind.waveform, .inverted, event)
            XCTAssertEqual(kind.sound, .lowTone, event)
            XCTAssertEqual(kind.consequence, .stayActive, event)
        }
    }

    func testAttentionEventsDemandAttention() {
        for event in ["Notification", "PermissionRequest"] {
            let kind = BeatKind(event: event)
            XCTAssertEqual(kind.waveform, .doublet, event)
            XCTAssertEqual(kind.sound, .chime, event)
            XCTAssertEqual(kind.consequence, .demandAttention, event)
        }
    }

    func testUnknownEventsAreNormalBeats() {
        for event in ["PreToolUse", "test", "refresh", "SomeFutureHook"] {
            let kind = BeatKind(event: event)
            XCTAssertEqual(kind.waveform, .normal, event)
            XCTAssertEqual(kind.sound, .blip, event)
            XCTAssertEqual(kind.consequence, .stayActive, event)
        }
    }
}
