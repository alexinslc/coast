import Foundation

enum CoastConstants {
    // ASCII-inspired namespace plus a version byte. Generated events carrying this
    // value must always pass through the event tap to prevent recursion.
    static let syntheticEventMarker: Int64 = 0x434F_4153_5400_0001
}

struct CoastSettings: Equatable {
    static let defaultSpeed = 1.0
    static let speedRange = 0.25 ... 4.0
    static let defaultSmoothness = 0.70
    static let smoothnessRange = 0.20 ... 1.20

    var isEnabled: Bool
    var speed: Double
    var smoothness: TimeInterval
    var reverseVertical: Bool
    var reverseHorizontal: Bool

    static let defaults = CoastSettings(
        isEnabled: true,
        speed: defaultSpeed,
        smoothness: defaultSmoothness,
        reverseVertical: false,
        reverseHorizontal: false
    )

    var physicsConfiguration: ScrollPhysicsConfiguration {
        ScrollPhysicsConfiguration(
            pixelsPerTick: 40,
            speed: speed,
            duration: smoothness,
            maximumAcceleration: 3
        )
    }
}

struct ScrollPhysicsConfiguration: Equatable {
    var pixelsPerTick: Double
    var speed: Double
    var duration: TimeInterval
    var maximumAcceleration: Double

    static let defaults = CoastSettings.defaults.physicsConfiguration
}

struct WheelImpulse: Equatable {
    var verticalTicks: Double
    var horizontalTicks: Double
    var timestamp: TimeInterval
}

struct PixelDelta: Equatable {
    var vertical: Int32
    var horizontal: Int32

    static let zero = PixelDelta(vertical: 0, horizontal: 0)

    var isZero: Bool {
        vertical == 0 && horizontal == 0
    }
}

struct ScrollEventMetadata: Equatable {
    var sourceUserData: Int64
    var isContinuous: Bool
    var verticalLineDelta: Int64
    var horizontalLineDelta: Int64
    var shiftIsPressed: Bool
    var timestamp: TimeInterval
}

enum ScrollEventDecision: Equatable {
    case passThrough(cancelPendingMotion: Bool)
    case suppress(WheelImpulse)
}

enum ScrollEventPolicy {
    private static let maximumTicksPerEvent: Double = 20

    static func decision(
        for metadata: ScrollEventMetadata,
        settings: CoastSettings
    ) -> ScrollEventDecision {
        if metadata.sourceUserData == CoastConstants.syntheticEventMarker {
            return .passThrough(cancelPendingMotion: false)
        }

        if metadata.isContinuous {
            return .passThrough(cancelPendingMotion: true)
        }

        var vertical = clampedTicks(metadata.verticalLineDelta)
        var horizontal = clampedTicks(metadata.horizontalLineDelta)

        guard vertical != 0 || horizontal != 0 else {
            return .passThrough(cancelPendingMotion: false)
        }

        if metadata.shiftIsPressed, horizontal == 0, vertical != 0 {
            horizontal = vertical
            vertical = 0
        }

        if settings.reverseVertical {
            vertical.negate()
        }
        if settings.reverseHorizontal {
            horizontal.negate()
        }

        return .suppress(
            WheelImpulse(
                verticalTicks: vertical,
                horizontalTicks: horizontal,
                timestamp: metadata.timestamp
            )
        )
    }

    private static func clampedTicks(_ value: Int64) -> Double {
        min(max(Double(value), -maximumTicksPerEvent), maximumTicksPerEvent)
    }
}

final class LockedBox<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read<T>(_ body: (Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(value)
    }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
