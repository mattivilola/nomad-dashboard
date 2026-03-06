# Nomad Dashboard

Nomad Dashboard is a native macOS menu bar companion for travelling developers
and remote workers. It lives in the top bar, stays out of the Dock, and opens a
compact dashboard for the signals that matter when your MacBook is your office:
network quality, public connectivity, power draw, travel context, and weather.

Maintainer: Matti Vilola  
Contributed by ILO APPLICATIONS SL ([iloapps.dev](https://iloapps.dev))

## Vision

Nomad Dashboard should feel like a compact travel instrument panel rather than a
generic system monitor. The app focuses on signals that help answer practical
questions quickly:

- Is this connection stable enough for calls and coding?
- How hard is the MacBook draining right now?
- Where does the network think I am?
- Am I on Wi-Fi, VPN, battery, and in the expected time zone?
- What does the local weather look like today and tomorrow?

## Planned v1 Capabilities

- Passive upload and download throughput
- Periodic latency and jitter checks
- Public IP and optional IP-based geolocation
- Battery percentage, charging state, discharge rate, and adapter context
- Wi-Fi signal context, VPN detection, and current time zone
- Current weather plus tomorrow's forecast summary
- Menu bar quick actions for refresh, settings, about, and updates
- Sparkle-based self-update plumbing for direct distribution

## Stack

- SwiftUI + AppKit bridges
- macOS 14+
- XcodeGen for project generation
- Swift Package Manager for local modules and remote dependencies
- Sparkle for in-app updates
- WeatherKit for weather data

## Repository Layout

```text
App/                    App target sources, assets, scenes, Sparkle glue
Packages/NomadCore/     Models, monitors, persistence, provider protocols
Packages/NomadUI/       Shared dashboard components, theme, charts
Config/                 xcconfig templates and release configuration
scripts/                Bootstrap, build, archive, DMG, notarization helpers
docs/                   Architecture, UX, release, roadmap, privacy notes
.github/                CI, issue templates, pull request template
```

## Quick Start

1. Install toolchain helpers:
   `make bootstrap`
2. Generate the Xcode project:
   `make generate`
3. Build the app:
   `make build`
4. Run the tests:
   `make test`

The generated `.xcodeproj` is intentionally not committed. `project.yml` is the
source of truth.

## Development Notes

- The app is a menu bar utility with `LSUIElement=1`, so it should not appear in
  the Dock during normal operation.
- External location lookups are opt-in. Device location and weather access use
  explicit permission prompts.
- Release automation is local-first. Signing, notarization, DMG packaging, and
  Sparkle publishing are wired through scripts and documented in
  [docs/release.md](docs/release.md).

## Open Source Collaboration

- License: Apache-2.0
- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Agent instructions: [AGENTS.md](AGENTS.md)
- Claude instructions: [CLAUDE.md](CLAUDE.md)

## Roadmap

The first milestone is the public bootstrap: a working menu bar shell, live and
sample data pipelines, local persistence, release helpers, and contributor-ready
documentation. See [docs/roadmap.md](docs/roadmap.md) for the staged plan.

