import XCTest
@testable import Coast

final class ScrollEventPolicyTests: XCTestCase {
    func testSyntheticEventPassesThroughWithoutCancellation() {
        let decision = decide(sourceUserData: CoastConstants.syntheticEventMarker, vertical: 1)
        XCTAssertEqual(decision, .passThrough(cancelPendingMotion: false))
    }

    func testContinuousEventPassesThroughAndCancelsPendingMotion() {
        let decision = decide(isContinuous: true, vertical: 3)
        XCTAssertEqual(decision, .passThrough(cancelPendingMotion: true))
    }

    func testZeroDeltaPassesThrough() {
        XCTAssertEqual(decide(), .passThrough(cancelPendingMotion: false))
    }

    func testDiscreteAxesArePreservedAndSuppressed() {
        XCTAssertEqual(
            decide(vertical: 2, horizontal: -3),
            .suppress(WheelImpulse(verticalTicks: 2, horizontalTicks: -3, timestamp: 12))
        )
    }

    func testShiftConvertsVerticalOnlyInputToHorizontal() {
        XCTAssertEqual(
            decide(vertical: 2, shift: true),
            .suppress(WheelImpulse(verticalTicks: 0, horizontalTicks: 2, timestamp: 12))
        )
    }

    func testShiftDoesNotReplaceNativeHorizontalInput() {
        XCTAssertEqual(
            decide(vertical: 2, horizontal: 1, shift: true),
            .suppress(WheelImpulse(verticalTicks: 2, horizontalTicks: 1, timestamp: 12))
        )
    }

    func testReversalAppliesAfterShiftRouting() {
        var settings = CoastSettings.defaults
        settings.reverseHorizontal = true
        XCTAssertEqual(
            decide(vertical: 2, shift: true, settings: settings),
            .suppress(WheelImpulse(verticalTicks: 0, horizontalTicks: -2, timestamp: 12))
        )
    }

    func testExtremeInputIsClamped() {
        XCTAssertEqual(
            decide(vertical: Int64.max, horizontal: Int64.min),
            .suppress(WheelImpulse(verticalTicks: 20, horizontalTicks: -20, timestamp: 12))
        )
    }

    private func decide(
        sourceUserData: Int64 = 0,
        isContinuous: Bool = false,
        vertical: Int64 = 0,
        horizontal: Int64 = 0,
        shift: Bool = false,
        settings: CoastSettings = .defaults
    ) -> ScrollEventDecision {
        ScrollEventPolicy.decision(
            for: ScrollEventMetadata(
                sourceUserData: sourceUserData,
                isContinuous: isContinuous,
                verticalLineDelta: vertical,
                horizontalLineDelta: horizontal,
                shiftIsPressed: shift,
                timestamp: 12
            ),
            settings: settings
        )
    }
}
