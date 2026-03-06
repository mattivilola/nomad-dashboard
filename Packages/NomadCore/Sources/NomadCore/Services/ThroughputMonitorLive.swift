import Darwin
import Foundation

public protocol InterfaceCounterReading: Sendable {
    func read() -> InterfaceCounterSnapshot?
}

public struct InterfaceCounterSnapshot: Sendable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let primaryInterface: String?
    public let capturedAt: Date
}

public struct SystemInterfaceCounterReader: InterfaceCounterReading {
    public init() {}

    public func read() -> InterfaceCounterSnapshot? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }

        defer {
            freeifaddrs(addressPointer)
        }

        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
        var primaryInterface: String?
        var busiestScore: UInt64 = 0

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            let isLoopback = (interface.ifa_flags & UInt32(IFF_LOOPBACK)) != 0

            guard !isLoopback,
                  let dataPointer = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else {
                continue
            }

            let interfaceReceived = UInt64(dataPointer.pointee.ifi_ibytes)
            let interfaceSent = UInt64(dataPointer.pointee.ifi_obytes)
            let score = interfaceReceived + interfaceSent

            receivedBytes += interfaceReceived
            sentBytes += interfaceSent

            if score >= busiestScore {
                busiestScore = score
                primaryInterface = name
            }
        }

        return InterfaceCounterSnapshot(
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            primaryInterface: primaryInterface,
            capturedAt: Date()
        )
    }
}

public actor LiveThroughputMonitor: ThroughputMonitor {
    private let reader: any InterfaceCounterReading
    private var previousSnapshot: InterfaceCounterSnapshot?

    public init(reader: any InterfaceCounterReading = SystemInterfaceCounterReader()) {
        self.reader = reader
    }

    public func currentSample() async -> NetworkThroughputSample? {
        guard let currentSnapshot = reader.read() else {
            return nil
        }

        defer {
            previousSnapshot = currentSnapshot
        }

        guard let previousSnapshot else {
            return NetworkThroughputSample(
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0,
                activeInterface: currentSnapshot.primaryInterface,
                collectedAt: currentSnapshot.capturedAt
            )
        }

        let elapsed = max(currentSnapshot.capturedAt.timeIntervalSince(previousSnapshot.capturedAt), 1)
        let receivedDelta = max(Int64(currentSnapshot.receivedBytes) - Int64(previousSnapshot.receivedBytes), 0)
        let sentDelta = max(Int64(currentSnapshot.sentBytes) - Int64(previousSnapshot.sentBytes), 0)

        return NetworkThroughputSample(
            downloadBytesPerSecond: Double(receivedDelta) / elapsed,
            uploadBytesPerSecond: Double(sentDelta) / elapsed,
            activeInterface: currentSnapshot.primaryInterface,
            collectedAt: currentSnapshot.capturedAt
        )
    }
}
