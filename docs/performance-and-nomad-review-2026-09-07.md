Performance and nomad workflow review — 7 September 2026

This is the original pre-implementation review. The implementation and validation record is appended below.

Reviewed commit: `810124fa39c4a734764e6310f836fbd8ede84e76`.

The strongest improvement is to separate immediate local interaction from external data refresh. The current source proves several avoidable delays and repeated operations. This review does not establish measured CPU, memory, battery consumption, or actual main-thread hang durations: no app was launched or profiled, no live provider calls were made, and tests were not run. Application code is unchanged.

**1. Publish useful data before slow providers finish — highest priority, medium/large effort.**

`Packages/NomadCore/Sources/NomadCore/Services/DashboardSnapshotStore.swift:229` begins local sampling, then `:257` onward awaits latency, power, Wi-Fi, VPN, reverse geocoding, IP, weather, local info, fuel, emergency care, marine, and travel alerts largely in sequence. The resulting dashboard snapshot is assigned only at `:399`. An unavailable optional provider therefore delays publication of already-collected information. The next scheduled refresh also waits for this entire operation.

An `await` does not itself block the main thread. This finding proves delayed data publication, not a beachball. Nevertheless, a dashboard that stays unchanged while showing a global refresh indicator feels stuck.

Publish local state independently; run eligible external cards with a small shared concurrency limit, initially two requests on a mobile connection. Each card should retain useful content, show its own updating/error state, and publish as soon as ready. Keep dependencies explicit: IP location depends on IP; country-based information depends on resolved country. Give each result a request/location generation so a late result cannot overwrite a newer destination. Avoid rebuilding the entire dashboard for each partial update by introducing narrow section models.

Validate with a suspended fake travel provider: local readings and another completed card must publish before that provider resumes. Controls, scrolling, window closing, and time allocation must work throughout.

**2. Opening the menu should respect caches — high priority, small/medium effort.**

`DashboardSnapshotStore.swift:103-113` calls `refresh(manual: true)` when the dashboard becomes active. Manual refresh forces slow metrics at `:177` and is forwarded as `forceRefresh` to multiple providers, beginning at `:285`. Repeated menu peeks can therefore trigger fresh external requests despite valid caches. The shared public-IP client also skips its reusable current response when force-refreshing location (`Services/PublicIPProviders.swift:78-104`).

Separate refresh reasons: launch, reopen, network change, location change, scheduled refresh, and explicit card retry. Reopen should display cached state and refresh only expired relevant data. A single user refresh should reuse its own newly fetched IP response. Coalesce equivalent in-flight work instead of scheduling a second forced pass. Test repeated open/close while an upstream request is suspended, and count provider calls.

**3. Remove metric-history write amplification — high priority, medium effort.**

`Storage/FileMetricHistoryStore.swift:18-22` reads and decodes all history, trims/sorts it, adds one point, trims/sorts again, then encodes and atomically rewrites the entire file (`:38-61`). `DashboardSnapshotStore.swift:1038-1067` appends upload, download, and battery metrics separately; latency is another append at `:274`. With all samples available, a slow refresh does five full rewrites plus the final history read at `:392`.

This storage is actor-isolated, so it is not evidence of direct main-thread disk I/O. It still consumes CPU and storage bandwidth and delays refresh completion. The default visible cadence is 15 seconds, with a supported minimum of five (`Models/AppSettings.swift:5-10`), making retained history progressively more expensive.

Load once into a bounded in-memory buffer, append a batch per sample cycle, and flush periodically. Preserve atomic writes initially; an immediate database migration is unnecessary. Keep full-resolution recent samples and aggregate older history if needed. Return already-bounded chart projections from storage. Define an acceptable loss window for disposable metrics separately from work-time records. Verify retention, chronological order, restart recovery, and write counts.

**4. Make time tracking cost independent of accumulated history — high priority, medium effort.**

`Services/ProjectTimeTrackingController.swift` is `@MainActor`. Its one-second ticker (`:721-727`) calls normalization and `refreshPublishedState` (`:757-769`), which normalizes entries and constructs a day summary/recent-project list (`:1131-1155`). Running tracking also saves the full ledger every ten seconds (`:775-792`); `Storage/FileTimeTrackingLedgerStore.swift:37-48` normalizes and serializes all records. Several normalization layers repeat this work.

Cache completed-day summaries and update only the active interval during a display tick. Derive elapsed time from timestamps so pausing hidden UI ticks does not lose tracked time. Perform larger historical summaries away from the main actor. Persist a small recovery heartbeat separately from full history; keep immediate durable writes for explicit edits and important lifecycle transitions. Preserve current crash-recovery guarantees rather than simply lengthening the heartbeat. Benchmark with synthetic multi-year ledgers and verify sleep, wake, midnight, crash recovery, and reassignment.

