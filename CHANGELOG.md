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


## [0.20.1] - 2026-10-13

### Changed

- Make DashboardSnapshotStoreTests deterministic

## [0.20.0] - 2026-10-13

### Added

- Add a departure checklist, "Before you leave", to the Trip Planner preview: suggested items grouped as Plan ahead, Money & power, Documents and On arrival (roaming, consular line and emergency numbers, plug adapter, local currency, driving side, travel registration, visa and Schengen checks, local periods, and public holidays and the advisory once they load), with checkboxes, a progress bar, Open buttons for official pages and up to 30 items of your own. The trip list shows the progress ("3/9"), in sand only when the trip starts within three days with items left. Ticks stay on the Mac with the trip.
- Add a map of the destination to the Trip Planner preview with your embassy or consulate locations: a marker for a precise location, an area with a label for a city-centre one, and a tap opens Apple Maps with the same search as the Your Embassy card; an Open in Maps button searches for the destination. Offline it says "Map needs a connection".
- Add a jet-lag nudge: after a time zone shift of three hours or more a "Jet lag: day 2 of about 5" heads-up with light-timing guidance (menu bar, overview, Siri and Shortcuts, Glance widget) and a row in the arrival briefing. The last 10 time zone changes are kept locally in `time-zone-shifts.json` and cleared with the visited places.

### Changed

- The Mac's time zone is re-read when it changes (travel, Date & Time settings), so a new zone registers without restarting the app.
- Add departure checklist, jet-lag and country map models
- Add the departure checklist, jet-lag nudge and trip map UI

### Fixed

- Editing a planned trip no longer loses its checklist ticks and own items.

## [0.19.0] - 2026-10-13

### Added

- Add a Trip Planner window (header menu, `Plan a trip` on the overview, or the new `Trip Planner` button on the Stays & Visas card): plan up to 20 trips and see, for the selected one, the time difference from home, emergency numbers, your embassy and consular line with links, driving side, plugs and currency (with a `Changed` chip where they differ from where you are), local periods such as Ramadan that overlap the trip, public holidays and the travel advisory (loaded after the preview, only the destination country code is sent), a price comparison with home, and a visa what-if for the Schengen 90/180 count, your stay allowance and the tax-residence days. Trips and the home country stay on the Mac.
- Add a `Next trip` line to the Stays & Visas card, in coral with the date when the plan would break the Schengen limit, and an upcoming-trip heads-up in the 14 days before a trip starts.
- Add a `Home country` setting under General, Home (defaults to your first citizenship) and a price comparison with home on the Local Info card ("Groceries ~30% cheaper than Finland", with the caption "Compared with Finland (your home)").
- Add the `Next Trip` Siri and Shortcuts action ("When is my next trip in Nomad Dashboard").

### Changed

- Cover 36 European countries for Eurostat price levels: the EU27 plus Albania, Bosnia and Herzegovina, Switzerland, Iceland, Montenegro, North Macedonia, Norway, Serbia and Türkiye, and the United Kingdom for the overall level only.
- Add trip planner and prices-vs-home model layers
- Add the Trip Planner window, home country and prices vs home

## [0.18.0] - 2026-10-12

### Added

