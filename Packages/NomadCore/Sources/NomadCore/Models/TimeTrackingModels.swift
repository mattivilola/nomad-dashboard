import Foundation

public struct TimeTrackingProject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isArchived: Bool

    public init(id: UUID = UUID(), name: String, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.isArchived = isArchived
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isActive: Bool {
        isArchived == false && trimmedName.isEmpty == false
    }
}

public enum TimeTrackingBucket: Codable, Equatable, Hashable, Sendable {
    case project(UUID)
    case other
    case unallocated

    public var stableID: String {
        switch self {
        case let .project(id):
            "project:\(id.uuidString.lowercased())"
        case .other:
            "other"
        case .unallocated:
            "unallocated"
        }
    }
}

public enum TimeTrackingActivityState: String, Codable, CaseIterable, Equatable, Sendable {
    case running
    case paused
    case stopped
}

public enum TimeTrackingShutdownKind: String, Codable, Equatable, Sendable {
    case none
    case paused
    case stopped
    case sleep
    case terminated
}

public enum TimeTrackingPeriod: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    public var id: String {
        rawValue
    }
}

public struct TimeTrackingInterruption: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var reportedAt: Date

    public init(id: UUID = UUID(), reportedAt: Date) {
        self.id = id
        self.reportedAt = reportedAt
    }
}

public struct TimeTrackingEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var startAt: Date
    public var endAt: Date?
    public var bucket: TimeTrackingBucket

    public init(
        id: UUID = UUID(),
        startAt: Date,
        endAt: Date? = nil,
        bucket: TimeTrackingBucket
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.bucket = bucket
    }

    public var isOpen: Bool {
        endAt == nil
    }

    public func resolvedEnd(at referenceDate: Date) -> Date {
        endAt ?? referenceDate
    }

    public func duration(at referenceDate: Date) -> TimeInterval {
        max(resolvedEnd(at: referenceDate).timeIntervalSince(startAt), 0)
    }
}

public enum TimeTrackingFocusMetrics {
    public static let interruptionRecoveryDuration: TimeInterval = 23 * 60

    public static func estimatedFocusLoss(for interruptionCount: Int) -> TimeInterval {
        max(Double(interruptionCount), 0) * interruptionRecoveryDuration
    }

    public static func focusAdjustedDuration(
        trackedDuration: TimeInterval,
        interruptionCount: Int
    ) -> TimeInterval {
        max(trackedDuration - estimatedFocusLoss(for: interruptionCount), 0)
    }
}

public struct TimeTrackingRuntimeState: Codable, Equatable, Sendable {
    public var activityState: TimeTrackingActivityState
    public var openEntryID: UUID?
    public var lastHeartbeatAt: Date?
    public var lastPersistedAt: Date?
    public var lastShutdownKind: TimeTrackingShutdownKind

    public init(
        activityState: TimeTrackingActivityState = .stopped,
        openEntryID: UUID? = nil,
        lastHeartbeatAt: Date? = nil,
        lastPersistedAt: Date? = nil,
        lastShutdownKind: TimeTrackingShutdownKind = .none
    ) {
        self.activityState = activityState
        self.openEntryID = openEntryID
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastPersistedAt = lastPersistedAt
        self.lastShutdownKind = lastShutdownKind
    }

    private enum CodingKeys: String, CodingKey {
        case activityState
        case openEntryID
        case lastHeartbeatAt
        case lastPersistedAt
        case lastShutdownKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityState = try container.decodeIfPresent(TimeTrackingActivityState.self, forKey: .activityState) ?? .stopped
        openEntryID = try container.decodeIfPresent(UUID.self, forKey: .openEntryID)
        lastHeartbeatAt = try container.decodeIfPresent(Date.self, forKey: .lastHeartbeatAt)
        lastPersistedAt = try container.decodeIfPresent(Date.self, forKey: .lastPersistedAt)
        lastShutdownKind = try container.decodeIfPresent(TimeTrackingShutdownKind.self, forKey: .lastShutdownKind) ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activityState, forKey: .activityState)
        try container.encodeIfPresent(openEntryID, forKey: .openEntryID)
        try container.encodeIfPresent(lastHeartbeatAt, forKey: .lastHeartbeatAt)
        try container.encodeIfPresent(lastPersistedAt, forKey: .lastPersistedAt)
        try container.encode(lastShutdownKind, forKey: .lastShutdownKind)
    }
}

