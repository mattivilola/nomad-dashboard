import Foundation

public struct MenuBarStatusPresentation: Equatable, Sendable {
    public enum Branch: Equatable, Sendable {
        case battery
        case offline
        case headsUp
        case latencyCaution
        case latencyAttention
        case weather
        case latencyFallback
        case empty
    }

    public enum Tone: Equatable, Sendable {
        case standard
        case attention
    }

    public let text: String?
    public let symbolName: String
    public let branch: Branch
    public let tone: Tone

    public init(text: String?, symbolName: String, branch: Branch, tone: Tone = .standard) {
        self.text = text
        self.symbolName = symbolName
        self.branch = branch
        self.tone = tone
    }
}

public extension DashboardSnapshot {
    /// Precedence: metered usage, battery at or below 50%, offline, a caution-or-worse heads-up,
    /// then latency and weather. Info-level heads-ups never reach the menu bar.
    func menuBarStatusPresentation(
        showMeteredUsage: Bool,
        headsUp: DashboardInsight? = nil
    ) -> MenuBarStatusPresentation {
        if showMeteredUsage,
           meteredData.isFeatureEnabled,
           meteredData.isMonitoringActive,
           let capBytes = meteredData.capBytes,
           capBytes > 0
        {
            return MenuBarStatusPresentation(
                text: MeteredUsageFormatting.compactUsage(used: meteredData.usedBytes, cap: capBytes),
                symbolName: meteredData.isCapReached ? "antenna.radiowaves.left.and.right.slash" : "arrow.up.arrow.down.circle",
                branch: meteredData.isCapReached ? .latencyAttention : .latencyFallback,
                tone: meteredData.isCapReached ? .attention : .standard
            )
        }

        return defaultMenuBarStatusPresentation(headsUp: headsUp)
    }

    var menuBarStatusPresentation: MenuBarStatusPresentation {
        defaultMenuBarStatusPresentation(headsUp: nil)
    }

    private func defaultMenuBarStatusPresentation(headsUp: DashboardInsight?) -> MenuBarStatusPresentation {
        if let chargePercent = power.snapshot?.chargePercent, chargePercent <= 0.5 {
            return MenuBarStatusPresentation(
                text: Self.formatBatteryPercentage(chargePercent),
                symbolName: Self.batterySymbolName(for: chargePercent),
                branch: .battery
            )
        }

        if network.connectivity.internetState == .offline {
            return Self.offlineMenuBarStatusPresentation
        }

        if let headsUp, headsUp.severity >= .caution {
            return MenuBarStatusPresentation(
                text: headsUp.menuBarText,
                symbolName: headsUp.symbolName,
                branch: .headsUp,
                tone: headsUp.severity == .attention ? .attention : .standard
            )
        }

        if let latencyMilliseconds = network.latency?.milliseconds, latencyMilliseconds >= 60 {
            return MenuBarStatusPresentation(
                text: Self.formatLatency(latencyMilliseconds),
                symbolName: latencyMilliseconds > 120 ? "wifi.exclamationmark" : "wifi",
                branch: latencyMilliseconds > 120 ? .latencyAttention : .latencyCaution
            )
        }

        if let weather, let temperatureCelsius = weather.currentTemperatureCelsius {
            return MenuBarStatusPresentation(
                text: TravelUnitFormatting.temperature(temperatureCelsius),
                symbolName: weather.symbolName,
                branch: .weather
            )
        }

        if let latencyMilliseconds = network.latency?.milliseconds {
            return MenuBarStatusPresentation(
                text: Self.formatLatency(latencyMilliseconds),
                symbolName: "wifi",
                branch: .latencyFallback
            )
        }

        return MenuBarStatusPresentation(
            text: nil,
            symbolName: "suitcase.rolling.fill",
            branch: .empty
        )
    }

    private static let offlineMenuBarStatusPresentation = MenuBarStatusPresentation(
        text: nil,
        symbolName: "wifi.slash",
        branch: .offline,
        tone: .attention
    )

    private static func formatBatteryPercentage(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func formatLatency(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }

    private static func batterySymbolName(for chargePercent: Double) -> String {
        switch chargePercent {
        case ...0.25:
            "battery.25percent"
        case ...0.5:
            "battery.50percent"
        case ...0.75:
            "battery.75percent"
        default:
            "battery.100percent"
        }
    }
}
