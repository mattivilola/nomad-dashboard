import Foundation
import NomadCore
import Testing

struct WidgetSnapshotTests {
    private let locale = QuickAnswersFixtures.locale
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(
        _ snapshot: DashboardSnapshot,
        settings: AppSettings = AppSettings(),
        visitedCountryDays: [VisitedCountryDay] = [],
        at date: Date? = nil
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            snapshot: snapshot,
            settings: settings,
            visitedCountryDays: visitedCountryDays,
            now: date ?? now,
            calendar: QuickAnswersFixtures.calendar,
            locale: locale,
            index: QuickAnswersFixtures.missionIndex
        )
    }

    // MARK: - Content

    @Test
    func carriesTheVerdictPlaceAndEmergencyNumber() {
        let widget = make(QuickAnswersFixtures.morocco())

        #expect(widget.version == WidgetSnapshot.schemaVersion)
        #expect(widget.verdict == WidgetSnapshot.Verdict(title: "Ready", level: .ready))
        #expect(widget.placeName == "Rabat, Morocco")
        #expect(widget.emergency == WidgetSnapshot.Emergency(countryName: "Morocco", generalNumber: "19"))
        #expect(widget.savedAt == now)
    }

    @Test
    func anOfflineMacIsAttention() {
        let widget = make(QuickAnswersFixtures.snapshot(offline: true))

        #expect(widget.verdict == WidgetSnapshot.Verdict(title: "Attention", level: .attention))
        #expect(widget.verdict.symbolName == "exclamationmark.triangle.fill")
    }

    @Test
    func theVerdictSymbolFollowsTheDashboardsOverallSymbols() {
        #expect(WidgetSnapshot.Verdict(title: "Ready", level: .ready).symbolName == "checkmark.seal.fill")
        #expect(WidgetSnapshot.Verdict(title: "Caution", level: .caution).symbolName == "exclamationmark.shield.fill")
        #expect(WidgetSnapshot.Verdict(title: "Attention", level: .attention).symbolName == "exclamationmark.triangle.fill")
        #expect(WidgetSnapshot.Verdict(title: "Waiting", level: .unavailable).symbolName == "timer")
    }

    @Test
    func anUnknownPlaceHasNoPlaceEmergencyOrDaylight() {
        let widget = make(QuickAnswersFixtures.snapshot())

        #expect(widget.placeName == nil)
        #expect(widget.emergency == nil)
        #expect(widget.embassy == nil)
        #expect(widget.daylight == nil)
    }

    @Test
    func aCountryWithoutVerifiedNumbersHasNoEmergencyNumber() {
        let widget = make(QuickAnswersFixtures.snapshot(device: QuickAnswersFixtures.location(countryCode: "LA")))

        #expect(widget.emergency == nil)
        #expect(widget.placeName == "Laos")
    }

    @Test
    func headsUpsAreCappedAtTwoAndKeepSeverityAndSymbol() {
        let widget = make(QuickAnswersFixtures.snapshot(metered: QuickAnswersFixtures.capReachedMetered()))

        #expect(widget.headsUp == [
            WidgetSnapshot.HeadsUp(title: "Data cap reached", symbolName: "antenna.radiowaves.left.and.right.slash", severity: .attention)
        ])
        #expect(WidgetSnapshot.maximumHeadsUps == 2)

        let many = WidgetSnapshot(
            verdict: widget.verdict,
            headsUp: (0..<5).map { WidgetSnapshot.HeadsUp(title: "Item \($0)", symbolName: "wind", severity: .info) },
            savedAt: now
        )
        #expect(many.headsUp.map(\.title) == ["Item 0", "Item 1"])
    }

    @Test
    func stayAndSchengenItemsReachTheWidgetHeadsUps() {
        let calendar = QuickAnswersFixtures.calendar
        let widget = make(
            QuickAnswersFixtures.morocco(),
            settings: AppSettings(citizenshipCountryCodes: ["US"], stayAllowances: ["MA": 90]),
            visitedCountryDays: QuickAnswersFixtures.consecutiveDays(85, endingOn: now, in: "MA", calendar: calendar)
        )

        #expect(widget.headsUp.map(\.title) == ["Morocco: 5 days left"])
        #expect(widget.headsUp.first?.severity == .caution)
    }

    @Test
    func withoutRecordedDaysTheWidgetHasNoStayHeadsUps() {
        let widget = make(QuickAnswersFixtures.morocco(), settings: AppSettings(stayAllowances: ["MA": 90]))

        #expect(widget.headsUp.isEmpty)
    }

    @Test
    func theDaylightHeadsUpNeverTakesAWidgetSlot() throws {
        let helsinki = QuickAnswersFixtures.helsinkiSnapshot()
        let sunset = try #require(DaylightOutlook(travelContext: helsinki.travelContext, now: QuickAnswersFixtures.helsinkiMidday)?.sunset)
        let settings = AppSettings(travelProfile: .roadTrip)
        let nearSunset = sunset.addingTimeInterval(-30 * 60)

        // The engine does raise it for the road trip profile...
        #expect(DashboardInsightEngine.insights(for: helsinki, now: nearSunset, profile: .roadTrip).contains { $0.kind == .daylight })
        // ...but the widget leaves it to the Daylight widget, so the snapshot does not change by the minute.
        #expect(make(helsinki, settings: settings, at: nearSunset).headsUp.isEmpty)
    }

    @Test
    func daylightIsComputedForTheCurrentPlace() {
        let widget = make(QuickAnswersFixtures.helsinkiSnapshot(), at: QuickAnswersFixtures.helsinkiMidday)

        #expect(widget.daylight?.timeZoneIdentifier == "Europe/Helsinki")
        #expect(widget.daylight?.sunset != nil)
        #expect(widget.daylight?.nextSunrise != nil)
    }

    // MARK: - Embassy

    @Test
    func noCitizenshipMeansNoEmbassy() {
        #expect(make(QuickAnswersFixtures.morocco()).embassy == nil)
    }

    @Test
    func theEmbassyCarriesTheNearestMissionAndTheHotline() throws {
        let widget = make(QuickAnswersFixtures.morocco(), settings: AppSettings(citizenshipCountryCodes: ["FI"]))
        let phone = try #require(ConsularContactsDirectory.contacts(forCitizenship: "FI")).emergencyPhone

        #expect(widget.embassy == WidgetSnapshot.Embassy(name: "Embassy of Finland in Rabat", hotline: phone))
    }

    @Test
    func atHomeOnlyTheHotlineRemains() throws {
        let widget = make(QuickAnswersFixtures.helsinkiSnapshot(), settings: AppSettings(citizenshipCountryCodes: ["FI"]))
        let phone = try #require(ConsularContactsDirectory.contacts(forCitizenship: "FI")).emergencyPhone

        #expect(widget.embassy == WidgetSnapshot.Embassy(name: nil, hotline: phone))
    }

    @Test
    func aCitizenshipWithNothingToShowLeavesTheEmbassyOut() {
        // Kosovo: no bundled consular line, and the test index lists no mission there.
        let widget = make(QuickAnswersFixtures.morocco(), settings: AppSettings(citizenshipCountryCodes: ["XK"]))

        #expect(widget.embassy == nil)
    }

    // MARK: - Privacy

    @Test
    func theStoredJSONHoldsNoIPAddressCoordinatesOrCitizenshipCode() throws {
        let snapshot = QuickAnswersFixtures.snapshot(
            device: QuickAnswersFixtures.location(
                city: "Rabat", country: "Morocco", countryCode: "MA", latitude: 34.0123, longitude: -6.8456, timeZone: "Africa/Casablanca"
            ),
            publicIP: "203.0.113.77"
        )
        let widget = make(snapshot, settings: AppSettings(citizenshipCountryCodes: ["FI"]), at: now)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-privacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        try store.save(widget)
        let json = try String(contentsOf: directory.appendingPathComponent(WidgetSnapshotStore.fileName), encoding: .utf8)

        #expect(json.contains("203.0.113.77") == false)
        #expect(json.contains("34.0123") == false)
        #expect(json.contains("-6.8456") == false)
        #expect(json.contains("latitude") == false)
        #expect(json.contains("longitude") == false)
        #expect(json.contains("\"FI\"") == false)
        #expect(json.contains("citizenship") == false)
        #expect(json.contains("Embassy of Finland in Rabat"))
    }

    @Test
    func stayHeadsUpsAddNoCountryCodesOrCitizenshipToTheStoredJSON() throws {
        let snapshot = QuickAnswersFixtures.snapshot(
            device: QuickAnswersFixtures.location(city: "Lisbon", country: "Portugal", countryCode: "PT", latitude: 38.7223, longitude: -9.1393)
        )
        let widget = make(
            snapshot,
            settings: AppSettings(citizenshipCountryCodes: ["US"], stayAllowances: ["PT": 90]),
            visitedCountryDays: QuickAnswersFixtures.consecutiveDays(85, endingOn: now, in: "PT", calendar: QuickAnswersFixtures.calendar)
        )
        #expect(widget.headsUp.isEmpty == false)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-stays-privacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        try store.save(widget)
        let json = try String(contentsOf: directory.appendingPathComponent(WidgetSnapshotStore.fileName), encoding: .utf8)

        #expect(json.contains("\"US\"") == false)
        #expect(json.contains("\"PT\"") == false)
        #expect(json.contains("citizenship") == false)
        #expect(json.contains("38.7223") == false)
        #expect(json.contains("latitude") == false)
    }

    // MARK: - Freshness

    @Test
    func staleOnlyAfterSixHours() {
        let widget = WidgetSnapshot(verdict: .init(title: "Ready", level: .ready), savedAt: now)

        #expect(widget.isStale(at: now) == false)
        #expect(widget.isStale(at: now.addingTimeInterval(6 * 3_600)) == false)
        #expect(widget.isStale(at: now.addingTimeInterval(6 * 3_600 + 1)))
        #expect(widget.isStale(at: widget.staleDate))
        #expect(widget.isStale(at: widget.staleDate.addingTimeInterval(-2)) == false)
    }

    @Test
    func aSavedTimeInTheFutureIsNotStale() {
        let widget = WidgetSnapshot(verdict: .init(title: "Ready", level: .ready), savedAt: now.addingTimeInterval(3_600))

        #expect(widget.isStale(at: now) == false)
    }

    @Test
    func sameContentIgnoresTheSavedTime() {
        let first = make(QuickAnswersFixtures.morocco(), at: now)
        let later = make(QuickAnswersFixtures.morocco(), at: now.addingTimeInterval(500))
        let elsewhere = make(QuickAnswersFixtures.helsinkiSnapshot(), at: now.addingTimeInterval(500))

        #expect(first != later)
        #expect(first.hasSameContent(as: later))
        #expect(first.hasSameContent(as: elsewhere) == false)
    }
}

struct WidgetSnapshotTimelineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let daylight = DaylightOutlook(
        sunrise: Date(timeIntervalSince1970: 1_800_000_000 - 3_600),
        sunset: Date(timeIntervalSince1970: 1_800_000_000 + 7_200),
        nextSunrise: Date(timeIntervalSince1970: 1_800_000_000 + 40_000),
        isPolarDay: false,
        isPolarNight: false,
        timeZoneIdentifier: "UTC"
    )

    private func snapshot(savedAgo: TimeInterval, daylight: DaylightOutlook?) -> WidgetSnapshot {
        WidgetSnapshot(verdict: .init(title: "Ready", level: .ready), daylight: daylight, savedAt: now.addingTimeInterval(-savedAgo))
    }

    /// Every 5 minutes up to the last hour before sunset (now + 2 h), then every minute until sunset.
    private var countdownMoments: [Date] {
        (Array(stride(from: 300.0, through: 3_600, by: 300)) + Array(stride(from: 3_660.0, through: 7_140, by: 60)))
            .map { now.addingTimeInterval($0) }
    }

    @Test
    func withoutASnapshotThereIsOnlyNow() {
        #expect(WidgetSnapshot.renderingMoments(of: nil, now: now, includesDaylightTransitions: true) == [now])
    }

    @Test
    func theStaleMomentIsPlannedWhileItIsAhead() {
        let fresh = snapshot(savedAgo: 3_600, daylight: nil)

        #expect(WidgetSnapshot.renderingMoments(of: fresh, now: now, includesDaylightTransitions: false) == [now, fresh.staleDate])
    }

    @Test
    func anAlreadyStaleSnapshotNeedsNoFurtherMoment() {
        let old = snapshot(savedAgo: 7 * 3_600, daylight: daylight)

        #expect(WidgetSnapshot.renderingMoments(of: old, now: now, includesDaylightTransitions: false) == [now])
    }

    @Test
    func daylightTransitionsOnlyCountForTheDaylightWidget() throws {
        let fresh = snapshot(savedAgo: 3_600, daylight: daylight)
        let sunset = try #require(daylight.sunset)

        #expect(WidgetSnapshot.renderingMoments(of: fresh, now: now, includesDaylightTransitions: false) == [now, fresh.staleDate])
        // The sunrise before `now` is skipped; the rest come in time order.
        let nextSunrise = try #require(daylight.nextSunrise)
        #expect(WidgetSnapshot.renderingMoments(of: fresh, now: now, includesDaylightTransitions: true)
            == [now] + countdownMoments + [sunset, fresh.staleDate, nextSunrise])
    }

    @Test
    func theDaylightLeftIsRefreshedEveryFiveMinutesAndEveryMinuteInTheLastHour() {
        // Sunset is 2 h ahead: every 5 minutes for the first hour, then every minute until sunset.
        let fresh = snapshot(savedAgo: 3_600, daylight: daylight)
        let sunset = now.addingTimeInterval(7_200)
        let moments = WidgetSnapshot.renderingMoments(of: fresh, now: now, includesDaylightTransitions: true).filter { $0 > now && $0 < sunset }

        #expect(moments.count == 12 + 59)
        #expect(moments.first == now.addingTimeInterval(300))
        #expect(moments[11] == now.addingTimeInterval(3_600))
        #expect(moments[12] == now.addingTimeInterval(3_660))
        #expect(moments.last == now.addingTimeInterval(7_140))
    }

    @Test
    func theCountdownNeedsDaylightAheadAndOnlyCountsForTheDaylightWidget() {
        let night = DaylightOutlook(
            sunrise: now.addingTimeInterval(-40_000), sunset: now.addingTimeInterval(-3_600), nextSunrise: now.addingTimeInterval(20_000),
            isPolarDay: false, isPolarNight: false, timeZoneIdentifier: "UTC"
        )
        let afterSunset = snapshot(savedAgo: 0, daylight: night)
        let moments = WidgetSnapshot.renderingMoments(of: afterSunset, now: now, includesDaylightTransitions: true)
        #expect(moments == [now, now.addingTimeInterval(20_000), afterSunset.staleDate].sorted())

        let fresh = snapshot(savedAgo: 3_600, daylight: daylight)
        #expect(WidgetSnapshot.renderingMoments(of: fresh, now: now, includesDaylightTransitions: false) == [now, fresh.staleDate])
    }

    @Test
    func momentsBeyondADayAreLeftOut() {
        let far = DaylightOutlook(
            sunrise: nil, sunset: now.addingTimeInterval(25 * 3_600), nextSunrise: nil,
            isPolarDay: false, isPolarNight: false, timeZoneIdentifier: "UTC"
        )
        let fresh = snapshot(savedAgo: 0, daylight: far)

        #expect(WidgetSnapshot.renderingMoments(of: fresh, now: now, includesDaylightTransitions: true) == [now, fresh.staleDate])
    }
}