- Add Siri and Shortcuts actions (App Intents) that run without opening a window: `Emergency Number`, `Dashboard Status`, `Nearest Embassy`, `Daylight` and `Set Travel Profile`, with phrases such as "What's the emergency number in Nomad Dashboard". Answers are short sentences built on the Mac from the dashboard, the bundled emergency numbers and embassy data, and your location, and the Status action measures network quality when you ask even while the dashboard is closed.
- Add desktop and Notification Center widgets: `Glance` (small and medium: verdict, place and top heads-up), `Safety` (emergency number and your consular line) and `Daylight` (sunset and daylight left, or when it gets light again). Each shows when it was last updated and marks itself out of date after six hours; a tap brings the app forward. The app shares a small snapshot (no IP address, coordinates or citizenship codes) with the widgets through an App Group on your Mac.
- Add the Stays & Visas card: the days of your current stay, an optional visa allowance per country with the date to leave by, the Schengen 90/180 counter (no limit shown for EU, EEA and Swiss citizens), and this year's days per country against a tax-residence threshold with a Review days button for the Visited Map. It is computed on the Mac from your saved visited days, turns sand and coral as limits near, and adds heads-up items and optional menu bar text. Settings, Stays & Visas sets the allowances, the threshold and the switches.
- Add an arrival briefing at the top of the overview when you arrive in a new country: local time and the difference from home, emergency numbers, your embassy and consular line, driving side, plugs and voltage, currency, a public holiday, a travel advisory, a Data Guard prompt and local rhythm, with `Got it` to dismiss it and `Show Arrival Briefing` in the header menu to open it again. It can be switched off under Safety.
- Add UV index (with today's peak) and air quality (European AQI with a 12-hour outlook, from Open-Meteo, only a location rounded to about 11 km is sent) to the Weather card, with heads-up items for high UV and poor air quality, an air quality line in Offline essentials, and an `Air quality` switch in Settings.
- Add a Local rhythm section to the Local Info card, and a heads-up item, for periods such as Ramadan, Lunar New Year, Holy Week, Songkran, Golden Week, Nyepi and Diwali, with their dates and what to expect.

### Changed

- Show `Stays & Visas` as a new page in Settings after Safety, and add an `Arrival briefing` group under Safety and an `Air quality` switch under Weather & Local.
- Add model layers for stays, arrival briefing, local rhythm, UV and air quality
- Add Siri and Shortcuts actions and desktop widgets
- Add Stays & Visas, arrival briefing, air quality and local rhythm UI
- Merge branch 'feature/intents-widgets' into feature/stays-arrival
- Feed stays into Siri and widgets, unify country names, add screenshot library
- Merge branch 'main' into feature/stays-arrival

## [0.17.2] - 2026-10-12

### Added

- Add a daylight heads-up for the Road trip & RV profile: within two hours of sunset it shows the sunset time, the daylight left, and when civil twilight ends (a caution in the last hour), and once it is dark it shows when the sun rises. It can also appear in the menu bar, ranks right after strong wind, and is calculated on the Mac from your location with no network request.
- Add today's sunrise and sunset to the Weather card in every profile (also when weather is unavailable), in the local time zone, with `Midnight sun` and `Polar night` near the poles.
- Emergency numbers now include the rural or highway police where a country advertises a separate short number: Guardia Civil 062 (Spain), Federal Highway Police 191 (Brazil) and Highway Police 1193 (Thailand), alongside Morocco's Gendarmerie.

### Changed

- Add a daylight heads-up and rural police emergency numbers

## [0.17.1] - 2026-10-12

### Added

- Add travel profiles (Nomad, Road trip & RV) in Settings and the dashboard header menu: a profile sets the recommended card order and ranks the glance heads-up items for road trips; a customized card order is kept, and Settings offers `Use recommended order`.
- Add `Show the top heads-up in the menu bar` (off by default): caution and attention items replace the temperature in the menu bar.
- Show the local emergency numbers at the top of Offline essentials.
- Add the Your Embassy card (turned off until you choose a citizenship): your foreign ministry's consular emergency line with a copy button, your own country's nearest embassies and consulates with distance and Apple Maps, website and address actions, EU consular protection or Nordic cooperation missions when your country has none listed, and links to your ministry's trip registration and list of missions. It collapses to one line, shows one line when you are home, and works offline from data bundled with the app.
- Add `Citizenship` under Settings, General (up to three countries, stored only on this Mac) and a `Your embassy` group under Safety that explains the data sources.
- Show your nearest own embassy and your ministry's consular line in Offline essentials, under the local emergency numbers.

### Changed

- Reorganize Settings into a sidebar of pages (General, Weather & Local, Safety, Connection & Data, Work, Privacy & Location, Advanced) with grouped forms. Every setting and action is kept; the Nomad Preferences window is folded in (home time zone under General, quiet connection alerts under Connection & Data, workplace diary under Work), the menu bar toggles are under General, `Use location to read Wi‑Fi names` and `Open Visited Map` are under Privacy & Location, and the long Privacy & Location paragraph is split into short notes next to the settings they describe.
- The dashboard clock's preferences button opens Settings on the home time zone, the setup buttons on Data Guard, Time Tracking, Local Info, Fuel Prices and Emergency Care cards and the "Turned off" row open Settings on the matching group, the Visited Map's Open Settings buttons open the visited places setting, and Settings remembers the last page you viewed while the app is running.
- `Reset Dashboard Layout` restores the card order recommended for the selected travel profile.
- Offline essentials format temperatures and fuel prices like the dashboard cards.
- Existing dashboards get the Your Embassy card right after Emergency Care (or after the nearest earlier default card present in a customized order), and a card order you never customized stays the recommended order.
- Fix the General settings note that still described the appearance toggle as a dashboard header button; it now lives in the header menu.
- Add travel profiles with road-trip ranking and a menu bar heads-up
- Reorganize Settings into sidebar pages grouped for travellers
- Add bundled diplomatic mission and consular contact directories
- Merge branch 'feature/settings-reorg' into feature/embassies
- Add the Your Embassy card with citizenship settings

## [0.17.0] - 2026-10-12

### Added

- Add Morocco emergency numbers (police 19, ambulance/fire 15, Gendarmerie 177).
- Add a collapse chevron to every dashboard card: a collapsed card is one line with a summary and status badge, stays collapsed across relaunches, and expands when a glance tile or heads-up row points at it.
- Add a glance overview at the top of the dashboard: a verdict strip, a single line of Here and Home clocks, four tappable vital tiles (Internet, Power, Data Guard or VPN, Weather) that scroll to their cards, and up to three ranked heads-up items (data cap, travel advisory, weather alert, regional security, strong wind, rain within six hours, public holiday within three days, cheapest nearby fuel).
- Add Customize Layout to the header menu; card width and drag controls now appear only while customizing.

### Changed

- Redesign the dashboard cards to be as compact as their content: sparklines replace the tall trend charts, Connectivity shows Down, Up, and Latency in one row, Power shows its history under Battery and Drain, and duplicate captions are gone.
- Condense Travel Context to public IP, Wi-Fi (name, signal, and rate), VPN, and location with the time zone.
- Travel Alerts keeps the highest alert level in its badge and reports stale data in a separate "may be outdated" note; each signal names its level once.
- Fuel and Emergency Care rows open the map preview when clicked and move Google Maps into a trailing menu; fuel prices and hospital ownership no longer use category colors, and the fuel backdrop is subtler.
- Time Tracking shows today, focus, and pending time with an allocation bar and legend, and a single interruption control.
- Local Info leads with the answer: holiday date and countdown, school break dates, and one "Prices vs EU" row, with the location in the card subtitle.
- Weather shows current conditions on one line with compact stats, always shows the hourly strip, and folds only the 7-day outlook; surf conditions fit one row with equal single-line forecast columns.
- Use one inline button style for every in-card action.
- Data Guard leads with what is left and a status-tinted bar, shows cap, reset date, and pace, explains why it is monitoring, and moves Remember, Forget, and Reset into a menu; the manual toggle is now labeled "Monitor manually".
- Cards whose feature is off are no longer rendered; one "Turned off" row names them with a Settings button. Customize Layout still shows every card.
- Fuel prices use the locale's currency format ("1,429 €/L").
- The fuel backdrop fades out behind station rows.
- Show the emergency number of the current country on the Emergency Care and Local Info cards (offline, selectable).
- "Prices vs EU" uses the numeric difference from the EU average ("≈ EU" within one percent).
- A narrow card without a narrow neighbour now renders full width with the wide layout instead of leaving a gap; paired half-width cards share the taller height.
- Lead the dashboard header with the current place and show device region and country beside the IP location on one line, instead of the app title.
- Move the appearance toggle into the header menu.
- Replace the time-tracking chip row with a single compact row and an Allocate menu that lists project names in full.
- Color metric values by status instead of by metric name, so healthy values no longer render in alarm colors.
- The power card shows adapter wattage while on external power, time to full while charging, and no longer repeats its subtitle.
- Show the device city for "Here" in the clocks instead of the time-zone city.
- Lead the dashboard with a glance overview and ranked heads-up items
- Compact dashboard cards with collapsible summaries and safety fixes
- Add Morocco emergency numbers with the rural Gendarmerie

### Fixed

- Fix half-width card titles and subtitles truncating because of always-visible card controls.

## [0.16.0] - 2026-09-22

### Changed

- Add Data Guard for metered network usage tracking with caps

## [0.15.1] - 2026-09-17

### Changed

- Make Nomads.com attribution prominent throughout Explore Cities and the dashboard, with direct source links beside city data and a Join Nomads.com action.
- Make Nomads.com attribution prominent and link to source cities

### Fixed

- Use the city-page link returned by refreshed Nomads.com details when it is missing from search results.

## [0.15.0] - 2026-09-13

### Changed

- Add city exploration and current city matching

## [0.14.2] - 2026-09-07

### Added

- See connection readiness, VPN, battery, and home/current clocks together at the top of the dashboard.
- Automatically retain enabled travel cards for offline use, with saved timestamps and an offline indicator.
- Choose Auto, Normal, or Low Data mode to control background network work.
- Keep a local workplace connection diary with stationary device-location visits, suggested nearby venues, private notes, and Google Maps links.
- Correct individual country days or date ranges, restore original observations, and export a versioned CSV.
- Enable silent contextual alerts for sustained connection, VPN, and charging changes, with quiet hours and cooldowns.

### Changed

- Publish local readings and completed cards independently, retain useful saved content during refresh, and offer individual card retries.
- Reuse fresh data when opening the menu and cache national fuel datasets across nearby searches.
- Buffer metric history writes, save compact time-tracking recovery heartbeats, and pause hidden time-tracking display ticks.
- Reuse unchanged visited-map content and reduce decorative animation under resource pressure.
- Make asynchronous URL protocol test capture explicit
- Read notification authorization through a Sendable value
- Await diary loading and finalize release validation notes
- Keep all notification center operations on their owning actor
- Preserve unreadable workplace diaries during shutdown

### Fixed

- Preserve an unreadable workplace diary and pause collection until it can be reopened.
- Keep venue lookup and notification permissions compatible with older supported macOS SDKs.
- Cancel obsolete refreshes and prevent late provider results from replacing newer location data.
- Bound provider waits and retry frequency so unavailable sources do not hold up the dashboard.
- Flush pending local diary and metric data before quitting.

## [0.14.1] - 2026-09-07

Unpublished release candidate.

### Added

- See connection readiness, VPN, battery, and home/current clocks together at the top of the dashboard.
- Automatically retain enabled travel cards for offline use, with saved timestamps and an offline indicator.
- Choose Auto, Normal, or Low Data mode to control background network work.
- Keep a local workplace connection diary with stationary device-location visits, suggested nearby venues, private notes, and Google Maps links.
- Correct individual country days or date ranges, restore original observations, and export a versioned CSV.
- Enable silent contextual alerts for sustained connection, VPN, and charging changes, with quiet hours and cooldowns.

### Changed

- Publish local readings and completed cards independently, retain useful saved content during refresh, and offer individual card retries.
- Reuse fresh data when opening the menu and cache national fuel datasets across nearby searches.
- Buffer metric history writes, save compact time-tracking recovery heartbeats, and pause hidden time-tracking display ticks.
- Reuse unchanged visited-map content and reduce decorative animation under resource pressure.
- Keep MapKit responses within their callback context

### Fixed

- Support venue lookup on the older macOS SDK used by CI.
- Cancel obsolete refreshes and prevent late provider results from replacing newer location data.
- Bound provider waits and retry frequency so unavailable sources do not hold up the dashboard.
- Flush pending local diary and metric data before quitting.

## [0.14.0] - 2026-09-07

Unpublished release candidate.

### Added

- See connection readiness, VPN, battery, and home/current clocks together at the top of the dashboard.
- Automatically retain enabled travel cards for offline use, with saved timestamps and an offline indicator.
- Choose Auto, Normal, or Low Data mode to control background network work.
- Keep a local workplace connection diary with stationary device-location visits, suggested nearby venues, private notes, and Google Maps links.
- Correct individual country days or date ranges, restore original observations, and export a versioned CSV.
- Enable silent contextual alerts for sustained connection, VPN, and charging changes, with quiet hours and cooldowns.

### Changed

- Publish local readings and completed cards independently, retain useful saved content during refresh, and offer individual card retries.
- Reuse fresh data when opening the menu and cache national fuel datasets across nearby searches.
- Buffer metric history writes, save compact time-tracking recovery heartbeats, and pause hidden time-tracking display ticks.
- Reuse unchanged visited-map content and reduce decorative animation under resource pressure.
- Merge branch 'staging'
- Instantiate `CLGeocoder` locally for each reverse geocoding request
- Improve dashboard responsiveness and add offline nomad tools
- Merge validated nomad tools from staging

### Fixed

- Cancel obsolete refreshes and prevent late provider results from replacing newer location data.
- Bound provider waits and retry frequency so unavailable sources do not hold up the dashboard.
- Flush pending local diary and metric data before quitting.

## [0.13.0] - 2026-05-18

### Changed

- Reduce idle battery impact by using slower default refresh intervals, enforcing safer persisted refresh bounds, and throttling hidden menu-bar background refreshes.
- Optimize battery life with adaptive background refreshes and time tracking

### Fixed

- Stop the project time-tracking ticker and heartbeat from running while time tracking is disabled.

## [0.12.2] - 2026-05-08

### Changed

- Enable daily-scoped editing for time tracking entries

## [0.12.1] - 2026-05-07

### Changed

- Refine handling of time tracking entries that span day boundaries. Entries are now accurately clipped for display and can be split for allocation to specific days.

## [0.12.0] - 2026-04-30

### Changed

- Add chronological travel path map and log
- Refine travel path event merging and map rendering

## [0.11.2] - 2026-04-20

### Changed

- Add `make release-check-setup` target to verify local release prerequisites

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
