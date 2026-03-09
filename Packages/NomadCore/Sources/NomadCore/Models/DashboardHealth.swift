import Foundation

public enum DashboardIssue: String, Codable, CaseIterable, Equatable, Sendable {
    case publicIPLookupUnavailable
    case ipLocationUnavailable
    case weatherLocationRequired
    case weatherUnavailable
    case marineSpotNotConfigured
    case marineSpotInvalid
    case marineUnavailable
    case travelAdvisoryCountryRequired
    case travelAdvisoryUnavailable
    case travelWeatherAlertsLocationRequired
    case travelWeatherAlertsUnavailable
    case regionalSecurityCountryRequired
    case regionalSecurityUnavailable
}

public enum HealthLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case ready
    case caution
    case attention
    case unavailable
}

public struct SectionHealth: Equatable, Sendable {
    public let label: String
    public let level: HealthLevel
    public let reason: String
    public let symbolName: String

    public init(label: String, level: HealthLevel, reason: String, symbolName: String) {
        self.label = label
        self.level = level
        self.reason = reason
        self.symbolName = symbolName
    }
}

public struct DashboardHealthSummary: Equatable, Sendable {
    public let overall: SectionHealth
    public let network: SectionHealth
    public let power: SectionHealth

    public init(overall: SectionHealth, network: SectionHealth, power: SectionHealth) {
        self.overall = overall
        self.network = network
        self.power = power
    }
}

public enum DashboardHealthEvaluator {
    public static func makeSummary(
        network: NetworkSectionSnapshot,
        power: PowerSectionSnapshot,
        travelContext: TravelContextSnapshot,
        appState: AppStatusSnapshot
    ) -> DashboardHealthSummary {
        let networkHealth = evaluateNetwork(network: network, travelContext: travelContext, appState: appState)
        let powerHealth = evaluatePower(power: power)
        let overallHealth = evaluateOverall(network: networkHealth, power: powerHealth)

        return DashboardHealthSummary(overall: overallHealth, network: networkHealth, power: powerHealth)
    }

    private static func evaluateNetwork(
        network: NetworkSectionSnapshot,
        travelContext: TravelContextSnapshot,
        appState: AppStatusSnapshot
    ) -> SectionHealth {
        guard let latency = network.latency else {
            return SectionHealth(
                label: "Waiting",
                level: .unavailable,
                reason: "Collecting network quality",
                symbolName: "timer"
            )
        }

        guard network.throughput?.activeInterface != nil else {
            return SectionHealth(
                label: "Attention",
                level: .attention,
                reason: "No active network interface",
                symbolName: "wifi.exclamationmark"
            )
        }

        if latency.milliseconds > 120 {
            return SectionHealth(
                label: "Attention",
                level: .attention,
                reason: "Latency \(formatLatency(latency.milliseconds))",
                symbolName: "wifi.exclamationmark"
            )
        }

        if let jitter = latency.jitterMilliseconds, jitter > 25 {
            return SectionHealth(
                label: "Attention",
                level: .attention,
                reason: "Jitter \(formatLatency(jitter))",
                symbolName: "waveform.path.ecg"
            )
        }

        if latency.milliseconds >= 60 {
            return SectionHealth(
                label: "Caution",
                level: .caution,
                reason: "Latency \(formatLatency(latency.milliseconds))",
                symbolName: "wifi"
            )
        }

        if let jitter = latency.jitterMilliseconds, jitter >= 10 {
            return SectionHealth(
                label: "Caution",
                level: .caution,
                reason: "Jitter \(formatLatency(jitter))",
                symbolName: "waveform.path.ecg"
            )
        }

        if let rssi = travelContext.wifi?.rssi, rssi <= -70 {
            return SectionHealth(
                label: "Caution",
                level: .caution,
                reason: "Weak Wi-Fi signal",
                symbolName: "wifi"
            )
        }

        if appState.issues.contains(.publicIPLookupUnavailable) {
            return SectionHealth(
                label: "Caution",
                level: .caution,
                reason: "Public IP lookup unavailable",
                symbolName: "globe.badge.chevron.backward"
            )
        }

        return SectionHealth(
            label: "Ready",
            level: .ready,
            reason: stableNetworkReason(network: network, travelContext: travelContext),
            symbolName: "checkmark.circle.fill"
        )
    }

