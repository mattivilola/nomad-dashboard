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


## [0.11.1] - 2026-04-20

### Changed

- Add make target to simplify notarization profile setup

## [0.11.0] - 2026-04-20

### Changed

- Combine local info row value and badge display
- Add device location to dashboard and show comparison with IP location
- Prepare weather data when local info is enabled and uses device location

## [0.10.0] - 2026-04-09

### Changed

- Introduce detailed travel advisory summaries and source links
- Introduce Local Info feature
- Display busy period badges for local public and school holidays.
- Correct UI test for school break badge display

## [0.9.0] - 2026-04-08

### Changed

- Introduce interruption reporting and focus metrics for time tracking

## [0.8.0] - 2026-04-08

### Changed

- Refine weather forecast expansion migration and expand quick allocate buttons
- Correct weather forecast expansion migration logic
- Introduce local price level and enhance travel advisory fetching

## [0.7.0] - 2026-04-02

### Changed

- Implement standardized styling for time tracking dashboard buttons
- Unify dashboard weather forecast and enhance wind data display

## [0.6.5] - 2026-04-02

### Changed

- Enhance time tracking persistence and recovery with shutdown awareness

## [0.6.4] - 2026-04-02

### Changed

- Implement quick allocation for time tracking entries

## [0.6.3] - 2026-04-01

### Changed

- Refine Sparkle CLI tool discovery and release prerequisites

## [0.6.2] - 2026-04-01

### Changed

- Enhance time tracking header adaptivity with dynamic layout and chrome density
- Enhance time tracking header with dynamic layout and panel adjustments

## [0.6.1] - 2026-04-01

### Changed

- Introduce storage namespaces and improve adaptive time tracking header UI

## [0.6.0] - 2026-03-31

### Changed

- Update marketing, privacy docs, and developer guidelines
- Add project time tracking and dedicated window
- Enhance time tracking quick allocation and pending intervals
- Introduce quick bucket chips for time tracking entry assignments
- Improve time tracking quick action chips for adaptive layout
- Introduce expandable time tracking entries and auto-expand those requiring attention
- Introduce adaptive configurations for time tracking header
- Introduce render state for TimeTrackingWindowView
- Introduce recent projects and improve time tracking quick actions
- Enhance time tracking day list with rich summary cards and visual insights
- Enhance time tracking quick action adaptivity and dashboard panel layout

## [0.5.0] - 2026-03-30

### Changed

- Add country-day history tracking and visualization.

## [0.4.1] - 2026-03-27

### Changed

- Add repository search hint for debug screenshot artifacts
- Extract summary tile presentation logic into dedicated model

## [0.4.0] - 2026-03-24

### Changed

- Automatically expand emergency care search radius
- Improve emergency care radius search resilience
- Add broader text search fallback for emergency care
- Add marketing documentation
- Add debug command to save window screenshots
- Refine emergency care search results with improved filtering and deduplication

## [0.3.0] - 2026-03-23

### Changed

- Add hourly and multi-day weather forecast models and display settings
- Add expandable hourly and multi-day weather forecasts to dashboard
- Add Emergency Care dashboard feature with map previews

## [0.2.0] - 2026-03-20

### Changed

- Introduce `StatusSymbolView` to standardize status icon styling
- Apply app-selected appearance to content while preserving system window chrome
- Add self-documenting help target to Makefile

## [0.1.22] - 2026-03-16

### Changed

- Add background activity tracking for usage estimation

## [0.1.21] - 2026-03-16

### Changed

- Introduce internet connectivity monitoring and status UI
- Add visual feedback for dashboard refresh activity
- Update marine forecast to provide a 24-hour outlook
- Integrate TelemetryDeck for anonymous usage analytics

## [0.1.20] - 2026-03-11

### Changed

- Refine Tankerkonig API key check in release script

## [0.1.19] - 2026-03-11

### Changed

- Remove AppKit-specific window appearance management
- Move Tankerkonig API key to user settings and remove from app bundle

## [0.1.18] - 2026-03-10

### Changed

- Refine dashboard layout for compact display
- Refine compact display for dashboard metrics and fuel rows

## [0.1.17] - 2026-03-10

### Changed

- Add dashboard card reordering and persistence
- Optimize dashboard data refreshes and UI animations
- Add dashboard card width customization and persistence
- Refine BadgeView for compact display and streamline FuelPriceRow
- Remove network throughput, power trend charts, and marine forecast from dashboard.

## [0.1.16] - 2026-03-10

### Changed

- Add detailed fuel price fetch diagnostics
- Add fuel station map preview and Google Maps integration
- Refine Swift Concurrency `Sendable` conformance and travel alert severity types. Improve conditional display of fuel price map actions.

## [0.1.15] - 2026-03-09

### Changed

- Remove explicit provisioning updates option for debug builds
- Merge branch 'main' into staging
- Add location fuel price card
- Add dynamic background to Fuel Prices dashboard card
- Enable automatic provisioning updates and fallback for signed debug builds
- Add fuel price probing to NomadSourceProbe

## [0.1.14] - 2026-03-09

### Changed

- Merge branch 'main' into staging
- Automate pushing of release tags and branches to origin
- help to fix these CI github errors (vibe-kanban MAT-1)
- Merge branch 'staging'
- fix the icon color - use the system theme as toolbar is system based and not light/dark theme (vibe-kanban MAT-2)
- power dashboard drain is always estimating.. how to fix? (vibe-kanban MAT-3)
- Fallback to unsigned local debug builds
- help to fix dev build/rerun script (vibe-kanban MAT-4)
- Relax HOME directory isolation for local signed dev builds

## [0.1.13] - 2026-03-09

### Changed

- Add release preflight to verify remote tag

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
