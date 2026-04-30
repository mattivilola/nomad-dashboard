# Nomad Dashboard Feature Inventory

This document is the factual product inventory for website generation, product communication, and feature summaries.

Use it to describe what Nomad Dashboard currently does, who each capability helps, and what caveats or dependencies apply.

## Product-Level Summary

Nomad Dashboard is a native macOS menu bar app that aggregates travel-relevant and work-relevant signals into one compact dashboard. Its current shipped scope covers connectivity, power, travel context, weather, local project time tracking, and several optional travel-aware modules including local price-level context.

## Connectivity And Internet Readiness

### What it does

- Shows internet reachability state
- Monitors passive download and upload throughput
- Runs periodic latency and jitter checks
- Shows Wi-Fi context such as interface, SSID, signal, noise, and transmit rate when available
- Detects VPN activity

### Who it helps

- remote workers on unstable hotel, apartment, airport, or coworking Wi-Fi
- developers who care about latency and network quality
- travelers who need a fast go/no-go signal before calls or uploads

### Practical benefit

Users can quickly judge whether their current connection is workable without opening multiple system panels or network tools.

### Dependencies or setup

- no special user setup for basic connectivity monitoring
- Wi-Fi and VPN context depend on what macOS exposes at the time

### Limitations

- this is a compact operational view, not a full packet-analysis or deep diagnostics tool
- captive portal and flaky network heuristics are roadmap items, not current core claims

## Power And Battery Context

### What it does

- Shows battery charge percentage
- Shows charging state
- Shows time remaining or time to full charge when available
- Shows low power mode state
- Shows discharge rate and adapter wattage when available

### Who it helps

- people working away from fixed desks
- travelers managing battery life during transit days
- remote workers deciding whether current power conditions are safe for longer sessions

### Practical benefit

Users can see whether the MacBook is draining normally, charging properly, or likely to need attention soon.

### Dependencies or setup

- no special setup beyond normal macOS power telemetry availability

### Limitations

- some power readings depend on what the system can report at that moment

## Travel Context And IP/Location Awareness

### What it does

- Shows public IP address
- Can show IP-based city, region, country, and time zone context
- Shows device and IP-based location side by side in the dashboard header when both are available
- Helps compare network-detected location with expected location
- Uses current country context to support travel-oriented features where available

### Who it helps

- digital nomads moving between countries and time zones
- users who rely on regional access, VPN checks, or quick location sanity checks

### Practical benefit

Users can understand how the outside network sees them and keep better awareness of time zone and place while moving around.

### Dependencies or setup

- external IP location can be disabled in Settings
- IP geolocation uses an external provider

### Limitations

- IP-based location is approximate and may not match the user’s physical location exactly

## Weather And Forecast

### What it does

- Shows current weather conditions
- Shows current, apparent, wind, and rain-chance key metrics
- Shows wind speed with compass direction
- Shows a unified forecast view with near-term checkpoints and a 7-day outlook
- Shows tomorrow summary when the full forecast is collapsed

### Who it helps

- travelers planning movement through a city or region
- remote workers deciding where and when to work
- users who want local conditions without leaving the dashboard

### Practical benefit

Users can make quick practical decisions about wind, rain risk, the next few hours, and the next day without opening a separate weather app.

### Dependencies or setup

- weather uses device location when enabled
- WeatherKit access depends on a properly signed build with the required capability

### Limitations

- in unsupported or unsigned builds, WeatherKit-backed weather may be unavailable

## Travel Alerts

### What it does

- Aggregates optional travel-oriented alert signals into one condensed card
- Supports travel advisory, weather alerts, and regional security context
- Uses the live Smartraveller destinations page first, falls back to `destinations-export`, and can retry through a hidden WebKit fetch when direct transport stalls
- Keeps Smartraveller severity sourced from the destination list, then optionally fetches the matched destination page for a short reason sentence and a `More details` link
- Keeps the dashboard compact by summarizing status rather than becoming a full alert center

### Who it helps

- travelers who want lightweight awareness of destination or surrounding-region conditions
- users who prefer a quick summary rather than opening several source sites

### Practical benefit

Users can notice higher-level advisory or environmental signals without doing a manual information sweep every time they move.

### Dependencies or setup

