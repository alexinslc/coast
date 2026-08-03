import AppKit

@MainActor
final class AppController {
    private let settingsStore = SettingsStore()
    private let permissionManager = AccessibilityPermissionManager()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let menuBarController = MenuBarController()
    private let syntheticEmitter = SyntheticScrollEmitter()

    private lazy var physicsEngine = ScrollPhysicsEngine(
        configuration: settingsStore.snapshot.physicsConfiguration,
        emitter: { [weak syntheticEmitter] delta in
            syntheticEmitter?.emit(delta)
        }
    )

    private lazy var eventTap = ScrollEventTap(
        settings: settingsStore.snapshot,
        onImpulse: { [weak physicsEngine] impulse in
            physicsEngine?.accept(impulse)
        },
        onCancelPendingMotion: { [weak physicsEngine] in
            physicsEngine?.cancel()
        },
        onUnavailable: { [weak self] in
            Task { @MainActor in
                self?.eventTapBecameUnavailable()
            }
        }
    )

    private lazy var settingsWindowController: SettingsWindowController = {
        let controller = SettingsWindowController(settingsStore: settingsStore)
        controller.onRequestPermission = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        controller.onLaunchAtLoginChanged = { [weak self] isEnabled in
            self?.setLaunchAtLogin(isEnabled)
        }
        controller.onOpenLoginItemsSettings = { [weak self] in
            self?.launchAtLoginManager.openSystemSettings()
        }
        return controller
    }()

    private lazy var onboardingWindowController: OnboardingWindowController = {
        let controller = OnboardingWindowController()
        controller.onRequestPermission = { [weak self] in
            self?.requestAccessibilityPermission()
        }
        controller.onLaunchAtLoginChanged = { [weak self] isEnabled in
            self?.setLaunchAtLogin(isEnabled)
        }
        controller.onOpenLoginItemsSettings = { [weak self] in
            self?.launchAtLoginManager.openSystemSettings()
        }
        controller.onComplete = { [weak self] in
            self?.settingsStore.markOnboardingCompleted()
            self?.reconcileRuntime()
        }
        return controller
    }()

    private var applicationObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var isSleeping = false
    private var tapUnavailable = false

