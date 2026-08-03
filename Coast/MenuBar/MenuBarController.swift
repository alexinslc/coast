import AppKit

enum CoastRuntimeStatus: Equatable {
    case disabled
    case permissionRequired
    case starting
    case active
    case tapUnavailable

    var title: String {
        switch self {
        case .disabled: return "Status: Off"
        case .permissionRequired: return "Permission Required…"
        case .starting: return "Status: Starting…"
        case .active: return "Status: Active"
        case .tapUnavailable: return "Scroll Engine Unavailable — Retry"
        }
    }

    var statusItemDescription: String {
        switch self {
        case .disabled: return "Off"
        case .permissionRequired: return "Accessibility Permission Required"
        case .starting: return "Starting"
        case .active: return "Active"
        case .tapUnavailable: return "Scroll Engine Unavailable"
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    var onToggle: (() -> Void)?
    var onSettings: (() -> Void)?
    var onStatusAction: (() -> Void)?
    var onRestoreDefaults: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let enabledItem = NSMenuItem()
    private let statusMenuItem = NSMenuItem()
    private var enabled = true
    private var runtimeStatus: CoastRuntimeStatus = .starting

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.autosaveName = "CoastStatusItem"

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel("Coast")

            if let image = NSImage(named: "CoastMenuBarTemplate")?.copy() as? NSImage {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                image.accessibilityDescription = "Coast"
                button.image = image
            } else if let fallback = NSImage(
                systemSymbolName: "water.waves",
                accessibilityDescription: "Coast"
            ) {
                fallback.isTemplate = true
                button.image = fallback
            } else {
                button.title = "C"
            }
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        enabledItem.target = self
        enabledItem.action = #selector(toggleSelected)
        menu.addItem(enabledItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsSelected), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        statusMenuItem.target = self
        statusMenuItem.action = #selector(statusSelected)
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        let restoreItem = NSMenuItem(title: "Restore Defaults", action: #selector(restoreSelected), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        let aboutItem = NSMenuItem(title: "About Coast", action: #selector(aboutSelected), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Coast", action: #selector(quitSelected), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshItems()
    }

    func update(enabled: Bool, status: CoastRuntimeStatus) {
        self.enabled = enabled
        runtimeStatus = status
        refreshItems()
    }

    private func refreshItems() {
        enabledItem.title = enabled ? "Coast: On" : "Coast: Off"
        enabledItem.state = enabled ? .on : .off
        statusMenuItem.title = runtimeStatus.title
        statusMenuItem.isEnabled = runtimeStatus == .permissionRequired || runtimeStatus == .tapUnavailable
        statusItem.button?.toolTip = "Coast — \(runtimeStatus.statusItemDescription)"
        statusItem.button?.setAccessibilityHelp(runtimeStatus.title)

        switch runtimeStatus {
        case .permissionRequired, .tapUnavailable:
            statusItem.button?.appearsDisabled = true
        case .disabled:
            statusItem.button?.appearsDisabled = true
        case .starting, .active:
            statusItem.button?.appearsDisabled = false
        }
    }

    @objc private func toggleSelected() { onToggle?() }
    @objc private func settingsSelected() { onSettings?() }
    @objc private func statusSelected() { onStatusAction?() }
    @objc private func restoreSelected() { onRestoreDefaults?() }
    @objc private func aboutSelected() { onAbout?() }
    @objc private func quitSelected() { onQuit?() }
}
