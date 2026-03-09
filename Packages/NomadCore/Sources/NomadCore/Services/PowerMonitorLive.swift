import Foundation
import IOKit.ps

public struct LivePowerMonitor: PowerMonitor {
    public init() {}

    public func currentSnapshot() async -> PowerSnapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        let currentCapacity = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
        let maxCapacity = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
        let chargePercent = { () -> Double? in
            guard let currentCapacity, let maxCapacity, maxCapacity > 0 else {
                return nil
            }

            return currentCapacity / maxCapacity
        }()

        let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
        let powerSource = (description[kIOPSPowerSourceStateKey] as? String) ?? ""
        let state: PowerSourceState = switch (powerSource, isCharging) {
        case (kIOPSACPowerValue, true):
            .charging
        case (kIOPSACPowerValue, false):
            .charged
        case (kIOPSBatteryPowerValue, _):
            .battery
        default:
            .unknown
        }

        let minutes = Self.normalizedTimeRemainingMinutes(
            (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
        )
        let amperageMilliAmps = (description[kIOPSCurrentKey] as? NSNumber)?.doubleValue
        let voltageMilliVolts = (description[kIOPSVoltageKey] as? NSNumber)?.doubleValue
        let dischargeRateWatts = { () -> Double? in
            guard let amperageMilliAmps, let voltageMilliVolts else {
                return nil
            }

            return abs(amperageMilliAmps * voltageMilliVolts) / 1_000_000
        }()

        var adapterWatts: Double?

        if let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapterDetails[kIOPSPowerAdapterWattsKey] as? NSNumber
        {
            adapterWatts = watts.doubleValue
        }

        return PowerSnapshot(
            chargePercent: chargePercent,
            state: state,
            timeRemainingMinutes: minutes,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            dischargeRateWatts: dischargeRateWatts,
            adapterWatts: adapterWatts,
            collectedAt: Date()
        )
    }

    static func normalizedTimeRemainingMinutes(_ rawValue: Int?) -> Int? {
        guard let rawValue, rawValue >= 0 else {
            return nil
        }

        return rawValue
    }
}
