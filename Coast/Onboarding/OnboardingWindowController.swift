import AppKit

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    var onRequestPermission: (() -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onOpenLoginItemsSettings: (() -> Void)?
    var onComplete: (() -> Void)?

    private enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case ready
    }

    private let pageContainer = NSView()
    private let progressLabel = NSTextField(labelWithString: "")
    private let backButton = NSButton()
    private let primaryButton = NSButton()

    private let launchAtLoginButton = NSButton()
    private let loginItemStatusLabel = NSTextField(labelWithString: "")
    private let loginItemSettingsButton = NSButton()
    private let permissionStatusLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()

    private var step = Step.welcome
    private var isTrusted = false
    private var launchAtLoginStatus = LaunchAtLoginStatus.disabled
    private var isUpdatingLaunchControl = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Coast"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)
        window.delegate = self
        configureContent(in: window)
        show(step: .welcome)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func showAccessibilityStep() {
        show(step: .accessibility)
        showWindow(nil)
    }

    func updatePermission(isTrusted: Bool) {
        self.isTrusted = isTrusted
        permissionStatusLabel.stringValue = isTrusted
            ? "Accessibility access is on. Coast can smooth your mouse wheel."
            : "Accessibility access is still needed before Coast can begin."
        permissionStatusLabel.textColor = isTrusted ? .systemGreen : .systemOrange
        permissionButton.isHidden = isTrusted
        if step == .accessibility {
            primaryButton.isEnabled = isTrusted
        }
    }

    func updateLaunchAtLogin(status: LaunchAtLoginStatus) {
        launchAtLoginStatus = status
        isUpdatingLaunchControl = true
        launchAtLoginButton.state = status.isRegistered ? .on : .off
        isUpdatingLaunchControl = false

        switch status {
        case .disabled:
            launchAtLoginButton.isEnabled = true
            loginItemStatusLabel.stringValue = "You can turn this on now or later in Settings."
            loginItemStatusLabel.textColor = .secondaryLabelColor
            loginItemSettingsButton.isHidden = true
        case .enabled:
            launchAtLoginButton.isEnabled = true
            loginItemStatusLabel.stringValue = "Coast will be ready after you sign in."
            loginItemStatusLabel.textColor = .secondaryLabelColor
            loginItemSettingsButton.isHidden = true
        case .requiresApproval:
            launchAtLoginButton.isEnabled = true
            loginItemStatusLabel.stringValue = "Registered, but macOS still needs your approval."
            loginItemStatusLabel.textColor = .systemOrange
            loginItemSettingsButton.isHidden = false
        case .unavailable:
            launchAtLoginButton.isEnabled = true
            loginItemStatusLabel.stringValue = "macOS hasn't registered this copy of Coast as a login item yet."
            loginItemStatusLabel.textColor = .systemOrange
            loginItemSettingsButton.isHidden = true
        }
    }

    private func configureContent(in window: NSWindow) {
        guard let contentView = window.contentView else { return }

        let appIcon = NSImageView()
        appIcon.image = NSApp.applicationIconImage
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "Coast")
        nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        let taglineLabel = NSTextField(labelWithString: "Smooth scrolling for the mouse you already own")
        taglineLabel.textColor = .secondaryLabelColor

        let nameStack = NSStackView(views: [nameLabel, taglineLabel])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 3

        let brandStack = NSStackView(views: [appIcon, nameStack])
        brandStack.orientation = .horizontal
        brandStack.alignment = .centerY
        brandStack.spacing = 15

        progressLabel.alignment = .right
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let header = NSStackView(views: [brandStack, NSView(), progressLabel])
        header.orientation = .horizontal
        header.alignment = .centerY

        pageContainer.translatesAutoresizingMaskIntoConstraints = false

        backButton.title = "Back"
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(backSelected)

        primaryButton.title = "Continue"
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(primarySelected)

        let footer = NSStackView(views: [backButton, NSView(), primaryButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let rootStack = NSStackView(views: [header, separator(), pageContainer, separator(), footer])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 64),
            appIcon.heightAnchor.constraint(equalToConstant: 64),
            header.widthAnchor.constraint(equalToConstant: 488),
            pageContainer.widthAnchor.constraint(equalToConstant: 488),
            pageContainer.heightAnchor.constraint(equalToConstant: 236),
            footer.widthAnchor.constraint(equalToConstant: 488),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 36),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -36),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func show(step: Step) {
        self.step = step
        pageContainer.subviews.forEach { $0.removeFromSuperview() }

        let page: NSView
        switch step {
        case .welcome:
            page = welcomePage()
            backButton.isHidden = true
            primaryButton.title = "Continue"
            primaryButton.isEnabled = true
        case .accessibility:
            page = accessibilityPage()
            backButton.isHidden = false
            primaryButton.title = "Continue"
            primaryButton.isEnabled = isTrusted
        case .ready:
            page = readyPage()
            backButton.isHidden = false
            primaryButton.title = "Start Coast"
            primaryButton.isEnabled = true
        }

        progressLabel.stringValue = String(format: "%d of %d", step.rawValue + 1, Step.allCases.count)
        page.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            page.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            page.bottomAnchor.constraint(lessThanOrEqualTo: pageContainer.bottomAnchor)
        ])
    }

    private func welcomePage() -> NSView {
        let title = pageTitle("Wheel scrolling that feels at home on your Mac.")
        let body = wrappingLabel(
            "Coast turns the individual ticks from a conventional mouse wheel into one continuous motion. Trackpads, Magic Mouse scrolling, keyboard input, clicks, files, and window contents are left alone."
        )

        launchAtLoginButton.setButtonType(.switch)
        launchAtLoginButton.title = "Open Coast at Login"
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginChanged)

        configureWrappingLabel(loginItemStatusLabel)
        loginItemSettingsButton.title = "Open Login Items…"
        loginItemSettingsButton.bezelStyle = .rounded
        loginItemSettingsButton.target = self
        loginItemSettingsButton.action = #selector(openLoginItemsSelected)

        let loginStack = NSStackView(views: [launchAtLoginButton, loginItemStatusLabel, loginItemSettingsButton])
        loginStack.orientation = .vertical
        loginStack.alignment = .leading
        loginStack.spacing = 8

        let stack = NSStackView(views: [title, body, loginStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(10, after: title)
        stack.widthAnchor.constraint(equalToConstant: 488).isActive = true
        updateLaunchAtLogin(status: launchAtLoginStatus)
        return stack
    }

    private func accessibilityPage() -> NSView {
        let title = pageTitle("Allow Coast to smooth mouse-wheel events.")
        let body = wrappingLabel(
            "macOS requires Accessibility permission before Coast can replace discrete wheel ticks with smooth scrolling. Coast does not monitor keyboard input, clicks, files, or the contents of your windows."
        )

        configureWrappingLabel(permissionStatusLabel)
        permissionButton.title = "Open Accessibility Permission…"
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(permissionSelected)

        let statusStack = NSStackView(views: [permissionStatusLabel, permissionButton])
        statusStack.orientation = .vertical
        statusStack.alignment = .leading
        statusStack.spacing = 10

        let stack = NSStackView(views: [title, body, statusStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(10, after: title)
        stack.widthAnchor.constraint(equalToConstant: 488).isActive = true
        updatePermission(isTrusted: isTrusted)
        return stack
    }

    private func readyPage() -> NSView {
        let title = pageTitle("Coast is ready.")
        let body = wrappingLabel(
            "Look for the Coast mark in your menu bar. From there you can pause smooth scrolling, open Settings, check Coast's status, or restore the tuned defaults at any time."
        )

        let tip = NSTextField(wrappingLabelWithString: "Tip: Try one slow wheel tick, then several quick ticks on a long page. Coast combines overlapping ticks into a smooth, responsive glide.")
        tip.textColor = .secondaryLabelColor
        tip.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [title, body, tip])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(10, after: title)
        stack.widthAnchor.constraint(equalToConstant: 488).isActive = true
        return stack
    }

    private func pageTitle(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        return label
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 14)
        return label
    }

    private func configureWrappingLabel(_ label: NSTextField) {
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 488).isActive = true
        return box
    }

    @objc private func backSelected() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        show(step: previous)
    }

    @objc private func primarySelected() {
        if step == .ready {
            onComplete?()
            close()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        show(step: next)
    }

    @objc private func launchAtLoginChanged() {
        guard !isUpdatingLaunchControl else { return }
        onLaunchAtLoginChanged?(launchAtLoginButton.state == .on)
    }

    @objc private func openLoginItemsSelected() {
        onOpenLoginItemsSettings?()
    }

    @objc private func permissionSelected() {
        onRequestPermission?()
    }
}
