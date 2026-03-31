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

public enum TimeTrackingPeriod: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    public var id: String {
        rawValue
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

public struct TimeTrackingRuntimeState: Codable, Equatable, Sendable {
    public var activityState: TimeTrackingActivityState
    public var openEntryID: UUID?
    public var lastHeartbeatAt: Date?

    public init(
        activityState: TimeTrackingActivityState = .stopped,
        openEntryID: UUID? = nil,
        lastHeartbeatAt: Date? = nil
    ) {
        self.activityState = activityState
        self.openEntryID = openEntryID
        self.lastHeartbeatAt = lastHeartbeatAt
    }
}

public struct TimeTrackingLedger: Codable, Equatable, Sendable {
    public var entries: [TimeTrackingEntry]
    public var runtimeState: TimeTrackingRuntimeState

    public init(
        entries: [TimeTrackingEntry] = [],
        runtimeState: TimeTrackingRuntimeState = TimeTrackingRuntimeState()
    ) {
        self.entries = TimeTrackingLedger.normalizedEntries(entries)
        self.runtimeState = runtimeState
    }

    public static let empty = TimeTrackingLedger()

    public static func normalizedEntries(_ entries: [TimeTrackingEntry]) -> [TimeTrackingEntry] {
        entries.sorted {
            if $0.startAt == $1.startAt {
                return $0.id.uuidString < $1.id.uuidString
            }

            return $0.startAt < $1.startAt
        }
    }
}

public struct TimeTrackingBucketDuration: Equatable, Identifiable, Sendable {
    public let bucket: TimeTrackingBucket
    public let duration: TimeInterval

    public init(bucket: TimeTrackingBucket, duration: TimeInterval) {
        self.bucket = bucket
        self.duration = duration
    }

    public var id: String {
        bucket.stableID
    }
}

public struct TimeTrackingDaySummary: Equatable, Identifiable, Sendable {
    public let dayStart: Date
    public let bucketDurations: [TimeTrackingBucketDuration]
    public let totalTrackedDuration: TimeInterval
    public let totalAllocatedDuration: TimeInterval
    public let unallocatedDuration: TimeInterval

    public init(
        dayStart: Date,
        bucketDurations: [TimeTrackingBucketDuration],
        totalTrackedDuration: TimeInterval,
        totalAllocatedDuration: TimeInterval,
        unallocatedDuration: TimeInterval
    ) {
        self.dayStart = dayStart
        self.bucketDurations = bucketDurations
        self.totalTrackedDuration = totalTrackedDuration
        self.totalAllocatedDuration = totalAllocatedDuration
        self.unallocatedDuration = unallocatedDuration
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

    public init(
        weekStart: Date,
        weekEnd: Date,
        daySummaries: [TimeTrackingDaySummary],
        bucketDurations: [TimeTrackingBucketDuration],
        totalTrackedDuration: TimeInterval
    ) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.daySummaries = daySummaries
        self.bucketDurations = bucketDurations
        self.totalTrackedDuration = totalTrackedDuration
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

    public init(
        monthStart: Date,
        monthEnd: Date,
        weekSummaries: [TimeTrackingWeekSummary],
        bucketDurations: [TimeTrackingBucketDuration],
        totalTrackedDuration: TimeInterval
    ) {
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.weekSummaries = weekSummaries
        self.bucketDurations = bucketDurations
        self.totalTrackedDuration = totalTrackedDuration
    }

    public var id: Date {
        monthStart
    }
}

public struct TimeTrackingDashboardState: Equatable, Sendable {
    public let isEnabled: Bool
    public let activityState: TimeTrackingActivityState
    public let activeProjects: [TimeTrackingProject]
    public let todaySummary: TimeTrackingDaySummary
    public let openUnallocatedEntryStartAt: Date?

    public init(
        isEnabled: Bool,
        activityState: TimeTrackingActivityState,
        activeProjects: [TimeTrackingProject],
        todaySummary: TimeTrackingDaySummary,
        openUnallocatedEntryStartAt: Date?
    ) {
        self.isEnabled = isEnabled
        self.activityState = activityState
        self.activeProjects = activeProjects
        self.todaySummary = todaySummary
        self.openUnallocatedEntryStartAt = openUnallocatedEntryStartAt
    }

    public static let disabled = TimeTrackingDashboardState(
        isEnabled: false,
        activityState: .stopped,
        activeProjects: [],
        todaySummary: TimeTrackingDaySummary(
            dayStart: Calendar.autoupdatingCurrent.startOfDay(for: .now),
            bucketDurations: [],
            totalTrackedDuration: 0,
            totalAllocatedDuration: 0,
            unallocatedDuration: 0
        ),
        openUnallocatedEntryStartAt: nil
    )
}

public extension AppSettings {
    var activeTimeTrackingProjects: [TimeTrackingProject] {
        timeTrackingProjects.filter(\.isActive)
    }
}
