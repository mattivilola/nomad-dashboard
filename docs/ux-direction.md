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
