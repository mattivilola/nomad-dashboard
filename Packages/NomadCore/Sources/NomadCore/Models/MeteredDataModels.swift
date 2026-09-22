import Foundation

public enum MeteredBillingPeriod: String, Codable, CaseIterable, Sendable {
    case session
    case calendarMonth
    case manual

    public var title: String {
        switch self {
        case .session: "Per connection"
        case .calendarMonth: "Calendar month"
        case .manual: "Until you reset"
        }
    }
}

public struct MeteredNetworkProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var networkKey: String
    public var displayName: String
    public var isUserMarkedMetered: Bool
    public var capBytes: UInt64?
    public var periodKind: MeteredBillingPeriod
    public var autoEnableMonitoring: Bool

    public init(
        id: UUID = UUID(),
        networkKey: String,
        displayName: String,
        isUserMarkedMetered: Bool = true,
        capBytes: UInt64? = nil,
        periodKind: MeteredBillingPeriod = .session,
        autoEnableMonitoring: Bool = true
    ) {
        self.id = id
        self.networkKey = networkKey
        self.displayName = displayName
        self.isUserMarkedMetered = isUserMarkedMetered
        self.capBytes = capBytes
        self.periodKind = periodKind
        self.autoEnableMonitoring = autoEnableMonitoring
    }
}

public enum MeteredNetworkNameSource: String, Codable, Sendable, Equatable {
    case liveSSID
    case cachedSSID
    case expensivePath
    case interfaceFallback
    case unknown
}

public struct MeteredNetworkIdentity: Equatable, Sendable {
    public let key: String
    public let displayName: String
    public let source: MeteredNetworkNameSource

    public var isWiFiNetwork: Bool {
        key.hasPrefix("wifi:")
    }
}

public struct MeteredWiFiSSIDCacheEntry: Codable, Equatable, Sendable {
    public var ssid: String
    public var interfaceName: String
    public var lastSeenAt: Date

    public init(ssid: String, interfaceName: String, lastSeenAt: Date) {
        self.ssid = ssid
        self.interfaceName = interfaceName
        self.lastSeenAt = lastSeenAt
    }
}

public enum MeteredNetworkKeyResolver {
    public static let cachedSSIDMaxAge: TimeInterval = 8 * 3_600

    public static func resolve(
        ssid: String?,
        interfaceName: String?,
        isExpensive: Bool,
        isConstrained: Bool,
        cachedSSID: MeteredWiFiSSIDCacheEntry? = nil,
        now: Date = .now
    ) -> MeteredNetworkIdentity {
        if let normalized = normalizedSSID(ssid) {
            return MeteredNetworkIdentity(key: "wifi:\(normalized)", displayName: normalized, source: .liveSSID)
        }

        if let cachedSSID,
           cachedSSID.interfaceName == interfaceName || interfaceName == nil,
           now.timeIntervalSince(cachedSSID.lastSeenAt) <= cachedSSIDMaxAge,
           let normalized = normalizedSSID(cachedSSID.ssid)
        {
            return MeteredNetworkIdentity(
                key: "wifi:\(normalized)",
                displayName: normalized,
                source: .cachedSSID
            )
        }

        if isExpensive || isConstrained {
            return MeteredNetworkIdentity(key: "path:expensive", displayName: "Expensive connection", source: .expensivePath)
        }
        if let interfaceName, !interfaceName.isEmpty {
            return MeteredNetworkIdentity(key: "iface:\(interfaceName)", displayName: interfaceName, source: .interfaceFallback)
        }
        return MeteredNetworkIdentity(key: "unknown", displayName: "Unknown network", source: .unknown)
    }

