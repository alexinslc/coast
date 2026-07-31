import XCTest
@testable import Coast

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsAreStable() {
        XCTAssertEqual(store.snapshot, .defaults)
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    func testValidValuesRoundTrip() {
        store.setEnabled(false)
        store.setSpeed(2.25)
        store.setSmoothness(0.3)
        store.setReverseVertical(true)
        store.setReverseHorizontal(true)

        XCTAssertEqual(
            store.snapshot,
            CoastSettings(
                isEnabled: false,
                speed: 2.25,
                smoothness: 0.3,
                reverseVertical: true,
                reverseHorizontal: true
            )
        )
    }

    func testVersionTwoMigrationAdoptsCubicDefaultAndPreservesOtherSettings() {
        defaults.removeObject(forKey: "settingsVersion")
        defaults.set(2.25, forKey: "speed")
        defaults.set(0.4, forKey: "smoothness")
        defaults.set(true, forKey: "reverseVertical")

        store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.snapshot.speed, 2.25)
        XCTAssertEqual(store.snapshot.smoothness, 0.7)
        XCTAssertTrue(store.snapshot.reverseVertical)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), 2)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        defaults.set("yes", forKey: "isEnabled")
        defaults.set(Double.nan, forKey: "speed")
        defaults.set(99, forKey: "smoothness")
        defaults.set(1, forKey: "reverseVertical")

        XCTAssertEqual(store.snapshot, .defaults)
    }

    func testInvalidSetterValuesUseDefaults() {
        store.setSpeed(.infinity)
        store.setSmoothness(-1)

        XCTAssertEqual(store.snapshot.speed, CoastSettings.defaults.speed)
        XCTAssertEqual(store.snapshot.smoothness, CoastSettings.defaults.smoothness)
    }

    func testRestoreDefaultsResetsEverySetting() {
        store.setEnabled(false)
        store.setSpeed(3)
        store.setSmoothness(0.35)
        store.setReverseVertical(true)
        store.setReverseHorizontal(true)

        store.restoreDefaults()
        XCTAssertEqual(store.snapshot, .defaults)
    }

    func testOnboardingCompletionPersistsAndIsNotResetWithScrollSettings() {
        store.markOnboardingCompleted()
        XCTAssertTrue(store.hasCompletedOnboarding)

        store.restoreDefaults()
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    func testLaunchAtLoginRegistrationStatesAreDistinguished() {
        XCTAssertFalse(LaunchAtLoginStatus.disabled.isRegistered)
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRegistered)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRegistered)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isRegistered)
    }
}
