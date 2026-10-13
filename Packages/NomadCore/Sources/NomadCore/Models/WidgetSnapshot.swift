import Foundation

/// The compact, display-ready state the home screen widgets read.
///
/// The app writes it into the App Group container after each dashboard refresh and the widget
/// extension reads it from there; nothing is sent anywhere. It deliberately holds only what the
/// widgets show: no IP address, no coordinates, no citizenship codes. The embassy and hotline are
/// shown on the widget, so they are the only trace of the citizenship setting.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    /// The widgets mark their content as out of date after this long without an update from the app.
    public static let staleInterval: TimeInterval = 6 * 3_600
    public static let maximumHeadsUps = 2

    public struct Verdict: Codable, Equatable, Sendable {
        /// "Ready", "Caution", "Attention" or "Waiting".
        public let title: String
        public let level: HealthLevel

        public init(title: String, level: HealthLevel) {
            self.title = title
            self.level = level
        }

        /// The symbol the dashboard uses for the same overall verdict.
        public var symbolName: String {
            switch level {
            case .ready: "checkmark.seal.fill"
            case .caution: "exclamationmark.shield.fill"
            case .attention: "exclamationmark.triangle.fill"
            case .unavailable: "timer"
            }
        }
    }

    public enum Severity: String, Codable, Equatable, Sendable {
        case info
        case caution
        case attention

        /// The health level whose status colour the severity shares: attention is coral, caution is sand
        /// and info is teal, like the glance heads-up rows.
        public var level: HealthLevel {
            switch self {
            case .info: .ready
            case .caution: .caution
            case .attention: .attention
            }
        }

        init(_ severity: DashboardInsightSeverity) {
            switch severity {
            case .info: self = .info
            case .caution: self = .caution
            case .attention: self = .attention
            }
        }
    }

    public struct HeadsUp: Codable, Equatable, Sendable {
        public let title: String
        public let symbolName: String
        public let severity: Severity

        public init(title: String, symbolName: String, severity: Severity) {
            self.title = title
            self.symbolName = symbolName
            self.severity = severity
        }
    }

    public struct Emergency: Codable, Equatable, Sendable {
        public let countryName: String
        /// The number to call first.
        public let generalNumber: String

        public init(countryName: String, generalNumber: String) {
            self.countryName = countryName
            self.generalNumber = generalNumber
        }
    }

    /// The nearest embassy and the consular hotline; only present once a citizenship is chosen.
    public struct Embassy: Codable, Equatable, Sendable {
        public let name: String?
        public let hotline: String?

        public init(name: String?, hotline: String?) {
            self.name = name
            self.hotline = hotline
        }
    }

    public let version: Int
    public let verdict: Verdict
    /// "Rabat, Morocco".
    public let placeName: String?
    /// At most `maximumHeadsUps`, most important first.
    public let headsUp: [HeadsUp]
    public let emergency: Emergency?
    public let embassy: Embassy?
    public let daylight: DaylightOutlook?
    public let savedAt: Date

    public init(
        verdict: Verdict,
        placeName: String? = nil,
        headsUp: [HeadsUp] = [],
        emergency: Emergency? = nil,
        embassy: Embassy? = nil,
        daylight: DaylightOutlook? = nil,
        savedAt: Date
    ) {
        version = Self.schemaVersion
        self.verdict = verdict
        self.placeName = placeName
        self.headsUp = Array(headsUp.prefix(Self.maximumHeadsUps))
        self.emergency = emergency
        self.embassy = embassy
        self.daylight = daylight
        self.savedAt = savedAt
    }

    /// Everything the widgets show, from the live dashboard state.
    public init(
        snapshot: DashboardSnapshot,
        settings: AppSettings,
        visitedCountryDays: [VisitedCountryDay],
        timeZoneShifts: [TimeZoneShiftRecord] = [],
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current,
        index: DiplomaticMissionIndex = .bundled
    ) {
        let overall = snapshot.healthSummary.overall

        // The daylight heads-up counts down by the minute and has its own widget, so it never takes
        // a heads-up slot (and never makes the snapshot change every minute).
        let headsUp = DashboardInsightEngine.insights(
            for: snapshot,
            now: now,
            calendar: calendar,
            limit: Self.maximumHeadsUps + 1,
            profile: settings.travelProfile,
            stays: StayInsightInput(
                countryDays: visitedCountryDays,
                settings: settings,
                currentCountryCode: snapshot.currentCountryCode
            ),
            timeZoneShifts: timeZoneShifts
        )
        .filter { $0.kind != .daylight }
        .map { HeadsUp(title: $0.title, symbolName: $0.symbolName, severity: Severity($0.severity)) }

        let emergencyAnswer = QuickAnswers.emergencyNumbers(snapshot: snapshot, locale: locale)
        let emergency = emergencyAnswer.numbers.flatMap { numbers in
            emergencyAnswer.countryName.map { Emergency(countryName: $0, generalNumber: numbers.general) }
        }

        let embassyAnswer = QuickAnswers.nearestEmbassy(snapshot: snapshot, settings: settings, index: index, locale: locale)
        let embassy: Embassy? = if embassyAnswer.state == .citizenshipNeeded
            || (embassyAnswer.mission == nil && embassyAnswer.hotline == nil)
        {
            nil
        } else {
            Embassy(name: embassyAnswer.mission?.name, hotline: embassyAnswer.hotline?.phone)
        }

        self.init(
            verdict: Verdict(title: overall.label, level: overall.level),
            placeName: QuickAnswers.placeName(snapshot: snapshot, locale: locale),
            headsUp: headsUp,
            emergency: emergency,
            embassy: embassy,
            daylight: DaylightOutlook(travelContext: snapshot.travelContext, now: now),
            savedAt: now
        )
    }

    // MARK: - Freshness

    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(savedAt) > Self.staleInterval
    }

    /// The moment the widgets start showing the out-of-date state.
    public var staleDate: Date {
        savedAt.addingTimeInterval(Self.staleInterval).addingTimeInterval(1)
    }

    /// How far ahead a widget timeline plans.
    public static let timelineLookAhead: TimeInterval = 24 * 3_600

    /// The Daylight widget writes the daylight left as text ("3 h 11 min"), which a widget cannot keep counting
    /// by itself, so it renders again every 5 minutes while the sun is up and every minute in its last hour.
    static let daylightCountdownStep: TimeInterval = 5 * 60
    static let daylightCountdownFineStep: TimeInterval = 60
    static let daylightCountdownFineInterval: TimeInterval = 3_600

    private static func daylightCountdownMoments(of daylight: DaylightOutlook?, after now: Date) -> [Date] {
        guard let daylight, case let .daylight(sunset)? = daylight.phase(at: now) else {
            return []
        }

        let horizon = now.addingTimeInterval(timelineLookAhead)
        var moments: [Date] = []
        var moment = now
        while moments.count < 1_000 {
            let step = sunset.timeIntervalSince(moment) <= daylightCountdownFineInterval ? daylightCountdownFineStep : daylightCountdownStep
            moment = moment.addingTimeInterval(step)
            guard moment < sunset, moment <= horizon else {
                break
            }
            moments.append(moment)
        }
        return moments
    }

    /// `now` first, then every later moment within a day at which a widget has to render again without
    /// the app's help: when the content turns out of date and, for the Daylight widget, sunrise and sunset.
    public static func renderingMoments(of snapshot: WidgetSnapshot?, now: Date, includesDaylightTransitions: Bool) -> [Date] {
        guard let snapshot else {
            return [now]
        }

        var later = [snapshot.staleDate]
        if includesDaylightTransitions {
            later += snapshot.daylight?.transitions ?? []
            later += daylightCountdownMoments(of: snapshot.daylight, after: now)
        }

        let horizon = now.addingTimeInterval(timelineLookAhead)
        let upcoming = Set(later.filter { $0 > now && $0 <= horizon }).sorted()
        return [now] + upcoming
    }

    /// Whether two snapshots show the same thing, ignoring when they were saved.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        WidgetSnapshot(
            verdict: verdict,
            placeName: placeName,
            headsUp: headsUp,
            emergency: emergency,
            embassy: embassy,
            daylight: daylight,
            savedAt: other.savedAt
        ) == other
    }
}

/// When the app should write a new widget snapshot and reload the widgets.
///
/// The dashboard snapshot changes every few seconds but the widgets show much less, so a write only
/// happens when the shown content changed (at most once a minute) or, with nothing changed, as a
/// heartbeat that keeps "Updated 12:40" and the 6 hour out-of-date state honest.
public enum WidgetSnapshotPublishPolicy {
    public static let minimumInterval: TimeInterval = 60
    public static let heartbeatInterval: TimeInterval = 30 * 60

    public static func shouldPublish(_ candidate: WidgetSnapshot, previous: WidgetSnapshot?) -> Bool {
        guard let previous else {
            return true
        }

        let elapsed = candidate.savedAt.timeIntervalSince(previous.savedAt)
        // A clock that moved backwards cannot be throttled against.
        guard elapsed >= 0 else {
            return true
        }

        if candidate.hasSameContent(as: previous) {
            return elapsed >= heartbeatInterval
        }
        return elapsed >= minimumInterval
    }
}