**5. Avoid rebuilding the visited map for unrelated updates — high priority when map is open, small/medium effort.**

`App/Sources/Features/Visited/VisitedMapWindowView.swift:6-8` observes the whole snapshot store. `Packages/NomadUI/Sources/NomadUI/Components/VisitedWorldMapView.swift:36-83` unconditionally removes every annotation and overlay, re-adds country geometry, and reconstructs routes whenever its representable updates. The geometry itself is cached, but scene reconstruction is not guarded.

Use a stable content signature and skip unchanged updates. Retain country overlays and update only changed country styles, places, and route segments. Preserve selection and viewport. Count map mutations while refreshing network state with no travel changes; expected count is zero. Measure first-open geometry work separately.

**6. Introduce a shared low-impact network and resource policy — high priority, medium effort.**

`Services/ConnectivityMonitorLive.swift:18-19` reduces `NWPath` to a reachability boolean, discarding constrained/expensive-path context. Hidden refresh already slows to at least 60 seconds and external work to 15 minutes (`DashboardSnapshotStore.swift:8-9,456-475`), but there is no shared thermal/low-data scheduling policy. Connectivity and latency make separate active TCP checks (`ConnectivityMonitorLive.swift:101-104`; `LatencyProbeLive.swift:64`). Many HTTP providers default to `URLSession.shared`; Smartraveller has its own explicit timeouts.

Add Auto / Normal / Low Data controls. Auto should use constrained/expensive paths, Low Power Mode, and thermal state, with a manual override because a mobile router may appear as ordinary Wi-Fi. Use this policy for background cadence, concurrency, optional downloads, and decoration. Preserve essential menu status and accurate time capture. Prefer path-change events plus occasional shared reachability probes; TCP success must not be presented as proof that a captive portal or a specific work service is usable.

Use injected sessions with explicit per-provider request/resource budgets. Apply bounded backoff on failures, respect server retry guidance, and avoid immediate retry loops offline. Keep interactive card retry available. Apple documents the relevant network controls in [allowsConstrainedNetworkAccess](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowsconstrainednetworkaccess).

Specific expensive paths deserve extra controls: Spain downloads a national fuel feed (`Services/FuelPriceProviderLive.swift:316-330`), and Italy downloads two national CSV files (`:527-543`). Cache source datasets independently of nearby-search results, reuse them when the user moves, and use conditional HTTP requests where supported. Do not assume payload sizes without measuring them. The advisory fallback creates a JavaScript-enabled hidden WKWebView with a 20-second timeout (`App/Sources/Support/WebKitSmartravellerBrowserFetcher.swift:18-48`); defer this fallback in low-impact mode and show cached advisory freshness instead.

**7. Make cancellation real — medium priority, small/medium effort.**

`DashboardSnapshotStore.swift:81-84` swallows sleep cancellation and then refreshes once more. Broad provider catches also do not distinguish cancellation from an outage. The WebKit fallback has a timeout but no task-cancellation handler.

Exit after a cancelled sleep, propagate cancellation across provider boundaries, cancel underlying operations where supported, and clear activity state with reliable cleanup. Prevent results for disabled features or obsolete locations from publishing. Preserve coalescing without draining queued work after cancellation. Test cancellation while sleeping and while a provider is suspended.

**8. Persist useful travel content and make freshness consistent — medium/high priority, medium effort.**

The dashboard starts from `.placeholder` (`DashboardSnapshotStore.swift:44`); application-level weather, marine, fuel, and IP caches are held in memory. HTTP caching may help individual sources, but there is no persisted aggregate suitable for immediate offline startup. Advisory state already retains previous values with an explicit stale state (`:1253-1264`); marine failures instead clear the previous result (`:346-348`).

Persist selected last-successful card values with source, fetched time, location scope, schema version, and expiry rules. Render that content immediately on restart. Show “Updated 42 minutes ago · Offline” or “Refreshing…” alongside retained content. A failed refresh must not silently make old information look current. Never present a previous country's safety information as local after crossing a border. Provide cache clearing and document the added local location data.

**Existing optimizations worth preserving.**

The app is native and menu-bar-first, uses actors for many service/storage operations, has provider caches and hidden refresh throttling, and caps dashboard chart series at 120 points (`DashboardSnapshotStore.swift:1365-1382`). Fuel decoration already gates animation on visibility and Reduce Motion (`DashboardPanelView.swift:3070-3080,3215-3233`). It should additionally become static under resource pressure; it is not an always-running offscreen animation bug. Nearby map sheets already guard repeated map updates. Optimize measured remaining rendering costs rather than replacing SwiftUI wholesale.

**Feature additions, in recommended order.**

