import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
public final class NomadLifeController: ObservableObject {
    @Published public private(set) var entries: [NomadLifeConnectionDiaryEntry] = []
    @Published public private(set) var isLoadingDiary = true
    @Published public var preferences: NomadLifePreferences {
        didSet { savePreferences() }
    }

    @Published public private(set) var timeZones: NomadLifeTimeZonePresentation
    @Published public private(set) var pendingAlerts: [NomadLifeQuietAlert] = []

    private let diaryStore: NomadLifeDiaryStore
    private let preferencesKey: String
    private let defaults: UserDefaults
    private var activeCluster: Cluster?
    private var previousInternetState: InternetReachabilityState?
    private var previousVPNState: Bool?
    private var disconnectedSince: Date?
    private var alertDates: [NomadLifeQuietAlertKind: Date] = [:]
    private var lastVenueSuggestionAt: Date = .distantPast
    private var persistTask: Task<Void, Never>?
    private var samplingState = NomadLifeSamplingState()
    private var weakChargingSince: Date?
    private var lastDiaryInternetState: InternetReachabilityState?
    private var lastAlertConnectivityAt: Date?
    private var lastAlertPowerAt: Date?
    private var venueSearchTask: Task<Void, Never>?
    private var diaryLoadTask: Task<Void, Never>?

    public init(storageURL: URL, preferencesKey: String, defaults: UserDefaults = .standard) {
        diaryStore = NomadLifeDiaryStore(url: storageURL)
        self.preferencesKey = preferencesKey
        self.defaults = defaults
        let loadedPreferences = Self.loadPreferences(defaults: defaults, key: preferencesKey)
        preferences = loadedPreferences
        entries = []
        timeZones = NomadLifeTimeZonePresentation(homeTimeZoneIdentifier: loadedPreferences.homeTimeZoneIdentifier, currentTimeZoneIdentifier: TimeZone.current.identifier)
        diaryLoadTask = Task { [weak self, diaryStore] in
            let loaded = await diaryStore.load()
            guard let self else { return }
            guard entries.isEmpty else { isLoadingDiary = false
                return
            }
            entries = loaded.sorted { $0.endedAt > $1.endedAt }
            isLoadingDiary = false
        }
    }

