# Coast for macOS — Build Plan

Status: product-polish implementation complete. Automated tests and running-app UI inspection pass; Open at Login is verified from `/Applications`. Full hands-on compatibility testing, user-controlled permission/session checks, and Developer ID notarization remain release gates.

Last reviewed: 2026-07-31

## 1. Product goal

Build a lightweight, open-source macOS menu-bar app that replaces discrete mouse-wheel events with short streams of smooth, pixel-based scroll events. Trackpads, Magic Mouse input, and any other continuous/pixel-based scrolling must pass through unchanged.

Coast must:

- Run entirely on the Mac.
- Use no networking, analytics, telemetry, crash-reporting service, updater, web view, or runtime-downloaded code.
- Monitor only scroll-wheel events.
- Request only Accessibility permission.
- Store settings locally in `UserDefaults`.
- Remain easy to rename after version 1.

The product and target name is `Coast`. The bundle identifier is `com.alexinslc.coast`.

## 2. Reviewed platform decisions

- Language and UI: Swift with AppKit, using programmatic views. SwiftUI is not needed for version 1.
- Project: native Xcode project with an application target and unit-test target.
- Deployment target: macOS 13.0.
- Architectures: Xcode standard architectures (`arm64` and `x86_64`) for Release.
- Dependencies: Apple frameworks only; no package manager or third-party code.
- License: MIT.
- App form: menu-bar agent with `LSUIElement = YES`, no Dock icon, and no ordinary application menu bar.
- Distribution: outside the Mac App Store through versioned GitHub Releases and a Homebrew Cask.
- App Sandbox: disabled. Apple documents Accessibility APIs in assistive apps as incompatible with App Sandbox. No network or file-access entitlements will be added.
- Hardened Runtime: enabled for signed Release builds.
- Signing during development: automatic signing is not required; local/ad-hoc Debug builds are sufficient.
- Public release identity: sign with a `Developer ID Application` certificate, include a secure timestamp, submit to Apple's notarization service, inspect the notary log, and staple the ticket before packaging the final release.
- API policy: documented public Apple APIs only.

The local build environment was checked before implementation: Xcode 26.6 and Swift 6.3.3 are installed.

## 3. Version 1 scope

### Included

- Menu-bar-only application.
- Smooth vertical and horizontal scrolling for discrete wheel events.
- Continuous/pixel-based input passthrough.
- Shift + vertical-wheel conversion to horizontal scrolling when there is no native horizontal delta.
- Enable/disable control.
- Scroll-speed control.
- Smoothness/duration control.
- Independent reverse-vertical and reverse-horizontal controls.
- Restore Defaults, About, Settings, and Quit actions.
- Three-step first-run onboarding.
- Open at Login using `SMAppService.mainApp`, with no separate helper executable.
- Local validated preferences.
- Accessibility-permission explanation and request flow.
- Detection and recovery for revoked permission, disabled event taps, timeout, sleep, and wake.
- Universal Release build.
- Deterministic unit tests for physics and settings.
- Privacy, build, installation, limitations, and release documentation.

### Excluded

- Analytics, telemetry, accounts, networking, cloud sync, crash-reporting services, or automatic updates.
- Mouse-button remapping, keyboard capture, gestures, per-app profiles, auto-scroll, or grab-and-drag scrolling.
- A separate background helper or privileged daemon.
- Apple Events automation, clipboard access, arbitrary file access, or shell-command execution in the app.
- Private/undocumented APIs or undocumented System Settings URL schemes.
- Mac App Store distribution.

## 4. Project layout

