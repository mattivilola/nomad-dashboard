import Foundation

public enum DashboardInsightSeverity: Int, Comparable, Sendable {
    case info = 0
    case caution = 1
    case attention = 2

    public static func < (lhs: DashboardInsightSeverity, rhs: DashboardInsightSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum DashboardInsightKind: String, CaseIterable, Sendable {
    // Declaration order is the tie-break priority within the same severity (earlier wins).
    case dataCap
    case stayAllowance
    case schengenLimit
    case taxResidenceDays
    case travelAdvisory
    case weatherAlert
    case regionalSecurity
    case strongWind
    case rainSoon
    case uvIndex
    case airQuality
    case publicHoliday
    case localRhythm
    case fuelNearby
    case daylight

    /// Kinds in tie-break priority within the same severity (earlier wins) for a travel profile.
    public static func tieBreakOrder(for profile: TravelProfile) -> [DashboardInsightKind] {
        switch profile {
        case .nomad:
            allCases
        case .roadTrip:
            [.strongWind, .daylight, .uvIndex, .airQuality, .fuelNearby, .weatherAlert, .dataCap, .stayAllowance, .schengenLimit, .taxResidenceDays, .travelAdvisory, .regionalSecurity, .rainSoon, .publicHoliday, .localRhythm]
        }
    }
}

public struct DashboardInsight: Identifiable, Equatable, Sendable {
    public let kind: DashboardInsightKind
    public var id: DashboardInsightKind { kind }
    public let severity: DashboardInsightSeverity
    public let symbolName: String
    public let title: String
    /// Compact label (about 12 characters or fewer) for the menu bar.
    public let menuBarText: String
    public let detail: String?
    public let relatedCard: DashboardCardID

    public init(
        kind: DashboardInsightKind,
        severity: DashboardInsightSeverity,
        symbolName: String,
        title: String,
        menuBarText: String,
        detail: String?,
        relatedCard: DashboardCardID
    ) {
        self.kind = kind
        self.severity = severity
        self.symbolName = symbolName
        self.title = title
        self.menuBarText = menuBarText
        self.detail = detail
        self.relatedCard = relatedCard
    }
}

/// What the engine needs, beyond the dashboard snapshot, to derive stay heads-ups.
public struct StayInsightInput: Equatable, Sendable {
    public let countryDays: [VisitedCountryDay]
    public let settings: AppSettings
    /// ISO 3166-1 alpha-2 code of the country the Mac is in right now, if known.
    public let currentCountryCode: String?

    public init(countryDays: [VisitedCountryDay], settings: AppSettings, currentCountryCode: String?) {
        self.countryDays = countryDays
        self.settings = settings
        self.currentCountryCode = currentCountryCode
    }
}

/// Derives the few actionable "heads-up" items for a travelling remote worker from a snapshot.
///
/// Network and power health are intentionally excluded: `DashboardHealthEvaluator` owns those.
public enum DashboardInsightEngine {
    static let lookAheadInterval: TimeInterval = 6 * 3_600
    static let currentReadingMaxAge: TimeInterval = 2 * 3_600
    static let dataCapCautionFraction = 0.8
    static let windCautionKph = 40.0
    static let windAttentionKph = 60.0
    static let rainChanceThreshold = 0.6
    /// WHO UV index categories: 6-7 high, 8-10 very high, 11+ extreme.
    /// https://www.who.int/news-room/questions-and-answers/item/radiation-the-ultraviolet-(uv)-index
    static let airQualityLookAheadInterval: TimeInterval = 12 * 3_600
    static let uvHighThreshold = 6
    static let uvVeryHighThreshold = 8
    static let uvExtremeThreshold = 11
    static let holidayLookAheadDays = 3
    static let localRhythmLookAheadDays = 14
    private static let menuBarTextCharacterLimit = 12
    static let daylightCautionInterval: TimeInterval = 60 * 60
    static let daylightInfoInterval: TimeInterval = 120 * 60
    /// The dark heads-up waits this long after civil dusk so it does not flicker while the light fades.
    static let darkGraceInterval: TimeInterval = 30 * 60
    private static let detailCharacterLimit = 44

    public static func insights(
        for snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 3,
        profile: TravelProfile = .nomad,
        stays: StayInsightInput? = nil
    ) -> [DashboardInsight] {
        guard limit > 0 else {
            return []
        }

        let locale = calendar.locale ?? .autoupdatingCurrent
        var candidates: [DashboardInsight] = []

        candidates.append(contentsOf: dataCapInsight(for: snapshot.meteredData))
        if let stays {
            candidates.append(contentsOf: stayInsights(for: stays, now: now, calendar: calendar, locale: locale))
        }
        candidates.append(contentsOf: travelAlertInsights(for: snapshot.travelAlerts))
        candidates.append(contentsOf: windInsight(for: snapshot.weather, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: rainInsight(for: snapshot.weather, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: uvInsight(
            for: snapshot.weather,
            travelContext: snapshot.travelContext,
            now: now,
            calendar: calendar,
            locale: locale
        ))
        candidates.append(contentsOf: airQualityInsight(for: snapshot.airQuality, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: holidayInsight(for: snapshot.localInfo, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: localRhythmInsight(for: snapshot, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: fuelInsight(for: snapshot.fuelPrices, locale: locale))
        if profile == .roadTrip {
            candidates.append(contentsOf: daylightInsight(for: snapshot.travelContext, now: now, locale: locale))
        }

        let order = Dictionary(uniqueKeysWithValues: DashboardInsightKind.tieBreakOrder(for: profile).enumerated().map { ($1, $0) })
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return order[lhs.kind, default: .max] < order[rhs.kind, default: .max]
        }

        return Array(sorted.prefix(limit))
    }

    // MARK: - Data cap

    private static func dataCapInsight(for metered: MeteredUsageSnapshot) -> [DashboardInsight] {
        // Nomad only enforces the cap (and pauses large downloads) while it is monitoring the metered connection.
        guard metered.isFeatureEnabled, metered.isMonitoringActive,
              let capBytes = metered.capBytes, capBytes > 0
        else {
            return []
        }

        let usedBytes = switch metered.billingPeriod {
        case .session:
            metered.sessionTotalBytes
        case .calendarMonth, .manual:
            metered.periodTotalBytes
        }
        let fraction = Double(usedBytes) / Double(capBytes)
        let used = MeteredUsageFormatting.byteCount(usedBytes)
        let cap = MeteredUsageFormatting.byteCount(capBytes)

        if metered.isCapReached || fraction >= 1.0 {
            return [DashboardInsight(
                kind: .dataCap,
                severity: .attention,
                symbolName: "antenna.radiowaves.left.and.right.slash",
                title: "Data cap reached",
                menuBarText: "Cap reached",
                detail: "\(used) of \(cap) · downloads paused",
                relatedCard: .meteredData
            )]
        }

        if fraction >= dataCapCautionFraction {
            let percent = Int(fraction * 100)
            return [DashboardInsight(
                kind: .dataCap,
                severity: .caution,
                symbolName: "arrow.up.arrow.down.circle",
                title: "Data cap at \(percent)%",
                menuBarText: "Cap \(percent)%",
                detail: "\(used) of \(cap) used",
                relatedCard: .meteredData
            )]
        }

        return []
    }

    // MARK: - Stays

    private static func stayInsights(
        for input: StayInsightInput,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        let settings = input.settings
        guard DashboardCardID.stays.isFeatureEnabled(in: settings) else {
            return []
        }

        let currentCode = input.currentCountryCode.flatMap(AppSettings.normalizedCountryCode)
        let calculator = StayCalculator(
            days: input.countryDays,
            now: now,
            calendar: calendar,
            liveCountryCode: currentCode
        )
        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)

        var insights: [DashboardInsight] = []

        if let currentCode,
           let allowanceDays = settings.stayAllowances[currentCode],
           let status = calculator.allowanceStatus(country: currentCode, allowanceDays: allowanceDays),
           status.remainingDays <= StayWarningThresholds.cautionDays
        {
            let countryName = CountryNames.displayName(forCode: currentCode, locale: locale)
            let leaveBy = status.lastPermittedDay.formatted(dayStyle)
            let phrase: (title: String, menuBar: String) = if status.overstayDays > 0 {
                ("\(dayCount(status.overstayDays)) over", "\(dayCount(status.overstayDays)) over")
            } else if status.remainingDays == 0 {
                ("last day", "Last day")
            } else {
                ("\(dayCount(status.remainingDays)) left", "\(dayCount(status.remainingDays)) left")
            }
            insights.append(DashboardInsight(
                kind: .stayAllowance,
                severity: status.remainingDays <= StayWarningThresholds.attentionDays ? .attention : .caution,
                symbolName: "calendar.badge.clock",
                title: "\(countryName): \(phrase.title)",
                menuBarText: phrase.menuBar,
                detail: status.overstayDays > 0
                    ? "Allowance \(dayCount(allowanceDays)) · ended \(leaveBy)"
                    : "Allowance \(dayCount(allowanceDays)) · leave by \(leaveBy)",
                relatedCard: .stays
            ))
        }

        // Without a citizenship it is unknown whether the limit applies, so only the card says so.
        if settings.schengenCounterEnabled,
           case let .counting(allowance) = calculator.schengenStatus(citizenships: settings.citizenshipCountryCodes),
           let mustLeaveBy = allowance.mustLeaveBy,
           allowance.remainingDays <= StayWarningThresholds.cautionDays
        {
            let limit = SchengenArea.maximumStayDays
            let overstay = allowance.usedDays - limit
            insights.append(DashboardInsight(
                kind: .schengenLimit,
                severity: allowance.remainingDays <= StayWarningThresholds.attentionDays ? .attention : .caution,
                symbolName: "globe.europe.africa",
                title: "Schengen: \(allowance.remainingDays) of \(limit) days left",
                menuBarText: "Schengen \(allowance.remainingDays)d",
                detail: overstay > 0
                    ? "Over the limit by \(dayCount(overstay))"
                    : "Leave by \(mustLeaveBy.formatted(dayStyle))",
                relatedCard: .stays
            ))
        }

        if settings.taxResidenceDaysEnabled, let currentCode {
            let threshold = settings.taxResidenceThresholdDays
            let days = calculator.taxYearDays(year: calendar.component(.year, from: now)).days(inCountry: currentCode)
            if days > 0, days >= threshold - StayWarningThresholds.taxResidenceInfoLeadDays {
                let countryName = CountryNames.displayName(forCode: currentCode, locale: locale)
                insights.append(DashboardInsight(
                    kind: .taxResidenceDays,
                    severity: days >= threshold - StayWarningThresholds.taxResidenceCautionLeadDays ? .caution : .info,
                    symbolName: "building.columns",
                    title: "\(countryName): \(dayCount(days)) this year",
                    menuBarText: dayCount(days),
                    detail: "\(threshold)-day tax residence threshold · not tax advice",
                    relatedCard: .stays
                ))
            }
        }

        return insights
    }

    private static func dayCount(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    // MARK: - Travel alerts

    private static func travelAlertInsights(for alerts: TravelAlertsSnapshot?) -> [DashboardInsight] {
        guard let alerts else {
            return []
        }

        return alerts.states.compactMap { state in
            // Stale, checking, and unavailable states are not trustworthy enough for a heads-up.
            guard alerts.enabledKinds.contains(state.kind),
                  state.status == .ready,
                  let signal = state.signal,
                  let severity = insightSeverity(for: signal.severity)
            else {
                return nil
            }

            switch state.kind {
            case .advisory:
                return DashboardInsight(
                    kind: .travelAdvisory,
                    severity: severity,
                    symbolName: "exclamationmark.shield.fill",
                    title: signal.summary.trimmingCharacters(in: CharacterSet(charactersIn: ". ")),
                    menuBarText: "Advisory",
                    detail: truncated(signal.detailSummary ?? "Source: \(signal.sourceName)"),
                    relatedCard: .travelAlerts
                )
            case .weather:
                let alertCount = signal.itemCount ?? 1
                return DashboardInsight(
                    kind: .weatherAlert,
                    severity: severity,
                    symbolName: "cloud.bolt.rain.fill",
                    title: alertCount > 1
                        ? "\(alertCount) weather alerts active"
                        : (severity == .attention ? "Severe weather alert" : "Weather alert active"),
                    menuBarText: "Weather alert",
                    detail: truncated(signal.summary),
                    relatedCard: .travelAlerts
                )
            case .security:
                return DashboardInsight(
                    kind: .regionalSecurity,
                    severity: severity,
                    symbolName: "shield.lefthalf.filled.trianglebadge.exclamationmark",
                    title: severity == .attention ? "Regional security alert" : "Regional security watch",
                    menuBarText: "Security",
                    detail: truncated(signal.summary),
                    relatedCard: .travelAlerts
                )
            }
        }
    }

    /// `clear` and `info` carry no action for the traveller, so they produce no insight.
    private static func insightSeverity(for severity: TravelAlertSeverity) -> DashboardInsightSeverity? {
        switch severity {
        case .clear, .info:
            nil
        case .caution:
            .caution
        case .warning, .critical:
            .attention
        }
    }

    // MARK: - Weather

    private static func windInsight(
        for weather: WeatherSnapshot?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let weather else {
            return []
        }

        var peak: (speed: Double, degrees: Double?, date: Date?)?

        if isCurrentReadingFresh(weather, now: now), let speed = weather.windSpeedKph {
            peak = (speed, weather.windDirectionDegrees, nil)
        }

        for slot in upcomingSlots(of: weather, now: now) {
            guard let speed = slot.windSpeedKph else {
                continue
            }
            if speed > (peak?.speed ?? -.infinity) {
                peak = (speed, slot.windDirectionDegrees, slot.date)
            }
        }

        guard let peak, peak.speed >= windCautionKph else {
            return []
        }

        let timeText = peak.date.map { "around \(timeString($0, calendar: calendar, locale: locale))" } ?? "now"
        let detail: String
        if let degrees = peak.degrees {
            detail = "From \(TravelUnitFormatting.compassDirection(degrees)) \(timeText)"
        } else {
            detail = timeText.prefix(1).uppercased() + timeText.dropFirst()
        }

        let speedText = String(format: "%.0f", peak.speed)
        return [DashboardInsight(
            kind: .strongWind,
            severity: peak.speed >= windAttentionKph ? .attention : .caution,
            symbolName: "wind",
            title: "Wind up to \(speedText) km/h",
            menuBarText: "Wind \(speedText)",
            detail: detail,
            relatedCard: .weather
        )]
    }

    private static func rainInsight(
        for weather: WeatherSnapshot?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let weather else {
            return []
        }

        func insight(chance: Double, startsAt: Date?) -> DashboardInsight {
            let startText = startsAt.map { timeString($0, calendar: calendar, locale: locale) }
            return DashboardInsight(
                kind: .rainSoon,
                severity: .info,
                symbolName: "cloud.rain.fill",
                title: startText.map { "Rain likely from \($0)" } ?? "Rain likely now",
                menuBarText: startText.map { "Rain \($0)" } ?? "Rain now",
                detail: "\(Int((chance * 100).rounded()))% chance",
                relatedCard: .weather
            )
        }

        if isCurrentReadingFresh(weather, now: now),
           let chance = weather.precipitationChance, chance >= rainChanceThreshold
        {
            return [insight(chance: chance, startsAt: nil)]
        }

        // The hourly slot that began before `now` but still covers it counts as "now".
        if let covering = weather.hourlyForecastSlots.first(where: { slot in
            slot.date <= now && now < slot.date.addingTimeInterval(3_600)
        }), let chance = covering.precipitationChance, chance >= rainChanceThreshold {
            return [insight(chance: chance, startsAt: nil)]
        }

        for slot in upcomingSlots(of: weather, now: now) {
            if let chance = slot.precipitationChance, chance >= rainChanceThreshold {
                return [insight(chance: chance, startsAt: slot.date)]
            }
        }

        return []
    }

    private static func isCurrentReadingFresh(_ weather: WeatherSnapshot, now: Date) -> Bool {
        let age = now.timeIntervalSince(weather.fetchedAt)
        return age <= currentReadingMaxAge
    }

    /// Hourly slots in `[now, now + 6h]`, earliest first.
    private static func upcomingSlots(of weather: WeatherSnapshot, now: Date) -> [WeatherHourlyForecastSlot] {
        let end = now.addingTimeInterval(lookAheadInterval)
        return weather.hourlyForecastSlots
            .filter { $0.date >= now && $0.date <= end }
            .sorted { $0.date < $1.date }
    }

    // MARK: - UV index

    /// Warns about the strongest UV left in today's daylight. The hourly forecast only has a few slots, so the
    /// time range is the run of consecutive readings (the current one first) that reach the same WHO category.
    private static func uvInsight(
        for weather: WeatherSnapshot?,
        travelContext: TravelContextSnapshot,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let weather else {
            return []
        }

        let reference = DaylightReference(travelContext: travelContext)
        let sunset = reference.flatMap { reference in
            let today = reference.solarDay(on: now)
            return today.isPolarDay || today.isPolarNight ? nil : today.sunset
        }
        // Without a location to compute the sunset, fall back to the rest of the calendar day.
        func isDaylight(_ date: Date) -> Bool {
            if let sunset {
                return date < sunset
            }
            return calendar.isDate(date, inSameDayAs: now)
        }

        var readings: [(date: Date?, uv: Int)] = []
        if isCurrentReadingFresh(weather, now: now), isDaylight(now), let uv = weather.uvIndex {
            readings.append((nil, uv))
        }
        for slot in weather.hourlyForecastSlots.sorted(by: { $0.date < $1.date })
            where slot.date >= now && isDaylight(slot.date)
        {
            if let uv = slot.uvIndex {
                readings.append((slot.date, uv))
            }
        }

        guard let peak = readings.map(\.uv).max(), peak >= uvHighThreshold,
              let peakIndex = readings.firstIndex(where: { $0.uv == peak })
        else {
            return []
        }

        let (severity, floor): (DashboardInsightSeverity, Int) = if peak >= uvExtremeThreshold {
            (.attention, uvExtremeThreshold)
        } else if peak >= uvVeryHighThreshold {
            (.caution, uvVeryHighThreshold)
        } else {
            (.info, uvHighThreshold)
        }

        // The run of consecutive readings at or above the category's floor around the peak.
        var first = peakIndex
        while first > readings.startIndex, readings[first - 1].uv >= floor {
            first -= 1
        }
        var last = peakIndex
        while last < readings.endIndex - 1, readings[last + 1].uv >= floor {
            last += 1
        }

        func clock(_ date: Date?) -> String {
            guard let date else {
                return "now"
            }
            return reference.map { $0.clockTime(date, locale: locale) } ?? timeString(date, calendar: calendar, locale: locale)
        }
        let start = clock(readings[first].date)
        let end = clock(readings[last].date)

        let label: String
        let detail: String
        switch severity {
        case .attention:
            label = "extreme"
            detail = "Avoid midday sun; cover up and use SPF 30+"
        case .caution:
            label = "very high"
            detail = "Seek shade at midday; SPF 30+"
        case .info:
            label = "high"
            detail = "Hat and sunscreen around midday"
        }

        // Caution reads "from 12:00"; the others give the span, or one moment when there is no span.
        let when: String = if severity == .caution {
            "from \(start)"
        } else if first == last {
            readings[first].date == nil ? "now" : "around \(start)"
        } else {
            "\(start)–\(end)"
        }

        return [DashboardInsight(
            kind: .uvIndex,
            severity: severity,
            symbolName: severity == .info ? "sun.max" : "sun.max.trianglebadge.exclamationmark",
            title: "UV \(label) (\(peak)) \(when)",
            menuBarText: "UV \(peak)",
            detail: detail,
            relatedCard: .weather
        )]
    }

    // MARK: - Air quality

    /// European AQI of 60+ (poor) is worth a heads-up; moderate or better is not. Also warns when the
    /// next hours are forecast to reach poor while the air is not poor now.
    private static func airQualityInsight(
        for airQuality: AirQualitySnapshot?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let airQuality, now.timeIntervalSince(airQuality.fetchedAt) <= currentReadingMaxAge else {
            return []
        }

        let aqi = airQuality.europeanAQI
        if aqi >= EuropeanAQIBand.poorThreshold {
            let isVeryPoor = aqi >= EuropeanAQIBand.veryPoorThreshold
            let advice = isVeryPoor ? "limit time outdoors" : "consider shorter outdoor activity"
            let detail = airQuality.mainPollutant.map { "Mostly \($0.displayName) · \(advice)" }
                ?? advice.prefix(1).uppercased() + advice.dropFirst()
            return [DashboardInsight(
                kind: .airQuality,
                severity: isVeryPoor ? .attention : .caution,
                symbolName: isVeryPoor ? "aqi.high" : "aqi.medium",
                title: "Air quality \(airQuality.band.title.lowercased()) (AQI \(aqi))",
                menuBarText: "AQI \(aqi)",
                detail: detail,
                relatedCard: .weather
            )]
        }

        let upcoming = airQuality.forecastSlots
            .filter { $0.date > now && $0.date <= now.addingTimeInterval(airQualityLookAheadInterval) }
            .sorted { $0.date < $1.date }
        guard let onset = upcoming.first(where: { ($0.europeanAQI ?? 0) >= EuropeanAQIBand.poorThreshold }) else {
            return []
        }

        let peak = upcoming.compactMap(\.europeanAQI).max() ?? aqi
        return [DashboardInsight(
            kind: .airQuality,
            severity: .caution,
            symbolName: "aqi.medium",
            title: "Air quality worsening from \(timeString(onset.date, calendar: calendar, locale: locale))",
            menuBarText: "AQI ↑\(peak)",
            detail: "Forecast AQI up to \(peak) · now \(aqi)",
            relatedCard: .weather
        )]
    }

    // MARK: - Public holiday

    /// The public holiday that is on now or starts within `holidayLookAheadDays`, with the number of
    /// whole days from today (0 = on today). The stored state was computed at fetch time, so this
    /// re-derives it relative to `now` from the periods.
    static func nextPublicHoliday(
        in localInfo: LocalInfoSnapshot?,
        now: Date,
        calendar: Calendar
    ) -> (period: HolidayPeriodSnapshot, offset: Int)? {
        guard let status = localInfo?.publicHolidayStatus else {
            return nil
        }

        let today = calendar.startOfDay(for: now)
        let upcoming: [(period: HolidayPeriodSnapshot, offset: Int)] = [status.currentPeriod, status.nextPeriod]
            .compactMap { $0 }
            .compactMap { period in
                let start = calendar.startOfDay(for: period.startDate)
                let end = calendar.startOfDay(for: period.endDate)
                if start <= today, today <= end {
                    return (period, 0)
                }
                guard let offset = calendar.dateComponents([.day], from: today, to: start).day, offset > 0 else {
                    return nil
                }
                return (period, offset)
            }

        guard let next = upcoming.min(by: { $0.offset < $1.offset }),
              next.offset <= holidayLookAheadDays
        else {
            return nil
        }
        return next
    }

    private static func holidayInsight(
        for localInfo: LocalInfoSnapshot?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let next = nextPublicHoliday(in: localInfo, now: now, calendar: calendar) else {
            return []
        }

        let name = truncated(next.period.name, limit: 28)
        switch next.offset {
        case 0:
            return [DashboardInsight(
                kind: .publicHoliday,
                severity: .caution,
                symbolName: "calendar.badge.exclamationmark",
                title: "Public holiday today",
                menuBarText: "Holiday today",
                detail: "\(name) · shops may close",
                relatedCard: .localInfo
            )]
        case 1:
            return [DashboardInsight(
                kind: .publicHoliday,
                severity: .info,
                symbolName: "calendar",
                title: "Public holiday tomorrow",
                menuBarText: "Holiday",
                detail: name,
                relatedCard: .localInfo
            )]
        default:
            let weekday = next.period.startDate.formatted(
                Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide)
            )
            return [DashboardInsight(
                kind: .publicHoliday,
                severity: .info,
                symbolName: "calendar",
                title: "Public holiday \(weekday)",
                menuBarText: "Holiday",
                detail: name,
                relatedCard: .localInfo
            )]
        }
    }

    // MARK: - Local rhythm

    /// One heads-up about the cultural or religious period that matters most in the current country: a full
    /// shutdown (Yom Kippur, Nyepi) that is on or starts tomorrow, else an active period, else the soonest
    /// one within `localRhythmLookAheadDays`.
    private static func localRhythmInsight(
        for snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let country = snapshot.currentCountryCode else {
            return []
        }

        let today = calendar.startOfDay(for: now)
        func days(from first: Date, to second: Date) -> Int? {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: second)).day
        }

        // Earliest first; the calendar only returns periods that are active or start within the window.
        let candidates = LocalRhythmCalendar.periods(
            forCountryCode: country,
            travelContext: snapshot.travelContext,
            around: now,
            lookaheadDays: localRhythmLookAheadDays,
            calendar: calendar
        ).compactMap { period -> (period: LocalRhythmPeriod, startsIn: Int)? in
            days(from: today, to: period.start).map { (period, $0) }
        }

        // The shutdown (a day with almost nothing open) outranks a month-long period that is still running.
        guard let (period, startsIn) = candidates.first(where: { isFullShutdown($0.period.kind) && $0.startsIn <= 1 })
            ?? candidates.first(where: { $0.startsIn <= 0 })
            ?? candidates.first
        else {
            return []
        }

        let dayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        let name = period.shortName
        let isShutdownHeadsUp = isFullShutdown(period.kind) && startsIn <= 1

        let title: String
        if isShutdownHeadsUp {
            title = "\(name) \(startsIn == 1 ? "tomorrow" : "today"): \(shutdownSummary(for: period.kind))"
        } else if startsIn > 0 {
            title = "\(name) starts \(startsIn == 1 ? "tomorrow" : "in \(startsIn) days")"
        } else {
            let length = (days(from: period.start, to: period.end) ?? 0) + 1
            title = if length == 1 {
                "\(name) today"
            } else if length <= 3 {
                "\(name) · until \(period.end.formatted(dayStyle))"
            } else {
                "\(name) · day \(1 - startsIn) of \(length)"
            }
        }

        let detail: String
        if startsIn > 0 {
            let start = period.start.formatted(dayStyle)
            detail = period.confidence == .expected ? "Expected \(start) · may shift a day" : "From \(start)"
        } else {
            detail = truncated(firstSentence(of: period.guidance))
        }

        return [DashboardInsight(
            kind: .localRhythm,
            severity: isShutdownHeadsUp ? .caution : .info,
            symbolName: "calendar.badge.clock",
            title: title,
            menuBarText: menuBarName(for: period),
            detail: detail,
            relatedCard: .localInfo
        )]
    }

    /// Periods when a whole country (or island) stops for a day, which a traveller must plan for the day before.
    private static func isFullShutdown(_ kind: LocalRhythmKind) -> Bool {
        kind == .yomKippur || kind == .nyepi
    }

    private static func shutdownSummary(for kind: LocalRhythmKind) -> String {
        switch kind {
        case .nyepi: "Bali shuts down for 24 h"
        default: "country stops for 25 h"
        }
    }

    /// The short name when it fits the menu bar, else a compact stand-in.
    private static func menuBarName(for period: LocalRhythmPeriod) -> String {
        let name = period.shortName
        guard name.count > menuBarTextCharacterLimit else {
            return name
        }
        return switch period.kind {
        case .lunarNewYear: "New Year"
        case .holyWeek: "Holy Week"
        default: truncated(name, limit: menuBarTextCharacterLimit)
        }
    }

    private static func firstSentence(of text: String) -> String {
        text.range(of: ". ").map { String(text[..<$0.lowerBound]) }
            ?? text.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    // MARK: - Fuel

    private static func fuelInsight(for fuelPrices: FuelPriceSnapshot?, locale: Locale) -> [DashboardInsight] {
        // The snapshot only carries the best station per fuel type; diesel leads, matching the fuel card's row order.
        guard let fuelPrices, fuelPrices.status == .ready,
              let station = [fuelPrices.diesel, fuelPrices.gasoline].compactMap({ $0 }).first
        else {
            return []
        }

        let price = FuelPriceFormatting.price(station.pricePerLiter, currencyCode: station.currencyCode, locale: locale)
        let distance = TravelUnitFormatting.kilometers(station.distanceKilometers)

        return [DashboardInsight(
            kind: .fuelNearby,
            severity: .info,
            symbolName: "fuelpump.fill",
            title: "\(station.fuelType.displayName) \(price) · \(distance)",
            menuBarText: price,
            detail: "Cheapest within \(Int(fuelPrices.searchRadiusKilometers)) km",
            relatedCard: .fuelPrices
        )]
    }

    // MARK: - Daylight

    /// Road trippers want to finish driving before dark: warns in the last two hours of daylight and
    /// says when it is dark. Computed on the Mac from the coordinates, so it also works offline.
    private static func daylightInsight(
        for travelContext: TravelContextSnapshot,
        now: Date,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let reference = DaylightReference(travelContext: travelContext) else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reference.timeZone
        func day(offset: Int) -> SolarDay? {
            calendar.date(byAdding: .day, value: offset, to: now).map(reference.solarDay(on:))
        }

        let today = reference.solarDay(on: now)
        guard today.isPolarDay == false, today.isPolarNight == false,
              let sunrise = today.sunrise, let sunset = today.sunset
        else {
            return []
        }

        if now < sunrise {
            // Before dawn: dark once the grace period after yesterday's civil dusk has passed.
            guard let dusk = day(offset: -1)?.civilDusk,
                  now >= dusk.addingTimeInterval(darkGraceInterval)
            else {
                return []
            }
            return [darkInsight(sunrise: sunrise, now: now, calendar: calendar, reference: reference, locale: locale)]
        }

        if now < sunset {
            let remaining = sunset.timeIntervalSince(now)
            guard remaining <= daylightInfoInterval else {
                return []
            }
            let sunsetText = reference.clockTime(sunset, locale: locale)
            return [DashboardInsight(
                kind: .daylight,
                severity: remaining <= daylightCautionInterval ? .caution : .info,
                symbolName: "sunset",
                title: "Sunset \(sunsetText) · \(DurationText.hoursAndMinutes(remaining)) of daylight",
                menuBarText: "Sunset \(sunsetText)",
                detail: today.civilDusk.map { "Dusk (civil twilight) ends \(reference.clockTime($0, locale: locale))" },
                relatedCard: .weather
            )]
        }

        // After sunset: dark once civil twilight is over (plus the grace period), until tomorrow's sunrise.
        guard let dusk = today.civilDusk, now >= dusk.addingTimeInterval(darkGraceInterval),
              let nextSunrise = day(offset: 1)?.sunrise
        else {
            return []
        }
        return [darkInsight(sunrise: nextSunrise, now: now, calendar: calendar, reference: reference, locale: locale)]
    }

    private static func darkInsight(
        sunrise: Date,
        now: Date,
        calendar: Calendar,
        reference: DaylightReference,
        locale: Locale
    ) -> DashboardInsight {
        let sunriseText = reference.clockTime(sunrise, locale: locale)
        let day = calendar.isDate(sunrise, inSameDayAs: now) ? "today" : "tomorrow"
        return DashboardInsight(
            kind: .daylight,
            severity: .info,
            symbolName: "moon.stars",
            title: "Dark until \(sunriseText)",
            menuBarText: "Dark",
            detail: "Sunrise \(day) \(sunriseText)",
            relatedCard: .weather
        )
    }

    // MARK: - Formatting

    private static func timeString(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        )
    }

    private static func truncated(_ text: String, limit: Int = detailCharacterLimit) -> String {
        guard text.count > limit else {
            return text
        }
        return text.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