| Feature | Practical behavior | Cost and boundaries |
| --- | --- | --- |
| Low Data mode and offline status | One control pauses optional heavy requests; shows what is cached and when next refresh is eligible. | Reuses the performance policy above; highest immediate value. |
| Compact work-readiness view | Put connection stability, VPN, battery outlook, and next local interruption such as a holiday near the top; keep detailed cards collapsed. | Mostly existing signals. Show uncertainty; passive throughput is not available bandwidth. |
| Saved workplace connection diary | Remember user-named cafes, campsites, apartments, and hotspots with disconnect counts, latency distribution, user notes, and observed charging conditions. | Local, opt-in; passive collection first. Offer explicit lightweight pre-call checks, never automatic bulk speed tests. Avoid implying old observations guarantee today's quality. |
| Home/client timezone overlap | Pin a few cities or contacts, show overlap with chosen working hours, and preview another date for DST changes. | Offline system timezone data; no account or server required. |
| Offline destination essentials | User-selected pack containing accommodation address, emergency contacts, saved hospital references, links, last available weather/advisory, and notes. | Download deliberately before travel; show freshness and region. Saved references can work offline even when map tiles/routes cannot. |
| Better country-day diary and planning | Correct missing or inferred days; mark observed, inferred, and manual entries distinctly; export structured CSV as well as current text. Add user-defined stay reminders later. | Builds on existing history. Do not market inferred travel history as legal/tax proof or silently assume visa rules. |
| Quiet contextual notifications | Sustained connectivity loss/recovery, unexpected VPN change, or poor charging during a work session. | Local evaluation with opt-in thresholds, deduplication, and quiet hours; avoid polling each provider just to generate notifications. |

Each addition should reuse local state and add little or no default background work. Review marketing inventory and privacy documentation with implementation; this review itself changes no shipped capability or privacy behavior.

**Implementation sequence and acceptance criteria.**

Start with independent publication and reopen cache semantics, then metric batching and time-tracking costs. Guard map updates and cancellation in the same performance milestone. Add resource policy and persistent offline card state next. Timezone overlap and workplace history are good subsequent product increments.

Before claiming success, profile a release build on the user's Mac with: dashboard hidden/open; map open; tracking enabled/disabled; slow and offline networking; simultaneous CPU-heavy work; and large synthetic histories. Capture median and p95 open/action latency, main-thread stalls, process CPU, memory, wakeups, disk writes, and request/byte counts. Include WebKit helper cost when fallback is exercised.

Proposed targets, not current measurements: cached dashboard opens within 150 ms at p95 on a defined reference Mac; actions give feedback within 100 ms; a delayed external provider never prevents local publication; unchanged travel data causes zero map reconstruction; repeated reopen within TTL causes no forced provider calls; and hidden idle CPU averages below 1% of one core over a representative ten-minute interval. Evaluate these under a repeatable contention workload rather than promising responsiveness under total system starvation. Apple recommends keeping main-thread interaction work short in [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).

Use focused deterministic tests for publication ordering, cancellation, stale/location handling, cache reuse, retention, and time-tracking recovery. Run the repository's `make test`, `make build`, and available `make lint` after implementation. Existing package tests are useful correctness coverage but do not establish these runtime performance properties.


**Implementation and validation — 7 September 2026.**

Implemented the seven performance workstreams and the requested nomad additions: independent local/card publication; cache-aware reopen/coalescing; buffered history writes; compact timer recovery and hidden-display suspension; guarded map updates; shared resource/network policy and raw fuel-feed caches; cancellation/deadline handling; automatic offline essentials; fresh device-location workplace diary and venue suggestions; home/current clocks; compact readiness; editable country days; and opt-in quiet alerts.

Validation completed with 249 core tests, 77 shared UI tests, release preparation/publishing tests, and a signed development build. Focused regressions cover suspended providers, cancellation and late results, low-data scheduling, fresh-cache reopen, rapid settings edits, stale device fixes, CSV export, offline-cache restoration, buffered history, and timer recovery. Existing formatting debt was normalized so repository-wide lint passes.

Native UI inspection covered the dashboard, saved essentials with real provider data, workplace empty state, preferences, timezone search/selection, visited map, and country-day range editor. No history changes were saved during this inspection. Subsequent polish added permission recovery in the workplace window, a timezone Cancel button and full-row click targets, clearer unavailable fuel copy, and a standard Quit persistence hook.

A five-second sample of the hidden signed development process on macOS 15.7.9 found the main thread waiting for events in 4,391 of 4,392 samples; the sampled process footprint was 95.5 MB. This is a narrow idle sanity check, not a release benchmark or proof of the proposed latency/CPU/battery targets. Those targets and the broader contention benchmark above remain unmeasured. No marketing claim relies on them.