    private static func evaluatePower(power: PowerSectionSnapshot) -> SectionHealth {
        guard let snapshot = power.snapshot else {
            return SectionHealth(
                label: "Waiting",
                level: .unavailable,
                reason: "Collecting power status",
                symbolName: "timer"
            )
        }

        switch snapshot.state {
        case .unknown:
            return SectionHealth(
                label: "Waiting",
                level: .unavailable,
                reason: "Power source unavailable",
                symbolName: "battery.0"
            )
        case .battery:
            if let chargePercent = snapshot.chargePercent, chargePercent < 0.25 {
                return SectionHealth(
                    label: "Attention",
                    level: .attention,
                    reason: "Battery \(formatPercentage(chargePercent))",
                    symbolName: "battery.25percent"
                )
            }

            if let timeRemainingMinutes = snapshot.timeRemainingMinutes, timeRemainingMinutes < 45 {
                return SectionHealth(
                    label: "Attention",
                    level: .attention,
                    reason: "\(formatMinutes(timeRemainingMinutes)) remaining",
                    symbolName: "battery.25percent"
                )
            }

            if let chargePercent = snapshot.chargePercent, chargePercent <= 0.5 {
                return SectionHealth(
                    label: "Caution",
                    level: .caution,
                    reason: "Battery \(formatPercentage(chargePercent))",
                    symbolName: "battery.50percent"
                )
            }

            if let timeRemainingMinutes = snapshot.timeRemainingMinutes, timeRemainingMinutes <= 120 {
                return SectionHealth(
                    label: "Caution",
                    level: .caution,
                    reason: "\(formatMinutes(timeRemainingMinutes)) remaining",
                    symbolName: "battery.50percent"
                )
            }

            if snapshot.isLowPowerModeEnabled {
                return SectionHealth(
                    label: "Caution",
                    level: .caution,
                    reason: "Low Power Mode enabled",
                    symbolName: "leaf.fill"
                )
            }

            return SectionHealth(
                label: "Ready",
                level: .ready,
                reason: readyPowerReason(snapshot),
                symbolName: "battery.100percent"
            )
        case .charging:
            if snapshot.isLowPowerModeEnabled {
                return SectionHealth(
                    label: "Caution",
                    level: .caution,
                    reason: "Low Power Mode enabled",
                    symbolName: "leaf.fill"
                )
            }

            return SectionHealth(
                label: "Ready",
                level: .ready,
                reason: "Charging on external power",
                symbolName: "bolt.batteryblock.fill"
            )
        case .charged:
            if snapshot.isLowPowerModeEnabled {
                return SectionHealth(
                    label: "Caution",
                    level: .caution,
                    reason: "Low Power Mode enabled",
                    symbolName: "leaf.fill"
                )
            }

            return SectionHealth(
                label: "Ready",
                level: .ready,
                reason: "Connected to power",
                symbolName: "powerplug.fill"
            )
        }
    }

    private static func evaluateOverall(network: SectionHealth, power: SectionHealth) -> SectionHealth {
        if network.level == .attention {
            return SectionHealth(
                label: "Attention",
                level: .attention,
                reason: "Network: \(network.reason)",
                symbolName: "exclamationmark.triangle.fill"
            )
        }

        if power.level == .attention {
            return SectionHealth(
                label: "Attention",
                level: .attention,
                reason: "Power: \(power.reason)",
                symbolName: "exclamationmark.triangle.fill"
            )
        }

        if network.level == .caution {
            return SectionHealth(
                label: "Caution",
                level: .caution,
                reason: "Network: \(network.reason)",
                symbolName: "exclamationmark.shield.fill"
            )
        }

        if power.level == .caution {
            return SectionHealth(
                label: "Caution",
                level: .caution,
                reason: "Power: \(power.reason)",
                symbolName: "exclamationmark.shield.fill"
            )
        }

        if network.level == .unavailable {
            return SectionHealth(
                label: "Waiting",
                level: .unavailable,
                reason: "Network: \(network.reason)",
                symbolName: "timer"
            )
        }

        if power.level == .unavailable {
            return SectionHealth(
                label: "Waiting",
                level: .unavailable,
                reason: "Power: \(power.reason)",
                symbolName: "timer"
            )
        }

        return SectionHealth(
            label: "Ready",
            level: .ready,
            reason: "Network and power look good",
            symbolName: "checkmark.seal.fill"
        )
    }

    private static func stableNetworkReason(network: NetworkSectionSnapshot, travelContext: TravelContextSnapshot) -> String {
        if let interfaceName = network.throughput?.activeInterface {
            return "Stable on \(interfaceName)"
        }

        if let ssid = travelContext.wifi?.ssid {
            return "Stable on \(ssid)"
        }

        return "Connection looks stable"
    }

    private static func readyPowerReason(_ snapshot: PowerSnapshot) -> String {
        if let timeRemainingMinutes = snapshot.timeRemainingMinutes {
            return "\(formatMinutes(timeRemainingMinutes)) remaining"
        }

        if let chargePercent = snapshot.chargePercent {
            return "Battery \(formatPercentage(chargePercent))"
        }

        return "Power status looks good"
    }

    private static func formatLatency(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }

    private static func formatPercentage(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func formatMinutes(_ value: Int) -> String {
        let hours = value / 60
        let minutes = value % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}
