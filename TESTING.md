# Coast Testing

## Automated tests

Run the deterministic unit suite:

```sh
xcodebuild \
  -project Coast.xcodeproj \
  -scheme Coast \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The suite covers cubic ease-out shape, overlapping animations, duration and distance, acceleration, reversal, independent axes, fractional accumulation, clamping, cancellation, long clock gaps, continuous-event passthrough, synthetic-event recursion filtering, Shift routing, settings validation, and onboarding-completion persistence.

## Optional sanitized diagnostics

Debug builds can log only coarse event metadata when launched with this environment variable:

```sh
COAST_DEBUG_SCROLL_EVENTS=1 /path/to/Coast.app/Contents/MacOS/Coast
```

Diagnostics indicate only whether the event was continuous, which axes were nonzero, and whether Shift was present. They do not contain application names, window information, typed content, files, or persisted input. Release builds compile this logging out.

## Accessibility approval for development builds

Debug builds use the requirement in `Coast/DevelopmentRequirements` to keep their macOS Accessibility identity stable across ordinary rebuilds. The first build made with this requirement needs one clean approval:

1. Quit all running copies of Coast.
2. In System Settings > Privacy & Security > Accessibility, remove every existing Coast entry.
3. Run Coast from Xcode, choose `Permission Required…`, and continue through the system prompt.
4. Toggle Coast on. Return to Coast; it should report `Status: Active` within two seconds.

If more than one Coast copy is present on the Mac, reveal Xcode's current build product and confirm that exact app is the one in Accessibility. A public Developer ID release uses its Apple-issued signing identity instead of this development-only requirement.

## Onboarding and Open at Login

Debug builds accept two presentation-only launch arguments:

- `--show-onboarding` opens the welcome flow without erasing its saved completion state.
- `--show-settings` opens Settings immediately.

Test Open at Login from a Coast copy in `/Applications`, not directly from DerivedData:

1. Open Settings and turn on `Open Coast at Login`.
2. Confirm the status says Coast will open automatically.
3. Quit and reopen Coast; confirm the toggle remains on.
4. Turn it off and confirm the status changes immediately, then turn it back on if desired.
5. If Coast reports that approval is required, use `Open Login Items…`, make the user-controlled change in System Settings, and return to Coast. The status should refresh when the app becomes active.

The registration API can be verified without signing out. A true subsequent-login launch test still requires the tester to sign out and back in (or restart) at a convenient time.

## Current local verification

On 2026-07-31, the Debug app was installed to `/Applications` and the following passed on the development Mac:

- All 29 unit tests.
- All three onboarding pages and the polished Settings window in the running AppKit app.
- Login-item registration, unregistration, re-registration, and state persistence across an app restart.
- Live detection of the currently granted Accessibility permission.

Accessibility revocation/restoration and a real sleep/wake or sign-out/sign-in cycle remain user-controlled manual checks because they change security or session state.

## Manual matrix

Hardware, as available:

- Generic USB mouse
- Bluetooth mouse
- Logitech mouse and vendor driver
- MacBook trackpad
- Magic Mouse
- 60 Hz display
- High-refresh display
- Intel Mac, or at minimum an explicit universal-binary inspection

Applications:

- Finder
- Safari, Chrome, and Firefox
- Preview with a long PDF
- Notes and System Settings
- Visual Studio Code or another Electron app
- Native vertical and horizontal scroll views

Scenarios:

- One slow tick and rapid repeated ticks
- Immediate direction reversal
- Native horizontal wheel input
- Shift + vertical wheel
- Simultaneous axes
- Switch from an animating wheel to trackpad/Magic Mouse input
- Enable and disable
- Grant, revoke, and restore Accessibility permission
- Sleep and wake
- Quit and restart
- Launch Coast twice, then launch a separately built copy with the same bundle identifier; verify only one process and one menu-bar item remain and the existing copy opens Settings
- Multiple displays and changing frontmost windows
- Several idle minutes while observing CPU use

Record the exact macOS version, hardware, driver, display refresh rate, and application for each manual result. Do not mark unavailable hardware as passing; list it as unverified.

## Verified 0.1.0 release candidate

The following checks passed for version 0.1.0, build 2, on August 2, 2026:

- All 28 unit tests passed.
- Xcode's Release analyzer completed successfully. Its only toolchain message was the expected metadata notice that Coast has no App Intents dependency.
- The archive contains native `arm64` and `x86_64` slices and targets macOS 13.0 or later.
- The app has a timestamped Developer ID Application signature and Hardened Runtime. It has no embedded entitlements.
- Apple notarization submission `6868b421-1aae-417c-a7c5-abbf8de7e092` was accepted with no issues, and its ticket was stapled and validated.
- The packaged ZIP's SHA-256 checksum passed. A freshly extracted copy was given a quarantine attribute, then passed strict signature validation, stapler validation, and Gatekeeper assessment as `Notarized Developer ID`.
- Bundle inspection found only the Coast executable, Info.plist, icon/asset resources, package metadata, and signature resources. The executable links only Apple system frameworks and Swift runtime libraries.
- A source scan found no networking or web-view API references.

Build 2 predates the single-instance and UI fixes and is preserved only as a successful release rehearsal. Do not publish it; create and verify build 3 or later from the current source first.

Still required before calling the public distribution path verified: download the exact GitHub Release asset, repeat the quarantine/launch check on another Mac if available, install that asset through the Homebrew Cask, observe the running Release app for network connections, and complete any remaining hardware/application matrix entries.

## Release checks

Before publishing:

1. Run the automated suite and Xcode analyzer.
2. Build both `arm64` and `x86_64` slices.
3. Verify the Developer ID signature, Hardened Runtime, and lack of unintended entitlements.
4. Inspect linked frameworks and bundle contents.
5. Submit to Apple notarization, inspect the log, and staple the ticket.
6. Test a freshly downloaded quarantined artifact with Gatekeeper.
7. Observe the Release process and confirm it makes no network connections.
8. Install the exact GitHub asset through the Homebrew Cask.
