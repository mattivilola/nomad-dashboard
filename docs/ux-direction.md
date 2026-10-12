# UX Direction

Nomad Dashboard should feel like a compact travel instrument panel:

- warm sand, teal, and coral accents instead of default monochrome utility UI
- strong hierarchy with a concise headline signal in each section
- soft material surfaces and small trend charts
- dense enough for fast scanning, but never terminal-style clutter

## Glance

- The header leads with the current place (device city, then IP city) rather than the app name, with device region/country and IP location on one caption line.
- The first screen answers "can I work here?": a tinted verdict strip, one line of clocks (Here and Home), four tappable vital tiles (Internet, Power, Data or VPN, Weather) and at most three heads-up rows.
- Color means status only: teal is good, sand is caution, coral is attention, and neutral values use primary text. Never color a value by its metric name.
- Vital tiles and heads-up rows scroll to the related card instead of repeating its content.
- Card controls (width toggle, drag handle) appear only in Customize Layout mode so half-width cards keep their titles and subtitles readable.
- Time tracking is a single compact row; project names live in the Allocate menu so they never truncate.
- Appearance toggle, Customize Layout, and the other secondary actions live in the header overflow menu.

## Cards

- Cards are as tall as their information. Charts are 24 pt sparklines placed under the metric they describe, with the time span and min/max on hover.
- Every inline action ("Open Settings", "More details", Data Guard actions) uses one button style: teal caption text on the inline button background in a rounded rectangle. No system links or prominent buttons.
- Color encodes status only. Fuel types, hospital ownership, and chart series are never tinted by category; allocated time uses a ramp of teal and neutral tones with pending time in sand.
- A narrow card without a narrow neighbour renders with the wide layout at full width. The stored width preference is untouched, so it narrows again as soon as it has a partner. Paired half-width cards share the height of the taller card.
- List rows (fuel stations, hospitals) are one button that opens the map preview; secondary actions live in a trailing menu.
- The hourly weather strip is always visible; the disclosure only governs the 7-day outlook.
- Every card has a chevron that collapses it to one line (title, one-line summary, status badge). Collapsed cards are always full width and never pair; pointing a tile or heads-up row at a collapsed card expands it.
- Cards whose feature is off are not rendered. One "Turned off" row at the bottom names them and links to Settings; Customize Layout shows every card.
- Data Guard leads with what is left, drawn in the status color with a thin status-tinted bar; the actions that are rarely needed sit in a small menu.

## Sections

- Connectivity
- Power
- Travel Context
- Travel Alerts
- Weather

## Travel Alerts

- Travel risk stays in one condensed `Travel Alerts` card.
- The menu bar panel must not expand into a multi-panel alert center.
- Show one overall badge and short per-signal summaries instead of long lists or drill-downs.
- Detailed source links or deeper investigation belong in a separate window later, not in the main dashboard panel.

## Quick Actions

- Refresh now
- Customize Layout
- Switch appearance
- Copy public IP
- Open Network Settings
- Check for updates
- Open Settings
- Open About