public struct TimeTrackingLedger: Codable, Equatable, Sendable {
    public var entries: [TimeTrackingEntry]
    public var interruptions: [TimeTrackingInterruption]
    public var runtimeState: TimeTrackingRuntimeState

    public init(
        entries: [TimeTrackingEntry] = [],
        interruptions: [TimeTrackingInterruption] = [],
        runtimeState: TimeTrackingRuntimeState = TimeTrackingRuntimeState()
    ) {
        self.entries = TimeTrackingLedger.normalizedEntries(entries)
        self.interruptions = TimeTrackingLedger.normalizedInterruptions(interruptions)
        self.runtimeState = runtimeState
    }

    public static let empty = TimeTrackingLedger()

    private enum CodingKeys: String, CodingKey {
        case entries
        case interruptions
        case runtimeState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = TimeTrackingLedger.normalizedEntries(
            try container.decodeIfPresent([TimeTrackingEntry].self, forKey: .entries) ?? []
        )
        interruptions = TimeTrackingLedger.normalizedInterruptions(
            try container.decodeIfPresent([TimeTrackingInterruption].self, forKey: .interruptions) ?? []
        )
        runtimeState = try container.decodeIfPresent(TimeTrackingRuntimeState.self, forKey: .runtimeState) ?? TimeTrackingRuntimeState()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(TimeTrackingLedger.normalizedEntries(entries), forKey: .entries)
        try container.encode(TimeTrackingLedger.normalizedInterruptions(interruptions), forKey: .interruptions)
        try container.encode(runtimeState, forKey: .runtimeState)
    }

    public static func normalizedEntries(_ entries: [TimeTrackingEntry]) -> [TimeTrackingEntry] {
        entries.sorted {
            if $0.startAt == $1.startAt {
                return $0.id.uuidString < $1.id.uuidString
            }

            return $0.startAt < $1.startAt
        }
    }

    public static func normalizedInterruptions(_ interruptions: [TimeTrackingInterruption]) -> [TimeTrackingInterruption] {
        interruptions.sorted {
            if $0.reportedAt == $1.reportedAt {
                return $0.id.uuidString < $1.id.uuidString
            }

            return $0.reportedAt < $1.reportedAt
        }
    }
}

public struct TimeTrackingBucketDuration: Equatable, Identifiable, Sendable {
    public let bucket: TimeTrackingBucket
    public let duration: TimeInterval
    public let interruptionCount: Int

    public init(bucket: TimeTrackingBucket, duration: TimeInterval, interruptionCount: Int = 0) {
        self.bucket = bucket
        self.duration = duration
        self.interruptionCount = interruptionCount
    }

    public var id: String {
        bucket.stableID
    }

    public var estimatedFocusLossDuration: TimeInterval {
        TimeTrackingFocusMetrics.estimatedFocusLoss(for: interruptionCount)
    }

    public var focusAdjustedDuration: TimeInterval {
        TimeTrackingFocusMetrics.focusAdjustedDuration(
            trackedDuration: duration,
            interruptionCount: interruptionCount
        )
    }
}

public struct TimeTrackingDaySummary: Equatable, Identifiable, Sendable {
    public let dayStart: Date
    public let bucketDurations: [TimeTrackingBucketDuration]
    public let totalTrackedDuration: TimeInterval
    public let totalAllocatedDuration: TimeInterval
    public let unallocatedDuration: TimeInterval
    public let interruptionCount: Int
    public let estimatedFocusLossDuration: TimeInterval
    public let focusAdjustedDuration: TimeInterval
    public let lastInterruptionAt: Date?

    public init(
        dayStart: Date,
        bucketDurations: [TimeTrackingBucketDuration],
        totalTrackedDuration: TimeInterval,
        totalAllocatedDuration: TimeInterval,
        unallocatedDuration: TimeInterval,
        interruptionCount: Int,
        estimatedFocusLossDuration: TimeInterval,
        focusAdjustedDuration: TimeInterval,
        lastInterruptionAt: Date?
    ) {
        self.dayStart = dayStart
        self.bucketDurations = bucketDurations
        self.totalTrackedDuration = totalTrackedDuration
        self.totalAllocatedDuration = totalAllocatedDuration
        self.unallocatedDuration = unallocatedDuration
        self.interruptionCount = interruptionCount
        self.estimatedFocusLossDuration = estimatedFocusLossDuration
        self.focusAdjustedDuration = focusAdjustedDuration
        self.lastInterruptionAt = lastInterruptionAt
    }

