# Coast Brand Pack

Version 1.0 — Momentum direction

Coast turns discrete mouse-wheel input into smooth motion. Its mark expresses that idea with three progressively longer strokes: separate impulses resolving into momentum.

## Start here

- `Preview/coast-brand-sheet.png` — generated overview of the system
- `Sources/BrandSheet/coast-brand-sheet.svg` — editable source for the brand overview
- `Sources/` — editable SVG source artwork
- `Exports/` — generated PNG, iconset, and `.icns` deliverables
- `Tokens/` — color tokens for Swift, CSS, and JSON
- `../../Coast/Resources/Assets.xcassets` — the build-ready Xcode resources used by the app

## macOS menu-bar usage

Use the `CoastMenuBarTemplate` image set from the app asset catalog and let macOS apply the correct appearance automatically:

```swift
if let image = NSImage(named: "CoastMenuBarTemplate") {
    image.isTemplate = true
    statusItem.button?.image = image
}
```

Do not place the full-color mark in the menu bar. Template rendering keeps the glyph legible in light, dark, highlighted, and accessibility appearances.

## App icon usage

The app target uses `Coast/Resources/Assets.xcassets/AppIcon.appiconset` as its App Icon source. The 1024px master, iconset, and compiled `.icns` in `Exports/AppIcon` are retained for release tooling and non-Xcode uses; do not add those exports to the app bundle.

## Typography

Use the macOS system font for product UI and the Coast wordmark. Recommended weights:

- Wordmark: SF Pro Display Medium/Semibold
- Interface headings: system semibold
- Body and settings: system regular

The SVG wordmark uses a system-font stack so it remains editable. Convert the wordmark to outlines in your design application before sending it to a print vendor.

## License note

No trademark or artwork license is assigned by this pack. Choose and document the logo license separately from the open-source software license before public distribution.
