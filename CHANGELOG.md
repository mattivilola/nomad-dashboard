# Changelog

All notable changes to Nomad Dashboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- _Nothing yet_

### Changed

- _Nothing yet_

### Fixed

- _Nothing yet_


## [0.1.4] - 2026-03-06

### Added

- Enhance release notes generation by merging and categorizing entries
- Introduce comprehensive travel alerts feature
- Introduce Visited Map for tracking travel history
- Add world map rendering for visited places
- Improve travel alert UI to reflect diverse states

## [0.1.3] - 2026-03-06

### Added

- Added dashboard health summary tiles for overall, network, and power status, including readiness badges directly in the main dashboard cards.
- Added a full settings window for appearance, launch at login, refresh cadence, metric retention, location and weather controls, and support actions.
- Added explicit System, Dark, and Light appearance modes with live theme updates across the menu bar dashboard, Settings, and About windows.

### Changed

- Dashboard actions now open and focus Settings, About, and macOS Network settings more reliably from the menu bar interface.
- Public IP and location lookups now use FreeIPAPI with cached responses, and IP-based location display is enabled by default for new installs.
- Temporarily paused in-app update checks until the signed release and appcast publishing pipeline is in place.

### Fixed

- FreeIPAPI time zone parsing now handles both string and array responses so travel context stays populated.

## [0.1.2] - 2026-03-06

### Added

- Shipped the first native macOS menu bar dashboard for connectivity, public IP and geolocation, weather, VPN visibility, Wi-Fi context, and power telemetry.
- Added About and Settings views, launch-at-login support, persisted app settings, and local metric history built on reusable `NomadCore` and `NomadUI` packages.
- Added local-first project tooling for bootstrap, project generation, build, archive, DMG creation, signing, publishing dry runs, CI, and package tests.

### Changed

- Added `make open`, `make run`, and `make rerun` shortcuts to streamline the daily macOS app workflow.
- Centralized marketing version and build metadata, and automated release preparation so patch, minor, and major releases update the changelog, create a release commit, and tag `vX.Y.Z`.