```text
Coast/
├── Coast.xcodeproj
├── Coast/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   └── AppController.swift
│   ├── MenuBar/
│   │   └── MenuBarController.swift
│   ├── Onboarding/
│   │   └── OnboardingWindowController.swift
│   ├── Permissions/
│   │   └── AccessibilityPermissionManager.swift
│   ├── Scrolling/
│   │   ├── ScrollEventTap.swift
│   │   ├── ScrollPhysicsEngine.swift
│   │   ├── ScrollTypes.swift
│   │   └── SyntheticScrollEmitter.swift
│   ├── Settings/
│   │   ├── SettingsStore.swift
│   │   └── SettingsWindowController.swift
│   ├── Startup/
│   │   └── LaunchAtLoginManager.swift
│   ├── Resources/
│   └── Info.plist
├── CoastTests/
│   ├── ScrollPhysicsEngineTests.swift
│   └── SettingsStoreTests.swift
├── BUILD_PLAN.md
├── LICENSE
├── PRIVACY.md
└── README.md
```

The Xcode groups should mirror the folders. All UI/lifecycle types are main-actor isolated. Scroll processing uses explicit ownership and queues so Swift concurrency checks do not hide data races.

## 5. Components and responsibilities

### `AppController`

- Own the application lifecycle and coordinate the other components.
- Create the menu bar and settings window.
- Start the event tap only when the app is enabled and trusted.
- Cancel motion and stop the tap on disable, permission loss, sleep, or termination.
- Re-check permission and restart the tap after wake or app activation.
- Expose a small status model: disabled, permission required, starting, active, and tap unavailable.

### `AccessibilityPermissionManager`

- Check trust passively with `AXIsProcessTrustedWithOptions` and prompting disabled.
- Show an in-app explanation before the first explicit permission request.
- On the user's button press, call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt = true`; let macOS own the authorization UI.
- Never prompt automatically at launch.
- Re-check periodically at a low frequency while permission is missing, and on application activation.
- Detect revocation through the same check and notify `AppController`.
- If macOS does not reopen its pane after a previous denial, show concise manual navigation instructions rather than using an undocumented deep link.

### `ScrollEventTap`

- Install a `.scrollWheel`-only Core Graphics event tap; do not add keyboard, click, or modifier event types to its mask.
- Run the tap on a dedicated thread/run loop so UI work cannot stall it.
- Keep the C callback allocation-light and nonblocking.
- Convert accepted input into a small value-type `WheelImpulse` and dispatch it asynchronously to the physics queue.
- Return `nil` only after an input event has passed all acceptance checks and the impulse has been queued.
- Re-enable the tap for both timeout/user-input disabled callbacks, and report failure if it cannot remain enabled.
- Invalidate the run-loop source and tap cleanly on stop.

### `ScrollPhysicsEngine`

- Contain no AppKit, Core Graphics event objects, UI, or global state.
- Use a monotonic injectable clock.
- Own independent horizontal and vertical velocity, signed fractional-output remainder, direction, and recent-input state.
- Accept impulses asynchronously on one dedicated serial queue.
- Start a `DispatchSourceTimer` only while motion exists; begin at roughly 120 updates/second and calculate every step from actual elapsed time.
- Stop and release the timer when both axes settle so idle animation CPU cost is zero.
- Emit value-type pixel deltas through an injected closure/protocol.
- Clear all velocity, pending deltas, timing history, and remainders when cancelled or disabled.

### `SyntheticScrollEmitter`

- Create pixel-unit Core Graphics scroll events with both axes represented correctly.
- Use one private `CGEventSource` whose 64-bit `userData` contains a fixed app marker.
- Also set/verify the event's `eventSourceUserData` field so recursion filtering is testable.
- Post through the documented Core Graphics event-posting API.
- Receive already-quantized integer pixel deltas from the engine and preserve their axes and signs.
- Do no logging in Release.

### `SettingsStore`

- Expose typed settings and one immutable defaults definition.
- Validate every value read from `UserDefaults`.
- Publish changes so the engine/UI update immediately.
- Allow injection of a named/in-memory `UserDefaults` suite for tests.
- Never store event data.

### `MenuBarController` and `SettingsWindowController`

- Use Coast's custom template asset in the menu bar and Coast's application icon in window headers.
- Menu items: enabled toggle, Settings…, status (disabled/non-actionable except when permission is needed), Restore Defaults, About Coast, separator, Quit.
- Settings: speed slider, smoothness slider, reverse vertical, reverse horizontal, short test instructions or a native scroll test area, Restore Defaults.
- Keep the permission action visible when needed.
- Bring the accessory application and settings window forward correctly when Settings is selected.
- Use text plus state/icon—not color alone—for warnings.

