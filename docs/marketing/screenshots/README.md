# Nomad Dashboard Screenshot Library

Real product screenshots for the website, the README and launch material.

## What these images are

The images are rendered from the app's real UI (the same SwiftUI views the app ships) using **built-in demo data**: a Valencia, Spain scenario and a Morocco arrival scenario with invented sample values. They are **not live personal data**. No real location, Wi-Fi name, IP address, citizenship, time tracking or travel history appears in them. The demo uses neutral names such as "Nomad Hub" and "Atlas migration", and placeholder IP addresses from the documentation range `203.0.113.0/24`.

Because the numbers are demo values, treat the images as illustrations of what the app shows, not as claims about real readings (for example the Schengen count, UV 9 and air quality 64 are scenario values).

## Format

- PNG, rendered at 2x (Retina). Dashboard popover images are 860 x 1280 px, which is the real 430 x 640 pt popover size.
- Every image exists in a light and a dark version: `NN-topic-light.png` and `NN-topic-dark.png`.
- Dashboard images are opaque. Widget and Settings window images keep transparent corners and the window shadow.
- Re-encoded losslessly (no colour reduction), about 15 MB for the whole folder.
- Text is in English with 24-hour clock times.

## Images

| File | What it shows | Variants | Pixel size |
| --- | --- | --- | --- |
| `01-glance-*.png` | Top of the dashboard in Valencia: header, time tracking pill, verdict ("Ready to work"), clocks, the four vital tiles (Internet, Power, Data Guard, Weather) and three heads-up items (Schengen limit, UV very high, air quality poor) | light, dark | 860 x 1280 |
| `02-arrival-morocco-*.png` | The one-time "Welcome to Morocco" arrival briefing: time, emergency numbers, Your Embassy (Finland), driving side, plugs, currency, travel advisory and Ramadan | light, dark | 860 x 1280 |
| `03-cards-overview-*.png` | The card list: Connectivity open, Data Guard, Power, Time Tracking and Travel Context collapsed to one line, Stays & Visas open | light, dark | 860 x 1280 |
| `04-your-embassy-*.png` | Your Embassy card for a Finnish citizen in Morocco: foreign ministry consular line, nearest mission and its distance | light, dark | 860 x 1280 |
| `05-stays-visas-*.png` | Stays & Visas card near the Schengen limit for a non-EU citizen (82 of 90 days used, leave by Oct 20) and the days per country this year against the tax-residence threshold | light, dark | 860 x 1280 |
| `06-weather-*.png` | Weather card, first page: temperature, feels like, wind, UV 9 (very high), air quality 64 (poor, mostly PM10) and the hourly outlook | light, dark | 860 x 1280 |
| `06-weather-sun-surf-*.png` | Weather card, second page (scrolled): tomorrow, the 7-day outlook, sunrise and sunset, and the surf spot (wave, swell, wind, sea temperature and forecast) | light, dark | 860 x 1280 |
| `07-local-info-ramadan-*.png` | Local Info card in Rabat: emergency numbers, the next public holiday and the Local rhythm section with Ramadan (dates and what to expect) | light, dark | 860 x 1280 |
| `08-emergency-care-fuel-*.png` | Emergency Care (nearby hospitals with distance and public/private) and the start of the Fuel Prices card (cheapest diesel and gasoline) | light, dark | 860 x 1280 |
| `09-data-guard-*.png` | Data Guard card monitoring a capped hotspot: data left, usage bar, pace estimate, download and upload totals | light, dark | 860 x 1280 |
| `10-road-trip-glance-*.png` | Glance of the Road trip & RV profile with the daylight heads-up (sunset time, daylight left, end of civil twilight) next to a wind heads-up | light, dark | 860 x 1280 |
| `11-widgets-*.png` | The three desktop widgets side by side on a plain backdrop: Safety (small), Daylight (small) and Glance (medium) | light, dark | 1664 x 484 |
| `11-widget-glance-medium-*.png` | Glance widget (medium) alone, with transparent corners | light, dark | 728 x 340 |
| `11-widget-safety-*.png` | Safety widget (small) alone: emergency number and the foreign ministry's consular line | light, dark | 340 x 340 |
| `11-widget-daylight-*.png` | Daylight widget (small) alone: sunset and the daylight left | light, dark | 340 x 340 |
| `13-trip-planner-*.png` | Trip Planner window for a Finnish citizen with Finland as home: three planned trips on the left (with the checklist progress "4/10" next to the dates) and the top of the preview of a Morocco trip in January 2027 on the right: the "Before you leave" departure checklist (progress bar, items grouped as Plan ahead, Money & power, Documents and On arrival with checkboxes and Open buttons, and two items of the traveller's own), then the time difference, emergency numbers, plugs and currency with Changed chips, and your embassy and consular line with links. The image ends after the Your embassy card: the map card is not pictured, and neither are the holiday and advisory, price and visa what-if cards below it. Content only, no window frame; the window is rendered taller than its default 900 x 640 pt and cropped | light, dark | 1800 x 2772 |
| `14-local-info-prices-vs-home-*.png` | Local Info card in Valencia for a Finnish citizen with Finland as home: the "Prices vs EU" row with one neutral line per category compared with home ("Meals out ~25% cheaper than Finland") and the caption "Compared with Finland (your home)" | light, dark | 860 x 1280 |
| `15-jet-lag-heads-up-*.png` | Top of the dashboard in Bangkok after a time zone shift from Helsinki (4 h east, arrived a day ago): the "Jet lag: day 2 of about 4" heads-up with the light timing for the day ("Get morning light 6.08–8.38 · dim lights after 21.00") below the vital tiles, and the Connectivity card start | light, dark | 860 x 1280 |
| `12-settings-general-*.png` | Settings window, General page: travel profile, home time zone and citizenship | light, dark | 1896 x 1560 |
| `12-settings-stays-visas-*.png` | Settings window, Stays & Visas page: Schengen counter, stay allowances and tax residence days | light, dark | 1896 x 1560 |
| `12-settings-safety-*.png` | Settings window, Safety page: travel alerts, emergency care and Your embassy | light, dark | 1896 x 1560 |

## Usage notes

- Scenario story: images 01, 03, 05, 06, 08, 09, 11 and 12 follow a US citizen working from Valencia; images 02, 04 and 07 follow a Finnish citizen who has just arrived in Rabat, Morocco; images 13 and 14 follow a Finnish citizen (home Finland) who plans a Morocco trip and is working from Valencia; image 15 follows a Finnish citizen who has just flown from Helsinki to Bangkok; image 10 is a road trip in Helsinki. Do not present them as one traveller.
- Image 07 (and the Ramadan row in image 02) shows Ramadan as it appears while it is on. The renders shifted the date used for the local rhythm calculation to mid-February 2027 so the period shows as "Now"; the card text itself is the app's own.
- The Settings window images were captured while the Mac was locked, so macOS drew toggles and the sidebar selection in their inactive grey instead of the usual accent colour, and the traffic lights were painted in their active colours. The page content is the app's real Settings views. Recapture them from the running app on an unlocked Mac if the exact active look matters.
- Respect the brand and messaging rules in [../brand-assets.md](../brand-assets.md) and [../README.md](../README.md): native macOS, free, provided as-is, no App Store claims.
- Images 13 and 14 use invented demo values: the Eurostat price levels in image 14 are made up, and the advisory text, the holiday and the planned trips in image 13 are sample data (Eurostat does not cover Morocco, so the trip preview has no "Prices vs home" section). They were rendered from the app's own SwiftUI views in a temporary harness with the system language set to English (UK). The window was not the active window while rendering, so buttons and the list selection draw in their inactive look; recapture from the running app on an unlocked Mac if the exact active look matters.
- The time difference in image 13 ("Home (Helsinki) is 2 h ahead") comes from the Mac's time-zone data for the date of the trip.
- Image 13 is cropped above the Map card on purpose: MapKit does not draw tiles in the offscreen render used for these images, so the card would show an empty map. The card itself is part of the app and shows the destination framed on its bundled bounds with the embassy marker, an Open in Maps button and the caption "Map © Apple · embassy locations from Wikidata, approximate where marked".
- In image 13 the checklist ticks (four suggested items and one of the traveller's own) are sample data, as are the holiday ("Independence Manifesto Day") and the advisory text, which appear as checklist items; the checklist items, their groups and wording are generated by the app.
- Image 15 was rendered with the Mac's current clock and region settings, so its times ("Last refresh", "Here Bangkok", the light window) use the system's 24-hour format with dots as separators, and the light window is for the render date in Bangkok. The time zone history (Helsinki then Bangkok) is invented sample data; the weather tile reads "Unavailable" because the demo snapshot carries no Bangkok weather.
