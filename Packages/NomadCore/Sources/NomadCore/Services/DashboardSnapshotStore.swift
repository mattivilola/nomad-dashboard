import Combine
import CoreLocation
import Foundation
import OSLog

@MainActor
public final class DashboardSnapshotStore: ObservableObject {
    private static let minimumBackgroundRefreshIntervalSeconds: TimeInterval = 60
    private static let minimumBackgroundSlowRefreshIntervalSeconds: TimeInterval = 900
    private static let maximumDeviceLocationAge: TimeInterval = 15 * 60

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
        category: "TravelAlerts"
    )
    private static let fuelLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
        category: "FuelPrices"
    )

    @Published public private(set) var snapshot: DashboardSnapshot
    @Published public private(set) var visitedPlaces: [VisitedPlace] = []
    @Published public private(set) var visitedPlaceEvents: [VisitedPlaceEvent] = []
    @Published public private(set) var visitedCountryDays: [VisitedCountryDay] = []
    @Published public private(set) var refreshActivity: DashboardRefreshActivity = .idle

    public let settingsStore: AppSettingsStore

    private let dependencies: DashboardDependencies
    private let analytics: AppAnalytics?
    private var refreshTask: Task<Void, Never>?
    private var settingsObservation: AnyCancellable?
    private var appliedSettings: AppSettings
    private var currentLocation: CLLocation?
    private var currentCoordinate: CLLocationCoordinate2D?
    private var lastSlowRefresh: Date?
    private var localRefreshTask: Task<Void, Never>?
    private var externalRefreshTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Never>?
    private var cacheSaveTask: Task<Void, Never>?
    private var settingsRefreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var activeManualRequests = 0
    private var activeAutomaticSlowRequests = 0
    private var externalRefreshIsManual = false
    private var lastLatencyCheck: Date?
    private var failureCounts: [DashboardDataSection: Int] = [:]
    private var retryAfter: [DashboardDataSection: Date] = [:]
    private var cachedLocationKey: String?
    private var automaticPlaceCollectionEnabled = false
    @Published public private(set) var sectionActivity: [DashboardDataSection: DashboardSectionActivity] = [:]
    @Published public private(set) var resourcePolicy = DashboardResourcePolicy.normal
    @Published public private(set) var offlineSavedAt: Date?
    @Published public private(set) var offlineCacheError: String?
    private var dashboardInterfaceActive = true

    public init(
        settingsStore: AppSettingsStore,
        dependencies: DashboardDependencies,
        initialSnapshot: DashboardSnapshot = .placeholder,
        analytics: AppAnalytics? = nil
    ) {
        self.settingsStore = settingsStore
        self.dependencies = dependencies
        self.analytics = analytics
        snapshot = initialSnapshot
        appliedSettings = settingsStore.settings
        snapshot = snapshot.replacingTravelAlerts(
            synchronizedTravelAlertsSnapshot(
                previous: initialSnapshot.travelAlerts,
                settings: settingsStore.settings,
                locationSnapshot: initialSnapshot.travelContext.location
            )
        )
        configureSettingsObservation()
        initializationTask = Task { [weak self] in
            await self?.applyInitialSettings()
        }
    }

    deinit {
        refreshTask?.cancel()
        externalRefreshTask?.cancel()
        localRefreshTask?.cancel()
        cacheSaveTask?.cancel()
        settingsRefreshTask?.cancel()
    }

    public func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.initializationTask?.value
            var initial = true
            while !Task.isCancelled {
                guard let self else { return }
                updateResourcePolicy()
                _ = scheduleExternalRefresh(force: false, startup: initial)
                await refreshLocalMetrics()
                initial = false
                do { try await Task.sleep(for: .seconds(effectiveRefreshInterval(for: settingsStore.settings))) }
                catch { return }
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        localRefreshTask?.cancel()
        localRefreshTask = nil
        invalidateExternalRefresh()
        Task { await flushPersistence() }
    }

    public func flushPersistence() async {
        await initializationTask?.value
        if let flushable = dependencies.historyStore as? any MetricHistoryFlushable {
            try? await flushable.flush()
        }
        await saveOfflineContent()
    }

    public func setWeatherCoordinate(_ coordinate: CLLocationCoordinate2D?) {
        currentCoordinate = coordinate
    }

    public func setAutomaticPlaceCollectionEnabled(_ enabled: Bool) {
        guard automaticPlaceCollectionEnabled != enabled else { return }
        automaticPlaceCollectionEnabled = enabled
        lastSlowRefresh = nil
    }

    public func setCurrentLocation(_ location: CLLocation?) {
        let moved = currentLocation.map { previous in location.map { $0.distance(from: previous) > 1_000 } ?? true } ?? (location != nil)
        currentLocation = location
        currentCoordinate = location?.coordinate
        if moved {
            invalidateExternalRefresh()
            lastSlowRefresh = nil
            failureCounts = [:]
            retryAfter = [:]
            if let location, let cachedLocationKey, cachedLocationKey != locationKey(location.coordinate) {
                clearLocationDependentContent()
            }
        }
    }

    public func setDashboardInterfaceActive(_ isActive: Bool) {
        guard dashboardInterfaceActive != isActive else { return }
        dashboardInterfaceActive = isActive
        if isActive {
            Task { [weak self] in await self?.refresh() }
        } else {
            Task { [weak self] in await self?.flushPersistence() }
        }
    }

    public func setCountryDayOverride(_ override: VisitedCountryDayOverride) async throws {
        guard let store = dependencies.visitedCountryDaysStore as? any EditableVisitedCountryDaysStore else {
            throw CocoaError(.featureUnsupported)
        }
        try await store.setOverride(override)
        await loadVisitedCountryDays()
    }

    public func restoreCountryDay(_ day: VisitedCountryDayStamp) async throws {
        guard let store = dependencies.visitedCountryDaysStore as? any EditableVisitedCountryDaysStore else {
            throw CocoaError(.featureUnsupported)
        }
        try await store.restoreObservation(for: day)
        await loadVisitedCountryDays()
    }

    public var visitedPlaceSummary: VisitedPlaceSummary {
        visitedPlaces.visitedPlaceSummary
    }

    public var visitedCountryDayYears: [Int] {
        visitedCountryDays.availableYears
    }

    public var visitedPlaceEventYears: [Int] {
        visitedPlaceEvents.availableYears
    }

    public func visitedPlaceTravelStops(for year: Int) -> [VisitedPlaceTravelStop] {
        visitedPlaceEvents.travelStops(for: year)
    }

    public func visitedCountryDaySummary(for year: Int) -> VisitedCountryDayYearSummary? {
        visitedCountryDays.yearSummary(for: year)
    }

    public func clearVisitedPlaces() {
        Task { [weak self] in
            guard let self else {
                return
            }

            try? await dependencies.visitedPlacesStore.reset()
            try? await dependencies.visitedPlaceEventsStore.reset()
            try? await dependencies.visitedCountryDaysStore.reset()
            await loadVisitedPlaces()
            await loadVisitedPlaceEvents()
            await loadVisitedCountryDays()
        }
    }

    public func checkForUpdates() {
        Task {
            await dependencies.updateCoordinator.checkForUpdates()
            await refresh(manual: true)
        }
    }

    /// Explicit refresh waits for completion; the periodic local sampler never waits for remote cards.
    public func refresh(manual: Bool = false) async {
        let showsSlowActivity = !manual && shouldRefreshSlowMetrics(now: Date(), interval: effectiveSlowRefreshInterval(for: settingsStore.settings))
        if manual {
            activeManualRequests += 1
        }
        if showsSlowActivity {
            activeAutomaticSlowRequests += 1
        }
        updateRefreshActivity()
        defer {
            if manual {
                activeManualRequests -= 1
            }
            if showsSlowActivity {
                activeAutomaticSlowRequests -= 1
            }
            updateRefreshActivity()
        }
        await initializationTask?.value
        guard !Task.isCancelled else { return }
        if let localRefreshTask {
            await localRefreshTask.value
            await externalRefreshTask?.value
            return
        }
        updateResourcePolicy()
        let external = scheduleExternalRefresh(force: manual)
        updateRefreshActivity()
        await refreshLocalMetrics()
        await external?.value
    }

    public func refresh(section: DashboardDataSection) async {
        await initializationTask?.value
        // A click never creates overlapping calls to the same source.
        if let externalRefreshTask {
            await externalRefreshTask.value
        }
        guard !Task.isCancelled else { return }
        activeManualRequests += 1
        defer { activeManualRequests -= 1
            updateRefreshActivity()
        }
        updateResourcePolicy()
        let task = scheduleExternalRefresh(force: true, only: section)
        updateRefreshActivity()
        await task?.value
    }

    private func updateRefreshActivity() {
        let next: DashboardRefreshActivity = if activeManualRequests > 0 || (externalRefreshTask != nil && externalRefreshIsManual) {
            .manualInProgress
        } else if externalRefreshTask != nil || activeAutomaticSlowRequests > 0 {
            .slowAutomaticInProgress
        } else {
            .idle
        }
        if refreshActivity != next {
            refreshActivity = next
        }
    }

    private func updateResourcePolicy() {
        var conditions = dependencies.resourceConditions.currentConditions()
        if snapshot.network.connectivity.internetState == .offline {
            conditions.pathAvailable = false
        }
        let previous = resourcePolicy
        let next = DashboardResourcePolicy(mode: settingsStore.settings.dataUsageMode, conditions: conditions)
        if previous != next {
            resourcePolicy = next
        }
        if previous.isOffline, !next.isOffline {
            lastSlowRefresh = nil
            retryAfter = [:]
        }
    }

    private func mutateSnapshot(_ mutation: (inout DashboardSnapshotDraft) -> Void) {
        var draft = DashboardSnapshotDraft(snapshot)
        mutation(&draft)
        let next = draft.snapshot
        if snapshot != next {
            snapshot = next
        }
    }

    private func refreshLocalMetrics() async {
        if let localRefreshTask {
            await localRefreshTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await collectLocalMetrics()
        }
        localRefreshTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        localRefreshTask = nil
    }

    private enum LocalReading: Sendable {
        case throughput(NetworkThroughputSample?), connectivity(ConnectivitySnapshot), power(PowerSnapshot?)
        case wifi(WiFiSnapshot?), vpn(VPNStatusSnapshot), latency(LatencySample?)
    }

    private func collectLocalMetrics() async {
        let dependencies = dependencies
        let now = Date()
        let shouldProbeLatency = !resourcePolicy.isOffline && !resourcePolicy.reducesBackgroundWork && dashboardInterfaceActive
            && (lastLatencyCheck.map { now.timeIntervalSince($0) >= 60 } ?? true)
        if shouldProbeLatency {
            lastLatencyCheck = now
        }
        await withTaskGroup(of: LocalReading.self) { group in
            group.addTask { await .throughput(dependencies.throughputMonitor.currentSample()) }
            group.addTask { await .connectivity(dependencies.connectivityMonitor.currentSnapshot()) }
            group.addTask { await .power(dependencies.powerMonitor.currentSnapshot()) }
            group.addTask { await .wifi(dependencies.wifiMonitor.currentSnapshot()) }
            group.addTask { await .vpn(dependencies.vpnStatusProvider.currentStatus()) }
            if shouldProbeLatency {
                group.addTask { await .latency(dependencies.latencyProbe.currentSample()) }
            }
            for await reading in group {
                guard !Task.isCancelled else { group.cancelAll()
                    return
                }
                switch reading {
                case let .throughput(sample):
                    if let sample {
                        mutateSnapshot { draft in
                            let old = draft.network
                            draft.network = NetworkSectionSnapshot(
                                throughput: sample,
                                connectivity: old.connectivity,
                                latency: old.latency,
                                downloadHistory: old.downloadHistory,
                                uploadHistory: old.uploadHistory,
                                latencyHistory: old.latencyHistory
                            )
                        }
                        await appendHistory(from: sample)
                    }
                case let .connectivity(value):
                    mutateSnapshot { draft in
                        let old = draft.network
                        draft.network = NetworkSectionSnapshot(
                            throughput: old.throughput,
                            connectivity: value,
                            latency: old.latency,
                            downloadHistory: old.downloadHistory,
                            uploadHistory: old.uploadHistory,
                            latencyHistory: old.latencyHistory
                        )
                    }
                    updateResourcePolicy()
                case let .power(value):
                    if let value {
                        mutateSnapshot { $0.power = PowerSectionSnapshot(snapshot: value, chargeHistory: $0.power.chargeHistory, dischargeHistory: $0.power.dischargeHistory) }
                        await appendHistory(from: value)
                    }
                case let .wifi(value):
                    mutateSnapshot { draft in
                        let old = draft.travelContext
                        draft.travelContext = TravelContextSnapshot(
                            wifi: value,
                            vpn: old.vpn,
                            timeZoneIdentifier: old.timeZoneIdentifier,
                            deviceLocation: old.deviceLocation,
                            publicIP: old.publicIP,
                            location: old.location
                        )
                    }
                case let .vpn(value):
                    mutateSnapshot { draft in
                        let old = draft.travelContext
                        draft.travelContext = TravelContextSnapshot(
                            wifi: old.wifi,
                            vpn: value,
                            timeZoneIdentifier: old.timeZoneIdentifier,
                            deviceLocation: old.deviceLocation,
                            publicIP: old.publicIP,
                            location: old.location
                        )
                    }
                case let .latency(value):
                    if let value {
                        mutateSnapshot { draft in
                            let old = draft.network
                            draft.network = NetworkSectionSnapshot(
                                throughput: old.throughput,
                                connectivity: old.connectivity,
                                latency: value,
                                downloadHistory: old.downloadHistory,
                                uploadHistory: old.uploadHistory,
                                latencyHistory: old.latencyHistory
                            )
                        }
                        try? await dependencies.historyStore.append(MetricPoint(timestamp: value.collectedAt, value: value.milliseconds), to: .latencyMilliseconds)
                    }
                }
            }
        }
        guard !Task.isCancelled else { return }
        let history = await projectedDashboardHistory((try? dependencies.historyStore.loadAll()) ?? [:])
        let update = await dependencies.updateCoordinator.currentState()
        mutateSnapshot { draft in
            let old = draft.network
            draft.network = NetworkSectionSnapshot(
                throughput: old.throughput,
                connectivity: old.connectivity,
                latency: old.latency,
                downloadHistory: history[.downloadMbps] ?? [],
                uploadHistory: history[.uploadMbps] ?? [],
                latencyHistory: history[.latencyMilliseconds] ?? []
            )
            draft.power = PowerSectionSnapshot(snapshot: draft.power.snapshot, chargeHistory: history[.batteryChargePercent] ?? [], dischargeHistory: history[.batteryDischargeWatts] ?? [])
            draft.appState = AppStatusSnapshot(lastRefresh: now, updateState: update, issues: draft.appState.issues)
        }
    }

    private func scheduleExternalRefresh(force: Bool, startup: Bool = false, only: DashboardDataSection? = nil) -> Task<Void, Never>? {
        if let externalRefreshTask {
            return externalRefreshTask
        }
        let now = Date()
        guard force || shouldRefreshSlowMetrics(now: now, interval: effectiveSlowRefreshInterval(for: settingsStore.settings)) else { return nil }
        if resourcePolicy.isOffline {
            for section in enabledSections() {
                var state = sectionActivity[section] ?? DashboardSectionActivity()
                state.isRefreshing = false
                state.message = state.lastSuccessAt == nil ? "Available when you're online" : "Offline · showing saved information"
                sectionActivity[section] = state
            }
            return nil
        }
        let sections = enabledSections().filter { section in
            guard only == nil || only == section || section == .location || section == .publicIP else { return false }
            if !force, resourcePolicy.reducesBackgroundWork, section.isLargeDownload {
                return false
            }
            return force || (retryAfter[section].map { now >= $0 } ?? true)
        }
        guard !sections.isEmpty else { return nil }
        lastSlowRefresh = now
        let generation = refreshGeneration
        let settings = settingsStore.settings
        externalRefreshIsManual = force || startup
        let task = Task(priority: force ? .userInitiated : .utility) { [weak self] in
            guard let self else { return }
            await performExternalRefresh(sections: sections, manual: force, settings: settings, generation: generation)
            guard generation == refreshGeneration else { return }
            externalRefreshTask = nil
            externalRefreshIsManual = false
            if !force, !startup {
                analytics?.recordBackgroundActiveDay()
            }
            updateRefreshActivity()
            await saveOfflineContent()
        }
        externalRefreshTask = task
        updateRefreshActivity()
        return task
    }

    private func enabledSections() -> [DashboardDataSection] {
        let settings = settingsStore.settings
        var result: [DashboardDataSection] = [.publicIP]
        if settings.usesDeviceLocation || automaticPlaceCollectionEnabled {
            result.append(.location)
        }
        if settings.useCurrentLocationForWeather {
            result.append(.weather)
        }
        if settings.localInfoEnabled {
            result.append(.localInfo)
        }
        if settings.fuelPricesEnabled {
            result.append(.fuel)
        }
        if settings.emergencyCareEnabled {
            result.append(.emergencyCare)
        }
        if settings.surfSpotConfiguration.isValid {
            result.append(.marine)
        }
        if !settings.travelAlertPreferences.enabledKinds.isEmpty {
            result.append(.travelAlerts)
        }
        return result
    }

    private func performExternalRefresh(sections: [DashboardDataSection], manual: Bool, settings: AppSettings, generation: Int) async {
        let budget = ProviderRequestBudget(limit: resourcePolicy.reducesBackgroundWork ? 1 : 3)
        let location = currentLocation
        let coordinate = currentCoordinate
        let deviceTask = Task { [weak self] () -> IPLocationSnapshot? in
            guard let self, sections.contains(.location), let location else { return nil }
            return await refreshDeviceLocation(location, budget: budget, generation: generation)
        }
        let ipTask = Task { [weak self] () -> IPLocationSnapshot? in
            guard let self, sections.contains(.publicIP) else { return nil }
            return await refreshPublicIP(settings: settings, manual: manual, budget: budget, generation: generation)
        }
        await withTaskCancellationHandler {
            await withTaskGroup(of: Void.self) { group in
                for section in sections where section != .location && section != .publicIP {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        var context: IPLocationSnapshot?
                        if section == .localInfo || section == .fuel || section == .travelAlerts {
                            context = await deviceTask.value
                            if context == nil {
                                context = await ipTask.value
                            }
                        }
                        guard !Task.isCancelled else { return }
                        await self.refreshSection(
                            section,
                            context: context,
                            coordinate: coordinate,
                            settings: settings,
                            manual: manual,
                            budget: budget,
                            generation: generation
                        )
                    }
                }
            }
            let device = await deviceTask.value
            let ip = await ipTask.value
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            if settings.visitedPlacesEnabled, let observed = device ?? ip {
                if await recordVisitedPlace(from: observed, source: device == nil ? .publicIPGeolocation : .deviceLocation, visitedAt: Date()) {
                    await loadVisitedPlaces()
                    await loadVisitedPlaceEvents()
                    await loadVisitedCountryDays()
                }
            }
        } onCancel: { deviceTask.cancel()
            ipTask.cancel()
        }
    }

    private func refreshDeviceLocation(_ location: CLLocation, budget: ProviderRequestBudget, generation: Int) async -> IPLocationSnapshot? {
        guard location.timestamp >= Date().addingTimeInterval(-Self.maximumDeviceLocationAge) else {
            return nil
        }
        beginSection(.location, generation: generation)
        do {
            let value = try await budget.run {
                try await withProviderDeadline { try await self.makeDeviceLocationSnapshot(from: location, now: Date()) }
            }
            guard accepts(generation) else { return nil }
            cachedLocationKey = locationKey(location.coordinate)
            mutateSnapshot { draft in
                let old = draft.travelContext
                draft.travelContext = TravelContextSnapshot(
                    wifi: old.wifi,
                    vpn: old.vpn,
                    timeZoneIdentifier: value.timeZone ?? TimeZone.current.identifier,
                    deviceLocation: value,
                    publicIP: old.publicIP,
                    location: old.location
                )
            }
            finishSection(.location, fetchedAt: value.fetchedAt, generation: generation)
            return value
        } catch { failSection(.location, error: error, generation: generation)
            return nil
        }
    }

    private func refreshPublicIP(settings: AppSettings, manual: Bool, budget: ProviderRequestBudget, generation: Int) async -> IPLocationSnapshot? {
        beginSection(.publicIP, generation: generation)
        do {
            let ip = try await budget.run {
                try await withProviderDeadline { try await self.dependencies.publicIPProvider.currentIP(forceRefresh: manual) }
            }
            guard accepts(generation) else { return nil }
            mutateSnapshot { draft in
                let old = draft.travelContext
                draft.travelContext = TravelContextSnapshot(
                    wifi: old.wifi,
                    vpn: old.vpn,
                    timeZoneIdentifier: old.timeZoneIdentifier,
                    deviceLocation: old.deviceLocation,
                    publicIP: ip,
                    location: settings.publicIPGeolocationEnabled ? old.location : nil
                )
            }
            setIssue(.publicIPLookupUnavailable, present: false)
            var resolved: IPLocationSnapshot?
            if settings.publicIPGeolocationEnabled {
                do {
                    resolved = try await budget.run {
                        try await withProviderDeadline { try await self.dependencies.publicIPLocationProvider.currentLocation(for: ip.address, forceRefresh: manual) }
                    }
                } catch {
                    guard accepts(generation) else { return nil }
                    setIssue(.ipLocationUnavailable, present: true)
                    failSection(.publicIP, error: error, generation: generation)
                    return nil
                }
            }
            guard accepts(generation) else { return nil }
            if let resolved {
                mutateSnapshot { draft in
                    let old = draft.travelContext
                    draft.travelContext = TravelContextSnapshot(
                        wifi: old.wifi,
                        vpn: old.vpn,
                        timeZoneIdentifier: old.deviceLocation?.timeZone ?? TimeZone.current.identifier,
                        deviceLocation: old.deviceLocation,
                        publicIP: ip,
                        location: resolved
                    )
                }
            }
            setIssue(.ipLocationUnavailable, present: false)
            finishSection(.publicIP, fetchedAt: ip.fetchedAt, generation: generation)
            return resolved
        } catch {
            if accepts(generation) {
                setIssue(.publicIPLookupUnavailable, present: true)
            }
            failSection(.publicIP, error: error, generation: generation)
            return nil
        }
    }

    private enum RemoteValue: Sendable {
        case weather(WeatherSnapshot), localInfo(LocalInfoSnapshot), fuel(FuelPriceSnapshot, FuelDiagnosticsSnapshot)
        case emergency(EmergencyCareSnapshot), marine(MarineSnapshot), alerts(TravelAlertsSnapshot)
    }

    private func refreshSection(
        _ section: DashboardDataSection,
        context: IPLocationSnapshot?,
        coordinate: CLLocationCoordinate2D?,
        settings: AppSettings,
        manual: Bool,
        budget: ProviderRequestBudget,
        generation: Int
    ) async {
        guard accepts(generation) else { return }
        beginSection(section, generation: generation)
        let previousAlerts = snapshot.travelAlerts?.primaryCountryCode == context?.countryCode?.uppercased() ? snapshot.travelAlerts : nil
        do {
            let value: RemoteValue = try await budget.run {
                try await withProviderDeadline(seconds: section == .travelAlerts ? 55 : 25) {
                    switch section {
                    case .weather: return try await .weather(self.dependencies.weatherProvider.weather(for: coordinate))
                    case .localInfo: return await .localInfo(self.refreshLocalInfo(manual: manual, ipLocationSnapshot: context))
                    case .fuel:
                        let value = await self.refreshFuelPrices(manual: manual)
                        return .fuel(value.snapshot, value.diagnostics)
                    case .emergencyCare: return await .emergency(self.refreshEmergencyCare(manual: manual))
                    case .marine:
                        guard let name = settings.surfSpotConfiguration.name, let spotCoordinate = settings.surfSpotConfiguration.coordinate else { throw ProviderError.missingCoordinate }
                        return try await .marine(self.dependencies.marineProvider.marine(for: MarineSpot(name: name, coordinate: spotCoordinate)))
                    case .travelAlerts:
                        return await .alerts(self.refreshTravelAlerts(settings: settings, locationSnapshot: context, previousSnapshot: previousAlerts, manual: manual, now: Date()))
                    case .location, .publicIP: throw ProviderError.invalidResponse
                    }
                }
            }
            guard accepts(generation) else { return }
            var fetchedAt: Date?
            var failed = false
            mutateSnapshot { draft in
                switch value {
                case let .weather(value): draft.weather = value
                    fetchedAt = value.fetchedAt
                case let .localInfo(value):
                    failed = value.status == .unavailable
                    if !failed || draft.localInfo == nil {
                        draft.localInfo = value
                    }
                    fetchedAt = failed ? nil : value.fetchedAt
                case let .fuel(value, diagnostics):
                    failed = value.status == .unavailable
                    if !failed || draft.fuelPrices == nil {
                        draft.fuelPrices = value
                    }
                    draft.fuelDiagnostics = diagnostics
                    fetchedAt = failed ? nil : value.fetchedAt
                case let .emergency(value):
                    failed = value.status == .unavailable
                    if !failed || draft.emergencyCare == nil {
                        draft.emergencyCare = value
                    }
                    fetchedAt = failed ? nil : value.fetchedAt
                case let .marine(value): draft.marine = value
                    fetchedAt = value.fetchedAt
                case let .alerts(value):
                    draft.travelAlerts = value
                    failed = value.hasStaleStates || value.hasUnavailableStates
                    fetchedAt = failed ? nil : value.fetchedAt
                }
            }
            if failed {
                failSection(section, error: ProviderError.invalidResponse, generation: generation)
            } else {
                finishSection(section, fetchedAt: fetchedAt, generation: generation)
                if section == .weather {
                    setIssue(.weatherUnavailable, present: false)
                    setIssue(.weatherLocationRequired, present: false)
                }
                if section == .marine {
                    setIssue(.marineUnavailable, present: false)
                }
            }
        } catch {
            guard accepts(generation) else { return }
            if section == .weather {
                if case ProviderError.missingCoordinate = error {
                    setIssue(.weatherLocationRequired, present: true)
                } else {
                    setIssue(.weatherUnavailable, present: true)
                }
            }
            if section == .marine {
                setIssue(.marineUnavailable, present: true)
            }
            failSection(section, error: error, generation: generation)
        }
    }

    private func accepts(_ generation: Int) -> Bool {
        generation == refreshGeneration && !Task.isCancelled
    }

    private func beginSection(_ section: DashboardDataSection, generation: Int) {
        guard accepts(generation) else { return }
        var state = sectionActivity[section] ?? DashboardSectionActivity()
        state.isRefreshing = true
        state.message = nil
        sectionActivity[section] = state
    }

    private func finishSection(_ section: DashboardDataSection, fetchedAt: Date?, generation: Int) {
        guard accepts(generation) else { return }
        sectionActivity[section] = DashboardSectionActivity(lastSuccessAt: fetchedAt)
        failureCounts[section] = nil
        retryAfter[section] = nil
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await self?.saveOfflineContent()
        }
    }

    private func failSection(_ section: DashboardDataSection, error: Error, generation: Int) {
        guard accepts(generation), !(error is CancellationError) else { return }
        var state = sectionActivity[section] ?? DashboardSectionActivity()
        state.isRefreshing = false
        state.message = state.lastSuccessAt == nil ? "Couldn't update. Try again when your connection improves." : "Couldn't update · keeping saved information"
        sectionActivity[section] = state
        let failures = min((failureCounts[section] ?? 0) + 1, 6)
        failureCounts[section] = failures
        retryAfter[section] = Date().addingTimeInterval(min(1_800, 30 * pow(2, Double(failures - 1))))
    }

    private func setIssue(_ issue: DashboardIssue, present: Bool) {
        mutateSnapshot { draft in
            var issues = draft.appState.issues.filter { $0 != issue }
            if present {
                issues.append(issue)
            }
            draft.appState = AppStatusSnapshot(lastRefresh: draft.appState.lastRefresh, updateState: draft.appState.updateState, issues: issues)
        }
    }

    private func invalidateExternalRefresh() {
        refreshGeneration += 1
        externalRefreshTask?.cancel()
        externalRefreshTask = nil
        externalRefreshIsManual = false
        for section in sectionActivity.keys {
            sectionActivity[section]?.isRefreshing = false
        }
        updateRefreshActivity()
    }

    private func locationKey(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }

    private func clearLocationDependentContent() {
        mutateSnapshot { draft in
            draft.weather = nil
            draft.localInfo = nil
            draft.fuelPrices = nil
            draft.fuelDiagnostics = nil
            draft.emergencyCare = nil
            draft.travelAlerts = nil
            let old = draft.travelContext
            draft.travelContext = TravelContextSnapshot(
                wifi: old.wifi,
                vpn: old.vpn,
                timeZoneIdentifier: TimeZone.current.identifier,
                deviceLocation: nil,
                publicIP: old.publicIP,
                location: old.location
            )
        }
        for section in [DashboardDataSection.location, .weather, .localInfo, .fuel, .emergencyCare, .travelAlerts] {
            sectionActivity[section] = DashboardSectionActivity(message: "Updating for your new location")
        }
    }

    private func saveOfflineContent() async {
        guard let cache = dependencies.offlineCache else { return }
        guard hasOfflineContentWorthSaving else { return }
        do {
            let content = OfflineDashboardContent(snapshot: snapshot, savedAt: Date(), locationKey: cachedLocationKey)
            try await cache.save(content)
            offlineSavedAt = content.savedAt
            offlineCacheError = nil
        } catch { offlineCacheError = "Couldn't save offline information. Your live dashboard is still available." }
    }

    private var hasOfflineContentWorthSaving: Bool {
        snapshot.weather != nil
            || snapshot.localInfo != nil
            || snapshot.fuelPrices != nil
            || snapshot.emergencyCare != nil
            || snapshot.marine != nil
            || snapshot.travelAlerts?.states.contains(where: { $0.resolvedSignal != nil }) == true
            || snapshot.travelContext.deviceLocation != nil
            || snapshot.travelContext.location != nil
    }

    private func shouldRefreshSlowMetrics(now: Date, interval: TimeInterval) -> Bool {
        guard let lastSlowRefresh else {
            return true
        }

        return now.timeIntervalSince(lastSlowRefresh) >= interval
    }

    private func effectiveRefreshInterval(for settings: AppSettings) -> TimeInterval {
        let interval = max(AppSettings.sanitizedRefreshInterval(settings.refreshIntervalSeconds), resourcePolicy.reducesBackgroundWork ? 30 : 0)
        guard dashboardInterfaceActive == false else {
            return interval
        }

        return max(interval, Self.minimumBackgroundRefreshIntervalSeconds)
    }

    private func effectiveSlowRefreshInterval(for settings: AppSettings) -> TimeInterval {
        guard dashboardInterfaceActive == false || resourcePolicy.reducesBackgroundWork else {
            return settings.slowRefreshIntervalSeconds.isFinite
                ? settings.slowRefreshIntervalSeconds
                : AppSettings.defaultSlowRefreshIntervalSeconds
        }

        let interval = AppSettings.sanitizedSlowRefreshInterval(settings.slowRefreshIntervalSeconds)
        return max(interval, Self.minimumBackgroundSlowRefreshIntervalSeconds)
    }

    private func projectedDashboardHistory(_ history: [MetricSeriesKind: [MetricPoint]]) -> [MetricSeriesKind: [MetricPoint]] {
        history.mapValues { projectedMetricHistory($0, maxPoints: dashboardChartPointLimit) }
    }

    private func configureSettingsObservation() {
        settingsObservation = settingsStore.$settings
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newSettings in
                guard let self else {
                    return
                }

                let previousSettings = appliedSettings
                appliedSettings = newSettings

                Task { [weak self] in
                    await self?.applySettingsChange(from: previousSettings, to: newSettings)
                }
            }
    }

    private func applyInitialSettings() async {
        if let cache = dependencies.offlineCache {
            do {
                if let content = try await cache.load() {
                    let currentLocationKey = currentLocation.map { locationKey($0.coordinate) }
                    if currentLocationKey == nil || currentLocationKey == content.locationKey {
                        snapshot = content.applying(to: snapshot)
                        cachedLocationKey = content.locationKey
                        offlineSavedAt = content.savedAt
                        let dates: [DashboardDataSection: Date?] = [
                            .location: content.deviceLocation?.fetchedAt, .weather: content.weather?.fetchedAt,
                            .localInfo: content.localInfo?.fetchedAt, .fuel: content.fuelPrices?.fetchedAt,
                            .emergencyCare: content.emergencyCare?.fetchedAt, .marine: content.marine?.fetchedAt,
                            .travelAlerts: content.travelAlerts?.fetchedAt
                        ]
                        for (section, date) in dates {
                            if let date {
                                sectionActivity[section] = DashboardSectionActivity(lastSuccessAt: date, isSaved: true)
                            }
                        }
                    }
                }
            } catch { offlineCacheError = "Saved information couldn't be opened. It will refresh when you're online." }
        }
        sanitizeDisabledSections()
        try? await dependencies.historyStore.setRetentionHours(appliedSettings.historyRetentionHours)
        await dependencies.updateCoordinator.setAutomaticChecksEnabled(appliedSettings.automaticUpdateChecksEnabled)
        await loadVisitedPlaces()
        await loadVisitedPlaceEvents()
        await loadVisitedCountryDays()
    }

    private func applySettingsChange(from previousSettings: AppSettings, to newSettings: AppSettings) async {
        if previousSettings.dataUsageMode != newSettings.dataUsageMode {
            invalidateExternalRefresh()
            updateResourcePolicy()
            lastSlowRefresh = nil
        }
        if previousSettings.automaticUpdateChecksEnabled != newSettings.automaticUpdateChecksEnabled {
            await dependencies.updateCoordinator.setAutomaticChecksEnabled(newSettings.automaticUpdateChecksEnabled)
        }

        var needsManualRefresh = false

        if previousSettings.historyRetentionHours != newSettings.historyRetentionHours {
            try? await dependencies.historyStore.setRetentionHours(newSettings.historyRetentionHours)
            needsManualRefresh = true
        }

        if previousSettings.publicIPGeolocationEnabled != newSettings.publicIPGeolocationEnabled {
            needsManualRefresh = true
        }

        if previousSettings.useCurrentLocationForWeather != newSettings.useCurrentLocationForWeather {
            needsManualRefresh = true
        }

        if previousSettings.localInfoEnabled != newSettings.localInfoEnabled {
            needsManualRefresh = true
        }

        if previousSettings.fuelPricesEnabled != newSettings.fuelPricesEnabled {
            needsManualRefresh = true
        }

        if previousSettings.emergencyCareEnabled != newSettings.emergencyCareEnabled {
            needsManualRefresh = true
        }

        if previousSettings.tankerkonigAPIKey != newSettings.tankerkonigAPIKey {
            if let configurableFuelProvider = dependencies.fuelPriceProvider as? FuelPriceProviderConfigurationUpdating {
                await configurableFuelProvider.setTankerkonigAPIKey(
                    AppRuntimeConfiguration.resolveTankerkonigAPIKey(userSetting: newSettings.tankerkonigAPIKey)
                )
            }
            needsManualRefresh = true
        }

        if previousSettings.hudUserAPIToken != newSettings.hudUserAPIToken {
            if let configurableLocalInfoProvider = dependencies.localInfoProvider as? LocalPriceLevelProviderConfigurationUpdating {
                await configurableLocalInfoProvider.setHUDUserAPIToken(
                    AppRuntimeConfiguration.resolveHUDUserAPIToken(userSetting: newSettings.hudUserAPIToken)
                )
            }
            needsManualRefresh = true
        }

        if previousSettings.surfSpotName != newSettings.surfSpotName
            || previousSettings.surfSpotLatitude != newSettings.surfSpotLatitude
            || previousSettings.surfSpotLongitude != newSettings.surfSpotLongitude
        {
            needsManualRefresh = true
        }

        if previousSettings.visitedPlacesEnabled != newSettings.visitedPlacesEnabled {
            needsManualRefresh = true
        }

        if previousSettings.travelAdvisoryEnabled != newSettings.travelAdvisoryEnabled {
            needsManualRefresh = true
        }

        if previousSettings.travelWeatherAlertsEnabled != newSettings.travelWeatherAlertsEnabled {
            needsManualRefresh = true
        }

        if previousSettings.regionalSecurityEnabled != newSettings.regionalSecurityEnabled {
            needsManualRefresh = true
        }

        if previousSettings.travelAlertPreferences != newSettings.travelAlertPreferences {
            snapshot = snapshot.replacingTravelAlerts(
                synchronizedTravelAlertsSnapshot(
                    previous: snapshot.travelAlerts,
                    settings: newSettings,
                    locationSnapshot: snapshot.travelContext.location
                )
            )
        }

        sanitizeDisabledSections()
        if needsManualRefresh {
            invalidateExternalRefresh()
            lastSlowRefresh = nil
            scheduleSettingsRefresh()
        }
    }

    private func scheduleSettingsRefresh() {
        settingsRefreshTask?.cancel()
        settingsRefreshTask = Task { [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            await self?.performScheduledSettingsRefresh()
        }
    }

    private func performScheduledSettingsRefresh() async {
        settingsRefreshTask = nil
        await refresh(manual: true)
    }

    private func sanitizeDisabledSections() {
        let settings = settingsStore.settings
        mutateSnapshot { draft in
            if !settings.useCurrentLocationForWeather {
                draft.weather = nil
            }
            if !settings.localInfoEnabled {
                draft.localInfo = nil
            }
            if !settings.fuelPricesEnabled {
                draft.fuelPrices = nil
                draft.fuelDiagnostics = nil
            }
            if !settings.emergencyCareEnabled {
                draft.emergencyCare = nil
            }
            if !settings.surfSpotConfiguration.isValid {
                draft.marine = nil
            }
            if let marine = draft.marine, let coordinate = settings.surfSpotConfiguration.coordinate,
               marine.coordinate.latitude != coordinate.latitude || marine.coordinate.longitude != coordinate.longitude
            {
                draft.marine = nil
            }
            let old = draft.travelContext
            draft.travelContext = TravelContextSnapshot(
                wifi: old.wifi,
                vpn: old.vpn,
                timeZoneIdentifier: old.timeZoneIdentifier,
                deviceLocation: settings.usesDeviceLocation || automaticPlaceCollectionEnabled ? old.deviceLocation : nil,
                publicIP: old.publicIP,
                location: settings.publicIPGeolocationEnabled ? old.location : nil
            )
            draft.travelAlerts = synchronizedTravelAlertsSnapshot(
                previous: draft.travelAlerts,
                settings: settings,
                locationSnapshot: old.deviceLocation ?? old.location
            )
        }
        setIssue(.marineSpotNotConfigured, present: !settings.surfSpotConfiguration.isConfigured)
        setIssue(.marineSpotInvalid, present: settings.surfSpotConfiguration.isConfigured && !settings.surfSpotConfiguration.isValid)
        let enabled = Set(enabledSections())
        sectionActivity = sectionActivity.filter { enabled.contains($0.key) }
    }

    private func refreshLocalInfo(
        manual: Bool,
        ipLocationSnapshot: IPLocationSnapshot?
    ) async -> LocalInfoSnapshot {
        var resolvedCountryCode = normalizedValue(ipLocationSnapshot?.countryCode)?.uppercased()
        var resolvedCountryName = normalizedValue(ipLocationSnapshot?.country)
        var locality = normalizedValue(ipLocationSnapshot?.city)
        var administrativeRegion = normalizedValue(ipLocationSnapshot?.region)
        var timeZoneIdentifier = normalizedValue(ipLocationSnapshot?.timeZone)

        if let currentLocation {
            do {
                let reverseGeocodedLocation = try await dependencies.reverseGeocodingProvider.details(for: currentLocation)
                try Task.checkCancellation()
                resolvedCountryCode = normalizedValue(reverseGeocodedLocation.countryCode)?.uppercased()
                resolvedCountryName = normalizedValue(reverseGeocodedLocation.country)
                locality = normalizedValue(reverseGeocodedLocation.city) ?? locality
                administrativeRegion = normalizedValue(reverseGeocodedLocation.region) ?? administrativeRegion
                timeZoneIdentifier = normalizedValue(reverseGeocodedLocation.timeZoneIdentifier) ?? timeZoneIdentifier
            } catch {
                // Keep the IP-derived country fallback when reverse geocoding is unavailable.
            }
        }

        guard let countryCode = resolvedCountryCode else {
            return LocalInfoSnapshot(
                status: .locationRequired,
                locality: locality,
                administrativeRegion: administrativeRegion,
                countryCode: nil,
                countryName: nil,
                timeZoneIdentifier: timeZoneIdentifier,
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Allow current location or external IP location to look up local holiday information."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: nil,
                detail: "Allow current location or external IP location to estimate local info.",
                note: nil
            )
        }

        let request = LocalInfoRequest(
            coordinate: currentLocation?.coordinate,
            countryCode: countryCode,
            countryName: resolvedCountryName,
            locality: locality,
            administrativeRegion: administrativeRegion,
            timeZoneIdentifier: timeZoneIdentifier
        )

        do {
            try Task.checkCancellation()
            return try await dependencies.localInfoProvider.info(
                for: request,
                forceRefresh: manual
            )
        } catch {
            return LocalInfoSnapshot(
                status: .unavailable,
                locality: locality,
                administrativeRegion: administrativeRegion,
                countryCode: countryCode,
                countryName: resolvedCountryName,
                timeZoneIdentifier: timeZoneIdentifier,
                subdivisionCode: nil,
                publicHolidayStatus: LocalHolidayStatus(
                    state: .unavailable,
                    currentPeriod: nil,
                    nextPeriod: nil,
                    note: "Local holiday calendar is unavailable right now."
                ),
                schoolHolidayStatus: nil,
                localPriceLevel: nil,
                sources: [],
                fetchedAt: Date(),
                detail: "Local info is unavailable right now.",
                note: nil
            )
        }
    }

    private func refreshFuelPrices(manual: Bool) async -> (snapshot: FuelPriceSnapshot, diagnostics: FuelDiagnosticsSnapshot) {
        let radiusKilometers = 50.0
        let currentCoordinate = currentLocation?.coordinate
        let existingSourceName = snapshot.fuelPrices?.sourceName ?? "Nomad Fuel Prices"
        let existingSourceURL = snapshot.fuelPrices?.sourceURL
        var resolvedCountryCode: String?
        var resolvedCountryName: String?

        guard let currentLocation else {
            let fuelSnapshot = FuelPriceSnapshot(
                status: .locationRequired,
                sourceName: existingSourceName,
                sourceURL: nil,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: radiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: nil,
                detail: "Allow current location to look up nearby fuel prices.",
                note: nil
            )
            let diagnostics = FuelDiagnosticsSnapshot(
                status: .locationRequired,
                stage: .locationMissing,
                countryCode: nil,
                countryName: nil,
                latitude: currentCoordinate?.latitude,
                longitude: currentCoordinate?.longitude,
                searchRadiusKilometers: radiusKilometers,
                providerName: existingSourceName,
                sourceURL: existingSourceURL,
                startedAt: nil,
                finishedAt: Date(),
                elapsedMilliseconds: nil,
                summary: "Fuel lookup skipped because current location is unavailable.",
                error: nil
            )
            Self.fuelLogger.info("Fuel fetch skipped because current location is unavailable.")
            return (fuelSnapshot, diagnostics)
        }

        do {
            let reverseGeocodedLocation = try await dependencies.reverseGeocodingProvider.details(for: currentLocation)
            try Task.checkCancellation()
            resolvedCountryName = reverseGeocodedLocation.country
            guard let countryCode = normalizedValue(reverseGeocodedLocation.countryCode)?.uppercased() else {
                let fuelSnapshot = FuelPriceSnapshot(
                    status: .unavailable,
                    sourceName: "Apple Reverse Geocoder",
                    sourceURL: nil,
                    countryCode: nil,
                    countryName: reverseGeocodedLocation.country,
                    searchRadiusKilometers: radiusKilometers,
                    diesel: nil,
                    gasoline: nil,
                    fetchedAt: Date(),
                    detail: "Current location country could not be resolved.",
                    note: nil
                )
                let diagnostics = FuelDiagnosticsSnapshot(
                    status: .unavailable,
                    stage: .reverseGeocoding,
                    countryCode: nil,
                    countryName: reverseGeocodedLocation.country,
                    latitude: currentLocation.coordinate.latitude,
                    longitude: currentLocation.coordinate.longitude,
                    searchRadiusKilometers: radiusKilometers,
                    providerName: "Apple Reverse Geocoder",
                    sourceURL: nil,
                    startedAt: nil,
                    finishedAt: fuelSnapshot.fetchedAt,
                    elapsedMilliseconds: nil,
                    summary: "Current location country could not be resolved.",
                    error: nil
                )
                Self.fuelLogger.error("Fuel fetch reverse geocoding resolved no country code for lat=\(currentLocation.coordinate.latitude, privacy: .public) lon=\(currentLocation.coordinate.longitude, privacy: .public)")
                return (fuelSnapshot, diagnostics)
            }
            resolvedCountryCode = countryCode

            let request = FuelSearchRequest(
                coordinate: currentLocation.coordinate,
                countryCode: countryCode,
                countryName: reverseGeocodedLocation.country,
                searchRadiusKilometers: radiusKilometers
            )
            Self.fuelLogger.info(
                "Fuel fetch start providerCountry=\(countryCode, privacy: .public) lat=\(request.coordinate.latitude, privacy: .public) lon=\(request.coordinate.longitude, privacy: .public) radiusKm=\(radiusKilometers, privacy: .public)"
            )

            let fuelSnapshot = try await dependencies.fuelPriceProvider.prices(
                for: request,
                forceRefresh: manual
            )
            let providerDiagnosticsProvider = dependencies.fuelPriceProvider as? FuelPriceDiagnosticsProviding
            let providerDiagnostics: FuelProviderRequestDiagnostics? = if let providerDiagnosticsProvider {
                await providerDiagnosticsProvider.latestRequestDiagnostics()
            } else {
                nil
            }
            let diagnostics = makeFuelDiagnostics(
                snapshot: fuelSnapshot,
                request: request,
                providerDiagnostics: providerDiagnostics
            )
            logFuelSuccess(snapshot: fuelSnapshot, diagnostics: diagnostics)
            return (fuelSnapshot, diagnostics)
        } catch let error as FuelPriceProviderError {
            let note = error.diagnosticSummary == "The operation could not be completed. (NomadCore.ProviderError error 0.)" ? nil : error.diagnosticSummary
            let fuelSnapshot = FuelPriceSnapshot(
                status: .unavailable,
                sourceName: error.sourceName,
                sourceURL: error.sourceURL,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: radiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: Date(),
                detail: "Nearby fuel prices are unavailable right now.",
                note: note
            )
            let providerDiagnosticsProvider = dependencies.fuelPriceProvider as? FuelPriceDiagnosticsProviding
            let providerDiagnostics: FuelProviderRequestDiagnostics? = if let providerDiagnosticsProvider {
                await providerDiagnosticsProvider.latestRequestDiagnostics()
            } else {
                nil
            }
            let diagnostics = FuelDiagnosticsSnapshot(
                status: .unavailable,
                stage: error.stage,
                countryCode: resolvedCountryCode,
                countryName: resolvedCountryName,
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                searchRadiusKilometers: radiusKilometers,
                providerName: error.sourceName,
                sourceURL: error.sourceURL,
                startedAt: providerDiagnostics?.startedAt,
                finishedAt: providerDiagnostics?.finishedAt ?? Date(),
                elapsedMilliseconds: providerDiagnostics?.elapsedMilliseconds,
                summary: error.diagnosticSummary,
                error: error.details
            )
            logFuelFailure(error: error, diagnostics: diagnostics)
            return (fuelSnapshot, diagnostics)
        } catch {
            let diagnosticsError = makeDiagnosticsError(
                from: error,
                fallbackURL: nil,
                summary: "Fuel price request failed before the provider completed."
            )
            let fuelSnapshot = FuelPriceSnapshot(
                status: .unavailable,
                sourceName: snapshot.fuelPrices?.sourceName ?? "Nomad Fuel Prices",
                sourceURL: snapshot.fuelPrices?.sourceURL,
                countryCode: nil,
                countryName: nil,
                searchRadiusKilometers: radiusKilometers,
                diesel: nil,
                gasoline: nil,
                fetchedAt: Date(),
                detail: "Nearby fuel prices are unavailable right now.",
                note: diagnosticsError.preferredSummary
            )
            let diagnostics = FuelDiagnosticsSnapshot(
                status: .unavailable,
                stage: .reverseGeocoding,
                countryCode: resolvedCountryCode,
                countryName: resolvedCountryName,
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude,
                searchRadiusKilometers: radiusKilometers,
                providerName: fuelSnapshot.sourceName,
                sourceURL: fuelSnapshot.sourceURL,
                startedAt: nil,
                finishedAt: Date(),
                elapsedMilliseconds: nil,
                summary: diagnosticsError.preferredSummary,
                error: diagnosticsError
            )
            Self.fuelLogger.error("Fuel fetch failed before provider request: \(diagnosticsError.preferredSummary, privacy: .public)")
            return (fuelSnapshot, diagnostics)
        }
    }

    private func refreshEmergencyCare(manual: Bool) async -> EmergencyCareSnapshot {
        let radiusKilometers = 25.0

        guard let currentLocation else {
            return EmergencyCareSnapshot(
                status: .locationRequired,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: radiusKilometers,
                hospitals: [],
                fetchedAt: nil,
                detail: "Allow current location to look up nearby emergency hospitals."
            )
        }

        do {
            try Task.checkCancellation()
            return try await dependencies.emergencyCareProvider.nearbyHospitals(
                for: EmergencyCareSearchRequest(
                    coordinate: currentLocation.coordinate,
                    searchRadiusKilometers: radiusKilometers,
                    maximumResults: 3
                ),
                forceRefresh: manual
            )
        } catch {
            return EmergencyCareSnapshot(
                status: .unavailable,
                sourceName: "Apple Maps",
                sourceURL: URL(string: "https://maps.apple.com"),
                searchRadiusKilometers: radiusKilometers,
                hospitals: [],
                fetchedAt: Date(),
                detail: "Nearby emergency hospitals are unavailable right now."
            )
        }
    }

    private func makeFuelDiagnostics(
        snapshot: FuelPriceSnapshot,
        request: FuelSearchRequest,
        providerDiagnostics: FuelProviderRequestDiagnostics?
    ) -> FuelDiagnosticsSnapshot {
        FuelDiagnosticsSnapshot(
            status: snapshot.status,
            stage: providerDiagnostics?.stage ?? .bestPriceSelection,
            countryCode: snapshot.countryCode ?? request.countryCode,
            countryName: snapshot.countryName ?? request.countryName,
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude,
            searchRadiusKilometers: snapshot.searchRadiusKilometers,
            providerName: providerDiagnostics?.providerName ?? snapshot.sourceName,
            sourceURL: providerDiagnostics?.sourceURL ?? snapshot.sourceURL,
            startedAt: providerDiagnostics?.startedAt,
            finishedAt: providerDiagnostics?.finishedAt ?? snapshot.fetchedAt,
            elapsedMilliseconds: providerDiagnostics?.elapsedMilliseconds,
            summary: providerDiagnostics?.summary ?? snapshot.detail ?? "Fuel price lookup completed.",
            error: providerDiagnostics?.error
        )
    }

    private func logFuelSuccess(snapshot: FuelPriceSnapshot, diagnostics: FuelDiagnosticsSnapshot) {
        let diesel = snapshot.diesel.map {
            "\($0.stationName) \(String(format: "%.3f", $0.pricePerLiter)) \($0.currencyCode)/L \(String(format: "%.1f", $0.distanceKilometers))km"
        } ?? "n/a"
        let gasoline = snapshot.gasoline.map {
            "\($0.stationName) \(String(format: "%.3f", $0.pricePerLiter)) \($0.currencyCode)/L \(String(format: "%.1f", $0.distanceKilometers))km"
        } ?? "n/a"
        Self.fuelLogger.info(
            "Fuel fetch success status=\(snapshot.status.rawValue, privacy: .public) provider=\(snapshot.sourceName, privacy: .public) country=\(snapshot.countryCode ?? "n/a", privacy: .public) diesel=\(diesel, privacy: .public) gasoline=\(gasoline, privacy: .public) elapsedMs=\(diagnostics.elapsedMilliseconds ?? -1, privacy: .public)"
        )
    }

    private func logFuelFailure(error: FuelPriceProviderError, diagnostics: FuelDiagnosticsSnapshot) {
        Self.fuelLogger.error(
            "Fuel fetch failed provider=\(error.sourceName, privacy: .public) stage=\(diagnostics.stage.rawValue, privacy: .public) kind=\(error.failureKind?.rawValue ?? "unknown", privacy: .public) domain=\(error.underlyingDomain ?? "n/a", privacy: .public) code=\(error.underlyingCode ?? -1, privacy: .public) urlError=\(error.urlErrorSymbol ?? "n/a", privacy: .public) failingURL=\(error.failingURL?.absoluteString ?? "n/a", privacy: .public) httpStatus=\(error.httpStatusCode ?? -1, privacy: .public) mime=\(error.responseMIMEType ?? "n/a", privacy: .public) bytes=\(error.payloadByteCount ?? -1, privacy: .public) summary=\(diagnostics.summary, privacy: .public)"
        )
    }

    private func loadVisitedPlaces() async {
        visitedPlaces = await (try? dependencies.visitedPlacesStore.loadAll()) ?? []
    }

    private func loadVisitedPlaceEvents() async {
        visitedPlaceEvents = await (try? dependencies.visitedPlaceEventsStore.loadAll()) ?? []
    }

    private func loadVisitedCountryDays() async {
        visitedCountryDays = await (try? dependencies.visitedCountryDaysStore.loadAll()) ?? []
    }

    private func recordVisitedPlace(
        from snapshot: IPLocationSnapshot,
        source: VisitedPlaceSource,
        visitedAt: Date
    ) async -> Bool {
        guard let country = normalizedValue(snapshot.country) else {
            return false
        }

        let placeInput = VisitedPlaceInput(
            city: normalizedValue(snapshot.city),
            region: normalizedValue(snapshot.region),
            country: country,
            countryCode: normalizedValue(snapshot.countryCode)?.uppercased(),
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            source: source,
            visitedAt: visitedAt
        )
        let dayInput = VisitedCountryDayInput(
            day: VisitedCountryDayStamp(date: visitedAt, calendar: .autoupdatingCurrent),
            country: country,
            countryCode: normalizedValue(snapshot.countryCode)?.uppercased(),
            source: source,
            observedAt: visitedAt
        )
        let eventInput = VisitedPlaceEventInput(
            city: placeInput.city,
            region: placeInput.region,
            country: placeInput.country,
            countryCode: placeInput.countryCode,
            latitude: placeInput.latitude,
            longitude: placeInput.longitude,
            source: placeInput.source,
            observedAt: visitedAt,
            observedDay: dayInput.day
        )

        return await recordVisitedHistory(placeInput: placeInput, eventInput: eventInput, dayInput: dayInput)
    }

    private func recordVisitedHistory(
        placeInput: VisitedPlaceInput,
        eventInput: VisitedPlaceEventInput,
        dayInput: VisitedCountryDayInput
    ) async -> Bool {
        var didRecord = false

        do {
            try await dependencies.visitedPlacesStore.record(placeInput)
            didRecord = true
        } catch {}

        do {
            try await dependencies.visitedPlaceEventsStore.record(eventInput)
            didRecord = true
        } catch {}

        do {
            try await dependencies.visitedCountryDaysStore.record(dayInput)
            didRecord = true
        } catch {}

        return didRecord
    }

    private func makeDeviceLocationSnapshot(from location: CLLocation, now: Date) async throws -> IPLocationSnapshot {
        let details = try await dependencies.reverseGeocodingProvider.details(for: location)

        return IPLocationSnapshot(
            city: normalizedValue(details.city),
            region: normalizedValue(details.region),
            country: normalizedValue(details.country),
            countryCode: normalizedValue(details.countryCode)?.uppercased(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timeZone: normalizedValue(details.timeZoneIdentifier),
            provider: "Core Location",
            fetchedAt: now
        )
    }

    private func appendHistory(from throughputSample: NetworkThroughputSample) async {
        try? await dependencies.historyStore.append(
            MetricPoint(
                timestamp: throughputSample.collectedAt,
                value: throughputSample.downloadMegabitsPerSecond
            ),
            to: .downloadMbps
        )
        try? await dependencies.historyStore.append(
            MetricPoint(
                timestamp: throughputSample.collectedAt,
                value: throughputSample.uploadMegabitsPerSecond
            ),
            to: .uploadMbps
        )
    }

    private func appendHistory(from powerSnapshot: PowerSnapshot) async {
        if let chargePercent = powerSnapshot.chargePercent {
            try? await dependencies.historyStore.append(
                MetricPoint(timestamp: powerSnapshot.collectedAt, value: chargePercent * 100),
                to: .batteryChargePercent
            )
        }

        if let dischargeRateWatts = powerSnapshot.dischargeRateWatts {
            try? await dependencies.historyStore.append(
                MetricPoint(timestamp: powerSnapshot.collectedAt, value: dischargeRateWatts),
                to: .batteryDischargeWatts
            )
        }
    }

    private func refreshTravelAlerts(
        settings: AppSettings,
        locationSnapshot: IPLocationSnapshot?,
        previousSnapshot: TravelAlertsSnapshot?,
        manual: Bool,
        now: Date
    ) async -> TravelAlertsSnapshot {
        let preferences = settings.travelAlertPreferences
        let enabledKinds = preferences.enabledKinds
        let primaryCountryCode = locationSnapshot?.countryCode?.uppercased()
        let primaryCountryName = locationSnapshot?.country
        let coverageCountryCodes = coverageCountryCodes(for: primaryCountryCode)
        var states: [TravelAlertSignalState] = []

        guard enabledKinds.isEmpty == false else {
            return TravelAlertsSnapshot(
                enabledKinds: [],
                primaryCountryCode: primaryCountryCode,
                primaryCountryName: primaryCountryName,
                coverageCountryCodes: coverageCountryCodes,
                states: [],
                fetchedAt: nil
            )
        }

        if preferences.advisoryEnabled, !Task.isCancelled {
            await states.append(
                refreshAlertState(
                    kind: .advisory,
                    previous: previousSnapshot?.state(for: .advisory),
                    source: dependencies.travelAdvisoryProvider.sourceDescriptor,
                    attemptedAt: now,
                    prerequisiteFailure: primaryCountryCode == nil ? .countryRequired : nil
                ) {
                    guard let primaryCountryCode else {
                        throw ProviderError.missingCountryCode
                    }

                    return try await dependencies.travelAdvisoryProvider.advisory(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: manual
                    )
                }
            )
        }

        if preferences.weatherEnabled, !Task.isCancelled {
            let weatherAlertCoordinate = currentCoordinate ?? locationSnapshot?.coordinate
            await states.append(
                refreshAlertState(
                    kind: .weather,
                    previous: previousSnapshot?.state(for: .weather),
                    source: dependencies.travelWeatherAlertsProvider.sourceDescriptor,
                    attemptedAt: now,
                    prerequisiteFailure: weatherAlertCoordinate == nil ? .locationRequired : nil
                ) {
                    try await dependencies.travelWeatherAlertsProvider.alerts(
                        for: weatherAlertCoordinate,
                        forceRefresh: manual
                    )
                }
            )
        }

        if preferences.securityEnabled, !Task.isCancelled {
            await states.append(
                refreshAlertState(
                    kind: .security,
                    previous: previousSnapshot?.state(for: .security),
                    source: dependencies.regionalSecurityProvider.sourceDescriptor,
                    attemptedAt: now,
                    prerequisiteFailure: primaryCountryCode == nil ? .countryRequired : nil
                ) {
                    guard let primaryCountryCode else {
                        throw ProviderError.missingCountryCode
                    }

                    return try await dependencies.regionalSecurityProvider.security(
                        for: coverageCountryCodes,
                        primaryCountryCode: primaryCountryCode,
                        forceRefresh: manual
                    )
                }
            )
        }

        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: primaryCountryCode,
            primaryCountryName: primaryCountryName,
            coverageCountryCodes: coverageCountryCodes,
            states: states,
            fetchedAt: now
        )
    }

    private func synchronizedTravelAlertsSnapshot(
        previous: TravelAlertsSnapshot?,
        settings: AppSettings,
        locationSnapshot: IPLocationSnapshot?
    ) -> TravelAlertsSnapshot {
        let enabledKinds = settings.travelAlertPreferences.enabledKinds
        let primaryCountryCode = locationSnapshot?.countryCode?.uppercased()
        let primaryCountryName = locationSnapshot?.country
        let coverageCountryCodes = coverageCountryCodes(for: primaryCountryCode)

        return TravelAlertsSnapshot(
            enabledKinds: enabledKinds,
            primaryCountryCode: primaryCountryCode,
            primaryCountryName: primaryCountryName,
            coverageCountryCodes: coverageCountryCodes,
            states: enabledKinds.map { kind in
                previous?.state(for: kind) ?? checkingAlertState(for: kind)
            },
            fetchedAt: enabledKinds.isEmpty ? nil : previous?.fetchedAt
        )
    }

    private func checkingAlertState(for kind: TravelAlertKind) -> TravelAlertSignalState {
        let source = sourceDescriptor(for: kind)
        return TravelAlertSignalState(
            kind: kind,
            status: .checking,
            signal: nil,
            reason: nil,
            sourceName: source.name,
            sourceURL: source.url,
            lastAttemptedAt: nil,
            lastSuccessAt: nil
        )
    }

    private func refreshAlertState(
        kind: TravelAlertKind,
        previous: TravelAlertSignalState?,
        source: TravelAlertSourceDescriptor,
        attemptedAt: Date,
        prerequisiteFailure: TravelAlertUnavailableReason?,
        fetch: () async throws -> TravelAlertSignalSnapshot
    ) async -> TravelAlertSignalState {
        let retainedSourceName = previous?.sourceName ?? source.name
        let retainedSourceURL = previous?.sourceURL ?? source.url

        if let prerequisiteFailure {
            return TravelAlertSignalState(
                kind: kind,
                status: .unavailable,
                signal: nil,
                reason: prerequisiteFailure,
                diagnosticSummary: nil,
                sourceName: retainedSourceName,
                sourceURL: retainedSourceURL,
                lastAttemptedAt: attemptedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }

        do {
            let signal = try await fetch()
            return TravelAlertSignalState(
                kind: kind,
                status: .ready,
                signal: signal,
                reason: nil,
                diagnosticSummary: nil,
                sourceName: signal.sourceName.isEmpty ? retainedSourceName : signal.sourceName,
                sourceURL: signal.sourceURL ?? retainedSourceURL,
                lastAttemptedAt: attemptedAt,
                lastSuccessAt: attemptedAt
            )
        } catch {
            let reason = unavailableReason(for: error)
            let diagnosticSummary = diagnosticSummary(for: error)
            logTravelAlertFailure(
                kind: kind,
                sourceName: retainedSourceName,
                reason: reason,
                diagnosticSummary: diagnosticSummary,
                error: error
            )

            if let previousSignal = previous?.signal {
                return TravelAlertSignalState(
                    kind: kind,
                    status: .stale,
                    signal: previousSignal,
                    reason: reason,
                    diagnosticSummary: diagnosticSummary,
                    sourceName: retainedSourceName,
                    sourceURL: retainedSourceURL,
                    lastAttemptedAt: attemptedAt,
                    lastSuccessAt: previous?.lastSuccessAt
                )
            }

            return TravelAlertSignalState(
                kind: kind,
                status: .unavailable,
                signal: nil,
                reason: reason,
                diagnosticSummary: diagnosticSummary,
                sourceName: retainedSourceName,
                sourceURL: retainedSourceURL,
                lastAttemptedAt: attemptedAt,
                lastSuccessAt: previous?.lastSuccessAt
            )
        }
    }

    private func sourceDescriptor(for kind: TravelAlertKind) -> TravelAlertSourceDescriptor {
        switch kind {
        case .advisory:
            dependencies.travelAdvisoryProvider.sourceDescriptor
        case .weather:
            dependencies.travelWeatherAlertsProvider.sourceDescriptor
        case .security:
            dependencies.regionalSecurityProvider.sourceDescriptor
        }
    }

    private func unavailableReason(for error: Error) -> TravelAlertUnavailableReason {
        switch error {
        case ProviderError.missingCountryCode:
            .countryRequired
        case ProviderError.missingCoordinate:
            .locationRequired
        case ProviderError.missingConfiguration:
            .sourceConfigurationRequired
        case ReliefWebProviderError.appNameApprovalRequired, ReliefWebProviderError.appNameMissing:
            .sourceConfigurationRequired
        default:
            .sourceUnavailable
        }
    }

    private func diagnosticSummary(for error: Error) -> String? {
        switch error {
        case let error as TravelAlertDiagnosticError:
            error.diagnosticSummary
        default:
            nil
        }
    }

    private func logTravelAlertFailure(
        kind: TravelAlertKind,
        sourceName: String,
        reason: TravelAlertUnavailableReason,
        diagnosticSummary: String?,
        error: Error
    ) {
        let summary = diagnosticSummary ?? unavailableSummary(for: reason)
        Self.logger.error(
            "Travel alert fetch failed kind=\(kind.rawValue, privacy: .public) source=\(sourceName, privacy: .public) summary=\(summary, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }

    private func unavailableSummary(for reason: TravelAlertUnavailableReason) -> String {
        switch reason {
        case .countryRequired:
            "Country needed for nearby alerts"
        case .locationRequired:
            "Location needed for local alerts"
        case .sourceUnavailable:
            "Source unavailable"
        case .sourceConfigurationRequired:
            "Source setup required"
        }
    }

    private func coverageCountryCodes(for primaryCountryCode: String?) -> [String] {
        guard let primaryCountryCode else {
            return []
        }

        return ([primaryCountryCode] + dependencies.neighborCountryResolver.neighboringCountryCodes(for: primaryCountryCode))
            .map { $0.uppercased() }
            .reduce(into: [String]()) { result, countryCode in
                if result.contains(countryCode) == false {
                    result.append(countryCode)
                }
            }
    }

    private func normalizedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }

        return value
    }
}

public let dashboardChartPointLimit = 120

public func projectedMetricHistory(_ points: [MetricPoint], maxPoints: Int = 120) -> [MetricPoint] {
    guard maxPoints > 1, points.count > maxPoints else {
        return points
    }

    let scale = Double(points.count - 1) / Double(maxPoints - 1)

    return (0..<maxPoints).map { position in
        let index: Int = if position == maxPoints - 1 {
            points.count - 1
        } else {
            Int((Double(position) * scale).rounded(.down))
        }

        return points[index]
    }
}
