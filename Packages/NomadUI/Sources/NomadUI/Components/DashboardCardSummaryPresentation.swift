import Foundation
import NomadCore

/// The one-line summary a collapsed card shows next to its title ("28 ms · 96 ↓ 19 ↑").
/// It leads with what matters and never repeats the status badge shown next to it.
struct DashboardCardSummaryPresentation: Equatable {
    let text: String
    /// Longer wording for hover and VoiceOver; the same as `text` unless the summary is shortened.
    let help: String

    init(
        cardID: DashboardCardID,
        snapshot: DashboardSnapshot,
        settings: AppSettings,
        travelAlertPreferences: TravelAlertPreferences,
        timeTracking: TimeTrackingDashboardState,
        visitedCountryDays: [VisitedCountryDay] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        var help: String?
        let text: String
        switch cardID {
        case .connectivity:
            text = Self.connectivity(snapshot.network)
        case .meteredData:
            text = Self.meteredData(snapshot.meteredData, now: now, calendar: calendar)
        case .power:
            text = Self.power(snapshot.power.snapshot)
        case .timeTracking:
            text = timeTracking.isEnabled
                ? "Pending \(TimeTrackingDurationFormatting.text(timeTracking.todaySummary.unallocatedDuration))"
                : "Off"
        case .travelContext:
            text = Self.travelContext(snapshot)
        case .stays:
            let stays = StaysCardPresentation(
                settings: settings,
                countryDays: visitedCountryDays,
                currentCountryCode: snapshot.currentCountryCode,
                now: now,
                calendar: calendar
            )
            (text, help) = (stays.summary, stays.summaryHelp)
        case .localInfo:
            text = Self.localInfo(settings: settings, snapshot: snapshot, now: now, calendar: calendar)
        case .fuelPrices:
            text = Self.fuel(settings: settings, snapshot: snapshot)
        case .emergencyCare:
            (text, help) = Self.emergency(settings: settings, snapshot: snapshot)
        case .embassy:
            let embassy = EmbassyCardPresentation(settings: settings, snapshot: snapshot)
            (text, help) = (embassy.summary, embassy.summaryHelp)
        case .travelAlerts:
            text = Self.travelAlerts(preferences: travelAlertPreferences, snapshot: snapshot)
        case .weather:
            text = Self.weather(settings: settings, snapshot: snapshot)
        }

        self.text = text
        self.help = help ?? text
    }

    private static func connectivity(_ network: NetworkSectionSnapshot) -> String {
        var parts: [String] = []

        if let latency = network.latency?.milliseconds {
            parts.append(NomadFormatters.latency(latency))
        }

        if let throughput = network.throughput {
            parts.append(String(format: "%.0f ↓ %.0f ↑", throughput.downloadMegabitsPerSecond, throughput.uploadMegabitsPerSecond))
        }

        return parts.isEmpty ? "Collecting" : parts.joined(separator: " · ")
    }

    private static func meteredData(_ metered: MeteredUsageSnapshot, now: Date, calendar: Calendar) -> String {
        guard metered.isFeatureEnabled else {
            return "Off"
        }

        guard metered.isMonitoringActive else {
            return "Not monitoring"
        }

        return DataGuardCardPresentation(snapshot: metered, now: now, calendar: calendar).leadText
    }

    private static func power(_ snapshot: PowerSnapshot?) -> String {
        guard let percent = snapshot?.chargePercent else {
            return "Estimating"
        }

        let metrics = PowerMetricsPresentation(snapshot: snapshot)
        var parts = [NomadFormatters.percentage(percent * 100)]

        if metrics.timeLeftValue != "Estimating" {
            parts.append(metrics.timeLeftTitle == "To Full" ? "\(metrics.timeLeftValue) to full" : metrics.timeLeftValue)
        }

        return parts.joined(separator: " · ")
    }

