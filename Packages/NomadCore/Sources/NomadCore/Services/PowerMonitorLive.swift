import Foundation
import IOKit
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

        let timeRemainingMinutes: Int?
        let timeToFullChargeMinutes: Int?

        switch state {
        case .battery:
            timeRemainingMinutes = Self.normalizedEstimatedMinutes(
                (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
            )
            timeToFullChargeMinutes = nil
        case .charging:
            timeRemainingMinutes = nil
            timeToFullChargeMinutes = Self.normalizedEstimatedMinutes(
                (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue
            )
        case .charged, .unknown:
            timeRemainingMinutes = nil
            timeToFullChargeMinutes = nil
        }
        let dischargeRateWatts = Self.resolveDischargeRateWatts(
            state: state,
            description: description,
            registryValues: Self.batteryRegistryValues()
        )

        var adapterWatts: Double?

        if let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapterDetails[kIOPSPowerAdapterWattsKey] as? NSNumber
        {
            adapterWatts = watts.doubleValue
        }

        return PowerSnapshot(
            chargePercent: chargePercent,
            state: state,
            timeRemainingMinutes: timeRemainingMinutes,
            timeToFullChargeMinutes: timeToFullChargeMinutes,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            dischargeRateWatts: dischargeRateWatts,
            adapterWatts: adapterWatts,
            collectedAt: Date()
        )
    }

    static func normalizedEstimatedMinutes(_ rawValue: Int?) -> Int? {
        guard let rawValue, rawValue >= 0 else {
            return nil
        }

        return rawValue
    }

    static func resolveDischargeRateWatts(
        state: PowerSourceState,
        description: [String: Any],
        registryValues: [String: Any]?
    ) -> Double? {
        guard state == .battery else {
            return nil
        }

        return dischargeRateWatts(fromPowerSourceDescription: description)
            ?? registryValues.flatMap(dischargeRateWatts(fromBatteryRegistryValues:))
    }

    static func dischargeRateWatts(fromPowerSourceDescription description: [String: Any]) -> Double? {
        guard let amperageMilliAmps = (description[kIOPSCurrentKey] as? NSNumber)?.doubleValue,
              let voltageMilliVolts = (description[kIOPSVoltageKey] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return dischargeRateWatts(amperageMilliAmps: amperageMilliAmps, voltageMilliVolts: voltageMilliVolts)
    }

    static func dischargeRateWatts(fromBatteryRegistryValues values: [String: Any]) -> Double? {
        let currentValue = values["InstantAmperage"] as? NSNumber ?? values["Amperage"] as? NSNumber
        let voltageValue = values["Voltage"] as? NSNumber ?? values["AppleRawBatteryVoltage"] as? NSNumber

        guard let currentValue,
              let amperageMilliAmps = normalizedSignedMilliAmps(currentValue),
              let voltageMilliVolts = voltageValue?.doubleValue
        else {
            return nil
        }

        return dischargeRateWatts(amperageMilliAmps: amperageMilliAmps, voltageMilliVolts: voltageMilliVolts)
    }

    static func normalizedSignedMilliAmps(_ value: NSNumber) -> Double? {
        let unsignedValue = value.uint64Value
        if unsignedValue > UInt64(Int64.max) {
            return Double(Int64(bitPattern: unsignedValue))
        }

        return value.doubleValue
    }

    private static func dischargeRateWatts(amperageMilliAmps: Double, voltageMilliVolts: Double) -> Double? {
        guard voltageMilliVolts > 0 else {
            return nil
        }

        return abs(amperageMilliAmps * voltageMilliVolts) / 1_000_000
    }

    private static func batteryRegistryValues() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let properties = properties?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }

        return properties
    }
}
