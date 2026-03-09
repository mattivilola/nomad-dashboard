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


## [0.1.12] - 2026-03-09

### Added

- Introduce distinct "Dev" build flavor and improved diagnostics
- Enhance travel alert error diagnostics
- Introduce CLI tool for probing live external data sources
- Introduce compact typography for MetricBlock
- Implement ReliefWeb approved app name configuration
- Introduce time to full charge metric and update ReliefWeb integration
- Introduce near-term precipitation chance metric

### Changed

- Add surf spot configuration and marine data to dashboard
- Merge branch 'main' into staging
- Modernize Swift syntax and streamline developer tooling
- Set Swift version to 6.0 and establish SwiftFormat configuration
- Remove generated Xcode log files
- Simplify DerivedDataValidation .gitignore rules
- Merge branch 'staging'

## [0.1.11] - 2026-03-09

### Changed

- Add MenuBarStatusPresentation model for prioritized display

## [0.1.10] - 2026-03-09

### Changed

- Add location services support for macOS

## [0.1.9] - 2026-03-09

### Changed

- Add support for local release signing overrides

## [0.1.8] - 2026-03-09

### Added

- Enable WeatherKit integration

### Changed

- Merge branch 'staging'

## [0.1.7] - 2026-03-09

### Changed

- Ensure correct signing of Sparkle framework components

## [0.1.6] - 2026-03-09

### Added

- Update branding assets
- Implement automated release and Sparkle update pipeline

### Changed

- Modernize Sparkle update handling and ignore generated build data

## [0.1.5] - 2026-03-06

### Added

- Streamline Dashboard UI and add application quit option
- Centralize window routing and ensure opened windows are focused
- Close current dashboard window when opening a new destination
- Introduce programmatic branding asset generation and a styled DMG
- Display application icon in settings and dashboard
- Enhance DMG installer styling and update branding assets

### Changed

- Prepare app for distribution and streamline build process

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
