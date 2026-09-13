# Nomads.com destination explorer

Explore Cities combines an automatic current-city summary with a native visual destination explorer. `Around me` shows the saved automatic match; `Discover` supports explicit filtered searches. The work-readiness overview opens the explorer and also shows a compact current-city signal.

## Source contract

Verified against the live service on 2026-09-11:

- [API index](https://nomads.com/api): public city search and city detail routes, 60 requests/hour per public IP, no bulk export.
- [LLM guide](https://nomads.com/llms.txt), dated 2026-09-10: describes the same curated JSON API and an MCP alternative. This app uses JSON directly; it does not parse the guide or use an AI service.
- [Source terms](https://nomads.com/faq/nomadscom-terms-of-service-privacy-policy-8279217): link back to Nomads.com on the screen using its data. The explorer always displays that attribution and uses validated source links.

The older “Is there a Nomads.com API?” FAQ still says the API closed in 2016. That conflicts with the current API index, dated LLM guide, and successful unauthenticated requests. Recheck the current source guidance if availability or distribution terms change; a working endpoint is not a guarantee of future availability.

## Requests and presentation

- `GET /api/cities` for the documented map directory: names, slugs, coordinates, and supplied photo URLs. This is one directory request, not per-city scraping or a loop over city details. Matching happens locally.
- `GET /api/search` with `limit=20`, optional `country`, `max_cost_usd`, and `min_internet_mbps`.
- `GET /api/city/{slug}` for selected-city details, including `next_meetup` when returned.
- Search order comes from Nomads.com. The UI does not invent its own destination score or claim complete coverage of matching cities.
- Monthly lifestyle, central 1-bedroom rent, and coworking figures are separate USD reference estimates. Missing or nonpositive cost/speed values display as unavailable; a valid zero rating remains visible.
- City internet and community ratings are distinct from this Mac's live connection metrics and the dashboard's official travel advisory sources.
- No trip, member, authentication, or write endpoints are used.
- The directory contains `long_slug`, `short_slug`, `image`, and `image_large`; source photos are used only from validated HTTPS Nomads.com/resizeapi.com paths. No photo routes are invented.

## Resource and privacy behavior

`Follow my city` is enabled by default and can be disabled in the explorer. The app-owned controller consumes existing resolved dashboard location (device first, then approximate IP location), without new permission requests or a polling timer. It normalizes city and country identity, ignores coordinate jitter, and stores the last outcome and check time on disk. Success, no-match, and failure outcomes do not automatically recheck the same city, including after app restarts. An explicit Retry or a different city permits another lookup.

The directory is retained locally. An unambiguous same-country city-name match is preferred; valid coordinates allow a same-country nearest-city fallback within 50 km. Nearby matches are labeled with distance, never presented as the user's exact city. Missing city context waits instead of issuing a query. Results for an older location must not replace a newer location's state.

Automatic current-city details are displayed directly from the saved result, so opening and closing the explorer does not trigger a fresh detail API request. The saved check time stays visible; past meetups are not presented as upcoming. The directory and last result are separate from the existing offline-dashboard cache; unreadable state is preserved and reported.

The shared provider also caches manual search/detail responses for six hours, coalesces duplicate pending requests, and applies the same 60-request/hour local budget and upstream 429 cooldown to directory, search, and details. Shared public IPs can hit the service limit sooner. Photos load only on the explorer's visible view from the source's image service and are separate from city API lookups.

Only explicit search filters or matched/selected city slugs leave the Mac. Coordinates, workplace entries, and local travel history are not sent. See [privacy notes](privacy.md).

## Validation

Current-city tests cover exact/nearby matching, identity deduplication, saved positive/negative results, and location-change races. Mocked provider tests cover the response contract, optional data, URL validation, query encoding, caching, request sharing, and errors. UI formatting tests distinguish unavailable estimates from valid zero ratings. Run the repository's `make test`, `make build` after `make generate`, and `make lint` checks when changing this integration.
