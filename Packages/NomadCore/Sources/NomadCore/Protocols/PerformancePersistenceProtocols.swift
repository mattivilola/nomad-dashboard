import Foundation

/// An optional capability for stores that buffer durable metric writes.
public protocol MetricHistoryFlushable: Sendable {
    func flush() async throws
}

/// A small, independently persisted liveness marker for an open time-tracking entry.
public struct TimeTrackingHeartbeat: Codable, Equatable, Sendable {
    public let openEntryID: UUID
    public let recordedAt: Date

    public init(openEntryID: UUID, recordedAt: Date) {
        self.openEntryID = openEntryID
        self.recordedAt = recordedAt
    }
}

/// An optional capability that avoids rewriting an entire ledger for routine heartbeats.
public protocol TimeTrackingHeartbeatStore: Sendable {
    func loadHeartbeat() async throws -> TimeTrackingHeartbeat?
    func saveHeartbeat(_ heartbeat: TimeTrackingHeartbeat) async throws
    func clearHeartbeat() async throws
}
