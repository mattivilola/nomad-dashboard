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
    case travelAdvisory
    case weatherAlert
    case regionalSecurity
    case strongWind
    case rainSoon
    case publicHoliday
    case fuelNearby
}

public struct DashboardInsight: Identifiable, Equatable, Sendable {
    public let kind: DashboardInsightKind
    public var id: DashboardInsightKind { kind }
    public let severity: DashboardInsightSeverity
    public let symbolName: String
    public let title: String
    public let detail: String?
    public let relatedCard: DashboardCardID

    public init(
        kind: DashboardInsightKind,
        severity: DashboardInsightSeverity,
        symbolName: String,
        title: String,
        detail: String?,
        relatedCard: DashboardCardID
    ) {
        self.kind = kind
        self.severity = severity
        self.symbolName = symbolName
        self.title = title
        self.detail = detail
        self.relatedCard = relatedCard
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
    static let holidayLookAheadDays = 3
    private static let detailCharacterLimit = 44

    public static func insights(
        for snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [DashboardInsight] {
        guard limit > 0 else {
            return []
        }

        let locale = calendar.locale ?? .autoupdatingCurrent
        var candidates: [DashboardInsight] = []

        candidates.append(contentsOf: dataCapInsight(for: snapshot.meteredData))
        candidates.append(contentsOf: travelAlertInsights(for: snapshot.travelAlerts))
        candidates.append(contentsOf: windInsight(for: snapshot.weather, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: rainInsight(for: snapshot.weather, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: holidayInsight(for: snapshot.localInfo, now: now, calendar: calendar, locale: locale))
        candidates.append(contentsOf: fuelInsight(for: snapshot.fuelPrices, locale: locale))

        let order = Dictionary(uniqueKeysWithValues: DashboardInsightKind.allCases.enumerated().map { ($1, $0) })
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
                detail: "\(used) of \(cap) · downloads paused",
                relatedCard: .meteredData
            )]
        }

        if fraction >= dataCapCautionFraction {
            return [DashboardInsight(
                kind: .dataCap,
                severity: .caution,
                symbolName: "arrow.up.arrow.down.circle",
                title: "Data cap at \(Int(fraction * 100))%",
                detail: "\(used) of \(cap) used",
                relatedCard: .meteredData
            )]
        }

        return []
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
                    detail: truncated(signal.summary),
                    relatedCard: .travelAlerts
                )
            case .security:
                return DashboardInsight(
                    kind: .regionalSecurity,
                    severity: severity,
                    symbolName: "shield.lefthalf.filled.trianglebadge.exclamationmark",
                    title: severity == .attention ? "Regional security alert" : "Regional security watch",
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

        return [DashboardInsight(
            kind: .strongWind,
            severity: peak.speed >= windAttentionKph ? .attention : .caution,
            symbolName: "wind",
            title: "Wind up to \(String(format: "%.0f", peak.speed)) km/h",
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
            DashboardInsight(
                kind: .rainSoon,
                severity: .info,
                symbolName: "cloud.rain.fill",
                title: startsAt.map { "Rain likely from \(timeString($0, calendar: calendar, locale: locale))" } ?? "Rain likely now",
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

    // MARK: - Public holiday

    private static func holidayInsight(
        for localInfo: LocalInfoSnapshot?,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> [DashboardInsight] {
        guard let status = localInfo?.publicHolidayStatus else {
            return []
        }

        // The stored state was computed at fetch time, so re-derive relative to `now` from the periods.
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
                detail: "\(name) · shops may close",
                relatedCard: .localInfo
            )]
        case 1:
            return [DashboardInsight(
                kind: .publicHoliday,
                severity: .info,
                symbolName: "calendar",
                title: "Public holiday tomorrow",
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
                detail: name,
                relatedCard: .localInfo
            )]
        }
    }

    // MARK: - Fuel

    private static func fuelInsight(for fuelPrices: FuelPriceSnapshot?, locale: Locale) -> [DashboardInsight] {
        // The snapshot only carries the best station per fuel type; diesel leads, matching the fuel card's row order.
        guard let fuelPrices, fuelPrices.status == .ready,
              let station = [fuelPrices.diesel, fuelPrices.gasoline].compactMap({ $0 }).first
        else {
            return []
        }

        let price = formattedPrice(station.pricePerLiter, currencyCode: station.currencyCode, locale: locale)
        let distance = TravelUnitFormatting.kilometers(station.distanceKilometers)

        return [DashboardInsight(
            kind: .fuelNearby,
            severity: .info,
            symbolName: "fuelpump.fill",
            title: "\(station.fuelType.displayName) \(price) · \(distance)",
            detail: "Cheapest within \(Int(fuelPrices.searchRadiusKilometers)) km",
            relatedCard: .fuelPrices
        )]
    }

    private static func formattedPrice(_ value: Double, currencyCode: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.3f %@", value, currencyCode)
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
