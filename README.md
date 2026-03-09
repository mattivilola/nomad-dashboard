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
- Public IP and IP-based geolocation
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
3. Open the project in Xcode:
   `make open`
4. Build the app:
   `make build`
5. Launch the menu bar app:
   `make run`
6. Quit and relaunch the latest dev build:
   `make rerun`
7. Run the tests:
   `make test`
8. Probe the live external data sources:
   `make probe-sources`
9. Prepare a versioned release:
   `make release-patch`

The generated `.xcodeproj` is intentionally not committed. `project.yml` is the
source of truth.

`make build`, `make run`, and `make archive` use `xcbeautify` automatically when
it is installed, and fall back to `xcodebuild -quiet` otherwise.

`make run` builds the latest debug app and launches it from
`DerivedData/Build/Products/Debug/`. If the app is already running, it asks you
to quit the current menu bar instance first.

`make rerun` quits the current dev instance, rebuilds, and launches the latest
app again.

`make probe-sources` runs a CLI helper that exercises the live upstream data
sources used by the app. Pass extra arguments through the script directly, for
example:
`./scripts/probe-external-sources.sh --country-code ES --latitude 39.4699 --longitude -0.3763`
Set `RELIEFWEB_APPNAME` if you want to override the default ReliefWeb app name
used by the probe.

## Release Workflow

- Keep upcoming release notes under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md)
- Ensure the git working tree is clean before preparing a release
- Use one of:
  `make release-patch`
  `make release-minor`
  `make release-major`
- The release command bumps the app version and build number, updates
  `CHANGELOG.md`, merges curated `Unreleased` notes with categorized commit
  history since the latest tag, creates a `Release vX.Y.Z` commit, and creates
  a `vX.Y.Z` tag
- After that, push the branch and tags, then continue with archive/DMG/update
  publishing

## Development Notes

- The app is a menu bar utility with `LSUIElement=1`, so it should not appear in
  the Dock during normal operation.
- External IP lookups use FreeIPAPI. IP-based location display is enabled by
  default for new installs and can be turned off in Settings. Device location
  and weather access use explicit permission prompts.
- Release automation is local-first. Signing, notarization, DMG packaging, and
  Sparkle publishing are wired through scripts and documented in
  [docs/release.md](docs/release.md).
- Version metadata is centralized in `Config/Version.xcconfig`.

## Open Source Collaboration

- License: Apache-2.0
- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Agent instructions: [AGENTS.md](AGENTS.md)
- Claude instructions: [CLAUDE.md](CLAUDE.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)

## Roadmap

The first milestone is the public bootstrap: a working menu bar shell, live and
sample data pipelines, local persistence, release helpers, and contributor-ready
documentation. See [docs/roadmap.md](docs/roadmap.md) for the staged plan.