    func start() {
        configureMenuActions()
        configureObservers()

        permissionManager.onAuthorizationChanged = { [weak self] isTrusted in
            self?.onboardingWindowController.updatePermission(isTrusted: isTrusted)
            self?.reconcileRuntime()
        }
        permissionManager.startMonitoring()

        _ = physicsEngine
        _ = eventTap
        reconcileRuntime()

        #if DEBUG
        if CommandLine.arguments.contains("--show-onboarding") {
            showOnboarding()
        } else if CommandLine.arguments.contains("--show-settings") {
            showSettings()
        } else if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
        #else
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        }
        #endif
    }

    func shutdown() {
        applicationObservers.forEach(NotificationCenter.default.removeObserver)
        applicationObservers.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributedCenter.removeObserver)
        distributedObservers.removeAll()

        permissionManager.stopMonitoring()
        eventTap.stop()
        physicsEngine.cancelSynchronously()
    }

    private func configureMenuActions() {
        menuBarController.onToggle = { [weak self] in
            guard let self else { return }
            settingsStore.setEnabled(!settingsStore.snapshot.isEnabled)
        }
        menuBarController.onSettings = { [weak self] in
            self?.showSettings()
        }
        menuBarController.onStatusAction = { [weak self] in
            self?.performStatusAction()
        }
        menuBarController.onRestoreDefaults = { [weak self] in
            self?.settingsStore.restoreDefaults()
        }
        menuBarController.onAbout = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        menuBarController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func configureObservers() {
        let center = NotificationCenter.default
        applicationObservers.append(
            center.addObserver(forName: .coastSettingsDidChange, object: settingsStore, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.settingsChanged()
                }
            }
        )
        applicationObservers.append(
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.permissionManager.refresh()
                    self?.refreshLaunchAtLoginPresentation()
                    self?.reconcileRuntime()
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.prepareForSleep()
                }
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.recoverAfterWake()
                }
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.recoverAfterWake()
                }
            }
        )

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(
            distributedCenter.addObserver(
                forName: SingleInstanceCoordinator.showSettingsNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.showSettings()
                }
            }
        )
    }

    private func settingsChanged() {
        let settings = settingsStore.snapshot
        eventTap.updateSettings(settings)
        physicsEngine.updateConfiguration(settings.physicsConfiguration)
        reconcileRuntime()
    }

    private func reconcileRuntime() {
        let settings = settingsStore.snapshot
        settingsWindowController.updatePermission(isTrusted: permissionManager.isTrusted)
        onboardingWindowController.updatePermission(isTrusted: permissionManager.isTrusted)
        refreshLaunchAtLoginPresentation()

        guard settings.isEnabled else {
            stopScrolling()
            menuBarController.update(enabled: false, status: .disabled)
            return
        }

        guard permissionManager.isTrusted else {
            stopScrolling()
            menuBarController.update(enabled: true, status: .permissionRequired)
            return
        }

        guard !isSleeping else {
            stopScrolling()
            menuBarController.update(enabled: true, status: .starting)
            return
        }

        if !eventTap.isRunning {
            tapUnavailable = !eventTap.start()
        }

        menuBarController.update(
            enabled: true,
            status: tapUnavailable ? .tapUnavailable : .active
        )
    }

    private func stopScrolling() {
        eventTap.stop()
        physicsEngine.cancelSynchronously()
    }

    private func eventTapBecameUnavailable() {
        tapUnavailable = true
        stopScrolling()
        menuBarController.update(enabled: settingsStore.snapshot.isEnabled, status: .tapUnavailable)
    }

    private func performStatusAction() {
        if !permissionManager.isTrusted {
            if settingsStore.hasCompletedOnboarding {
                showSettings()
            } else {
                onboardingWindowController.showAccessibilityStep()
            }
        } else if tapUnavailable {
            tapUnavailable = false
            reconcileRuntime()
        }
    }

    func showSettings() {
        settingsWindowController.updatePermission(isTrusted: permissionManager.isTrusted)
        settingsWindowController.updateLaunchAtLogin(status: launchAtLoginManager.status)
        settingsWindowController.showWindow(nil)
    }

    private func showOnboarding() {
        onboardingWindowController.updatePermission(isTrusted: permissionManager.isTrusted)
        onboardingWindowController.updateLaunchAtLogin(status: launchAtLoginManager.status)
        onboardingWindowController.showWindow(nil)
    }

    private func requestAccessibilityPermission() {
        NSApp.activate(ignoringOtherApps: true)
        permissionManager.requestPermission()
        settingsWindowController.updatePermission(isTrusted: permissionManager.isTrusted)
        onboardingWindowController.updatePermission(isTrusted: permissionManager.isTrusted)
        reconcileRuntime()
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(isEnabled)
        } catch {
            presentLaunchAtLoginError(error)
        }
        refreshLaunchAtLoginPresentation()
    }

    private func refreshLaunchAtLoginPresentation() {
        let status = launchAtLoginManager.status
        settingsWindowController.updateLaunchAtLogin(status: status)
        onboardingWindowController.updateLaunchAtLogin(status: status)
    }

    private func presentLaunchAtLoginError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Coast Couldn't Update Login Items"
        alert.informativeText = "macOS reported: \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func prepareForSleep() {
        isSleeping = true
        stopScrolling()
        if settingsStore.snapshot.isEnabled {
            menuBarController.update(enabled: true, status: .starting)
        }
    }

    private func recoverAfterWake() {
        isSleeping = false
        tapUnavailable = false
        permissionManager.refresh()
        refreshLaunchAtLoginPresentation()
        reconcileRuntime()
    }
}
