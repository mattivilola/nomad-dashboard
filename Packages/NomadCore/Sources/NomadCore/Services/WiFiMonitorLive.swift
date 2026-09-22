import CoreLocation
import CoreWLAN
import Foundation
import OSLog

public struct LiveWiFiMonitor: WiFiMonitor {
    private static let logger = Logger(subsystem: "com.iloapps.NomadDashboard", category: "WiFiMonitor")

    public init() {}

    public func currentSnapshot() async -> WiFiSnapshot? {
        Self.logger.debug("currentSnapshot: reading CoreWLAN interface")
        guard let interface = CWWiFiClient.shared().interface() else {
            Self.logger.debug("currentSnapshot: no Wi-Fi interface")
            return nil
        }

        var ssid = interface.ssid()
        if ssid == nil, CLLocationManager.authorizationStatus().isNomadWeatherAuthorized {
            ssid = interface.ssid()
        }
        if ssid == nil {
            Self.logger.debug("currentSnapshot: SSID unavailable (location may be required)")
        }

        return WiFiSnapshot(
            interfaceName: interface.interfaceName,
            ssid: ssid,
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            transmitRateMbps: interface.transmitRate()
        )
    }
}