### `OnboardingWindowController` and `LaunchAtLoginManager`

- Explain Coast's narrow scroll-only behavior before requesting permission.
- Present Accessibility state live and do not let setup finish before access is granted.
- Offer Open at Login as an explicit user choice and represent disabled, enabled, and approval-required states honestly.
- Use `SMAppService.mainApp`; do not bundle or install a helper executable.
- Refresh login-item and permission state when Coast becomes active.

## 6. Event acceptance and routing contract

Process each `.scrollWheel` event in this exact order:

1. If `eventSourceUserData` equals Coast's marker, return the event unchanged.
2. If `scrollWheelEventIsContinuous != 0`, return it unchanged. Before returning, asynchronously cancel any remaining synthetic mouse-wheel motion so it cannot fight new trackpad/Magic Mouse input.
3. Read line deltas for axis 1 (vertical) and axis 2 (horizontal). Do not infer hardware identity from vendor-specific fields.
4. If both deltas are zero, return the event unchanged.
5. If Shift is present, horizontal delta is zero, and vertical delta is nonzero, route the vertical value to horizontal and clear vertical. Modifier state is read from the scroll event itself; no keyboard event tap is installed.
6. Apply independent reverse settings after axis routing.
7. Clamp the input to a safe per-event range.
8. Queue the accepted impulse without waiting for the physics engine.
9. Suppress the original event by returning `nil`.

This deliberately prioritizes not altering continuous input. Some mouse drivers emit continuous/pixel events even for a physical wheel; those events will pass through and will not be smoothed in version 1. Hardware brand alone is not a safe classifier.

## 7. Physics model

Use overlapping cubic ease-out animation segments with a finite cutoff:

- Default distance: 40 pixels per unit wheel tick.
- Default settling duration: 700 ms, based on hands-on comparison with the preferred Smooze Pro feel on an MX Master 3S.
- Speed setting: multiplier clamped to a documented range, initially 0.25×–4.0×.
- Smoothness setting: settling duration clamped to 200–1,200 ms.
- Acceleration: rapid, same-direction impulses may scale from 1× up to 3× using only timestamped impulse history.
- Direction reversal: clear the affected axis's old velocity before applying the new impulse.
- Axes: calculate and settle independently.
- Extreme elapsed times after stalls/wake: clamp the simulation step and cancel on lifecycle wake rather than emitting a large catch-up delta.

For a configured duration `T`, each impulse contributes a cubic ease-out position curve `1 - (1 - t/T)^3`. Same-direction impulses overlap instead of replacing the animation already in flight, producing continuous motion while preserving the requested distance of each impulse. Speed affects distance and smoothness affects time without unintentionally changing one another. New opposite-direction input clears only the affected axis before starting its new curve.

All constants and calculations live in pure Swift value types. Tests use a fake clock and capture emitter output, never wall-clock sleeps.

## 8. Permission, failure, and lifecycle behavior

- Launch without permission: menu bar and settings work; engine remains stopped; no input is suppressed.
- User requests permission: show the explanation, then invoke the documented macOS prompt.
- Permission granted: detect without requiring a relaunch where possible and install the tap.
- Permission revoked: cancel motion immediately, invalidate/disable the tap, show Permission Required, and never suppress events.
- Tap creation failure: show Tap Unavailable and offer a Retry action; keep the app usable.
- Tap disabled by timeout/user input: re-enable in the callback and confirm enabled state; repeated failures transition to Tap Unavailable.
- Sleep: cancel pending motion and stop/invalidate the tap.
- Wake/session activation: re-check permission and recreate the tap if enabled.
- Disable: stop accepting input first, invalidate the tap, cancel the engine, then update UI state.
- Quit: perform the same shutdown sequence synchronously enough to prevent further posting, without waiting on animation work.

