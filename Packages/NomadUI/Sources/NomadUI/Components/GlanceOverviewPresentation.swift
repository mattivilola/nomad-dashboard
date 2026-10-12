import Foundation
import NomadCore

// Pure presentation logic for the "glance" at the top of the dashboard: the
// location-led header, the verdict strip, the clocks line and the vital tiles.
// Views stay thin and everything here is unit tested.

extension Optional where Wrapped == String {
    /// The trimmed string, or `nil` when it is missing or blank.
    var trimmedNonEmpty: String? {
        self?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

extension IPLocationSnapshot {
    /// "City, Country" with blank parts dropped, or `nil` when neither is known.
    var cityCountryDescription: String? {
        let parts = [city.trimmedNonEmpty, country.trimmedNonEmpty].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Header

struct DashboardHeaderPresentation: Equatable {
    static let fallbackHeadline = "Travel-ready system telemetry"

    /// One candidate for the caption line under the headline. The device part is
    /// shown with a location icon, the IP part with a globe and an "IP" label.
    struct DetailVariant: Equatable {
        let device: String?
        let ip: String?
    }

    /// The place the user is in: device city, then IP city, then a generic line.
    let headline: String
    /// Caption candidates from most to least detailed. The view shows the first one
    /// that fits, so the IP comparison is never the part that gets cut off:
    /// "region, country · IP city, country", then "country · IP city, country",
    /// then "country · IP city".
    let detailVariants: [DetailVariant]

    init(deviceLocation: IPLocationSnapshot?, ipLocation: IPLocationSnapshot?) {
        let deviceCity = deviceLocation?.city.trimmedNonEmpty
        headline = deviceCity ?? ipLocation?.city.trimmedNonEmpty ?? Self.fallbackHeadline

        var seen = Set<String>()
        if let deviceCity {
            seen.insert(deviceCity.lowercased())
        }
        let region = deviceLocation?.region.trimmedNonEmpty.flatMap { seen.insert($0.lowercased()).inserted ? $0 : nil }
        let country = deviceLocation?.country.trimmedNonEmpty.flatMap { seen.insert($0.lowercased()).inserted ? $0 : nil }
        let regionAndCountry = [region, country].compactMap(\.self)

        let deviceDetails: [String?] = [
            regionAndCountry.isEmpty ? nil : regionAndCountry.joined(separator: ", "),
            country,
            country
        ]
        let ipDetails: [String?] = [
            ipLocation?.cityCountryDescription,
            ipLocation?.cityCountryDescription,
            ipLocation?.city.trimmedNonEmpty ?? ipLocation?.cityCountryDescription
        ]

        var variants: [DetailVariant] = []
        for (device, ip) in zip(deviceDetails, ipDetails) where device != nil || ip != nil {
            let variant = DetailVariant(device: device, ip: ip)
            if variants.last != variant {
                variants.append(variant)
            }
        }
        detailVariants = variants
    }
}

// MARK: - Verdict

struct GlanceVerdictPresentation: Equatable {
    let title: String
    let detail: String
    let symbolName: String
    let level: HealthLevel

    static func isOffline(snapshot: DashboardSnapshot, policy: DashboardResourcePolicy) -> Bool {
        policy.isOffline || snapshot.network.connectivity.internetState == .offline
    }

    init(snapshot: DashboardSnapshot, isOffline: Bool) {
        if isOffline {
            title = "You're offline"
            detail = "Saved essentials are available"
            symbolName = "wifi.slash"
            level = .caution
            return
        }

        let overall = snapshot.healthSummary.overall
        symbolName = overall.symbolName
        level = overall.level

        switch overall.level {
        case .ready:
            title = "Ready to work"
            var detail = snapshot.healthSummary.network.reason
            if snapshot.travelContext.vpn?.isActive == true {
                detail += " · VPN on"
            }
            self.detail = detail
        case .caution:
            title = "Workable"
            detail = overall.reason
        case .attention:
            title = "Needs attention"
            detail = overall.reason
        case .unavailable:
            title = "Checking conditions"
            detail = overall.reason
        }
    }
}

// MARK: - Clocks

enum GlanceClockPresentation {
    /// "Here" prefers the device's city over the city of the time zone identifier,
    /// which can differ from where the user actually is (a zone covers many towns).
    static func hereCity(deviceLocation: IPLocationSnapshot?, timeZoneIdentifier: String) -> String {
        deviceLocation?.city.trimmedNonEmpty ?? cityName(forTimeZoneIdentifier: timeZoneIdentifier)
    }

    static func cityName(forTimeZoneIdentifier identifier: String) -> String {
        identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? identifier
    }
}

// MARK: - Vital tiles

struct GlanceVitalTilePresentation: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case internet
        case power
        case data
        case vpn
        case weather
    }

    let kind: Kind
    let title: String
    /// Extra context next to the title, e.g. the Wi-Fi name.
    let titleDetail: String?
    let symbolName: String
    let value: String
    /// Optional symbol shown after the value (the weather condition).
    let valueSymbolName: String?
    let secondary: String
    /// Status of the value; `nil` means the tile has no status meaning and stays neutral.
    let level: HealthLevel?
    /// Fraction in 0...1 for tiles that draw a thin progress bar.
    let progress: Double?

    var id: Kind {
        kind
    }

    /// The dashboard card a tap on the tile scrolls to.
    var scrollTarget: DashboardCardID {
        switch kind {
        case .internet: .connectivity
        case .power: .power
        case .data: .meteredData
        case .vpn: .travelContext
        case .weather: .weather
        }
    }

    var accessibilityLabel: String {
        [title, titleDetail, value, secondary].compactMap(\.self).joined(separator: ", ")
    }

    static func tiles(
        snapshot: DashboardSnapshot,
        isOffline: Bool,
        weatherAvailabilityExplanation: String?,
        now: Date = .now
    ) -> [GlanceVitalTilePresentation] {
        [
            internet(snapshot: snapshot, isOffline: isOffline),
            power(snapshot: snapshot),
            dataOrVPN(snapshot: snapshot),
            weather(snapshot: snapshot, weatherAvailabilityExplanation: weatherAvailabilityExplanation, now: now)
        ]
    }

    static func internet(snapshot: DashboardSnapshot, isOffline: Bool) -> GlanceVitalTilePresentation {
        let health = snapshot.healthSummary.network
        let value: String = if isOffline {
            "Offline"
        } else if let latency = snapshot.network.latency {
            NomadFormatters.latency(latency.milliseconds)
        } else {
            "Waiting"
        }

        let secondary: String
        if isOffline == false, let throughput = snapshot.network.throughput {
            secondary = String(
                format: "%.1f ↓ · %.1f ↑ Mbps",
                throughput.downloadMegabitsPerSecond,
                throughput.uploadMegabitsPerSecond
            )
        } else {
            secondary = health.reason
        }

        return GlanceVitalTilePresentation(
            kind: .internet,
            title: "Internet",
            titleDetail: snapshot.travelContext.wifi?.ssid.trimmedNonEmpty
                ?? snapshot.network.throughput?.activeInterface.trimmedNonEmpty,
            symbolName: isOffline ? "wifi.slash" : "wifi",
            value: value,
            valueSymbolName: nil,
            secondary: secondary,
            level: isOffline ? .attention : health.level.statusOrNil,
            progress: nil
        )
    }

    static func power(snapshot: DashboardSnapshot) -> GlanceVitalTilePresentation {
        let power = snapshot.power.snapshot
        let metrics = PowerMetricsPresentation(snapshot: power)
        let symbolName: String = switch power?.state {
        case .charging: "battery.100percent.bolt"
        case .charged: "powerplug.fill"
        case .battery: "battery.50percent"
        case .unknown, nil: "battery.0percent"
        }

        return GlanceVitalTilePresentation(
            kind: .power,
            title: "Power",
            titleDetail: nil,
            symbolName: symbolName,
            value: power?.chargePercent.map { NomadFormatters.percentage($0 * 100) } ?? "—",
            valueSymbolName: nil,
            secondary: metrics.summary,
            level: snapshot.healthSummary.power.level.statusOrNil,
            progress: nil
        )
    }

    /// Data Guard when it is enabled, otherwise the VPN state (the tile slot stays useful).
    static func dataOrVPN(snapshot: DashboardSnapshot) -> GlanceVitalTilePresentation {
        let metered = snapshot.meteredData
        guard metered.isFeatureEnabled else {
            return vpn(snapshot: snapshot)
        }

        let networkName = metered.networkDisplayName.trimmedNonEmpty

        guard metered.isMonitoringActive else {
            return GlanceVitalTilePresentation(
                kind: .data,
                title: "Data",
                titleDetail: nil,
                symbolName: "arrow.up.arrow.down.circle",
                value: "Unmetered",
                valueSymbolName: nil,
                secondary: networkName ?? "No network",
                level: nil,
                progress: nil
            )
        }

        let used = MeteredUsageFormatting.byteCount(metered.displayedUsedBytes)
        let value: String
        let progress: Double?
        if let capBytes = metered.capBytes {
            value = "\(used) / \(MeteredUsageFormatting.byteCount(capBytes))"
            progress = metered.usageFraction.map { min(max($0, 0), 1) }
        } else {
            value = used
            progress = nil
        }

        return GlanceVitalTilePresentation(
            kind: .data,
            title: "Data",
            titleDetail: nil,
            symbolName: "arrow.up.arrow.down.circle",
            value: value,
            valueSymbolName: nil,
            secondary: networkName ?? "Monitoring",
            level: metered.usageLevel,
            progress: progress
        )
    }

    static func vpn(snapshot: DashboardSnapshot) -> GlanceVitalTilePresentation {
        let vpn = snapshot.travelContext.vpn
        let isActive = vpn?.isActive == true
        let value = vpn.map { $0.isActive ? "On" : "Off" } ?? "Checking"
        let secondary = snapshot.travelContext.location?.city.trimmedNonEmpty
            ?? snapshot.travelContext.publicIP?.address
            ?? "IP location unknown"

        return GlanceVitalTilePresentation(
            kind: .vpn,
            title: "VPN",
            titleDetail: nil,
            symbolName: isActive ? "lock.shield" : "shield",
            value: value,
            valueSymbolName: nil,
            secondary: secondary,
            level: isActive ? .ready : nil,
            progress: nil
        )
    }

    static func weather(
        snapshot: DashboardSnapshot,
        weatherAvailabilityExplanation: String?,
        now: Date = .now
    ) -> GlanceVitalTilePresentation {
        guard let weather = snapshot.weather else {
            let reason: String = if weatherAvailabilityExplanation != nil {
                "WeatherKit unavailable"
            } else if snapshot.appState.issues.contains(.weatherLocationRequired) {
                "Location needed"
            } else {
                "Unavailable"
            }

            return GlanceVitalTilePresentation(
                kind: .weather,
                title: "Weather",
                titleDetail: nil,
                symbolName: "cloud.sun",
                value: "—",
                valueSymbolName: nil,
                secondary: reason,
                level: nil,
                progress: nil
            )
        }

        return GlanceVitalTilePresentation(
            kind: .weather,
            title: "Weather",
            titleDetail: nil,
            symbolName: "cloud.sun",
            value: weather.currentTemperatureCelsius.map { NomadFormatters.celsius($0) } ?? "—",
            valueSymbolName: weather.symbolName,
            secondary: weatherSecondary(weather, now: now),
            level: nil,
            progress: nil
        )
    }

    /// Condition plus today's low/high. Rain and wind are covered by the heads-up list,
    /// so they are not repeated here. Without a current condition it falls back to tomorrow.
    static func weatherSecondary(_ weather: WeatherSnapshot, now: Date, calendar: Calendar = .current) -> String {
        guard let condition = weather.conditionDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return weather.tomorrow.map { "Tomorrow · \($0.summary)" } ?? "Unavailable"
        }

        let today = weather.dailyForecast.first { calendar.isDate($0.date, inSameDayAs: now) }
        guard let today, today.temperatureMinCelsius != nil || today.temperatureMaxCelsius != nil else {
            return condition
        }

        return "\(condition) · \(today.temperatureRangeText)"
    }
}

extension WeatherDaySummary {
    /// "12 C / 24 C"; a missing bound reads "Estimating".
    var temperatureRangeText: String {
        let minimum = temperatureMinCelsius.map { NomadFormatters.celsius($0) } ?? "Estimating"
        let maximum = temperatureMaxCelsius.map { NomadFormatters.celsius($0) } ?? "Estimating"
        return "\(minimum) / \(maximum)"
    }
}

// MARK: - Data Guard helpers

extension MeteredUsageSnapshot {
    /// Bytes counted against the cap for the active billing period.
    var displayedUsedBytes: UInt64 {
        billingPeriod == .session ? sessionTotalBytes : periodTotalBytes
    }

