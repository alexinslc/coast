import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    var onRequestPermission: (() -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onOpenLoginItemsSettings: (() -> Void)?

    private let settingsStore: SettingsStore
    private let speedSlider = NSSlider()
    private let speedValueLabel = NSTextField(labelWithString: "")
    private let smoothnessSlider = NSSlider()
    private let smoothnessValueLabel = NSTextField(labelWithString: "")
    private let reverseVerticalButton = NSButton()
    private let reverseHorizontalButton = NSButton()
    private let launchAtLoginButton = NSButton()
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    private let loginItemsButton = NSButton()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()
    private var settingsObserver: NSObjectProtocol?
    private var isUpdatingLaunchControl = false

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Coast Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("CoastSettingsWindow")
        window.center()

        super.init(window: window)
        configureContent(in: window)
        refreshControls()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .coastSettingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshControls()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        refreshControls()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func updatePermission(isTrusted: Bool) {
        permissionLabel.stringValue = isTrusted
            ? "Accessibility access is on. Smooth scrolling is available."
            : "Accessibility access is required to smooth mouse-wheel events."
        permissionLabel.textColor = isTrusted ? .systemGreen : .systemOrange
        permissionButton.isHidden = isTrusted
    }

    func updateLaunchAtLogin(status: LaunchAtLoginStatus) {
        isUpdatingLaunchControl = true
        launchAtLoginButton.state = status.isRegistered ? .on : .off
        isUpdatingLaunchControl = false

        switch status {
        case .disabled:
            launchAtLoginButton.isEnabled = true
            launchAtLoginStatusLabel.stringValue = "Coast will open only when you launch it."
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
            loginItemsButton.isHidden = true
        case .enabled:
            launchAtLoginButton.isEnabled = true
            launchAtLoginStatusLabel.stringValue = "Coast will open automatically when you sign in."
            launchAtLoginStatusLabel.textColor = .secondaryLabelColor
            loginItemsButton.isHidden = true
        case .requiresApproval:
            launchAtLoginButton.isEnabled = true
            launchAtLoginStatusLabel.stringValue = "Registered, but approval is still required in System Settings."
            launchAtLoginStatusLabel.textColor = .systemOrange
            loginItemsButton.isHidden = false
        case .unavailable:
            launchAtLoginButton.isEnabled = true
            launchAtLoginStatusLabel.stringValue = "macOS hasn't registered this copy of Coast as a login item yet."
            launchAtLoginStatusLabel.textColor = .systemOrange
            loginItemsButton.isHidden = true
        }
    }

    private func configureContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let appIcon = NSImageView()
        appIcon.image = NSApp.applicationIconImage
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Coast")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = wrappingLabel(
            "Smooth, responsive scrolling for conventional mouse wheels. Continuous trackpad and Magic Mouse input passes through unchanged."
        )
        let headingStack = NSStackView(views: [title, subtitle])
        headingStack.orientation = .vertical
        headingStack.alignment = .leading
        headingStack.spacing = 4

        let header = NSStackView(views: [appIcon, headingStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        configureSliders()

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Scroll speed"), speedSlider, speedValueLabel],
            [NSTextField(labelWithString: "Smoothness"), smoothnessSlider, smoothnessValueLabel]
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 2).xPlacement = .trailing

        reverseVerticalButton.setButtonType(.switch)
        reverseVerticalButton.title = "Reverse vertical scrolling"
        reverseVerticalButton.target = self
        reverseVerticalButton.action = #selector(reverseVerticalChanged)

        reverseHorizontalButton.setButtonType(.switch)
        reverseHorizontalButton.title = "Reverse horizontal scrolling"
        reverseHorizontalButton.target = self
        reverseHorizontalButton.action = #selector(reverseHorizontalChanged)

        let reverseStack = NSStackView(views: [reverseVerticalButton, reverseHorizontalButton])
        reverseStack.orientation = .horizontal
        reverseStack.alignment = .centerY
        reverseStack.spacing = 28

        let scrollingContent = NSStackView(views: [grid, reverseStack])
        scrollingContent.orientation = .vertical
        scrollingContent.alignment = .leading
        scrollingContent.spacing = 18

        launchAtLoginButton.setButtonType(.switch)
        launchAtLoginButton.title = "Open Coast at Login"
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged)

        configureWrappingLabel(launchAtLoginStatusLabel)
        loginItemsButton.title = "Open Login Items…"
        loginItemsButton.bezelStyle = .rounded
        loginItemsButton.target = self
        loginItemsButton.action = #selector(openLoginItemsSelected)

        let loginStatusRow = NSStackView(views: [launchAtLoginStatusLabel, loginItemsButton])
        loginStatusRow.orientation = .horizontal
        loginStatusRow.alignment = .centerY
        loginStatusRow.spacing = 12
        loginStatusRow.widthAnchor.constraint(equalToConstant: 490).isActive = true

        let generalContent = NSStackView(views: [launchAtLoginButton, loginStatusRow])
        generalContent.orientation = .vertical
        generalContent.alignment = .leading
        generalContent.spacing = 8

        configureWrappingLabel(permissionLabel)
        permissionButton.title = "Grant Permission…"
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(permissionSelected)

        let permissionRow = NSStackView(views: [permissionLabel, permissionButton])
        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        permissionRow.spacing = 12
        permissionRow.widthAnchor.constraint(equalToConstant: 490).isActive = true

        let tip = wrappingLabel("Try one slow wheel tick, then several quick ticks on a long page. New ticks should join the current glide without a visible restart.")
        tip.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let restoreButton = NSButton(title: "Restore Scrolling Defaults", target: self, action: #selector(restoreDefaultsSelected))
        restoreButton.bezelStyle = .rounded

        let footer = NSStackView(views: [tip, NSView(), restoreButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.widthAnchor.constraint(equalToConstant: 524).isActive = true
        tip.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [
            header,
            sectionBox(title: "Scrolling", content: scrollingContent, height: 146),
            sectionBox(title: "General", content: generalContent, height: 94),
            sectionBox(title: "Accessibility", content: permissionRow, height: 70),
            footer
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(18, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 64),
            appIcon.heightAnchor.constraint(equalToConstant: 64),
            header.widthAnchor.constraint(equalToConstant: 524),
            subtitle.widthAnchor.constraint(equalToConstant: 440),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    private func configureSliders() {
        speedSlider.minValue = CoastSettings.speedRange.lowerBound
        speedSlider.maxValue = CoastSettings.speedRange.upperBound
        speedSlider.isContinuous = true
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.widthAnchor.constraint(equalToConstant: 292).isActive = true
        speedValueLabel.alignment = .right
        speedValueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        smoothnessSlider.minValue = CoastSettings.smoothnessRange.lowerBound
        smoothnessSlider.maxValue = CoastSettings.smoothnessRange.upperBound
        smoothnessSlider.isContinuous = true
        smoothnessSlider.target = self
        smoothnessSlider.action = #selector(smoothnessChanged)
        smoothnessSlider.widthAnchor.constraint(equalToConstant: 292).isActive = true
        smoothnessValueLabel.alignment = .right
        smoothnessValueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
    }

    private func refreshControls() {
        let settings = settingsStore.snapshot
        speedSlider.doubleValue = settings.speed
        speedValueLabel.stringValue = String(format: "%.2f×", settings.speed)
        smoothnessSlider.doubleValue = settings.smoothness
        smoothnessValueLabel.stringValue = "\(Int((settings.smoothness * 1_000).rounded())) ms"
        reverseVerticalButton.state = settings.reverseVertical ? .on : .off
        reverseHorizontalButton.state = settings.reverseHorizontal ? .on : .off
    }

    private func sectionBox(title: String, content: NSView, height: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .primary
        box.title = title
        box.contentView = content
        box.widthAnchor.constraint(equalToConstant: 524).isActive = true
        box.heightAnchor.constraint(equalToConstant: height).isActive = true
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 30),
            content.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -14)
        ])
        return box
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func configureWrappingLabel(_ label: NSTextField) {
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @objc private func speedChanged() {
        settingsStore.setSpeed(speedSlider.doubleValue)
    }

    @objc private func smoothnessChanged() {
        settingsStore.setSmoothness(smoothnessSlider.doubleValue)
    }

    @objc private func reverseVerticalChanged() {
        settingsStore.setReverseVertical(reverseVerticalButton.state == .on)
    }

    @objc private func reverseHorizontalChanged() {
        settingsStore.setReverseHorizontal(reverseHorizontalButton.state == .on)
    }

    @objc private func launchAtLoginChanged() {
        guard !isUpdatingLaunchControl else { return }
        onLaunchAtLoginChanged?(launchAtLoginButton.state == .on)
    }

    @objc private func openLoginItemsSelected() {
        onOpenLoginItemsSettings?()
    }

    @objc private func restoreDefaultsSelected() {
        settingsStore.restoreDefaults()
    }

    @objc private func permissionSelected() {
        onRequestPermission?()
    }
}