- travel advisory is enabled by default
- weather alerts are optional
- regional security is optional
- some alert types depend on current country or device location context

### Limitations

- this is a compact summary layer, not a full travel risk management product
- source coverage and freshness depend on upstream providers

## Local Info

### What it does

- Can show a compact local info card for travelers
- Shows current local city, region, country, and holiday context when location or external IP location is available
- Shows next public holiday with free public data
- Shows school holiday context only when a confident local or regional match is available
- Reuses official country-level Eurostat price indices for European meal-out, groceries, and overall local cost context
- Can show a US 1-bedroom rent benchmark from HUD USER when the user adds a HUD API token
- Keeps source attribution visible for holidays and price signals

### Who it helps

- frequent travelers who want quick regional context without opening separate calendar or travel tools
- digital nomads deciding whether a stop feels cheap, medium, or expensive
- longer-stay travelers who want a rough rent anchor plus a quick holiday sanity check without leaving the dashboard

### Practical benefit

Users can get a quick sense of local holiday timing, place context, and price pressure without opening separate travel, calendar, cost-of-living, or housing tools.

### Dependencies or setup

- public holiday context works from resolved country context
- school holiday context depends on confident regional matching and upstream coverage
- Europe price-level signals work from location context and official Eurostat data
- US 1-bedroom rent requires a user-supplied HUD USER API token
- US rent benchmarks use current location to resolve the county through the US Census Geocoder

### Region Or Build Limitations

- school holiday coverage is best-effort and varies by country and subdivision support
- public holiday freshness and regional precision depend on upstream providers
- Europe currently uses country-level fallback data, not city-level venue prices
- US v1 currently focuses on the HUD 1-bedroom rent benchmark rather than a full meal-and-groceries set
- countries outside Europe and the United States are not supported in v1

## Nearby Fuel Prices

### What it does

- Can show nearby fuel price information
- Supports station rows and map preview behavior
- Can open selected stations in Google Maps
- Includes diagnostics in Settings for troubleshooting

### Who it helps

- road-tripping remote workers
- vanlife or car-based travelers
- users comparing local driving costs while moving between places

### Practical benefit

Users can spot nearby fuel context without switching from the dashboard into separate search flows.

### Dependencies or setup

- requires current location access
- country support varies
- Germany requires a user-supplied Tankerkonig API key

### Region Or Build Limitations

- fuel support is currently best in Spain, France, Italy, and Germany
- Germany support depends on the user adding their own API key in Settings

## Nearby Emergency Hospitals

### What it does

- Can show nearby emergency hospitals
- Supports preview maps inside the app
- Can open selected hospitals in Google Maps

### Who it helps

- travelers wanting nearby emergency-care context in unfamiliar places
- users who want a practical safety-oriented reference close at hand

### Practical benefit

Users can quickly identify nearby emergency hospital options without running a separate maps search from scratch.

### Dependencies or setup

- requires current location access
- depends on Apple Maps hospital points of interest

### Limitations

- this is a nearby-reference feature, not medical advice, triage, or guaranteed facility availability

## Surf Spot Forecast

### What it does

- Lets the user configure a surf spot
- Shows marine conditions for that saved spot
- Uses a dedicated surf spot instead of only the user’s current position

### Who it helps

- surfers and coastal travelers
- users with one recurring destination they want to keep an eye on

### Practical benefit

Users can monitor one chosen surf location directly from the dashboard without maintaining a separate dedicated surf app for quick checks.

### Dependencies or setup

- requires the user to configure a surf spot name and coordinates
- uses Open-Meteo for marine data

### Limitations

- current scope is one configured surf spot, not a multi-spot tracker

## Visited Places And Travel History

### What it does

- Can save visited places locally on the Mac
- Tracks visited cities and countries when enough context is available
- Includes a visited map window for viewing travel history
- Shows a yearly travel path with ordered stops when chronological visited-place events are available
- Includes a local travel log that groups city-level movement by year
- Builds a country-by-day local diary with yearly and monthly breakdowns
- Can export the selected year summary, including monthly totals, as plain text via the clipboard

### Who it helps

- digital nomads and long-term travelers who want a lightweight record of movement
- users who like place memory without adopting a heavy trip-management system

### Practical benefit