    public var id: Date {
        dayStart
    }
}

public struct TimeTrackingWeekSummary: Equatable, Identifiable, Sendable {
    public let weekStart: Date
    public let weekEnd: Date
    public let daySummaries: [TimeTrackingDaySummary]
    public let bucketDurations: [TimeTrackingBucketDuration]
    public let totalTrackedDuration: TimeInterval
    public let interruptionCount: Int
    public let estimatedFocusLossDuration: TimeInterval
    public let focusAdjustedDuration: TimeInterval

    public init(
        weekStart: Date,
        weekEnd: Date,
        daySummaries: [TimeTrackingDaySummary],
        bucketDurations: [TimeTrackingBucketDuration],
        totalTrackedDuration: TimeInterval,
        interruptionCount: Int,
        estimatedFocusLossDuration: TimeInterval,
        focusAdjustedDuration: TimeInterval
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.daySummaries = daySummaries
        self.bucketDurations = bucketDurations
        self.totalTrackedDuration = totalTrackedDuration
        self.interruptionCount = interruptionCount
        self.estimatedFocusLossDuration = estimatedFocusLossDuration
        self.focusAdjustedDuration = focusAdjustedDuration
    }

    public var id: Date {
        weekStart
    }
}

public struct TimeTrackingMonthSummary: Equatable, Identifiable, Sendable {
    public let monthStart: Date
    public let monthEnd: Date
    public let weekSummaries: [TimeTrackingWeekSummary]
    public let bucketDurations: [TimeTrackingBucketDuration]
    public let totalTrackedDuration: TimeInterval
    public let interruptionCount: Int
    public let estimatedFocusLossDuration: TimeInterval
    public let focusAdjustedDuration: TimeInterval

    public init(
        monthStart: Date,
        monthEnd: Date,
        weekSummaries: [TimeTrackingWeekSummary],
        bucketDurations: [TimeTrackingBucketDuration],
        totalTrackedDuration: TimeInterval,
        interruptionCount: Int,
        estimatedFocusLossDuration: TimeInterval,
        focusAdjustedDuration: TimeInterval
    ) {
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.weekSummaries = weekSummaries
        self.bucketDurations = bucketDurations
        self.totalTrackedDuration = totalTrackedDuration
        self.interruptionCount = interruptionCount
        self.estimatedFocusLossDuration = estimatedFocusLossDuration
        self.focusAdjustedDuration = focusAdjustedDuration
    }

    public var id: Date {
        monthStart
    }
}

public struct TimeTrackingDashboardState: Equatable, Sendable {
    public let isEnabled: Bool
    public let activityState: TimeTrackingActivityState
    public let activeProjects: [TimeTrackingProject]
    public let recentProjects: [TimeTrackingProject]
    public let todaySummary: TimeTrackingDaySummary
    public let openUnallocatedEntryStartAt: Date?

    public init(
        isEnabled: Bool,
        activityState: TimeTrackingActivityState,
        activeProjects: [TimeTrackingProject],
        recentProjects: [TimeTrackingProject],
        todaySummary: TimeTrackingDaySummary,
        openUnallocatedEntryStartAt: Date?
    ) {
        self.isEnabled = isEnabled
        self.activityState = activityState
        self.activeProjects = activeProjects
        self.recentProjects = recentProjects
        self.todaySummary = todaySummary
        self.openUnallocatedEntryStartAt = openUnallocatedEntryStartAt
    }

    public static let disabled = TimeTrackingDashboardState(
        isEnabled: false,
        activityState: .stopped,
        activeProjects: [],
        recentProjects: [],
        todaySummary: TimeTrackingDaySummary(
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: .now),
            bucketDurations: [],
            totalTrackedDuration: 0,
            totalAllocatedDuration: 0,
            unallocatedDuration: 0,
            interruptionCount: 0,
            estimatedFocusLossDuration: 0,
            focusAdjustedDuration: 0,
            lastInterruptionAt: nil
        ),
        openUnallocatedEntryStartAt: nil
    )
}

public extension AppSettings {
    var activeTimeTrackingProjects: [TimeTrackingProject] {
        timeTrackingProjects.filter(\.isActive)
    }
}
