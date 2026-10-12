# Nomad Dashboard Feature Inventory

This document is the factual product inventory for website generation, product communication, and feature summaries.

Use it to describe what Nomad Dashboard currently does, who each capability helps, and what caveats or dependencies apply.

## Product-Level Summary

Nomad Dashboard is a native macOS menu bar app that aggregates travel-relevant and work-relevant signals into one compact dashboard. Its current shipped scope covers connectivity, power, travel context, weather, local project time tracking, and several optional travel-aware modules including local price-level context and a Your Embassy card with the consular line and nearest embassy for your citizenship. Siri and Shortcuts actions and desktop widgets bring the emergency number, verdict, embassy line and daylight outside the menu bar.

## Connectivity And Internet Readiness

### What it does

- Shows internet reachability state
- Monitors passive download and upload throughput
- Runs periodic latency and jitter checks
- Shows download, upload, and latency side by side, each with a compact sparkline (hover for the time span and min/max) that shows a dashed baseline until enough history exists
- Shows Wi-Fi context such as interface, SSID, signal, noise, and transmit rate when available (name, signal strength, and rate share one Travel Context row; noise and the full signal detail appear on hover)
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

## Data Guard (Metered Hotspot Tracking)

### What it does

- Tracks cumulative download and upload on the Mac's default-route network interface during metered sessions
- Remembers Wi-Fi networks you mark as metered and can auto-start monitoring on expensive or constrained paths
- Supports default and per-network data caps with quiet alerts at 80%, 95%, and 100%
- Pauses Nomad's own large background downloads when a cap is reached
- Can show compact used/cap usage in the menu bar while monitoring
- Leads the card with what is left ("1.0 GB left", tinted by cap status) above a status-tinted progress bar, then the cap, reset date, and an estimate of how many days the remainder lasts at the current pace (parts that are unknown are left out)
- Says why it is monitoring (remembered metered network, turned on manually, or not monitoring) and keeps Remember, Forget, and Reset in a small actions menu

### Who it helps

- travelers on iPhone hotspots, travel routers, or capped mobile data plans
- anyone who wants warning before Nomad or the system burns through a limited allowance

### Practical benefit

You see how much data this connection has used, get warned before overage, and Nomad stops adding optional download load at the limit.

### Dependencies or setup

- enable Data Guard in Settings (on by default for new installs)
- optional: mark a Wi-Fi network as metered or toggle **Monitor manually** on the Data Guard card
- allow location access when prompted so macOS can expose the Wi‑Fi name (SSID) for each hotspot separately

### Limitations

- measures system traffic on the default-route interface, not per-app breakdown
- VPNs may shift which interface is measured
- does not block iCloud, OS updates, or other apps (unlike dedicated firewall tools)

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

## Glance Overview

### What it does

