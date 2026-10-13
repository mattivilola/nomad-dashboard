# Architecture

Nomad Dashboard is split into three layers:

- `App/`: the menu bar app target (plus the `App/PowerHelper` and `App/Widgets` targets), scenes, window orchestration, Sparkle glue,
  and platform-specific UX.
- `Packages/NomadCore/`: data collection, provider protocols, persistence,
  settings, and snapshot aggregation.
- `Packages/NomadUI/`: cards, charts, theme tokens, and reusable SwiftUI views.

## Data Flow

1. Live monitors sample network, power, Wi-Fi, VPN, IP, and weather state.
2. Travel alert providers normalize advisory, local weather alert, and regional security data into one travel-alert snapshot.
3. `DashboardSnapshotStore` aggregates current readings and persisted trends.
4. `NomadUI` renders the snapshot into a compact dashboard.
5. The app layer wires quick actions, windows, permissions, and update flow.

## Siri, Shortcuts, And Widgets

- `NomadCore/Models/QuickAnswers.swift` turns a snapshot into the spoken and written answers (emergency numbers, status, nearest embassy, daylight). App Intents in `App/Sources/Intents/` read the live stores registered with `AppDependencyManager` in the app's `init` and return those sentences; they never open a window.
- `WidgetSnapshot` (NomadCore) is the compact, display-ready state for the widgets. `WidgetSnapshotPublisher` (app) writes it to the App Group container after dashboard refreshes, throttled and only when the content changed, and reloads the WidgetKit timelines. The widget extension in `App/Widgets/` only reads it and renders it.
- The App Group is team-prefixed (`$(TeamIdentifierPrefix)com.iloapps.NomadDashboard[.dev]`, set as `APP_GROUP_IDENTIFIER` in `Config/*.xcconfig`) and is in the entitlements of both the app and the sandboxed extension. Builds without it have no widget data and the app skips writing.

## Keep Awake And The Power Helper

- `KeepAwakeController` (NomadCore) holds an IOKit power assertion for a chosen duration and publishes the running `KeepAwakeSession`. It never polls: one task sleeps until the deadline, and the wake notification re-checks it.
- Lid-closed mode is optional (`keepAwakeWhileLidClosed`, on by default) and goes through `LidClosedSleepControlling`. `PowerHelperClient` registers the launchd daemon with `SMAppService.daemon` and talks to it over one XPC connection that lives as long as the session. `refreshLidClosedStatus()` runs when the dashboard becomes visible and when the app becomes active, so approving the helper in Login Items takes effect without polling.
- `Packages/NomadCore` has a second, dependency-free library, `NomadPowerHelperKit`, shared by the app and the helper: the XPC protocols, the label and code-signing requirement helpers, and `LidClosedSessionEngine`, the helper's whole decision logic (journal first, restore rules, deadline, battery and heat guards) behind small protocols so it is unit tested without `pmset`.
- `App/PowerHelper/` is the `NomadDashboardPowerHelper` command-line target: `main.swift`, the XPC listener delegate and a coordinator that owns the session, the wall-clock deadline timer and the event-driven battery and thermal guards. It is embedded in `Contents/Library/HelperTools/`; its launchd plist is generated into `Contents/Library/LaunchDaemons/` by a build phase from `NOMAD_APP_BUNDLE_IDENTIFIER` and `NOMAD_POWER_HELPER_LABEL` in `Config/Identity.*.xcconfig`. See `docs/security.md` and `docs/release.md`.

## Design Goals

- Native macOS feel
- Low idle overhead
- Protocol-driven testability
- Clear privacy boundaries around external lookups and location access
- Compact menu-bar-first presentation, even when external travel signals are enabled
