import AppKit
import CoreGraphics
#if DEBUG
import os
#endif

final class ScrollEventTap {
    typealias ImpulseHandler = (WheelImpulse) -> Void
    typealias CancellationHandler = () -> Void
    typealias UnavailableHandler = () -> Void

    private struct LifecycleState {
        var tap: CFMachPort?
        var source: CFRunLoopSource?
        var runLoop: CFRunLoop?
        var thread: Thread?
        var generation = 0
        var isRunning = false
    }

    private let settings: LockedBox<CoastSettings>
    private let lifecycle = LockedBox(LifecycleState())
    private let onImpulse: ImpulseHandler
    private let onCancelPendingMotion: CancellationHandler
    private let onUnavailable: UnavailableHandler

    #if DEBUG
    private let debugLoggingEnabled = ProcessInfo.processInfo.environment["COAST_DEBUG_SCROLL_EVENTS"] == "1"
    private let logger = Logger(subsystem: "com.alexinslc.coast", category: "ScrollEventTap")
    #endif

    init(
        settings: CoastSettings,
        onImpulse: @escaping ImpulseHandler,
        onCancelPendingMotion: @escaping CancellationHandler,
        onUnavailable: @escaping UnavailableHandler
    ) {
        self.settings = LockedBox(settings)
        self.onImpulse = onImpulse
        self.onCancelPendingMotion = onCancelPendingMotion
        self.onUnavailable = onUnavailable
    }

    var isRunning: Bool {
        lifecycle.read(\.isRunning)
    }

    func updateSettings(_ settings: CoastSettings) {
        self.settings.withValue { $0 = settings }
    }

    @discardableResult
    func start() -> Bool {
        if isRunning {
            return true
        }

        let eventMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        let generation = lifecycle.withValue { state -> Int in
            state.generation += 1
            state.tap = tap
            state.source = source
            state.isRunning = true
            return state.generation
        }

        let thread = Thread { [weak self] in
            self?.runTap(tap: tap, source: source, generation: generation)
        }
        thread.name = "Coast Scroll Event Tap"
        thread.qualityOfService = .userInteractive
        lifecycle.withValue { state in
            guard state.generation == generation else { return }
            state.thread = thread
        }
        thread.start()
        return true
    }

    func stop() {
        let captured = lifecycle.withValue { state -> (CFMachPort?, CFRunLoop?) in
            state.generation += 1
            state.isRunning = false
            let values = (state.tap, state.runLoop)
            state.tap = nil
            state.source = nil
            state.runLoop = nil
            state.thread = nil
            return values
        }

        if let tap = captured.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = captured.1 {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func runTap(tap: CFMachPort, source: CFRunLoopSource, generation: Int) {
        let runLoop = CFRunLoopGetCurrent()
        let shouldRun = lifecycle.withValue { state -> Bool in
            guard state.generation == generation, state.isRunning else { return false }
            state.runLoop = runLoop
            return true
        }
        guard shouldRun else { return }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
        CFRunLoopRemoveSource(runLoop, source, .commonModes)

        lifecycle.withValue { state in
            guard state.generation == generation else { return }
            state.isRunning = false
            state.tap = nil
            state.source = nil
            state.runLoop = nil
            state.thread = nil
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let owner = Unmanaged<ScrollEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return owner.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tap = lifecycle.read(\.tap)
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) {
                    onUnavailable()
                }
            } else {
                onUnavailable()
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .scrollWheel, isRunning else {
            return Unmanaged.passUnretained(event)
        }

        let metadata = ScrollEventMetadata(
            sourceUserData: event.getIntegerValueField(.eventSourceUserData),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            verticalLineDelta: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            horizontalLineDelta: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            shiftIsPressed: event.flags.contains(.maskShift),
            timestamp: TimeInterval(event.timestamp) / 1_000_000_000
        )

        #if DEBUG
        if debugLoggingEnabled {
            logger.debug(
                "scroll continuous=\(metadata.isContinuous, privacy: .public) vertical=\(metadata.verticalLineDelta != 0, privacy: .public) horizontal=\(metadata.horizontalLineDelta != 0, privacy: .public) shift=\(metadata.shiftIsPressed, privacy: .public)"
            )
        }
        #endif

        switch settings.read({ ScrollEventPolicy.decision(for: metadata, settings: $0) }) {
        case let .passThrough(cancelPendingMotion):
            if cancelPendingMotion {
                onCancelPendingMotion()
            }
            return Unmanaged.passUnretained(event)

        case let .suppress(impulse):
            // Suppress only after the value-type impulse has been accepted by the
            // asynchronous physics handoff. The callback never waits on that queue.
            onImpulse(impulse)
            return nil
        }
    }
}