Users can build a simple local travel history over time, revisit where they have been, follow their route by year, and understand how time was split across countries by year and month.

### Dependencies or setup

- feature can be turned on or off in Settings
- visited place detection prefers device location and uses public IP geolocation only when device location cannot be resolved
- yearly travel paths depend on chronological visited-place events captured after the feature is enabled
- yearly and monthly country-day summaries depend on saved local travel history accumulating over time

### Limitations

- data stays local to the Mac unless the user moves it themselves
- this is not a multi-device synced travel journal
- country-day gaps are estimated from the surrounding known countries when the app has missing days between captures

## Project Time Tracking

### What it does

- Can track awake working time locally while Nomad Dashboard is running
- Lets the user define project buckets in Settings plus one built-in `Other` bucket
- Shows live pending unallocated time directly in the dashboard header
- Lets the user report interruptions from the dashboard or the full time-tracking window with an interruption count that resets per day
- Surfaces compact quick-action chips for recent or active projects plus `Other`
- Supports quick one-click allocation of today’s pending time into a project or `Other` without opening the full time-tracking view
- Includes a dedicated time-tracking window with day, week, and month views
- Attributes interruption events to the project or bucket that covered that moment once the time is allocated
- Estimates focus lost from interruptions at 23 minutes each and shows focus-adjusted time in summaries and exports
- Highlights the busiest days in week and month views and flags days that still have unallocated time for review
- Supports exact-entry editing for reassignment, resizing, and splitting
- Can export the selected month summary with weekly and daily breakdowns as plain text via the clipboard

### Who it helps

- freelancers, consultants, and agency operators who need a lightweight local work log
- remote workers who want fast project allocation without adopting a heavier full invoicing or PM suite

### Practical benefit

Users can capture and assign work time with less friction by using the dashboard’s quick chips for the common cases, then fix history later when needed and export a clean monthly text summary quickly.

### Dependencies or setup

- feature must be enabled in Settings
- project buckets are user-defined and stored locally on the Mac
- tracking counts only while the Mac is awake and Nomad Dashboard is running
- non-production builds keep their own local time-tracking storage instead of sharing the live app’s storage

### Limitations

- data stays local to the Mac unless the user copies or moves it themselves
- this is not a timesheet approval, invoicing, or multi-device sync system
- exact time is stored; quarter-hour rounding is not applied in the current version

## Settings, Layout Customization, Updates, And Launch At Login

### What it does

- Supports launch at login
- Supports appearance settings
- Supports configurable refresh cadence and history retention
- Supports dashboard card reordering
- Supports dashboard card width customization
- Supports settings for weather, travel modules, analytics, and location-aware features
- Supports direct-distribution update plumbing with Sparkle in release builds

### Who it helps

- users who want the app to fit their own workflow and tolerance for dashboard density
- users who prefer direct-download software that can still check for updates

### Practical benefit

Users can shape the dashboard around their needs instead of accepting a rigid one-size-fits-all layout.

### Dependencies or setup

- in-app updates depend on signed release builds with Sparkle metadata
- some module settings only matter when the related feature is enabled

### Limitations

- local and debug builds may not expose the same update behavior as signed public releases

## Availability And Caveats

- Some features require location permission.
- Weather relies on WeatherKit and needs proper signed release capability to work in release-quality builds.
- Nearby fuel prices are region-dependent, and Germany requires the user to provide a Tankerkonig API key.
- Some travel alerts are optional and disabled by default.
- Project time tracking is local-only and requires the user to enable it.
- External IP geolocation is approximate.
- Upstream data freshness and availability depend on external providers.
- The app is free to download and use.
- The app is provided as-is, with no guarantee, SLA, or promise of fitness for any specific use.

## Safe Website Claim Set

These are safe high-level claims for the landing page:

- native macOS menu bar app
- built for digital nomads, remote workers, and traveling developers
- connection, power, weather, and travel context in one place
- optional travel-aware tools plus local project time tracking, surf spot forecast, and visited places
- free and open source
- direct download outside the Mac App Store
- provided as-is

These are not safe as headline claims without qualification:

- works fully offline
- zero analytics
- all countries supported equally
- App Store app
- mission-critical monitoring
- guaranteed travel safety guidance