## 9. Settings defaults

Initial values, subject to hands-on tuning:

| Setting | Default | Valid range/behavior |
|---|---:|---|
| Enabled | `true` | Boolean |
| Speed | `1.0` | Clamp to 0.25–4.0 |
| Smoothness | `0.70 s` | Clamp to 0.20–1.20 s |
| Reverse vertical | `false` | Preserve incoming sign |
| Reverse horizontal | `false` | Preserve incoming sign |

Invalid types, non-finite numbers, and out-of-range stored numbers fall back to defaults. Runtime physics inputs are still clamped defensively. Restore Defaults resets every user-facing setting as one operation.

Settings schema version 2 migrates builds using the original exponential curve to the new 700 ms cubic default. Speed, enabled state, and direction preferences are preserved; the duration is reset because its meaning changed with the animation model.

## 10. Implementation phases and gates

### Phase 1 — Project foundation

- Create the app and test targets and the reviewed folder structure.
- Configure macOS 13, `LSUIElement`, supported architectures, and App Sandbox off.
- Add menu icon/menu shell, README, MIT license, and privacy document.
- Add a rename checklist to README (product name, target/module, bundle display name, marker namespace, and bundle identifier).
- Gate: Debug and Release compile for the host architecture; unit-test target launches.

### Phase 2 — Permission and lifecycle

- Implement passive authorization checks, explicit explanation/request, status UI, and activation polling.
- Add sleep/wake and session-active observers using `NSWorkspace.notificationCenter`.
- Gate: app stays usable without permission and reacts to a permission change without a normal relaunch when macOS permits.

### Phase 3 — Event inspection and filtering

- Install a scroll-only event tap on its dedicated run-loop thread.
- Add sanitized Debug-only metadata logging: continuous flag, nonzero axes, phases, flags, and timestamps—never application/window identity or long-term storage.
- Validate event classification using available mouse and trackpad hardware.
- Gate: continuous scrolling is byte-for-byte passed through; Release contains no per-event logging.

### Phase 4 — Smooth vertical prototype

- Add pure physics, tagged pixel emission, suppression-after-acceptance, and recursion prevention.
- Add vertical impulse, reversal, clamping, timer lifecycle, and cancellation tests.
- Gate: vertical wheel motion is smooth, synthetic events do not recurse, and unit tests pass.

### Phase 5 — Complete input and recovery

- Add horizontal input, Shift routing, simultaneous axes, independent reversal, timeout recovery, and sleep/wake recreation.
- Gate: all event-contract tests pass and manual trackpad/mouse switching does not create competing motion.

### Phase 6 — Settings and complete UI

- Add settings controls, immediate updates, validation, restore defaults, About, status/retry, and testing instructions/view.
- Gate: settings persist and invalid defaults tests pass.

### Phase 7 — Testing and tuning

- Run the automated suite and manual matrix.
- Measure callback time, active CPU, and idle CPU; tune only named constants.
- Test at 60 Hz and high refresh rates where hardware is available.
- Gate: acceptance criteria pass or any hardware gaps are documented as unverified, not silently claimed.

### Phase 8 — Release preparation

- Build a universal Release binary and verify both architectures.
- Set and verify a semantic marketing version plus a monotonically increasing build number.
- Archive and export `Coast.app` with a `Developer ID Application` identity, Hardened Runtime, secure timestamp, and no `get-task-allow` entitlement.
- Create a temporary ZIP of the signed app, submit it with `notarytool`, wait for completion, inspect the notary log even on success, then staple/validate the ticket on `Coast.app`.
- Package the stapled app as `Coast-<version>-macOS.zip` using macOS tooling that preserves the app bundle.
- Verify the final artifact with `codesign`, `spctl`, `stapler`, architecture inspection, and a clean-machine/quarantined-download launch test.
- Publish an immutable tagged GitHub Release containing the ZIP, SHA-256 checksum, release notes, and source archive.
- Add/update a Homebrew Cask whose versioned URL targets that GitHub asset, whose SHA-256 matches it, whose artifact is `Coast.app`, and whose minimum macOS version is Ventura.
- Start with a maintainer-owned tap for predictable releases; submission to the central `homebrew/cask` repository can happen later if desired and eligible.
- Inspect signature, Hardened Runtime, entitlements, linked frameworks, bundle contents, and source for networking APIs.
- Add complete local build/install instructions and public signing/notarization instructions. Never tell users to bypass Gatekeeper or use Homebrew's no-quarantine option.
- Gate: clean Release build, all automated tests pass, privacy checks pass, the notarization log is accepted without unresolved warnings, and the GitHub/Homebrew installation path passes Gatekeeper normally.

