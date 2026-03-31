import NomadCore

public struct TimeTrackingQuickBucketChip: Equatable, Identifiable, Sendable {
    public let bucket: TimeTrackingBucket
    public let title: String

    public init(bucket: TimeTrackingBucket, title: String) {
        self.bucket = bucket
        self.title = title
    }

    public var id: String {
        bucket.stableID
    }
}

public struct TimeTrackingQuickActionsPresentation: Equatable {
    public let pendingDurationText: String
    public let activityTitle: String
    public let primaryControlTitle: String
    public let stopControlTitle: String
    public let otherChipTitle: String
    public let openTitle: String
    public let openSystemImage: String
    private let activeProjects: [TimeTrackingProject]

    public init(
        activeProjects: [TimeTrackingProject],
        pendingDurationText: String,
        activityTitle: String,
        primaryControlTitle: String,
        stopControlTitle: String = "Stop",
        otherChipTitle: String = "Other",
        openTitle: String = "Open",
        openSystemImage: String = "clock.badge.checkmark"
    ) {
        self.activeProjects = activeProjects.filter(\.isActive)
        self.pendingDurationText = pendingDurationText
        self.activityTitle = activityTitle
        self.primaryControlTitle = primaryControlTitle
        self.stopControlTitle = stopControlTitle
        self.otherChipTitle = otherChipTitle
        self.openTitle = openTitle
        self.openSystemImage = openSystemImage
    }

    public func latestProjects(maxCount: Int) -> [TimeTrackingProject] {
        guard maxCount > 0 else {
            return []
        }

        return Array(activeProjects.suffix(maxCount).reversed())
    }

    public func quickBucketChips(
        maxProjectCount: Int,
        includeUnallocated: Bool
    ) -> [TimeTrackingQuickBucketChip] {
        let projectChips = latestProjects(maxCount: maxProjectCount).map {
            TimeTrackingQuickBucketChip(bucket: .project($0.id), title: $0.trimmedName)
        }

        var chips = projectChips + [TimeTrackingQuickBucketChip(bucket: .other, title: otherChipTitle)]
        if includeUnallocated {
            chips.append(TimeTrackingQuickBucketChip(bucket: .unallocated, title: "Unallocated"))
        }

        return chips
    }
}
