import XCTest
@testable import Coast

final class ScrollPhysicsEngineTests: XCTestCase {
    func testOneImpulseEasesOutAndTravelsConfiguredDistance() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))

        var emitted = 0
        var velocities: [Double] = []
        for frame in 1 ... 90 {
            emitted += Int(model.advance(to: Double(frame) / 120).vertical)
            velocities.append(abs(model.verticalVelocityForTesting))
        }

        XCTAssertEqual(emitted, 40, accuracy: 1)
        XCTAssertFalse(model.isActive)
        XCTAssertTrue(zip(velocities, velocities.dropFirst()).allSatisfy { $0 >= $1 })
    }

    func testOneImpulseStopsAtConfiguredDuration() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 10))

        _ = model.advance(to: 10.699)
        XCTAssertTrue(model.isActive)
        _ = model.advance(to: 10.701)
        XCTAssertFalse(model.isActive)
    }

    func testCubicEaseOutMovesMostDistanceInFirstHalf() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))

        var emitted = 0
        for frame in 1 ... 42 {
            emitted += Int(model.advance(to: Double(frame) / 120).vertical)
        }

        XCTAssertEqual(emitted, 35, accuracy: 1)
        XCTAssertTrue(model.isActive)
    }

    func testOverlappingImpulsesContinueExistingAnimation() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))
        _ = model.advance(to: 0.1)
        let velocityBeforeSecondImpulse = model.verticalVelocityForTesting

        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0.1))

        XCTAssertGreaterThan(model.verticalVelocityForTesting, velocityBeforeSecondImpulse)
        _ = model.advance(to: 0.701)
        XCTAssertTrue(model.isActive)
        _ = model.advance(to: 0.801)
        XCTAssertFalse(model.isActive)
    }

    func testRapidSameDirectionImpulsesAcceleratePredictably() {
        var baseline = ScrollPhysicsModel()
        baseline.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))
        let firstImpulseVelocity = baseline.verticalVelocityForTesting

        var accelerated = ScrollPhysicsModel()
        accelerated.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))
        _ = accelerated.advance(to: 0.05)
        let decayedVelocity = accelerated.verticalVelocityForTesting
        accelerated.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0.05))

        let addedVelocity = accelerated.verticalVelocityForTesting - decayedVelocity
        XCTAssertEqual(addedVelocity / firstImpulseVelocity, 1.25, accuracy: 0.001)
    }

    func testAccelerationResetsOutsideWindowAndNeverExceedsMaximum() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))
        let baseVelocity = model.verticalVelocityForTesting

        _ = model.advance(to: 0.1)
        let beforeSlowImpulse = model.verticalVelocityForTesting
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0.1))
        XCTAssertEqual(model.verticalVelocityForTesting - beforeSlowImpulse, baseVelocity, accuracy: 0.001)

        for index in 1 ... 20 {
            let time = 0.1 + Double(index) * 0.01
            _ = model.advance(to: time)
            model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: time))
        }
        XCTAssertLessThanOrEqual(model.verticalVelocityForTesting, 20_000)
    }

    func testOppositeDirectionCancelsExistingMomentum() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))
        XCTAssertGreaterThan(model.verticalVelocityForTesting, 0)

        _ = model.advance(to: 0.04)
        model.apply(WheelImpulse(verticalTicks: -1, horizontalTicks: 0, timestamp: 0.04))
        XCTAssertLessThan(model.verticalVelocityForTesting, 0)
    }

    func testAxesRemainIndependent() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))
        XCTAssertGreaterThan(model.verticalVelocityForTesting, 0)
        XCTAssertEqual(model.horizontalVelocityForTesting, 0)

        model.apply(WheelImpulse(verticalTicks: 0, horizontalTicks: -1, timestamp: 0.02))
        XCTAssertGreaterThan(model.verticalVelocityForTesting, 0)
        XCTAssertLessThan(model.horizontalVelocityForTesting, 0)
    }

    func testFractionalPixelsAccumulateAcrossImpulses() {
        let configuration = ScrollPhysicsConfiguration(
            pixelsPerTick: 0.4,
            speed: 1,
            duration: 0.2,
            maximumAcceleration: 1
        )
        var model = ScrollPhysicsModel(configuration: configuration)
        var total = 0

        for index in 0 ..< 3 {
            let start = Double(index)
            model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: start))
            for frame in 1 ... 30 {
                total += Int(model.advance(to: start + Double(frame) / 120).vertical)
            }
        }

        XCTAssertEqual(total, 1)
    }

    func testLargeInputsAreClamped() {
        var huge = ScrollPhysicsModel()
        huge.apply(WheelImpulse(verticalTicks: 10_000, horizontalTicks: 0, timestamp: 0))

        var clamped = ScrollPhysicsModel()
        clamped.apply(WheelImpulse(verticalTicks: 20, horizontalTicks: 0, timestamp: 0))

        XCTAssertEqual(huge.verticalVelocityForTesting, clamped.verticalVelocityForTesting, accuracy: 0.001)
    }

    func testCancelClearsPendingMotionAndRemainder() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 1, timestamp: 0))
        _ = model.advance(to: 0.01)
        model.cancel()

        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.advance(to: 0.02), .zero)
        XCTAssertEqual(model.verticalVelocityForTesting, 0)
        XCTAssertEqual(model.horizontalVelocityForTesting, 0)
    }

    func testLongClockGapDoesNotEmitCatchUpJump() {
        var model = ScrollPhysicsModel()
        model.apply(WheelImpulse(verticalTicks: 1, horizontalTicks: 0, timestamp: 0))

        let delta = model.advance(to: 60)
        XCTAssertLessThan(abs(Int(delta.vertical)), 40)
        XCTAssertFalse(model.isActive)
    }
}
