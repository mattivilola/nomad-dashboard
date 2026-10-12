import Foundation
import NomadCore

/// The four rows of the Travel Context card, already condensed: Wi‑Fi name and signal share
/// one row, and the time zone rides along with the location.
struct TravelContextPresentation: Equatable {
    let publicIP: String
    let hasPublicIP: Bool
    /// "Nomad Hub · −56 dBm · 720 Mbps".
    let wifi: String
    /// Full RSSI, noise and transmit rate for hover; nil when there is nothing to add.
    let wifiHelp: String?
    let vpn: String
    /// "Valencia, Spain · Europe/Madrid".
    let location: String

    init(
        travelContext: TravelContextSnapshot,
        issues: [DashboardIssue],
        isPublicIPLocationEnabled: Bool
    ) {
        if let address = travelContext.publicIP?.address {
            publicIP = address
            hasPublicIP = true
        } else {
            hasPublicIP = false
            publicIP = issues.contains(.publicIPLookupUnavailable) ? "Lookup unavailable" : "Refreshing…"
        }

        wifi = Self.wifiValue(travelContext.wifi)
        wifiHelp = Self.wifiHelp(travelContext.wifi)
        vpn = Self.vpnValue(travelContext.vpn)

        let place: String = if let formatted = travelContext.location?.cityCountryDescription {
            formatted
        } else if issues.contains(.ipLocationUnavailable) {
            "Lookup unavailable"
        } else if isPublicIPLocationEnabled == false {
            "Location off"
        } else {
            "Refreshing…"
        }
        location = [place, travelContext.timeZoneIdentifier.nilIfEmpty]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    /// "−56 dBm": a typographic minus keeps negative signal levels readable at caption size.
    static func decibelText(_ value: Int) -> String {
        value < 0 ? "\u{2212}\(abs(value)) dBm" : "\(value) dBm"
    }

    private static func wifiValue(_ snapshot: WiFiSnapshot?) -> String {
        guard let snapshot else {
            return "Not connected"
        }

        let pieces = [
            snapshot.ssid ?? "Connected",
            snapshot.rssi.map(decibelText),
            snapshot.transmitRateMbps.map { String(format: "%.0f Mbps", $0) }
        ]

        return pieces.compactMap(\.self).joined(separator: " · ")
    }

    private static func wifiHelp(_ snapshot: WiFiSnapshot?) -> String? {
        guard let snapshot else {
            return nil
        }

        let pieces = [
            snapshot.rssi.map { "Signal \(decibelText($0))" },
            snapshot.noise.map { "Noise \(decibelText($0))" },
            snapshot.transmitRateMbps.map { String(format: "Transmit rate %.0f Mbps", $0) }
        ]
        .compactMap(\.self)

        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    private static func vpnValue(_ snapshot: VPNStatusSnapshot?) -> String {
        guard let snapshot, snapshot.isActive else {
            return "Inactive"
        }

        if snapshot.serviceNames.isEmpty == false {
            return snapshot.serviceNames.joined(separator: ", ")
        }

        if snapshot.interfaceNames.isEmpty == false {
            return snapshot.interfaceNames.joined(separator: ", ")
        }

        return "Active"
    }
}
