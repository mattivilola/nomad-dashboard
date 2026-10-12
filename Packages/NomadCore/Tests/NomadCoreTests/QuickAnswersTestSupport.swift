import Foundation
import NomadCore

/// Builds dashboard snapshots for the Siri, Shortcuts and widget tests.
enum QuickAnswersFixtures {
    static let locale = Locale(identifier: "en_US")

    static let helsinki = (latitude: 60.1699, longitude: 24.9384, timeZone: "Europe/Helsinki")

    static func location(
        city: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timeZone: String? = nil
    ) -> IPLocationSnapshot {
        IPLocationSnapshot(
            city: city,
            region: nil,
            country: country,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            provider: "test",
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    /// A healthy, online snapshot (the preview) moved to the given places.
    static func snapshot(
        device: IPLocationSnapshot? = nil,
        ip: IPLocationSnapshot? = nil,
        publicIP: String? = nil,
        offline: Bool = false,
        metered: MeteredUsageSnapshot = .disabled
    ) -> DashboardSnapshot {
        let base = DashboardSnapshot.preview
        let network = offline
            ? NetworkSectionSnapshot(
                throughput: base.network.throughput,
                connectivity: ConnectivitySnapshot(pathAvailable: false, internetState: .offline, lastCheckedAt: nil),
                latency: base.network.latency,
                downloadHistory: [],
                uploadHistory: [],
                latencyHistory: []
            )
            : base.network

        return DashboardSnapshot(
            network: network,
            power: base.power,
            travelContext: TravelContextSnapshot(
                wifi: nil,
                vpn: nil,
                timeZoneIdentifier: "UTC",
                deviceLocation: device,
                publicIP: publicIP.map { PublicIPSnapshot(address: $0, provider: "test", fetchedAt: .now) },
                location: ip
            ),
            weather: nil,
            appState: base.appState,
            meteredData: metered
        )
    }

    static func morocco() -> DashboardSnapshot {
        snapshot(device: location(city: "Rabat", country: "Morocco", countryCode: "MA", latitude: 34.02, longitude: -6.84, timeZone: "Africa/Casablanca"))
    }

    static func helsinkiSnapshot() -> DashboardSnapshot {
        snapshot(device: location(
            city: "Helsinki",
            country: "Finland",
            countryCode: "FI",
            latitude: helsinki.latitude,
            longitude: helsinki.longitude,
            timeZone: helsinki.timeZone
        ))
    }

    /// A data cap that has been reached: the highest-priority heads-up there is.
    static func capReachedMetered() -> MeteredUsageSnapshot {
        MeteredUsageSnapshot(
            isFeatureEnabled: true,
            isMonitoringActive: true,
            networkKey: "wifi:Hotspot",
            networkDisplayName: "Hotspot",
            meteredInterfaceName: "en0",
            sessionStartedAt: nil,
            sessionBytesReceived: 6_000_000_000,
            sessionBytesSent: 0,
            periodBytesReceived: 6_000_000_000,
            periodBytesSent: 0,
            capBytes: 5_000_000_000,
            usageFraction: nil,
            isCapReached: true,
            billingPeriod: .session,
            manualSessionEnabled: false,
            isKnownMeteredNetwork: true,
            networkNameSource: .liveSSID,
            isWiFiConnected: true,
            needsLocationForWiFiNames: false,
            statusMessage: nil,
            capAlertSignal: nil
        )
    }

    static func mission(
        _ id: String,
        sending: String,
        host: String,
        name: String,
        city: String?,
        latitude: Double,
        longitude: Double,
        approximate: Bool = true
    ) -> DiplomaticMission {
        DiplomaticMission(
            id: id,
            sendingCountry: sending,
            hostCountry: host,
            kind: .embassy,
            name: name,
            city: city,
            latitude: latitude,
            longitude: longitude,
            isApproximateLocation: approximate
        )
    }

    static let missionIndex = DiplomaticMissionIndex(missions: [
        mission("FI-RAB", sending: "FI", host: "MA", name: "Embassy of Finland in Rabat", city: "Rabat", latitude: 34.05, longitude: -6.84, approximate: false),
        mission("SE-MAD", sending: "SE", host: "ES", name: "Embassy of Sweden in Madrid", city: "Madrid", latitude: 40.4, longitude: -3.7),
        mission("SE-RAB", sending: "SE", host: "MA", name: "Embassy of Sweden", city: "Rabat", latitude: 34.02, longitude: -6.84)
    ])

    /// 21 June 2026, 12:00 in Helsinki.
    static var helsinkiMidday: Date {
        date(2_026, 6, 21, 12, 0, timeZone: helsinki.timeZone)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, timeZone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
