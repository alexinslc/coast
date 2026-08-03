import AppKit
import Darwin

final class SingleInstanceCoordinator {
    static let showSettingsNotification = Notification.Name("com.alexinslc.coast.showSettings")

    private let bundleIdentifier: String
    private let lockURL: URL
    private var ownsLock = false

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.alexinslc.coast",
        lockURL: URL? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.lockURL = lockURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("\(bundleIdentifier).instance.lock")
    }

    var existingApplication: NSRunningApplication? {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier }
    }

    func acquireLock() -> Bool {
        guard !ownsLock else { return true }

        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        for _ in 0..<2 {
            if Darwin.symlink(String(processIdentifier), lockURL.path) == 0 {
                ownsLock = true
                return true
            }

            guard errno == EEXIST else {
                // Do not make Coast unusable if the per-user temporary directory is unavailable.
                return true
            }
            guard !lockOwnerIsRunning else { return false }
            Darwin.unlink(lockURL.path)
        }
        return false
    }

    func releaseLock() {
        guard ownsLock else { return }
        if lockOwnerProcessIdentifier == ProcessInfo.processInfo.processIdentifier {
            Darwin.unlink(lockURL.path)
        }
        ownsLock = false
    }

    func revealExistingApplication() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.showSettingsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        existingApplication?.activate(options: [.activateAllWindows])
    }

    deinit {
        releaseLock()
    }

    private var lockOwnerProcessIdentifier: pid_t? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(
            atPath: lockURL.path
        ) else {
            return nil
        }
        return pid_t(destination)
    }

    private var lockOwnerIsRunning: Bool {
        guard let processIdentifier = lockOwnerProcessIdentifier else { return false }
        if Darwin.kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private let singleInstanceCoordinator = SingleInstanceCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard allowsMultipleInstances || beginSingleInstanceSession() else {
            singleInstanceCoordinator.revealExistingApplication()
            NSApp.terminate(nil)
            return
        }

        let controller = AppController()
        appController = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.shutdown()
        singleInstanceCoordinator.releaseLock()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        appController?.showSettings()
        return false
    }

    private var allowsMultipleInstances: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--allow-multiple-instances")
            || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }

    private func beginSingleInstanceSession() -> Bool {
        guard singleInstanceCoordinator.existingApplication == nil else { return false }
        return singleInstanceCoordinator.acquireLock()
    }
}
