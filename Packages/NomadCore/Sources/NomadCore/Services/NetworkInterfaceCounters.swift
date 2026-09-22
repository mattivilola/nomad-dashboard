import Darwin
import Foundation
import OSLog

public struct InterfaceByteTotals: Equatable, Sendable, Codable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64

    public init(receivedBytes: UInt64, sentBytes: UInt64) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }

    public var totalBytes: UInt64 {
        receivedBytes + sentBytes
    }
}

public struct DetailedInterfaceCounterSnapshot: Sendable {
    public let perInterface: [String: InterfaceByteTotals]
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let primaryInterface: String?
    public let capturedAt: Date

    public init(
        perInterface: [String: InterfaceByteTotals],
        receivedBytes: UInt64,
        sentBytes: UInt64,
        primaryInterface: String?,
        capturedAt: Date
    ) {
        self.perInterface = perInterface
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.primaryInterface = primaryInterface
        self.capturedAt = capturedAt
    }
}

public protocol DetailedInterfaceCounterReading: Sendable {
    func read() -> DetailedInterfaceCounterSnapshot?
}

public struct SystemDetailedInterfaceCounterReader: DetailedInterfaceCounterReading {
    public init() {}

    public func read() -> DetailedInterfaceCounterSnapshot? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }

        defer {
            freeifaddrs(addressPointer)
        }

        var perInterface: [String: InterfaceByteTotals] = [:]
        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var primaryInterface: String?
        var busiestScore: UInt64 = 0

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            let isLoopback = (interface.ifa_flags & UInt32(IFF_LOOPBACK)) != 0

            guard !isLoopback,
                  let dataPointer = interface.ifa_data?.assumingMemoryBound(to: if_data.self)
            else {
                continue
            }

            let interfaceReceived = UInt64(dataPointer.pointee.ifi_ibytes)
            let interfaceSent = UInt64(dataPointer.pointee.ifi_obytes)
            let score = interfaceReceived + interfaceSent

            receivedBytes += interfaceReceived
            sentBytes += interfaceSent
            perInterface[name] = InterfaceByteTotals(receivedBytes: interfaceReceived, sentBytes: interfaceSent)

            if score >= busiestScore {
                busiestScore = score
                primaryInterface = name
            }
        }

        return DetailedInterfaceCounterSnapshot(
            perInterface: perInterface,
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            primaryInterface: primaryInterface,
            capturedAt: Date()
        )
    }
}

public protocol DefaultRouteInterfaceReading: Sendable {
    func defaultInterfaceName() -> String?
}

public struct DarwinDefaultRouteInterfaceReader: DefaultRouteInterfaceReading {
    private static let logger = Logger(subsystem: "com.iloapps.NomadDashboard", category: "DefaultRouteInterface")

    public init() {}

    public func defaultInterfaceName() -> String? {
        Self.logger.debug("defaultInterfaceName: resolving default route interface")
        return Self.interfaceName(forAddressFamily: AF_INET) ?? Self.interfaceName(forAddressFamily: AF_INET6)
    }

    private static func interfaceName(forAddressFamily family: Int32) -> String? {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, 0, family, NET_RT_FLAGS, RTF_GATEWAY]
        var length: size_t = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }

        var offset = 0
        while offset + MemoryLayout<rt_msghdr>.stride <= buffer.count {
            let header = buffer.withUnsafeBytes { rawBuffer in
                rawBuffer.load(fromByteOffset: offset, as: rt_msghdr.self)
            }
            let messageLength = Int(header.rtm_msglen)
            guard messageLength > 0 else { break }

            if (header.rtm_flags & RTF_GATEWAY) != 0, header.rtm_index != 0 {
                var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                if if_indextoname(UInt32(header.rtm_index), &buffer) != nil {
                    return String(cString: buffer)
                }
            }

            offset += messageLength
        }

        return nil
    }
}

public enum InterfaceByteDeltaAccounting {
    public static let maximumReasonableDeltaBytes: UInt64 = 5_000_000_000

    public static func delta(
        current: InterfaceByteTotals,
        previous: InterfaceByteTotals?
    ) -> InterfaceByteTotals {
        guard let previous else {
            return InterfaceByteTotals(receivedBytes: 0, sentBytes: 0)
        }

        let receivedDelta = monotonicDelta(current: current.receivedBytes, previous: previous.receivedBytes)
        let sentDelta = monotonicDelta(current: current.sentBytes, previous: previous.sentBytes)
        return InterfaceByteTotals(receivedBytes: receivedDelta, sentBytes: sentDelta)
    }

    public static func monotonicDelta(current: UInt64, previous: UInt64) -> UInt64 {
        guard current >= previous else {
            return 0
        }

        let delta = current - previous
        guard delta <= maximumReasonableDeltaBytes else {
            return 0
        }

        return delta
    }
}
