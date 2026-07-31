# Coast Privacy

Coast processes scroll-wheel events entirely on your Mac.

- Coast does not collect, store, or transmit personal data.
- Coast contains no analytics, telemetry, advertising, crash-reporting service, updater, or network functionality.
- Accessibility permission is used only to observe discrete scroll-wheel events, suppress accepted wheel events, and post smooth replacement scroll events.
- Coast does not monitor keyboard events, mouse clicks, clipboard contents, window contents, files, or application activity.
- Preferences are stored locally using macOS `UserDefaults`.
- Scroll input is never written to disk.

Debug builds can optionally print sanitized scroll metadata while a developer is testing hardware compatibility. This diagnostic output is disabled by default and is compiled out of Release builds.
