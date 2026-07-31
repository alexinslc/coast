import AppKit
import ApplicationServices

@MainActor
final class AccessibilityPermissionManager {
    var onAuthorizationChanged: ((Bool) -> Void)?

    private(set) var isTrusted = false
    private var pollingTimer: Timer?

    func startMonitoring() {
        guard pollingTimer == nil else { return }
        refresh()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        pollingTimer?.tolerance = 0.25
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func refresh() {
        let trusted = checkTrust(prompt: false)
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        onAuthorizationChanged?(trusted)
    }

    func requestPermission() {
        _ = checkTrust(prompt: true)
        refresh()
    }

    private func checkTrust(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