After every phase, keep the application runnable, run relevant tests, and record results before starting the next phase.

## 11. Automated tests

### Physics

- One impulse yields nonzero multi-frame cubic ease-out motion whose velocity decays monotonically.
- Same-direction animations overlap without truncating the existing curve.
- Motion stops within duration tolerance.
- Integrated emitted distance is within rounding tolerance.
- Same-direction rapid impulses accelerate predictably and never exceed 3×.
- Same-direction impulses outside the acceleration window do not accelerate.
- Opposite input clears prior momentum on only the affected axis.
- Vertical and horizontal state remain independent.
- Simultaneous axes emit correctly.
- Fractional output accumulates without permanent loss or sign bias.
- Input, velocity, elapsed-time, and output clamps prevent runaway motion.
- Cancellation/disabling clears motion and emits nothing afterward.
- A long clock gap never produces a catch-up jump.

### Event policy and emission

- Marker-matching events pass through.
- Continuous events pass through and request engine cancellation.
- Zero-delta events pass through.
- Accepted discrete events are suppressed only after queuing.
- Shift converts vertical-only input to horizontal; native horizontal input is preserved.
- Axis reversal settings apply after Shift routing.
- Generated events have pixel units, correct axes/signs, and the recursion marker.

Where Core Graphics objects make a true unit test awkward, isolate field-reading and policy decisions behind value types and test those without installing a global event tap.

### Settings

- Defaults are stable.
- Valid values round-trip.
- Invalid types and non-finite/out-of-range values become safe values.
- Restore Defaults resets every setting.
- Onboarding completion persists separately and is not erased by restoring scrolling defaults.
- Tests use an isolated `UserDefaults` suite.

## 12. Manual test matrix

Hardware, as available:

- Generic USB mouse.
- Bluetooth mouse.
- Logitech mouse/driver.
- MacBook trackpad.
- Magic Mouse.
- 60 Hz and high-refresh displays.
- Intel Mac or an explicit Rosetta/x86_64 build verification if Intel hardware is unavailable.

Applications:

- Finder, Safari, Chrome, Firefox, Preview/PDF, Notes, System Settings, VS Code/Electron, a long native scroll view, and a horizontal scroll view.

Scenarios:

- Single slow ticks, rapid repeated input, reversal, horizontal input, Shift-scroll, simultaneous axes, and extreme deltas.
- Switching from an animating mouse wheel to trackpad/Magic Mouse input.
- Enable/disable, permission grant/revocation/restoration, tap timeout recovery, sleep/wake, app restart, multiple displays, and changing/frontmost windows.
- Idle for several minutes to confirm no animation timer or meaningful CPU use.

## 13. Acceptance criteria

Version 1 is complete when:

- Compatible discrete mouse-wheel scrolling is visibly smooth across the tested applications.
- Continuous trackpad and Magic Mouse events are not suppressed or rewritten.
- Synthetic events never recurse.
- Direction reversal is immediate and horizontal/Shift scrolling works.
- No animation timer runs while idle and idle resource use is negligible.
- Permission loss, event-tap timeout, disable, sleep, and wake recover without swallowing input.
- Only Accessibility permission is requested.
- No network functionality, traffic, dependency, helper, or unexpected entitlement exists.
- Open at Login works through the main application registration and accurately reports whether macOS still requires approval.
- Settings persist and restore safely.
- All automated tests pass.
- Debug and Release builds succeed without correctness/security warnings.
- The Release app contains `arm64` and `x86_64` slices.
- The public artifact is Developer ID signed, notarized, stapled, and accepted by Gatekeeper without an unidentified-developer or malware-blocking warning. macOS may still show its normal first-launch confirmation for downloaded software.
- README, PRIVACY, license, build/install, known limitations, and signing/notarization documentation are complete.