    public static func normalizedSSID(_ ssid: String?) -> String? {
        guard let trimmed = ssid?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public enum MeteredDataCapAlertSignal: Equatable, Sendable {
    case warning(percent: Int)
    case reached
}

public struct MeteredUsageSnapshot: Equatable, Sendable {
    public let isFeatureEnabled: Bool
    public let isMonitoringActive: Bool
    public let networkKey: String?
    public let networkDisplayName: String?
    public let meteredInterfaceName: String?
    public let sessionStartedAt: Date?
    public let sessionBytesReceived: UInt64
    public let sessionBytesSent: UInt64
    public let periodBytesReceived: UInt64
    public let periodBytesSent: UInt64
    public let capBytes: UInt64?
    public let usageFraction: Double?
    public let isCapReached: Bool
    public let billingPeriod: MeteredBillingPeriod
    public let manualSessionEnabled: Bool
    public let isKnownMeteredNetwork: Bool
    public let networkNameSource: MeteredNetworkNameSource
    public let isWiFiConnected: Bool
    public let needsLocationForWiFiNames: Bool
    public let statusMessage: String?
    public let capAlertSignal: MeteredDataCapAlertSignal?

    public var sessionTotalBytes: UInt64 {
        sessionBytesReceived + sessionBytesSent
    }

    public var periodTotalBytes: UInt64 {
        periodBytesReceived + periodBytesSent
    }

    public static let disabled = MeteredUsageSnapshot(
        isFeatureEnabled: false,
        isMonitoringActive: false,
        networkKey: nil,
        networkDisplayName: nil,
        meteredInterfaceName: nil,
        sessionStartedAt: nil,
        sessionBytesReceived: 0,
        sessionBytesSent: 0,
        periodBytesReceived: 0,
        periodBytesSent: 0,
        capBytes: nil,
        usageFraction: nil,
        isCapReached: false,
        billingPeriod: .session,
        manualSessionEnabled: false,
        isKnownMeteredNetwork: false,
        networkNameSource: .unknown,
        isWiFiConnected: false,
        needsLocationForWiFiNames: false,
        statusMessage: nil,
        capAlertSignal: nil
    )
}

public struct MeteredPersistentState: Codable, Equatable, Sendable {
    public var periodKind: MeteredBillingPeriod
    public var periodStartedAt: Date
    public var periodBytesReceived: UInt64
    public var periodBytesSent: UInt64
    public var sessionNetworkKey: String?
    public var sessionDisplayName: String?
    public var sessionStartedAt: Date?
    public var sessionBytesReceived: UInt64
    public var sessionBytesSent: UInt64
    public var lastInterfaceName: String?
    public var lastInterfaceCounters: [String: InterfaceByteTotals]
    public var firedWarningPercents: [Int]
    public var ssidCacheByInterface: [String: MeteredWiFiSSIDCacheEntry]

    public init(
        periodKind: MeteredBillingPeriod = .session,
        periodStartedAt: Date = .now,
        periodBytesReceived: UInt64 = 0,
        periodBytesSent: UInt64 = 0,
        sessionNetworkKey: String? = nil,
        sessionDisplayName: String? = nil,
        sessionStartedAt: Date? = nil,
        sessionBytesReceived: UInt64 = 0,
        sessionBytesSent: UInt64 = 0,
        lastInterfaceName: String? = nil,
        lastInterfaceCounters: [String: InterfaceByteTotals] = [:],
        firedWarningPercents: [Int] = [],
        ssidCacheByInterface: [String: MeteredWiFiSSIDCacheEntry] = [:]
    ) {
        self.periodKind = periodKind
        self.periodStartedAt = periodStartedAt
        self.periodBytesReceived = periodBytesReceived
        self.periodBytesSent = periodBytesSent
        self.sessionNetworkKey = sessionNetworkKey
        self.sessionDisplayName = sessionDisplayName
        self.sessionStartedAt = sessionStartedAt
        self.sessionBytesReceived = sessionBytesReceived
        self.sessionBytesSent = sessionBytesSent
        self.lastInterfaceName = lastInterfaceName
        self.lastInterfaceCounters = lastInterfaceCounters
        self.firedWarningPercents = firedWarningPercents
        self.ssidCacheByInterface = ssidCacheByInterface
    }
}

public extension AppSettings {
    mutating func markNetworkAsMetered(networkKey: String, displayName: String) {
        if let index = knownMeteredProfiles.firstIndex(where: { $0.networkKey == networkKey }) {
            knownMeteredProfiles[index].isUserMarkedMetered = true
            knownMeteredProfiles[index].autoEnableMonitoring = true
            knownMeteredProfiles[index].displayName = displayName
        } else {
            knownMeteredProfiles.append(
                MeteredNetworkProfile(
                    networkKey: networkKey,
                    displayName: displayName,
                    isUserMarkedMetered: true,
                    capBytes: defaultMeteredCapBytes,
                    periodKind: defaultMeteredBillingPeriod,
                    autoEnableMonitoring: true
                )
            )
        }
    }

    mutating func forgetMeteredNetwork(networkKey: String) {
        knownMeteredProfiles.removeAll { $0.networkKey == networkKey }
    }
}

public enum MeteredUsageFormatting {
    public static func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    public static func compactUsage(used: UInt64, cap: UInt64?) -> String {
        guard let cap, cap > 0 else {
            return byteCount(used)
        }
        return "\(byteCount(used))/\(byteCount(cap))"
    }
}
