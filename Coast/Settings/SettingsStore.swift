import Foundation

extension Notification.Name {
    static let coastSettingsDidChange = Notification.Name("com.alexinslc.coast.settingsDidChange")
}

@MainActor
final class SettingsStore {
    private enum Key: String, CaseIterable {
        case settingsVersion
        case isEnabled
        case speed
        case smoothness
        case reverseVertical
        case reverseHorizontal
        case hasCompletedOnboarding
    }

    private static let currentSettingsVersion = 2
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateSettingsIfNeeded()
    }

    var snapshot: CoastSettings {
        CoastSettings(
            isEnabled: validBoolean(for: .isEnabled) ?? CoastSettings.defaults.isEnabled,
            speed: validNumber(for: .speed, in: CoastSettings.speedRange) ?? CoastSettings.defaults.speed,
            smoothness: validNumber(for: .smoothness, in: CoastSettings.smoothnessRange) ?? CoastSettings.defaults.smoothness,
            reverseVertical: validBoolean(for: .reverseVertical) ?? CoastSettings.defaults.reverseVertical,
            reverseHorizontal: validBoolean(for: .reverseHorizontal) ?? CoastSettings.defaults.reverseHorizontal
        )
    }

    var hasCompletedOnboarding: Bool {
        validBoolean(for: .hasCompletedOnboarding) ?? false
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: Key.hasCompletedOnboarding.rawValue)
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: Key.isEnabled.rawValue)
        notifyChange()
    }

    func setSpeed(_ value: Double) {
        defaults.set(validated(value, in: CoastSettings.speedRange, fallback: CoastSettings.defaults.speed), forKey: Key.speed.rawValue)
        notifyChange()
    }

    func setSmoothness(_ value: Double) {
        defaults.set(validated(value, in: CoastSettings.smoothnessRange, fallback: CoastSettings.defaults.smoothness), forKey: Key.smoothness.rawValue)
        notifyChange()
    }

    func setReverseVertical(_ value: Bool) {
        defaults.set(value, forKey: Key.reverseVertical.rawValue)
        notifyChange()
    }

    func setReverseHorizontal(_ value: Bool) {
        defaults.set(value, forKey: Key.reverseHorizontal.rawValue)
        notifyChange()
    }

    func restoreDefaults() {
        let values = CoastSettings.defaults
        defaults.set(Self.currentSettingsVersion, forKey: Key.settingsVersion.rawValue)
        defaults.set(values.isEnabled, forKey: Key.isEnabled.rawValue)
        defaults.set(values.speed, forKey: Key.speed.rawValue)
        defaults.set(values.smoothness, forKey: Key.smoothness.rawValue)
        defaults.set(values.reverseVertical, forKey: Key.reverseVertical.rawValue)
        defaults.set(values.reverseHorizontal, forKey: Key.reverseHorizontal.rawValue)
        notifyChange()
    }

    private func migrateSettingsIfNeeded() {
        guard defaults.integer(forKey: Key.settingsVersion.rawValue) < Self.currentSettingsVersion else {
            return
        }

        // Version 2 replaces exponential decay with a cubic ease-out curve. The
        // duration has different semantics, so carry the other preferences over
        // while starting the new curve at its tuned 700 ms default.
        defaults.set(CoastSettings.defaultSmoothness, forKey: Key.smoothness.rawValue)
        defaults.set(Self.currentSettingsVersion, forKey: Key.settingsVersion.rawValue)
    }

    private func validBoolean(for key: Key) -> Bool? {
        guard let number = defaults.object(forKey: key.rawValue) as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private func validNumber(for key: Key, in range: ClosedRange<Double>) -> Double? {
        guard let number = defaults.object(forKey: key.rawValue) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite, range.contains(value) else {
            return nil
        }
        return value
    }

    private func validated(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite, range.contains(value) else {
            return fallback
        }
        return value
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .coastSettingsDidChange, object: self)
    }
}