## 14. Security and privacy verification

- Event mask contains only `.scrollWheel` plus unavoidable tap-disabled callback event types supplied by the system.
- No keyboard, click, clipboard, window-content, process-name, or file data is captured.
- No input event values are persisted.
- Debug event diagnostics are sanitized and compiled out of Release.
- Search source and linked symbols/frameworks for URL loading, sockets, Network, WebKit, telemetry, update, shell, and Apple Events code.
- Inspect the built app with `codesign` for its signature and entitlements.
- Inspect binary architectures and linked frameworks.
- Observe the running Release app during the manual test to confirm it creates no network traffic.
- Document that preferences are the only persisted data and are stored in `UserDefaults`.

## 15. Known design limitations to document

- Classification is event-based, not hardware-brand-based. A conventional mouse whose driver emits continuous/pixel events will be passed through and may not be smoothed.
- Accessibility approval is tied to the signed app identity/path; rebuilding or changing signing may require reauthorizing during development.
- Public distribution requires a maintainer's Developer ID certificate and Apple notarization credentials.
- Apple Developer Program membership is required to obtain the Developer ID certificate used for public releases.
- Manual hardware/application coverage is limited to devices available during development; unavailable cases must be listed as unverified.

## 16. Confirmed decisions and release-time inputs

Confirmed:

- Product name: `Coast`.
- Bundle identifier: `com.alexinslc.coast`.
- Distribution: direct/outside the Mac App Store with App Sandbox disabled.
- Public channels: GitHub Releases plus a Homebrew Cask.
- Trust path: Developer ID signing, Hardened Runtime, Apple notarization, and a stapled ticket.

The custom Coast application and menu-bar assets are integrated in the asset catalog; editable brand sources remain outside the application bundle in `Design/Brand`.

The following are needed only before the first public release, not before implementation:

- The Apple Developer team/Team ID and an available `Developer ID Application` certificate. Credentials must remain in the maintainer's Keychain or CI secrets and must never be committed.
- Confirmation of the intended GitHub repository. The current proposed repository is `alexinslc/coast`.
- Confirmation or creation of the initial Homebrew tap. The current proposal is `alexinslc/homebrew-tap`, with a `coast` cask.

## 17. Primary Apple references

- [Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [`CGEventField.scrollWheelEventIsContinuous`](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventiscontinuous)
- [`CGEvent.tapEnable`](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:))
- [`CGEventType.tapDisabledByTimeout`](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout)
- [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [`SMAppService.register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [`CGEventSource.userData`](https://developer.apple.com/documentation/coregraphics/cgeventsource/userdata)
- [`CGEventCreateScrollWheelEvent`](https://developer.apple.com/documentation/coregraphics/cgeventcreatescrollwheelevent)
- [`NSWorkspace.didWakeNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)
- [`NSApplication.ActivationPolicy.accessory`](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)
- [Developer ID](https://developer.apple.com/support/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

## 18. Instructions for implementation

- Implement one phase at a time and satisfy its gate before continuing.
- Prefer the smallest clear implementation and do not add features outside this plan.
- Do not add dependencies without explicit approval.
- Do not use private APIs, undocumented Settings URLs, or instructions that weaken macOS security/Gatekeeper.
- Treat the event callback as latency-critical and never make it wait for physics, UI, logging, or disk work.
- Keep physics deterministic and testable.
- Comment the event-filtering, suppression, and synthetic-marker decisions.
- When uncertain, preserve/pass through the original event.
- At completion, report the implementation, build instructions, test evidence, known limitations, permissions, privacy/network verification, and any unverified manual-test cases.
