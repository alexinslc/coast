import CoreGraphics

final class SyntheticScrollEmitter {
    private let source: CGEventSource?

    init() {
        source = CGEventSource(stateID: .hidSystemState)
        source?.userData = CoastConstants.syntheticEventMarker
    }

    func emit(_ delta: PixelDelta) {
        guard !delta.isZero,
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: delta.vertical,
                wheel2: delta.horizontal,
                wheel3: 0
              ) else {
            return
        }

        // Defense in depth: mark both the reusable source and each event. The tap
        // checks this field before any other classification or suppression.
        event.setIntegerValueField(
            .eventSourceUserData,
            value: CoastConstants.syntheticEventMarker
        )
        event.post(tap: .cghidEventTap)
    }
}
