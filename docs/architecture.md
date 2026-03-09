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

## Design Goals

- Native macOS feel
- Low idle overhead
- Protocol-driven testability
- Clear privacy boundaries around external lookups and location access
- Compact menu-bar-first presentation, even when external travel signals are enabled