struct WidgetSnapshotSeverityTests {
    @Test
    func severityMapsToTheSharedStatusLevels() {
        #expect(WidgetSnapshot.Severity.info.level == .ready)
        #expect(WidgetSnapshot.Severity.caution.level == .caution)
        #expect(WidgetSnapshot.Severity.attention.level == .attention)
    }
}

struct WidgetSnapshotPublishPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ title: String = "Ready", at offset: TimeInterval) -> WidgetSnapshot {
        WidgetSnapshot(verdict: .init(title: title, level: .ready), savedAt: now.addingTimeInterval(offset))
    }

    @Test
    func theFirstSnapshotIsAlwaysPublished() {
        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot(at: 0), previous: nil))
    }

    @Test
    func unchangedContentWaitsForTheHeartbeat() {
        let previous = snapshot(at: 0)

        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot(at: 10), previous: previous) == false)
        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot(at: 29 * 60), previous: previous) == false)
        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot(at: 30 * 60), previous: previous))
    }

    @Test
    func changedContentIsThrottledToOncePerMinute() {
        let previous = snapshot(at: 0)

        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot("Caution", at: 59), previous: previous) == false)
        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot("Caution", at: 60), previous: previous))
    }

    @Test
    func aClockThatMovedBackwardsPublishes() {
        let previous = snapshot(at: 600)

        #expect(WidgetSnapshotPublishPolicy.shouldPublish(snapshot(at: 0), previous: previous))
    }

    @Test
    func theHeartbeatIsWellInsideTheStaleWindow() {
        #expect(WidgetSnapshotPublishPolicy.heartbeatInterval * 4 < WidgetSnapshot.staleInterval)
    }
}