    public func ingest(snapshot: DashboardSnapshot, allowsVenueLookup: Bool = true) {
        let now = Date.now
        timeZones = NomadLifeTimeZonePresentation(homeTimeZoneIdentifier: preferences.homeTimeZoneIdentifier, currentTimeZoneIdentifier: snapshot.travelContext.timeZoneIdentifier, date: now)
        evaluateAlerts(snapshot: snapshot, now: now)
        guard !isLoadingDiary else { return }
        guard preferences.isAutomaticCollectionEnabled else { activeCluster = nil
            venueSearchTask?.cancel()
            return
        }
        guard let location = snapshot.travelContext.deviceLocation,
              let latitude = location.latitude, let longitude = location.longitude,
              now.timeIntervalSince(location.fetchedAt) < 900,
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return }
        // Only the authorized device-location projection participates; IP and VPN never form a venue.
        let connectivityDate = snapshot.network.connectivity.lastCheckedAt
        let latencyDate = snapshot.network.latency?.collectedAt
        let acceptance = samplingState.accept(connectivity: connectivityDate, latency: latencyDate)
        guard acceptance.accepted else { return }
        ingestDeviceLocation(latitude: latitude, longitude: longitude, locality: location.city, latency: acceptance.hasNewLatency ? snapshot.network.latency?.milliseconds : nil, internet: snapshot.network.connectivity.internetState, allowsVenueLookup: allowsVenueLookup, now: now)
    }

    public func updateEntry(id: UUID, name: String?, note: String?, confirmVenue: Bool = false) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        if confirmVenue {
            entries[index].name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        entries[index].note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].confidence = entries[index].name?.isEmpty == false ? .confirmed : .suggested
        persistEntries()
    }

    public func confirmSuggestion(id: UUID) {
        updateEntry(id: id, name: entries.first(where: { $0.id == id })?.suggestedName, note: entries.first(where: { $0.id == id })?.note, confirmVenue: true)
    }

    public func consumeAlerts() -> [NomadLifeQuietAlert] {
        defer { pendingAlerts = [] }
        return pendingAlerts
    }

    private func ingestDeviceLocation(latitude: Double, longitude: Double, locality: String?, latency: Double?, internet: InternetReachabilityState, allowsVenueLookup: Bool, now: Date) {
        if var cluster = activeCluster, cluster.distance(to: latitude, longitude) < 180 {
            let disconnected = internet == .offline && lastDiaryInternetState != .offline
            cluster.add(now: now, latency: latency, disconnected: disconnected)
            activeCluster = cluster
            if cluster.sampleCount >= 3, now.timeIntervalSince(cluster.startedAt) >= 300 {
                upsert(cluster: cluster, locality: locality)
                if allowsVenueLookup, internet == .online, now.timeIntervalSince(lastVenueSuggestionAt) > 1_800 {
                    lastVenueSuggestionAt = now
                    suggestVenue(for: cluster, locality: locality)
                }
            }
        } else {
            activeCluster = Cluster(latitude: latitude, longitude: longitude, startedAt: now, latency: latency, disconnected: internet == .offline)
        }
        lastDiaryInternetState = internet
    }

    private func upsert(cluster: Cluster, locality: String?) {
        let suggested = locality.map { "Near \($0)" } ?? "Near this location"
        let entry = NomadLifeConnectionDiaryEntry(startedAt: cluster.startedAt, endedAt: cluster.lastSeenAt, latitude: cluster.latitude, longitude: cluster.longitude, suggestedName: suggested, sampleCount: cluster.sampleCount, averageLatencyMilliseconds: cluster.averageLatency, disconnectCount: cluster.disconnectCount)
        if let index = entries.firstIndex(where: { $0.startedAt == cluster.startedAt }) {
            entries[index].endedAt = entry.endedAt
            entries[index].latitude = entry.latitude
            entries[index].longitude = entry.longitude
            entries[index].sampleCount = entry.sampleCount
            entries[index].averageLatencyMilliseconds = entry.averageLatencyMilliseconds
            entries[index].disconnectCount = entry.disconnectCount
            // A MapKit suggestion is more specific than the locality fallback; retain it until the user confirms or edits.
            if entries[index].confidence == .suggested,
               entries[index].suggestedName == "Near this location" || entries[index].suggestedName == suggested
            {
                entries[index].suggestedName = suggested
            }
        } else {
            entries.insert(entry, at: 0)
        }
        persistEntries()
    }

    private func suggestVenue(for cluster: Cluster, locality: String?) {
        let startedAt = cluster.startedAt
        let coordinate = CLLocationCoordinate2D(latitude: cluster.latitude, longitude: cluster.longitude)
        venueSearchTask?.cancel()
        venueSearchTask = Task { [weak self] in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "coworking cafe"
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first,
                  !Task.isCancelled,
                  let name = item.name, !name.isEmpty,
                  let self, preferences.isAutomaticCollectionEnabled, let index = entries.firstIndex(where: { $0.startedAt == startedAt }), entries[index].confidence == .suggested
            else { return }
            entries[index].suggestedName = "Near \(name)"
            persistEntries()
        }
    }

    private func evaluateAlerts(snapshot: DashboardSnapshot, now: Date) {
        let state = snapshot.network.connectivity.internetState
        guard snapshot.network.connectivity.lastCheckedAt != lastAlertConnectivityAt || snapshot.power.snapshot?.collectedAt != lastAlertPowerAt else { return }
        lastAlertConnectivityAt = snapshot.network.connectivity.lastCheckedAt
        lastAlertPowerAt = snapshot.power.snapshot?.collectedAt
        guard state != .checking else { return }
        if state == .offline {
            disconnectedSince = disconnectedSince ?? now
        } else if previousInternetState == .offline {
            let sustained = disconnectedSince.map { now.timeIntervalSince($0) >= 90 } ?? false
            disconnectedSince = nil
            if sustained {
                enqueue(.recovered, now: now)
            }
        }
        if state == .offline, let since = disconnectedSince, now.timeIntervalSince(since) >= 90 {
            enqueue(.disconnected, now: now)
        }
        if let vpn = snapshot.travelContext.vpn?.isActive {
            if let previousVPNState, previousVPNState != vpn {
                enqueue(.vpnChanged, now: now)
            }
            previousVPNState = vpn
        }
        if let power = snapshot.power.snapshot, power.state == .charging, (power.adapterWatts ?? .infinity) < 12, (power.chargePercent ?? 1) < 0.20 {
            weakChargingSince = weakChargingSince ?? now
            if let since = weakChargingSince, now.timeIntervalSince(since) >= 300 {
                enqueue(.weakCharging, now: now)
            }
        } else {
            weakChargingSince = nil
        }
        previousInternetState = state
    }

    private func enqueue(_ kind: NomadLifeQuietAlertKind, now: Date) {
        guard preferences.areQuietAlertsEnabled, !inQuietHours(now), now.timeIntervalSince(alertDates[kind] ?? .distantPast) > 1_800 else { return }
        alertDates[kind] = now
        let text = switch kind { case .disconnected: ("Connection interrupted", "Nomad will keep your dashboard ready when service returns.")
        case .recovered: ("Connection restored", "Your dashboard is online again.")
        case .vpnChanged: ("VPN connection changed", "Your network privacy connection changed.")
        case .weakCharging: ("Charging may be weak", "Battery remains low while the connected charger reports limited power.") }
        pendingAlerts.append(NomadLifeQuietAlert(kind: kind, title: text.0, body: text.1))
    }

    private func inQuietHours(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        let start = preferences.quietHoursStart
        let end = preferences.quietHoursEnd
        return start == end ? false : (start < end ? hour >= start && hour < end : hour >= start || hour < end)
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: preferencesKey)
        }
    }

    private func persistEntries() {
        persistTask?.cancel()
        let entries = entries
        let store = diaryStore
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await store.save(entries)
            self?.persistTask = nil
        }
    }

    public func flush() async {
        if isLoadingDiary {
            await diaryLoadTask?.value
        }
        guard !isLoadingDiary else { return }
        persistTask?.cancel()
        persistTask = nil
        try? await diaryStore.save(entries)
    }

    private static func loadPreferences(defaults: UserDefaults, key: String) -> NomadLifePreferences {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(NomadLifePreferences.self, from: data) else { return NomadLifePreferences() }
        return value
    }
}

private struct Cluster {
    var latitude: Double
    var longitude: Double
    let startedAt: Date
    var lastSeenAt: Date
    var sampleCount: Int
    var latencyTotal: Double
    var latencyCount: Int
    var disconnectCount: Int
    init(latitude: Double, longitude: Double, startedAt: Date, latency: Double?, disconnected: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.startedAt = startedAt
        lastSeenAt = startedAt
        sampleCount = 1
        latencyTotal = latency ?? 0
        latencyCount = latency == nil ? 0 : 1
        disconnectCount = disconnected ? 1 : 0
    }

    mutating func add(now: Date, latency: Double?, disconnected: Bool) {
        lastSeenAt = now
        sampleCount += 1
        if let latency {
            latencyTotal += latency
            latencyCount += 1
        }
        if disconnected {
            disconnectCount += 1
        }
    }

    var averageLatency: Double? {
        latencyCount == 0 ? nil : latencyTotal / Double(latencyCount)
    }

    func distance(to latitude: Double, _ longitude: Double) -> Double {
        let dx = (self.latitude - latitude) * 111_000
        let dy = (self.longitude - longitude) * 111_000 * cos(self.latitude * .pi / 180)
        return hypot(dx, dy)
    }
}