- Opens with one verdict strip (`Ready to work`, `Workable`, `Needs attention`, `Checking conditions`, or `You're offline`) driven by the same network and power health checks used elsewhere in the dashboard
- Keeps the Auto, Normal, and Low Data control on the verdict strip
- Shows four vital tiles: Internet (latency, throughput, network name), Power (charge and time left or time to full), Data Guard usage against its cap (or VPN status when Data Guard is off), and Weather (current temperature and condition with today's low and high; imminent rain and strong wind are reported by the heads-up items instead)
- Colors tile values by status (teal good, sand caution, coral attention) instead of by metric type
- Tapping a tile scrolls the dashboard to the related card
- Lists at most three ranked heads-up items below the tiles when something needs attention: a data cap nearing or reaching its limit, a travel advisory, weather alert, or regional security signal, strong wind, rain within six hours, a public holiday within three days, and cheapest nearby fuel
- Adds a daylight heads-up on the Road trip & RV profile, so you can finish driving before dark: within two hours of sunset it shows the sunset time and the daylight left (a caution in the last hour) with when civil twilight ends, and once it is properly dark it shows when the sun rises again; nothing is shown at midday or in polar day and polar night
- Tapping a heads-up item jumps to the card that explains it; the list disappears when there is nothing to flag
- Puts Workplaces, Saved essentials, and Explore cities in a single row of links
- Offline essentials (Saved essentials) lead with the local emergency numbers for the current country, bundled with the app so they are available without a connection, followed by the saved weather, fuel, hospital, and alert summaries
- Offline essentials format temperatures and fuel prices the same way as the dashboard cards

### Who it helps

- travelers who want to know in a second whether the connection, battery, data allowance, and weather are workable
- remote workers who need the few things that changed, not a wall of metrics

### Limitations

- heads-up items are derived from data already shown in the cards; sources that are unavailable or stale are not reported
- the tiles show what Nomad Dashboard can measure at that moment, and Data Guard figures only count while it is monitoring the connection

## Travel Profile

### What it does

- Offers two profiles in Settings (General page) and in the dashboard header menu under `Travel Profile`: **Nomad** and **Road trip & RV**
- Nomad puts connection quality, work time, and city context first; Road trip & RV puts weather, fuel, emergency care, power, and the data allowance first
- Switching profile reorders the dashboard cards to that profile's recommended order, but only if the card order has not been customized; a custom order is kept, and Settings offers `Use recommended order` to restore the profile's own order in one click
- Ranks the glance overview's heads-up items by profile (for example fuel and weather ahead of work-related items on a road trip)
- Adds the daylight heads-up (sunset countdown and "dark until" sunrise) for the Road trip & RV profile only; it ranks right after strong wind
- Can show the top heads-up item in the menu bar in place of the temperature (`Show the top heads-up in the menu bar`, off by default); only caution or attention items replace the temperature, and metered data usage, low battery (50% or less), and being offline keep their own menu bar text
- `Reset Dashboard Layout` restores the order recommended for the selected profile

### Who it helps

- road-trippers, van-lifers, and RV travelers who care more about weather, fuel, power, emergency care, and mobile data than about coworking context
- digital nomads who keep the default Nomad profile

### Dependencies or setup

- no setup; the Nomad profile is the default and matches earlier versions
- the profile is stored locally with the other settings

### Limitations

- profiles change card order and heads-up ranking only; they do not turn cards or data sources on or off

## Travel Context And IP/Location Awareness

### What it does

- Shows public IP address with a copy action
- Condenses the card to four rows: public IP, Wi-Fi (name, signal strength, and transmit rate), VPN, and location with the time zone and a visited-map action
- Can show IP-based city, region, country, and time zone context
- Leads the dashboard header with the current place (device city, falling back to the IP city) and shows device region and country next to the IP-based location on one line when both are available
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
- Shows the current temperature and condition symbol on one line, with feels-like, wind (with m/s), and rain chance as small stats beneath it
- Always shows the near-term hourly strip; only the 7-day outlook folds away
- Shows tomorrow summary when the 7-day outlook is collapsed
- Shows today's sunrise and sunset ("Sunrise 07:45 · Sunset 18:12") in the card in every travel profile, even when weather data is unavailable, in the time zone of the place you are in, or "Midnight sun" and "Polar night" near the poles

### Who it helps

- travelers planning movement through a city or region
- remote workers deciding where and when to work
- users who want local conditions without leaving the dashboard

### Practical benefit

Users can make quick practical decisions about wind, rain risk, the next few hours, and the next day without opening a separate weather app.

### Dependencies or setup

- weather uses device location when enabled
- WeatherKit access depends on a properly signed build with the required capability
- sunrise, sunset, and the daylight heads-up are calculated on the Mac from the device location (or the approximate IP location), need no network or WeatherKit, and work offline

### Limitations

- in unsupported or unsigned builds, WeatherKit-backed weather may be unavailable
- sunrise and sunset are astronomical estimates accurate to about a minute; hills, mountains, and clouds make the real light fade earlier, and the line is hidden until a location is known

## Travel Alerts

### What it does

- Aggregates optional travel-oriented alert signals into one condensed card
- Supports travel advisory, weather alerts, and regional security context
- Uses the live Smartraveller destinations page first, falls back to `destinations-export`, and can retry through a hidden WebKit fetch when direct transport stalls
- Keeps Smartraveller severity sourced from the destination list, then optionally fetches the matched destination page for a short reason sentence and a `More details` link
- Keeps the dashboard compact by summarizing status rather than becoming a full alert center
- The card badge always names the highest alert level; stale data is called out beside it ("Updated 12 Oct · may be outdated") instead of replacing it, and each signal states its level once

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
- Shows the resolved place (city, region, country, time zone) in the card subtitle when location or external IP location is available
- Shows next public holiday with free public data as a date and countdown with the holiday name beneath it
- Shows school holiday context as a date range with the break name, only when a confident local or regional match is available
- Reuses official country-level Eurostat price indices for European meal-out, groceries, and overall local cost context as one "Prices vs EU" row (overall level plus the meal, grocery, and overall difference)
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

## Explore Cities

### What it does

- Shows an automatic current-city summary in the dashboard, with a clear nearby label and distance when the exact city is not listed
- Opens a native destination explorer with `Around me` and `Discover` views, destination photo cards, color-coded work signals, and source-linked details from the dashboard's `Explore cities` action
- Fits city photos and detail cards to the resizable pane, with vertical scrolling for longer content
- Searches up to 20 cities in Nomads.com's ranking order, optionally filtered by country, maximum monthly nomad budget in USD, and minimum city internet speed
- Shows monthly nomad lifestyle, central 1-bedroom rent, and coworking estimates alongside overall, safety, walkability, and English-speaking ratings
- Loads a selected city's next meetup when available, with a source link for event details and joining requirements
- Keeps a prominent linked Nomads.com credit above the explorer, source links beside every city card and dashboard estimate, a Join Nomads.com action, and retrieval times visible

### Dependencies and limits

- Uses the public Nomads.com API without an account or API key; manual searches remain explicit user actions
- `Follow my city` is on by default and uses existing dashboard location context. Turn it off in the explorer to stop automatic lookups
- Matches an exact city first, then a listed destination within 50 km in the same country using local coordinate comparison; IP location can be approximate
- Saves the last automatic result, including no-match results, across restarts; does not check again until a different city or an explicit Retry
- No trip synchronization or periodic polling; stored estimates can age while the user remains in the same city
- Reuses bounded in-memory results for six hours and respects a conservative local request budget and upstream rate-limit cooldowns; Nomads.com limits requests per public IP, so shared networks can reach the limit sooner
- Estimates and community ratings may be incomplete or out of date. City internet is not a measurement of a particular venue or the user's connection, and safety ratings do not replace official advisories
- Cost categories are reference estimates, not an itemized budget or guaranteed prices
- The current-city result and directory are retained locally; manual search results use a session cache. Photos and external links may still need a connection

## Nearby Fuel Prices

### What it does

- Can show nearby fuel price information
- Station rows open the map preview when clicked; a trailing menu offers the preview and Google Maps
- Can open selected stations in Google Maps
- Shows prices in the locale's currency style ("1,429 €/L") in primary text rather than fuel-type colors, and the animated road backdrop stays subtle and fades out behind the rows
- Includes diagnostics in Settings (Advanced page) for troubleshooting

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
- Hospital rows open the in-app map preview when clicked; a trailing menu offers the preview and Google Maps
- Shows the local emergency number for the current country (for example "Emergency 112") in the card subtitle and as an Emergency row in Local Info, with police, ambulance, and fire numbers where they differ, plus additional services such as Morocco's Gendarmerie and, where a country advertises a separate short number for rural or highway police, the Guardia Civil 062 (Spain), the Federal Highway Police 191 (Brazil) and the Highway Police 1193 (Thailand); the numbers are bundled with the app and work offline, and can be selected and copied
- Shows Public or Private ownership as a neutral label
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

## Your Embassy

### What it does

- Shows where to get consular help from the country you hold citizenship of, wherever you are; you add up to three citizenships (for example a dual national) under Settings, General, Citizenship, and the card stays off ("Turned off" row, with a Settings button that opens the Citizenship group) until you do
- Subtitle names who the card is for and where ("Finland in Morocco"; with dual citizenship both countries are named)
- Leads with your foreign ministry's consular emergency line for citizens abroad: the ministry's name, the number (selectable, with a copy button) and the ministry's own wording for when it is staffed ("24/7 consular line" only where the ministry says 24/7, otherwise its own note such as "outside office hours"); one row per citizenship that has a verified line
- Lists up to three embassies or consulates of your own country in the country you are in, nearest first when device location is available, with a neutral label for the kind (Embassy, Consulate-general, Consulate, Honorary consulate), the city and the distance ("4.2 km", or "~4 km" where the dataset only has the city centre); honorary consulates never rank ahead of career missions
- Clicking a mission opens Apple Maps (missions whose location is only a city centre are searched by name and city instead of pinned on a street); a trailing menu offers Show in Maps, Open website and Copy address, each only when available
- When your country has no listed mission where you are, shows a notice and the nearest known missions of other countries that may help: EU member states' missions for EU citizens under EU consular protection, and Nordic missions for citizens of other Nordic countries under Nordic cooperation; each row names the country that sends it
- Links to your ministry's travel registration service where one exists (for example "Travel notification" for Finland) and to its official list of all missions
- When you are in your own country, shows one line ("You're home in Finland") plus the consular line; when the country you are in is not known yet, asks for location
- Collapses to one line with the consular number and a neutral status badge (Listed, EU help, Nordic help, Not listed, Home)
- Offline essentials show your nearest own mission and your ministry's consular line under the local emergency numbers
- Settings, Safety, Your embassy explains the sources and jumps to the Citizenship setting

### Who it helps

- travelers, nomads and expats who want to know whom to call and where to go if a passport is lost or stolen, they are arrested, hospitalised or caught in a crisis abroad
- dual nationals, who see the embassies and consular lines of every citizenship that is not the country they are in
- travelers whose country has no embassy in the country they are in and who would not otherwise know that another EU or Nordic embassy can help

### Practical benefit

The right consular phone number and the nearest embassy are one glance away, in the same place as the local emergency numbers, and still there when the connection is not.

### Dependencies or setup

- requires choosing a citizenship in Settings
- needs a known current country (device location, or the external IP location) to find missions; distances need device location
- embassy locations come from Wikidata (CC0) and are bundled with the app, so the card and Offline essentials work without a connection; the footer shows the dataset's date
- consular phone lines, registration links and mission directories come from each foreign ministry's official website and are listed only for countries where the number could be confirmed first-hand

### Limitations

- the Wikidata dataset is community maintained and can be incomplete or stale, so the wording says "listed" and "nearest known"; most locations are city centres rather than exact buildings; always check the official site for opening hours and current contact details
- EU consular protection and Nordic cooperation describe arrangements, not a guarantee of help in a particular case
- not every country has a verified consular line yet; the card still shows missions for those countries
- some ministries publish their line only for out-of-hours emergencies, and the card says so
- the card is a reference, not legal, consular or emergency advice; in an emergency call the local emergency number first

## Siri And Shortcuts

### What it does

- Adds five Siri and Shortcuts actions (App Intents) that need no window and do not bring the app to the front: `Emergency Number`, `Dashboard Status`, `Nearest Embassy`, `Daylight` and `Set Travel Profile`
- Each action answers in a short natural sentence that Siri speaks, Shortcuts shows, and an automation can use as text
- `Emergency Number` gives the emergency number for the country you are in, then the police, ambulance, fire and rural police numbers where the bundled table lists them, or says clearly that the country is not known or not verified yet
- `Dashboard Status` gives the overall verdict (Ready, Caution, Attention) with its reason and your top heads-up for the selected travel profile
- `Nearest Embassy` gives your nearest embassy or consulate with distance and your foreign ministry's consular line, the EU or Nordic fallback when your country has no mission there, or "Set your citizenship in Nomad Dashboard settings" when no citizenship is chosen
- `Daylight` gives sunset and the daylight left, or when it gets light again, with midnight sun and polar night handled
- `Set Travel Profile` switches between Nomad and Road trip & RV; the card order follows only when it had not been customized
- Siri phrases include the app name, for example "What's the emergency number in Nomad Dashboard", "How am I doing in Nomad Dashboard", "When is sunset in Nomad Dashboard", "Switch Nomad Dashboard to Road trip & RV"; all actions also appear in the Shortcuts app for automations

### Who it helps

- travelers who want the local emergency number or their embassy by voice, hands-free, or from a shortcut
- road-trippers who ask for the daylight left before driving on
- people who automate their Mac with Shortcuts and want travel context as a step

### Dependencies or setup

- no setup; the actions appear in Shortcuts and Spotlight once the app has run
- the answers use what the app already knows; when the app is not running the system starts it in the background first and it gets a few seconds to collect readings
- the embassy answer needs a citizenship chosen in Settings

### Limitations

- the answers are as good as the app's current knowledge: without a known country there are no emergency numbers, and without a location there is no daylight answer
- the verdict's network quality is measured when you ask, but otherwise only while the dashboard is open
- the emergency number sentence names "the emergency number" and does not say which service every number reaches, because the bundled table does not
- Siri voice recognition of the phrases depends on your Mac's language and Siri setup

## Widgets

### What it does

- Adds three widgets for the desktop and Notification Center (macOS 14 and later): `Glance` (small and medium), `Safety` (small) and `Daylight` (small)
- `Glance` shows the overall verdict, the place you are in and your top heads-up (the medium size shows two)
- `Safety` shows the emergency number for your current country and your foreign ministry's consular line when a citizenship is chosen
- `Daylight` shows sunset and the daylight left, or "Dark until" sunrise, switching by itself at sunrise and sunset; the symbol turns to the caution colour in the last hour of daylight
- Every widget shows when it was last updated ("Updated 12:40") and switches to an "Out of date" state when the app has not refreshed it for more than six hours
- The widgets use the dashboard's colours and rounded type, and colour only status
- Tapping a widget brings Nomad Dashboard to the front

### Who it helps

- travelers who want the emergency number or the day's light on the desktop without opening the menu bar panel

### Dependencies or setup

- the app has to be running to keep the widgets current; add the widgets from the widget gallery (right-click the desktop, Edit Widgets)
- the Safety widget shows the consular line only after a citizenship is chosen in Settings

### Limitations

- the widgets show what the app last saved, not live data; the verdict's network quality is only measured while the dashboard is open, so a widget can show Waiting or an older reading until you open it
- a widget is visible to anyone who can see your screen, so the place, the emergency number and the consular line are on show
- tapping a widget brings the app forward but does not yet open the dashboard panel
- development and unsigned builds have no shared storage, so they cannot feed the widgets

## Surf Spot Forecast

### What it does

- Lets the user configure a surf spot
- Shows marine conditions for that saved spot: wave, swell, wind, and sea temperature in one row, plus four equal single-line forecast columns on full-width cards
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
- Supports adding, editing, and restoring locally saved country-day entries

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

## Nomad Life Diary And Work Readiness

### What it does

- Can automatically collect stationary workplace visits when the user enables it and grants device-location access
- Groups authorized device-location samples locally and can suggest a nearby coworking or café venue through Apple MapKit
- Keeps suggested venues separate from user-confirmed venue names
- Stores a local diary with connection and work-readiness context
- Shows current and chosen home time zones side by side on one line, naming the device's actual city for "Here" rather than only the time-zone city
- Offers optional quiet alerts for sustained connection, VPN, and charging changes, with cooldowns and user-set quiet hours

### Who it helps

- remote workers building a lightweight record of where and how reliably they worked
- travelers who want current and home-time context without a separate diary app

### Dependencies or setup

- automatic workplace collection and quiet alerts are off until enabled in Settings
- workplace collection uses authorized device location only; IP address and VPN state do not identify a venue
- venue suggestions depend on Apple MapKit availability

### Limitations

- diary data stays local to the Mac
- a suggested venue remains a suggestion until the user confirms or edits it
- Google Maps opens only when the user explicitly chooses an external map link

## Project Time Tracking

### What it does

- Can track awake working time locally while Nomad Dashboard is running
- Lets the user define project buckets in Settings plus one built-in `Other` bucket
- Shows live pending unallocated time and a status dot directly in the dashboard header as a single compact row with play/pause, stop, and interruption controls
- Shows today, focus, and pending time in the card with a thin allocation bar (allocated buckets in teal tones, pending time in sand) and a short legend
- Lets the user report interruptions from the dashboard or the full time-tracking window with an interruption count that resets per day
- Offers an `Allocate` menu in the header listing recent or active projects plus `Other` (full project names, never truncated) and a shortcut to the time-tracking window
- Supports one-click allocation of today’s pending time into a project or `Other` from the header Allocate menu without opening the full time-tracking view
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

Users can capture and assign work time with less friction by using the dashboard’s Allocate menu for the common cases, then fix history later when needed and export a clean monthly text summary quickly.

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
- Supports appearance settings, with a quick dark/light flip in the dashboard header menu
- Supports a travel profile (Nomad, Road trip & RV) that sets the recommended card order and heads-up ranking; see Travel Profile
- Supports configurable refresh cadence and history retention
- Slows hidden menu-bar background refreshes automatically to reduce battery impact
- Retains a bounded local cache of selected remote dashboard content for a more useful offline or temporarily disconnected view
- Supports dashboard card reordering
- Supports dashboard card width customization
- Lets every card collapse to a single line (title, one-line summary such as "72% · 3h 28m", status badge) with a chevron in its header; collapsed cards stay collapsed across relaunches, expand when a glance tile or heads-up row points at them, and reset with `Reset Dashboard Layout`
- Hides cards whose feature is turned off and names them in one "Turned off" row with a Settings button at the bottom; `Customize Layout` still shows every card so it can be ordered
- Keeps the dashboard clean by default: the per-card width and drag controls only appear after choosing `Customize Layout` from the header menu, with an inline hint and a `Done` button while customizing
- Moves the appearance toggle into the header menu
- Supports settings for weather, travel modules, analytics, and location-aware features
- Lets you choose up to three citizenships under General, Citizenship (a searchable country list); the choice is stored only on the Mac and is used only for the Your Embassy card and Offline essentials
- Organizes Settings into a sidebar of pages, each a grouped form like macOS System Settings: **General** (travel profile, home time zone, citizenship, appearance and startup, menu bar, dashboard layout), **Weather & Local** (weather, surf spot, Local Info, fuel prices), **Safety** (travel alerts, emergency care, your embassy), **Connection & Data** (data usage, Data Guard, quiet connection alerts), **Work** (project time tracking, workplace diary), **Privacy & Location** (location, external IP location, Wi-Fi names, visited places, analytics), and **Advanced** (refresh and history, fuel diagnostics, about)
- Puts each privacy and data-source note next to the setting it describes instead of in one long paragraph
- Opens Settings on the right group from the dashboard (for example the clock's preferences button opens the home time zone, and a turned-off card's setup button opens that feature's setting) and remembers the last page while the app is running
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
- Your Embassy needs a citizenship chosen in Settings; its embassy data is bundled with the app, community maintained and can be incomplete.
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
