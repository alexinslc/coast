<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/Brand/Sources/Logo/coast-lockup-horizontal-reversed.svg">
    <source media="(prefers-color-scheme: light)" srcset="Design/Brand/Sources/Logo/coast-lockup-horizontal.svg">
    <img alt="Coast" src="Design/Brand/Sources/Logo/coast-lockup-horizontal.svg" width="310">
  </picture>
</h1>

<p align="center">
  <strong>Smooth mouse-wheel scrolling for macOS.</strong><br>
  Turn every wheel tick into a fluid, adjustable glide—without changing the natural feel of your trackpad or Magic Mouse.
</p>

<p align="center">
  <a href="https://alexinslc.com/coast/">Website</a> ·
  <a href="https://github.com/alexinslc/coast/releases/latest">Download</a> ·
  <a href="PRIVACY.md">Privacy</a> ·
  <a href="TESTING.md">Testing</a>
</p>

<p align="center">
  <a href="https://github.com/alexinslc/coast/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/alexinslc/coast?style=flat-square&amp;color=6068FF&amp;label=release"></a>
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-10143D?style=flat-square&amp;logo=apple&amp;logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-2F49F5?style=flat-square"></a>
</p>

Coast is a small, native, open-source menu-bar app for conventional mouse wheels. Discrete wheel ticks use a continuous cubic ease-out animation; continuous trackpad and Magic Mouse input passes through unchanged. The default 700 ms glide is tuned against an MX Master 3S and can be adjusted from 200–1,200 ms in Settings.

## Why Coast

- **Fluid, responsive motion:** repeated wheel ticks build naturally, while reversals remain immediate.
- **Native where it matters:** trackpads and other continuous scrolling retain Apple’s original behavior.
- **Private by construction:** no account, analytics, network access, updater, helper process, or third-party dependencies.

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

The app is written in Swift and AppKit and has no third-party dependencies. Development builds use local/ad-hoc signing with a stable, bundle-identifier-based development requirement so Accessibility approval survives ordinary rebuilds. Open `Coast.xcodeproj` in Xcode to run the app and grant Accessibility access when prompted. Coast prevents separately built copies with the same bundle identifier from running simultaneously, so quit an installed copy before running from Xcode. For deliberate multi-instance debugging, add `--allow-multiple-instances` to the Debug scheme. Test Open at Login from a copy installed in `/Applications`; macOS may not register a login item for an app running directly from DerivedData.

Build-ready icons live in `Coast/Resources/Assets.xcassets`. Editable brand sources, generated exports, usage guidance, and cross-platform color tokens live separately in `Design/Brand` so design artifacts are not copied into the application bundle.

## Install and use

Install the signed and notarized release with Homebrew:

```sh
brew install --cask alexinslc/tap/coast
```

Alternatively, download the ZIP from the [latest GitHub Release](https://github.com/alexinslc/coast/releases/latest) and copy `Coast.app` to `/Applications`.

Visit the [Coast website](https://alexinslc.com/coast/) for the product overview and current download link.

Then:

1. Open Coast and follow the three-step welcome flow. It explains what Coast changes, offers to open Coast at login, and guides you through the macOS Accessibility prompt.
2. Look for the Coast mark in the menu bar; Coast has no Dock icon.
3. Adjust speed, smoothness, direction, Accessibility access, or Open at Login from Settings.

Coast uses Apple's current Service Management API for Open at Login. It does not install a separate helper executable. If macOS says approval is required, use Coast's `Open Login Items…` button and approve Coast in System Settings.

Public releases are signed with Developer ID, notarized by Apple, and distributed through GitHub Releases and a Homebrew Cask. Never bypass a Gatekeeper warning for an artifact whose signature or notarization cannot be verified.

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

The script also saves Apple's complete notarization log beside the ZIP and checksum in `dist/<version>/`; inspect it before publishing. Verify the checksum with `shasum -a 256 -c dist/<version>/Coast-<version>-macOS.zip.sha256`, then upload the ZIP and checksum to a matching immutable GitHub tag such as `v0.1.0`. Replace `VERSION` and `SHA256` in [Packaging/coast.rb.template](Packaging/coast.rb.template), commit the resulting `Casks/coast.rb` to the Homebrew tap, and test installation from that exact GitHub asset.

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
