import Foundation

protocol ScrollClock: AnyObject {
    var now: TimeInterval { get }
}

final class SystemScrollClock: ScrollClock {
    var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

struct ScrollPhysicsModel {
    private struct MotionSegment {
        let startTime: TimeInterval
        let duration: TimeInterval
        let distance: Double
        var emittedPosition = 0.0

        var deadline: TimeInterval {
            startTime + duration
        }

        func position(at timestamp: TimeInterval) -> Double {
            let progress = min(max((timestamp - startTime) / duration, 0), 1)
            let remaining = 1 - progress
            return distance * (1 - remaining * remaining * remaining)
        }

        func velocity(at timestamp: TimeInterval) -> Double {
            guard timestamp >= startTime, timestamp < deadline else { return 0 }
            let progress = (timestamp - startTime) / duration
            let remaining = 1 - progress
            return distance * 3 * remaining * remaining / duration
        }
    }

    private struct AxisState {
        var segments: [MotionSegment] = []
        var fractionalRemainder = 0.0
        var lastImpulseTime: TimeInterval?
        var lastImpulseDirection = 0.0
        var accelerationStep = 0

        var isActive: Bool {
            !segments.isEmpty
        }

        var motionDirection: Double {
            guard let distance = segments.last?.distance, distance != 0 else { return 0 }
            return distance.sign == .minus ? -1 : 1
        }

        func velocity(at timestamp: TimeInterval) -> Double {
            segments.reduce(0) { $0 + $1.velocity(at: timestamp) }
        }

        mutating func cancel(clearRemainder: Bool) {
            segments.removeAll(keepingCapacity: true)
            lastImpulseTime = nil
            lastImpulseDirection = 0
            accelerationStep = 0
            if clearRemainder {
                fractionalRemainder = 0
            }
        }
    }

    private(set) var configuration: ScrollPhysicsConfiguration
    private var vertical = AxisState()
    private var horizontal = AxisState()
    private var lastUpdateTime: TimeInterval?

    private let accelerationWindow: TimeInterval = 0.08
    private let accelerationIncrement = 0.25
    private let maximumTimeStep: TimeInterval = 0.05
    private let maximumInputTicks = 20.0
    private let maximumVelocity = 20_000.0
    private let maximumActiveSegments = 128

    init(configuration: ScrollPhysicsConfiguration = .defaults) {
        self.configuration = Self.validated(configuration)
    }

    var isActive: Bool {
        vertical.isActive || horizontal.isActive
    }

    var verticalVelocityForTesting: Double { velocityForTesting(vertical) }
    var horizontalVelocityForTesting: Double { velocityForTesting(horizontal) }

    mutating func updateConfiguration(_ configuration: ScrollPhysicsConfiguration) {
        self.configuration = Self.validated(configuration)
        cancel()
    }

    mutating func apply(_ impulse: WheelImpulse) {
        let effectiveTimestamp = max(impulse.timestamp, lastUpdateTime ?? impulse.timestamp)
        if lastUpdateTime == nil {
            lastUpdateTime = effectiveTimestamp
        }
        var verticalState = vertical
        var horizontalState = horizontal
        applyAxis(ticks: impulse.verticalTicks, timestamp: effectiveTimestamp, state: &verticalState)
        applyAxis(ticks: impulse.horizontalTicks, timestamp: effectiveTimestamp, state: &horizontalState)
        vertical = verticalState
        horizontal = horizontalState
    }

    mutating func advance(to timestamp: TimeInterval) -> PixelDelta {
        guard let previousUpdate = lastUpdateTime else {
            lastUpdateTime = timestamp
            return .zero
        }

        guard timestamp >= previousUpdate else {
            return .zero
        }

        var verticalState = vertical
        var horizontalState = horizontal
        let verticalPixels = advanceAxis(&verticalState, from: previousUpdate, to: timestamp)
        let horizontalPixels = advanceAxis(&horizontalState, from: previousUpdate, to: timestamp)
        vertical = verticalState
        horizontal = horizontalState
        lastUpdateTime = timestamp

        return PixelDelta(vertical: verticalPixels, horizontal: horizontalPixels)
    }

    mutating func cancel() {
        vertical.cancel(clearRemainder: true)
        horizontal.cancel(clearRemainder: true)
        lastUpdateTime = nil
    }

