# Coast

Coast is a small, open-source macOS menu-bar app that makes a conventional mouse wheel scroll smoothly while leaving trackpads and other continuous scrolling unchanged.

Discrete wheel ticks use a continuous cubic ease-out animation. The default 700 ms glide is tuned against an MX Master 3S and can be adjusted from 200–1,200 ms in Settings.

## Requirements

- macOS 13 Ventura or later
- Xcode 26 or a compatible Xcode version with the macOS SDK
- Accessibility permission while Coast is running

## Build locally

```sh
xcodebuild \
  -project Coast.xcodeproj \
  -scheme Coast \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build
```

The app is written in Swift and AppKit and has no third-party dependencies. Development builds use local/ad-hoc signing with a stable, bundle-identifier-based development requirement so Accessibility approval survives ordinary rebuilds. Open `Coast.xcodeproj` in Xcode to run the app and grant Accessibility access when prompted. Test Open at Login from a copy installed in `/Applications`; macOS may not register a login item for an app running directly from DerivedData.

Build-ready icons live in `Coast/Resources/Assets.xcassets`. Editable brand sources, generated exports, usage guidance, and cross-platform color tokens live separately in `Design/Brand` so design artifacts are not copied into the application bundle.

## Install and use

1. Copy `Coast.app` to `/Applications`.
2. Open Coast and follow the three-step welcome flow. It explains what Coast changes, offers to open Coast at login, and guides you through the macOS Accessibility prompt.
3. Look for the Coast mark in the menu bar; Coast has no Dock icon.
4. Adjust speed, smoothness, direction, Accessibility access, or Open at Login from Settings.

Coast uses Apple's current Service Management API for Open at Login. It does not install a separate helper executable. If macOS says approval is required, use Coast's `Open Login Items…` button and approve Coast in System Settings.

Public releases will be signed with Developer ID, notarized by Apple, and distributed through GitHub Releases and a Homebrew Cask. Never bypass a Gatekeeper warning for an artifact whose signature or notarization cannot be verified.

## Test

```sh
xcodebuild \
  -project Coast.xcodeproj \
  -scheme Coast \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

See [TESTING.md](TESTING.md) for the automated coverage and manual hardware/application matrix.

## Prepare a public release

Public distribution requires an active Apple Developer Program membership, a `Developer ID Application` certificate, and notarization credentials stored in Keychain. Do not put certificate material or notarization passwords in the repository.

Store notarization credentials once:

```sh
xcrun notarytool store-credentials "coast-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Then build, sign, notarize, staple, verify, and package a release:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
NOTARYTOOL_PROFILE="coast-notary" \
BUILD_NUMBER="1" \
./Scripts/build-release.sh 0.1.0
```

The script also saves Apple's complete notarization log beside the ZIP and checksum in `dist/<version>/`; inspect it before publishing. Upload the ZIP and checksum to a matching immutable GitHub tag such as `v0.1.0`. Replace `VERSION` and `SHA256` in [Packaging/coast.rb.template](Packaging/coast.rb.template), commit the resulting `Casks/coast.rb` to the Homebrew tap, and test installation from that exact GitHub asset.

## Privacy

All processing is local. Coast has no networking or analytics and monitors only scroll-wheel events. See [PRIVACY.md](PRIVACY.md).

## Known limitations

- Coast classifies input from event metadata, not hardware identity. Mouse drivers that emit continuous pixel-based scrolling are passed through unchanged and may not be smoothed.
- The first build after changing Coast's development or release signing requirement needs a fresh Accessibility approval. Remove stale Coast entries in System Settings, add the exact app copy being tested, and toggle that copy on.
- Hardware behavior varies. Please include the macOS version and mouse model in compatibility reports, but never attach private system or input logs.

## Rename checklist

If the product is renamed, update the Xcode product/target/module names, bundle display name and identifier, status/about text, synthetic-event marker namespace, documentation, release artifact name, and Homebrew cask.

## License

MIT. See [LICENSE](LICENSE).