    /// Cap status as a health level: ready below 80 %, caution from 80 %, attention at the cap.
    var usageLevel: HealthLevel {
        if isCapReached {
            return .attention
        }

        guard let usageFraction else {
            return .ready
        }

        if usageFraction >= 1 {
            return .attention
        }

        return usageFraction >= 0.8 ? .caution : .ready
    }
}

// MARK: - Heads-up

struct GlanceHeadsUpRowPresentation: Equatable, Identifiable {
    let kind: DashboardInsightKind
    let symbolName: String
    let title: String
    let detail: String?
    /// Severity as a health level so the row reuses the shared `HealthLevel.tint`:
    /// attention is coral, caution is sand and info is teal.
    let level: HealthLevel
    let relatedCard: DashboardCardID

    var id: DashboardInsightKind {
        kind
    }

    var accessibilityHint: String {
        "Shows the \(relatedCard.displayTitle) card"
    }

    init(insight: DashboardInsight) {
        kind = insight.kind
        symbolName = insight.symbolName
        title = insight.title
        detail = insight.detail
        level = Self.level(for: insight.severity)
        relatedCard = insight.relatedCard
    }

    static func level(for severity: DashboardInsightSeverity) -> HealthLevel {
        switch severity {
        case .attention: .attention
        case .caution: .caution
        case .info: .ready
        }
    }
}

extension DashboardCardID {
    /// The title shown on the card itself.
    var displayTitle: String {
        switch self {
        case .connectivity: "Connectivity"
        case .meteredData: "Data Guard"
        case .power: "Power"
        case .timeTracking: "Time Tracking"
        case .travelContext: "Travel Context"
        case .localInfo: "Local Info"
        case .fuelPrices: "Fuel Prices"
        case .emergencyCare: "Emergency Care"
        case .travelAlerts: "Travel Alerts"
        case .weather: "Weather"
        }
    }
}

private extension HealthLevel {
    /// `.unavailable` means "no reading yet", which is neutral rather than a status.
    var statusOrNil: HealthLevel? {
        self == .unavailable ? nil : self
    }
}