    private mutating func applyAxis(
        ticks: Double,
        timestamp: TimeInterval,
        state: inout AxisState
    ) {
        guard ticks.isFinite, ticks != 0 else { return }

        let safeTicks = min(max(ticks, -maximumInputTicks), maximumInputTicks)
        let direction = safeTicks.sign == .minus ? -1.0 : 1.0

        if state.motionDirection != 0, state.motionDirection != direction {
            state.cancel(clearRemainder: true)
        }

        if state.lastImpulseDirection == direction,
           let lastTime = state.lastImpulseTime,
           timestamp >= lastTime,
           timestamp - lastTime <= accelerationWindow {
            state.accelerationStep += 1
        } else {
            state.accelerationStep = 0
        }

        let acceleration = min(
            configuration.maximumAcceleration,
            1 + Double(state.accelerationStep) * accelerationIncrement
        )
        var distance = safeTicks * configuration.pixelsPerTick * configuration.speed * acceleration
        let existingVelocity = abs(state.velocity(at: timestamp))
        let requestedVelocity = abs(3 * distance / configuration.duration)
        let availableVelocity = max(0, maximumVelocity - existingVelocity)
        if requestedVelocity > availableVelocity, requestedVelocity > 0 {
            distance *= availableVelocity / requestedVelocity
        }

        if distance != 0 {
            if state.segments.count >= maximumActiveSegments {
                let remainingDistance = state.segments.reduce(0) {
                    $0 + ($1.distance - $1.emittedPosition)
                }
                let maximumDistance = maximumVelocity * configuration.duration / 3
                distance = min(max(remainingDistance + distance, -maximumDistance), maximumDistance)
                state.segments.removeAll(keepingCapacity: true)
            }
            state.segments.append(
                MotionSegment(
                    startTime: timestamp,
                    duration: configuration.duration,
                    distance: distance
                )
            )
        }
        state.lastImpulseTime = timestamp
        state.lastImpulseDirection = direction
    }

    private mutating func advanceAxis(
        _ state: inout AxisState,
        from start: TimeInterval,
        to end: TimeInterval
    ) -> Int32 {
        guard state.isActive else { return 0 }

        let sampleTime = min(end, start + maximumTimeStep)
        if sampleTime > start {
            for index in state.segments.indices {
                let position = state.segments[index].position(at: sampleTime)
                state.fractionalRemainder += position - state.segments[index].emittedPosition
                state.segments[index].emittedPosition = position
            }
        }

        // Use the real clock to expire animations after a stall, but sample at a
        // bounded time so wake or debugger pauses never produce a catch-up jump.
        state.segments.removeAll { end >= $0.deadline }

        let wholePixels = state.fractionalRemainder.rounded(.towardZero)
        let safePixels = min(max(wholePixels, Double(Int32.min)), Double(Int32.max))
        state.fractionalRemainder -= safePixels
        return Int32(safePixels)
    }

    private func velocityForTesting(_ state: AxisState) -> Double {
        let timestamp = max(lastUpdateTime ?? 0, state.lastImpulseTime ?? 0)
        return state.velocity(at: timestamp)
    }

    private static func validated(_ value: ScrollPhysicsConfiguration) -> ScrollPhysicsConfiguration {
        let defaults = ScrollPhysicsConfiguration.defaults
        return ScrollPhysicsConfiguration(
            pixelsPerTick: value.pixelsPerTick.isFinite && value.pixelsPerTick > 0 ? value.pixelsPerTick : defaults.pixelsPerTick,
            speed: value.speed.isFinite && CoastSettings.speedRange.contains(value.speed) ? value.speed : defaults.speed,
            duration: value.duration.isFinite && CoastSettings.smoothnessRange.contains(value.duration) ? value.duration : defaults.duration,
            maximumAcceleration: value.maximumAcceleration.isFinite && value.maximumAcceleration >= 1 ? min(value.maximumAcceleration, 3) : defaults.maximumAcceleration
        )
    }
}

final class ScrollPhysicsEngine {
    typealias Emitter = (PixelDelta) -> Void

    private let queue = DispatchQueue(label: "com.alexinslc.coast.scroll-physics", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let clock: ScrollClock
    private let emitter: Emitter
    private let activity = LockedBox(false)
    private var model: ScrollPhysicsModel
    private var timer: DispatchSourceTimer?

    init(
        configuration: ScrollPhysicsConfiguration,
        clock: ScrollClock = SystemScrollClock(),
        emitter: @escaping Emitter
    ) {
        self.clock = clock
        self.emitter = emitter
        model = ScrollPhysicsModel(configuration: configuration)
        queue.setSpecific(key: queueKey, value: 1)
    }

    func accept(_ impulse: WheelImpulse) {
        activity.withValue { $0 = true }
        queue.async { [weak self] in
            guard let self else { return }
            emitIfNeeded(self.model.advance(to: impulse.timestamp))
            self.model.apply(impulse)
            self.startTimerIfNeeded()
        }
    }

    func updateConfiguration(_ configuration: ScrollPhysicsConfiguration) {
        activity.withValue { $0 = false }
        queue.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            self.model.updateConfiguration(configuration)
        }
    }

    func cancel() {
        let shouldCancel = activity.withValue { isActive -> Bool in
            guard isActive else { return false }
            isActive = false
            return true
        }
        guard shouldCancel else { return }
        queue.async { [weak self] in
            self?.cancelOnQueue()
        }
    }

    func cancelSynchronously() {
        activity.withValue { $0 = false }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            cancelOnQueue()
        } else {
            queue.sync { cancelOnQueue() }
        }
    }

    private func startTimerIfNeeded() {
        guard model.isActive, timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now(),
            repeating: .nanoseconds(8_333_333),
            leeway: .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.resume()
    }

    private func tick() {
        emitIfNeeded(model.advance(to: clock.now))
        if !model.isActive {
            activity.withValue { $0 = false }
            stopTimer()
        }
    }

    private func emitIfNeeded(_ delta: PixelDelta) {
        guard !delta.isZero else { return }
        emitter(delta)
    }

    private func cancelOnQueue() {
        activity.withValue { $0 = false }
        stopTimer()
        model.cancel()
    }

    private func stopTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
