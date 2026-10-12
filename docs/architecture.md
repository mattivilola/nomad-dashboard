# Architecture

Nomad Dashboard is split into three layers:

- `App/`: the menu bar app target, scenes, window orchestration, Sparkle glue,
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

## Design Goals

- Native macOS feel
- Low idle overhead
- Protocol-driven testability
- Clear privacy boundaries around external lookups and location access
- Compact menu-bar-first presentation, even when external travel signals are enabled
