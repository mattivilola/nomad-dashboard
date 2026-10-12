import Foundation
import OSLog

public struct MeteredDataTickInput: Sendable {
    public let settings: AppSettings
    public let wifiSSID: String?
    public let wifiInterfaceName: String?
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let isWiFiConnected: Bool
    public let isLocationAuthorizedForSSID: Bool
    public let now: Date

    public init(
        settings: AppSettings,
        wifiSSID: String?,
        wifiInterfaceName: String?,
        isExpensive: Bool,
        isConstrained: Bool,
        isWiFiConnected: Bool = false,
        isLocationAuthorizedForSSID: Bool = false,
        now: Date = .now
    ) {
        self.settings = settings
        self.wifiSSID = wifiSSID
        self.wifiInterfaceName = wifiInterfaceName
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.isWiFiConnected = isWiFiConnected
        self.isLocationAuthorizedForSSID = isLocationAuthorizedForSSID
        self.now = now
    }
}

public actor MeteredDataController {
    private static let logger = Logger(subsystem: "com.iloapps.NomadDashboard", category: "MeteredData")
    private static let warningPercents = [80, 95, 100]

    private let store: MeteredUsageStore
    private let counterReader: any DetailedInterfaceCounterReading
    private let routeReader: any DefaultRouteInterfaceReading
    private var lastSnapshot: MeteredUsageSnapshot = .disabled

    public init(
        store: MeteredUsageStore,
        counterReader: any DetailedInterfaceCounterReading = SystemDetailedInterfaceCounterReader(),
        routeReader: any DefaultRouteInterfaceReading = DarwinDefaultRouteInterfaceReader()
    ) {
        self.store = store
        self.counterReader = counterReader
        self.routeReader = routeReader
    }

    public func flush() async {
        try? await store.save()
    }

    public func currentSnapshot() -> MeteredUsageSnapshot {
        lastSnapshot
    }

    public func isMonitoringActive() -> Bool {
        lastSnapshot.isMonitoringActive
    }

    public func tick(input: MeteredDataTickInput) async -> MeteredUsageSnapshot {
        Self.logger.debug("tick: metered data evaluation started")
        guard input.settings.meteredDataEnabled else {
            lastSnapshot = .disabled
            return .disabled
        }

        var state = await store.currentState()
        updateSSIDCache(state: &state, input: input)

        let cachedEntry = input.wifiInterfaceName.flatMap { state.ssidCacheByInterface[$0] }
        let resolved = MeteredNetworkKeyResolver.resolve(
            ssid: input.wifiSSID,
            interfaceName: input.wifiInterfaceName,
            isExpensive: input.isExpensive,
            isConstrained: input.isConstrained,
            cachedSSID: cachedEntry,
            now: input.now
        )
        let profile = input.settings.knownMeteredProfiles.first { $0.networkKey == resolved.key }
        let monitoringActive = shouldMonitor(
            settings: input.settings,
            profile: profile,
            resolved: resolved,
            isExpensive: input.isExpensive,
            isConstrained: input.isConstrained,
            isWiFiConnected: input.isWiFiConnected
        )

        let meteredInterface = resolveMeteredInterface(wifiInterfaceName: input.wifiInterfaceName)
        let billingPeriod = profile?.periodKind ?? input.settings.defaultMeteredBillingPeriod
        state = alignPeriodIfNeeded(state: state, billingPeriod: billingPeriod, now: input.now)

        if monitoringActive {
            if state.sessionNetworkKey != resolved.key {
                if canMigrateSession(from: state.sessionNetworkKey, to: resolved) {
                    Self.logger.info("tick: migrating metered session to \(resolved.key, privacy: .public)")
                    state.sessionNetworkKey = resolved.key
                    state.sessionDisplayName = profile?.displayName ?? resolved.displayName
                } else {
                    Self.logger.info("tick: starting new metered session for \(resolved.key, privacy: .public)")
                    closeSession(&state, endedAt: input.now)
                    state.sessionNetworkKey = resolved.key
                    state.sessionDisplayName = profile?.displayName ?? resolved.displayName
                    state.sessionStartedAt = input.now
                    state.sessionBytesReceived = 0
                    state.sessionBytesSent = 0
                    state.lastInterfaceCounters = [:]
                    state.lastInterfaceName = meteredInterface
                }
            }

            if let counters = counterReader.read(), let meteredInterface {
                applyCounterDelta(
                    state: &state,
                    interfaceName: meteredInterface,
                    counters: counters,
                    now: input.now
                )
            }
        } else if state.sessionNetworkKey != nil {
            Self.logger.info("tick: ending metered session")
            closeSession(&state, endedAt: input.now)
        }

        let capBytes = profile?.capBytes ?? input.settings.defaultMeteredCapBytes
        let usageBytes = usageTotal(for: billingPeriod, state: state)
        let usageFraction = capBytes.map { cap in
            guard cap > 0 else { return 0.0 }
            return min(Double(usageBytes) / Double(cap), 1.0)
        }
        let isCapReached = capBytes.map { usageBytes >= $0 } ?? false
        let capAlertSignal = evaluateCapAlerts(
            state: &state,
            usageBytes: usageBytes,
            capBytes: capBytes,
            isMonitoringActive: monitoringActive
        )

        do {
            try await store.update { persisted in
                persisted = state
            }
        } catch {
            Self.logger.error("tick: failed to persist metered usage state")
        }

        let needsLocation = input.isWiFiConnected
            && MeteredNetworkKeyResolver.normalizedSSID(input.wifiSSID) == nil
            && resolved.source != .cachedSSID
            && !input.isLocationAuthorizedForSSID

        let snapshot = MeteredUsageSnapshot(
            isFeatureEnabled: true,
            isMonitoringActive: monitoringActive,
            networkKey: resolved.key,
            networkDisplayName: profile?.displayName ?? resolved.displayName,
            meteredInterfaceName: meteredInterface,
            sessionStartedAt: state.sessionStartedAt,
            sessionBytesReceived: state.sessionBytesReceived,
            sessionBytesSent: state.sessionBytesSent,
            periodStartedAt: state.periodStartedAt,
            periodBytesReceived: state.periodBytesReceived,
            periodBytesSent: state.periodBytesSent,
            capBytes: capBytes,
            usageFraction: usageFraction,
            isCapReached: isCapReached,
            billingPeriod: billingPeriod,
            manualSessionEnabled: input.settings.manualMeteredSessionEnabled,
            isKnownMeteredNetwork: profile?.isUserMarkedMetered == true,
            networkNameSource: resolved.source,
            isWiFiConnected: input.isWiFiConnected,
            needsLocationForWiFiNames: needsLocation,
            statusMessage: statusMessage(
                monitoringActive: monitoringActive,
                isCapReached: isCapReached,
                capBytes: capBytes,
                resolved: resolved,
                needsLocation: needsLocation
            ),
            capAlertSignal: capAlertSignal
        )
        lastSnapshot = snapshot
        return snapshot
    }

    public func resetPeriod() async throws {
        Self.logger.info("resetPeriod: clearing metered usage counters")
        try await store.update { state in
            state.periodBytesReceived = 0
            state.periodBytesSent = 0
            state.periodStartedAt = .now
            state.sessionBytesReceived = 0
            state.sessionBytesSent = 0
            state.firedWarningPercents = []
        }
    }

    private func shouldMonitor(
        settings: AppSettings,
        profile: MeteredNetworkProfile?,
        resolved: MeteredNetworkIdentity,
        isExpensive: Bool,
        isConstrained: Bool,
        isWiFiConnected: Bool
    ) -> Bool {
        if settings.manualMeteredSessionEnabled {
            return true
        }
        if settings.autoMonitorRememberedWiFiHotspots,
           profile?.isUserMarkedMetered == true,
           profile?.autoEnableMonitoring != false
        {
            return true
        }
        if settings.autoEnableOnExpensivePath, isExpensive || isConstrained {
            return true
        }
        return false
    }

    private func updateSSIDCache(state: inout MeteredPersistentState, input: MeteredDataTickInput) {
        guard let interfaceName = input.wifiInterfaceName,
              let ssid = MeteredNetworkKeyResolver.normalizedSSID(input.wifiSSID)
        else {
            return
        }

        state.ssidCacheByInterface[interfaceName] = MeteredWiFiSSIDCacheEntry(
            ssid: ssid,
            interfaceName: interfaceName,
            lastSeenAt: input.now
        )
    }

    private func canMigrateSession(from previousKey: String?, to resolved: MeteredNetworkIdentity) -> Bool {
        guard let previousKey, resolved.isWiFiNetwork else { return false }
        return previousKey == "path:expensive" || previousKey.hasPrefix("iface:")
    }

    private func resolveMeteredInterface(wifiInterfaceName: String?) -> String? {
        if let routeInterface = routeReader.defaultInterfaceName() {
            return routeInterface
        }
        if let wifiInterfaceName, !wifiInterfaceName.isEmpty {
            return wifiInterfaceName
        }
        return counterReader.read()?.primaryInterface
    }

    private func applyCounterDelta(
        state: inout MeteredPersistentState,
        interfaceName: String,
        counters: DetailedInterfaceCounterSnapshot,
        now: Date
    ) {
        guard let currentTotals = counters.perInterface[interfaceName] else {
            Self.logger.debug("applyCounterDelta: no counters for interface \(interfaceName, privacy: .public)")
            return
        }

        let previousTotals = state.lastInterfaceCounters[interfaceName]
        let delta = InterfaceByteDeltaAccounting.delta(current: currentTotals, previous: previousTotals)
        state.lastInterfaceCounters[interfaceName] = currentTotals
        state.lastInterfaceName = interfaceName
        state.sessionBytesReceived &+= delta.receivedBytes
        state.sessionBytesSent &+= delta.sentBytes
        state.periodBytesReceived &+= delta.receivedBytes
        state.periodBytesSent &+= delta.sentBytes
        _ = now
    }

    private func closeSession(_ state: inout MeteredPersistentState, endedAt: Date) {
        _ = endedAt
        state.sessionNetworkKey = nil
        state.sessionDisplayName = nil
        state.sessionStartedAt = nil
        state.sessionBytesReceived = 0
        state.sessionBytesSent = 0
        state.lastInterfaceCounters = [:]
        state.lastInterfaceName = nil
    }

    private func alignPeriodIfNeeded(
        state: MeteredPersistentState,
        billingPeriod: MeteredBillingPeriod,
        now: Date
    ) -> MeteredPersistentState {
        var updated = state
        updated.periodKind = billingPeriod

        switch billingPeriod {
        case .calendarMonth:
            let calendar = Calendar.current
            if !calendar.isDate(updated.periodStartedAt, equalTo: now, toGranularity: .month) {
                updated.periodStartedAt = now
                updated.periodBytesReceived = 0
                updated.periodBytesSent = 0
                updated.firedWarningPercents = []
            }
        case .session:
            break
        case .manual:
            break
        }

        return updated
    }

    private func usageTotal(for billingPeriod: MeteredBillingPeriod, state: MeteredPersistentState) -> UInt64 {
        switch billingPeriod {
        case .session:
            state.sessionBytesReceived + state.sessionBytesSent
        case .calendarMonth, .manual:
            state.periodBytesReceived + state.periodBytesSent
        }
    }

    private func evaluateCapAlerts(
        state: inout MeteredPersistentState,
        usageBytes: UInt64,
        capBytes: UInt64?,
        isMonitoringActive: Bool
    ) -> MeteredDataCapAlertSignal? {
        guard isMonitoringActive, let capBytes, capBytes > 0 else { return nil }

        for percent in Self.warningPercents {
            let threshold = UInt64(Double(capBytes) * Double(percent) / 100.0)
            guard usageBytes >= threshold, !state.firedWarningPercents.contains(percent) else { continue }
            state.firedWarningPercents.append(percent)
            if percent >= 100 {
                return .reached
            }
            return .warning(percent: percent)
        }

        return nil
    }

    private func statusMessage(
        monitoringActive: Bool,
        isCapReached: Bool,
        capBytes: UInt64?,
        resolved: MeteredNetworkIdentity,
        needsLocation: Bool
    ) -> String? {
        if isCapReached {
            return "Data cap reached — Nomad stays in Low Data until you reset or leave this network."
        }
        if needsLocation {
            return "Allow location access so macOS can expose this Wi‑Fi name (e.g. your hotspot SSID) for separate caps per network."
        }
        if monitoringActive, resolved.source == .cachedSSID {
            return "Using the last known Wi‑Fi name for this adapter. Monitoring continues on the default-route interface."
        }
        if monitoringActive, !resolved.isWiFiNetwork {
            return "Wi‑Fi name unavailable — usage is grouped as “\(resolved.displayName)”. Remember each hotspot once its name appears."
        }
        if monitoringActive, capBytes == nil {
            return "Monitoring this connection. Set a cap in Settings to get warnings."
        }
        if monitoringActive {
            return "Monitoring hotspot data on the default-route interface."
        }
        return nil
    }
}
