import Foundation

public struct MenuBarStatusPresentation: Equatable, Sendable {
    public enum Branch: Equatable, Sendable {
        case battery
        case latencyCaution
        case latencyAttention
        case weather
        case latencyFallback
        case empty
    }

    public let text: String?
    public let symbolName: String
    public let branch: Branch

    public init(text: String?, symbolName: String, branch: Branch) {
        self.text = text
        self.symbolName = symbolName
        self.branch = branch
    }
}

public extension DashboardSnapshot {
    var menuBarStatusPresentation: MenuBarStatusPresentation {
        if let chargePercent = power.snapshot?.chargePercent, chargePercent <= 0.5 {
            return MenuBarStatusPresentation(
                text: Self.formatBatteryPercentage(chargePercent),
                symbolName: Self.batterySymbolName(for: chargePercent),
                branch: .battery
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
                text: Self.formatCompactTemperature(temperatureCelsius),
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

    private static func formatBatteryPercentage(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func formatLatency(_ value: Double) -> String {
        String(format: "%.0f ms", value)
    }

    private static func formatCompactTemperature(_ value: Double) -> String {
        String(format: "%.0fC", value)
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
