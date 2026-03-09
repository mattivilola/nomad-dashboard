import CoreWLAN
import Foundation

public struct LiveWiFiMonitor: WiFiMonitor {
    public init() {}

    public func currentSnapshot() async -> WiFiSnapshot? {
        guard let interface = CWWiFiClient.shared().interface() else {
            return nil
        }

        return WiFiSnapshot(
            interfaceName: interface.interfaceName,
            ssid: interface.ssid(),
            rssi: interface.rssiValue(),
            noise: interface.noiseMeasurement(),
            transmitRateMbps: interface.transmitRate()
        )
    }
}