struct WidgetSnapshotStoreTests {
    private func temporaryStore() -> (WidgetSnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-store-\(UUID().uuidString)")
        return (WidgetSnapshotStore(directory: directory), directory)
    }

    private let sample = WidgetSnapshot(
        verdict: .init(title: "Caution", level: .caution),
        placeName: "Rabat, Morocco",
        headsUp: [.init(title: "Wind up to 45 km/h", symbolName: "wind", severity: .caution)],
        emergency: .init(countryName: "Morocco", generalNumber: "19"),
        embassy: .init(name: "Embassy of Finland in Rabat", hotline: "+358 9 160 55555"),
        daylight: DaylightOutlook(
            sunrise: Date(timeIntervalSince1970: 1_800_000_000.25),
            sunset: Date(timeIntervalSince1970: 1_800_040_000.5),
            nextSunrise: Date(timeIntervalSince1970: 1_800_086_400.75),
            isPolarDay: false,
            isPolarNight: false,
            timeZoneIdentifier: "Africa/Casablanca"
        ),
        savedAt: Date(timeIntervalSince1970: 1_800_001_000.125)
    )

    @Test
    func roundTripsExactlyIncludingFractionalSeconds() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(sample)

        #expect(store.load() == sample)
    }

    @Test
    func aSecondSaveReplacesTheFirst() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(sample)
        let newer = WidgetSnapshot(verdict: .init(title: "Ready", level: .ready), savedAt: Date(timeIntervalSince1970: 1_800_002_000))
        try store.save(newer)

        #expect(store.load() == newer)
    }

    @Test
    func nothingSavedLoadsNil() {
        let (store, _) = temporaryStore()

        #expect(store.load() == nil)
    }

    @Test
    func unreadableOrNewerFilesLoadNil() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(WidgetSnapshotStore.fileName)

        try Data("not json".utf8).write(to: file)
        #expect(store.load() == nil)

        try store.save(sample)
        let newerFormat = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "\"version\":\(WidgetSnapshot.schemaVersion)", with: "\"version\":\(WidgetSnapshot.schemaVersion + 1)")
        try Data(newerFormat.utf8).write(to: file)
        #expect(store.load() == nil)
    }

    @Test
    func theAppGroupIdentifierComesFromTheInfoDictionary() {
        #expect(WidgetSnapshotStore.appGroupIdentifier(bundle: Bundle(for: BundleToken.self)) == nil)
    }

    @Test
    func aProcessWithoutTheEntitlementHasNoAppGroupStore() {
        // The test runner is not signed with any App Group.
        #expect(AppGroupEntitlement.isGranted("ABCDE12345.com.iloapps.NomadDashboard") == false)
    }

    private final class BundleToken {}
}