    /// The badge already says whether the VPN is on, so the line gives the IP and the Wi-Fi name.
    private static func travelContext(_ snapshot: DashboardSnapshot) -> String {
        [
            snapshot.travelContext.publicIP?.address ?? "IP unavailable",
            snapshot.travelContext.wifi?.ssid
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    /// The badge carries the level, so the line says where the alerts apply.
    private static func travelAlerts(preferences: TravelAlertPreferences, snapshot: DashboardSnapshot) -> String {
        guard preferences.enabledKinds.isEmpty == false else {
            return "Off"
        }

        guard let alerts = snapshot.travelAlerts, let country = alerts.primaryCountryName else {
            return "Checking alerts"
        }

        let neighbours = max(alerts.coverageCountryCodes.count - 1, 0)
        return neighbours > 0 ? "\(country) + \(neighbours) nearby" : country
    }

    private static func localInfo(
        settings: AppSettings,
        snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar
    ) -> String {
        guard settings.localInfoEnabled else {
            return "Off"
        }

        guard let localInfo = snapshot.localInfo else {
            return "Checking"
        }

        let status = localInfo.publicHolidayStatus
        switch status.state {
        case .current:
            return "Holiday today"
        case .tomorrow:
            return "Holiday tomorrow"
        case .upcoming:
            return status.nextPeriod.map { "Holiday \(LocalInfoSectionPresentation.formattedDay($0.startDate))" } ?? "Holiday soon"
        case .unavailable, .unsupported:
            return LocalInfoSectionPresentation(
                settings: settings,
                snapshot: snapshot,
                locationStatusDetail: nil,
                now: now,
                calendar: calendar
            ).subtitle
        }
    }

    private static func fuel(settings: AppSettings, snapshot: DashboardSnapshot) -> String {
        let presentation = FuelPricesSectionPresentation(settings: settings, snapshot: snapshot, locationStatusDetail: nil)

        guard settings.fuelPricesEnabled else {
            return "Off"
        }

        guard let fuelPrices = snapshot.fuelPrices,
              fuelPrices.status == .ready,
              let station = fuelPrices.diesel ?? fuelPrices.gasoline
        else {
            return presentation.subtitle
        }

        let price = FuelPriceFormatting.price(station.pricePerLiter, currencyCode: station.currencyCode)
        return "\(station.fuelType.displayName) \(price) · \(NomadFormatters.kilometers(station.distanceKilometers))"
    }

    /// Number first, then how far the nearest hospital is; the hospital's name goes to the help.
    private static func emergency(settings: AppSettings, snapshot: DashboardSnapshot) -> (text: String, help: String) {
        guard settings.emergencyCareEnabled else {
            return ("Off", "Off")
        }

        let number = EmergencyNumberDirectory.numbers(forCountryCode: snapshot.currentCountryCode)?.general

        guard let emergencyCare = snapshot.emergencyCare,
              emergencyCare.status == .ready,
              let nearest = emergencyCare.hospitals.min(by: { $0.distanceKilometers < $1.distanceKilometers })
        else {
            let state = number ?? EmergencyCareSectionPresentation(settings: settings, snapshot: snapshot, locationStatusDetail: nil).subtitle
            return (state, state)
        }

        let distance = NomadFormatters.kilometers(nearest.distanceKilometers)
        let help = ["Nearest: \(nearest.name), \(distance)", number.map { "Emergency \($0)" }]
            .compactMap(\.self)
            .joined(separator: " · ")

        if let number {
            return ("\(number) · nearest \(distance)", help)
        }

        return ("Nearest \(distance) · \(nearest.name)", help)
    }

    private static func weather(settings: AppSettings, snapshot: DashboardSnapshot) -> String {
        guard let weather = snapshot.weather else {
            return WeatherSectionPresentation(
                settings: settings,
                snapshot: snapshot,
                weatherAvailabilityExplanation: nil,
                locationStatusDetail: nil
            ).subtitle
        }

        return [
            weather.currentTemperatureCelsius.map { NomadFormatters.celsius($0) },
            weather.conditionDescription
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }
}