struct DaylightOutlookTests {
    private let outlook = DaylightOutlook(
        sunrise: Date(timeIntervalSince1970: 1_000),
        sunset: Date(timeIntervalSince1970: 5_000),
        nextSunrise: Date(timeIntervalSince1970: 9_000),
        isPolarDay: false,
        isPolarNight: false,
        timeZoneIdentifier: "Europe/Helsinki"
    )

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    @Test
    func phasesFollowTheDay() {
        #expect(outlook.phase(at: at(0)) == .dark(sunrise: at(1_000)))
        #expect(outlook.phase(at: at(1_000)) == .daylight(sunset: at(5_000)))
        #expect(outlook.phase(at: at(4_999)) == .daylight(sunset: at(5_000)))
        #expect(outlook.phase(at: at(5_000)) == .dark(sunrise: at(9_000)))
        #expect(outlook.phase(at: at(8_999)) == .dark(sunrise: at(9_000)))
    }

    @Test
    func pastTheNextSunriseTheOutlookHasExpired() {
        #expect(outlook.phase(at: at(9_000)) == nil)
    }

    @Test
    func withoutANextSunriseItStaysDarkAfterSunset() {
        let open = DaylightOutlook(
            sunrise: at(1_000), sunset: at(5_000), nextSunrise: nil,
            isPolarDay: false, isPolarNight: false, timeZoneIdentifier: "UTC"
        )

        #expect(open.phase(at: at(50_000)) == .dark(sunrise: nil))
    }

    @Test
    func polarDaysAndNightsIgnoreTheClock() {
        let day = DaylightOutlook(sunrise: nil, sunset: nil, nextSunrise: nil, isPolarDay: true, isPolarNight: false, timeZoneIdentifier: "UTC")
        let night = DaylightOutlook(sunrise: nil, sunset: nil, nextSunrise: nil, isPolarDay: false, isPolarNight: true, timeZoneIdentifier: "UTC")

        #expect(day.phase(at: at(0)) == .midnightSun)
        #expect(night.phase(at: at(0)) == .polarNight)
    }

    @Test
    func transitionsAreSortedAndSkipMissingEvents() {
        #expect(outlook.transitions == [at(1_000), at(5_000), at(9_000)])
        let polar = DaylightOutlook(sunrise: nil, sunset: nil, nextSunrise: nil, isPolarDay: true, isPolarNight: false, timeZoneIdentifier: "UTC")
        #expect(polar.transitions.isEmpty)
    }

    @Test
    func clockTimesUseThePlacesTimeZone() {
        let utcMidnight = at(0)
        let helsinki = outlook.clockTime(utcMidnight, locale: Locale(identifier: "en_GB"))
        let utc = DaylightOutlook(
            sunrise: nil, sunset: nil, nextSunrise: nil, isPolarDay: false, isPolarNight: false, timeZoneIdentifier: "UTC"
        ).clockTime(utcMidnight, locale: Locale(identifier: "en_GB"))

        // Helsinki is UTC+2 on 1 Jan 1970; 24-hour clocks pad the hour, so only the suffix is compared.
        #expect(helsinki.hasSuffix("2:00"))
        #expect(utc.hasSuffix("0:00"))
        #expect(helsinki != utc)
    }

    @Test
    func computedFromALocationItCoversTodayAndTomorrowsSunrise() throws {
        let helsinki = QuickAnswersFixtures.helsinkiSnapshot()
        let now = QuickAnswersFixtures.helsinkiMidday
        let outlook = try #require(DaylightOutlook(travelContext: helsinki.travelContext, now: now))
        let sunrise = try #require(outlook.sunrise)
        let sunset = try #require(outlook.sunset)
        let nextSunrise = try #require(outlook.nextSunrise)

        #expect(sunrise < now && now < sunset && sunset < nextSunrise)
        #expect(outlook.timeZoneIdentifier == "Europe/Helsinki")
        #expect(DaylightOutlook(travelContext: QuickAnswersFixtures.snapshot().travelContext, now: now) == nil)
    }
}

struct NomadDeepLinkTests {
    @Test
    func theDashboardLinkRoundTripsPerScheme() throws {
        for scheme in ["nomaddashboard", "nomaddashboard-dev"] {
            let url = try #require(NomadDeepLink.dashboard.url(scheme: scheme))

            #expect(url.absoluteString == "\(scheme)://dashboard")
            #expect(NomadDeepLink(url: url, scheme: scheme) == .dashboard)
        }
    }

    @Test
    func theDevelopmentAppIgnoresTheReleaseAppsLinks() throws {
        let url = try #require(NomadDeepLink.dashboard.url(scheme: "nomaddashboard"))

        #expect(NomadDeepLink(url: url, scheme: "nomaddashboard-dev") == nil)
    }

    @Test
    func unknownDestinationsAreIgnored() throws {
        #expect(try NomadDeepLink(url: #require(URL(string: "nomaddashboard://settings")), scheme: "nomaddashboard") == nil)
        #expect(try NomadDeepLink(url: #require(URL(string: "https://dashboard")), scheme: "nomaddashboard") == nil)
    }

    @Test
    func theSchemeComesFromTheInfoDictionary() {
        #expect(NomadDeepLink.scheme(bundle: Bundle(for: SchemeToken.self)) == nil)
    }

    private final class SchemeToken {}
}
