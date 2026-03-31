import NomadCore

public enum TimeTrackingQuickControlKind: Equatable, Sendable {
    case primary
    case stop
}

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

public struct TimeTrackingQuickControlIcon: Equatable, Sendable {
    public let kind: TimeTrackingQuickControlKind
    public let title: String
    public let systemImage: String

    public init(kind: TimeTrackingQuickControlKind, title: String, systemImage: String) {
        self.kind = kind
        self.title = title
        self.systemImage = systemImage
    }
}

public struct TimeTrackingHeaderCompactConfiguration: Equatable, Sendable {
    public let chips: [TimeTrackingQuickBucketChip]

    public init(chips: [TimeTrackingQuickBucketChip]) {
        self.chips = chips
    }
}

public struct TimeTrackingQuickActionsPresentation: Equatable {
    public let pendingDurationText: String
    public let activityTitle: String
    public let activityState: TimeTrackingActivityState
    public let primaryControlTitle: String
    public let primaryControlSystemImage: String
    public let stopControlTitle: String
    public let stopControlSystemImage: String
    public let otherChipTitle: String
    public let openTitle: String
    public let openSystemImage: String
    private let activeProjects: [TimeTrackingProject]
    private let recentProjects: [TimeTrackingProject]

    public init(
        activeProjects: [TimeTrackingProject],
        recentProjects: [TimeTrackingProject] = [],
        pendingDurationText: String,
        activityState: TimeTrackingActivityState,
        otherChipTitle: String = "Other",
        openTitle: String = "Open",
        openSystemImage: String = "clock.badge.checkmark"
    ) {
        self.init(
            activeProjects: activeProjects,
            recentProjects: recentProjects,
            pendingDurationText: pendingDurationText,
            activityState: activityState,
            activityTitle: Self.activityTitle(for: activityState),
            primaryControlTitle: Self.primaryControlTitle(for: activityState),
            primaryControlSystemImage: Self.primaryControlSystemImage(for: activityState),
            stopControlTitle: "Stop",
            stopControlSystemImage: "stop.fill",
            otherChipTitle: otherChipTitle,
            openTitle: openTitle,
            openSystemImage: openSystemImage
        )
    }

    public init(
        activeProjects: [TimeTrackingProject],
        recentProjects: [TimeTrackingProject] = [],
        pendingDurationText: String,
        activityState: TimeTrackingActivityState,
        activityTitle: String,
        primaryControlTitle: String,
        primaryControlSystemImage: String = "pause.fill",
        stopControlTitle: String = "Stop",
        stopControlSystemImage: String = "stop.fill",
        otherChipTitle: String = "Other",
        openTitle: String = "Open",
        openSystemImage: String = "clock.badge.checkmark"
    ) {
        self.activeProjects = activeProjects.filter(\.isActive)
        let activeProjectsByID = Dictionary(uniqueKeysWithValues: self.activeProjects.map { ($0.id, $0) })
        self.recentProjects = recentProjects.compactMap { activeProjectsByID[$0.id] }
        self.pendingDurationText = pendingDurationText
        self.activityState = activityState
        self.activityTitle = activityTitle
        self.primaryControlTitle = primaryControlTitle
        self.primaryControlSystemImage = primaryControlSystemImage
        self.stopControlTitle = stopControlTitle
        self.stopControlSystemImage = stopControlSystemImage
        self.otherChipTitle = otherChipTitle
        self.openTitle = openTitle
        self.openSystemImage = openSystemImage
    }

    public var primaryControlIcon: TimeTrackingQuickControlIcon {
        TimeTrackingQuickControlIcon(kind: .primary, title: primaryControlTitle, systemImage: primaryControlSystemImage)
    }

    public var stopControlIcon: TimeTrackingQuickControlIcon {
        TimeTrackingQuickControlIcon(kind: .stop, title: stopControlTitle, systemImage: stopControlSystemImage)
    }

    public var openControlIcon: TimeTrackingQuickControlIcon {
        TimeTrackingQuickControlIcon(kind: .primary, title: openTitle, systemImage: openSystemImage)
    }

    public var visibleHeaderControls: [TimeTrackingQuickControlIcon] {
        switch activityState {
        case .running:
            [primaryControlIcon]
        case .paused:
            [primaryControlIcon, stopControlIcon]
        case .stopped:
            [primaryControlIcon]
        }
    }

    public func latestProjects(maxCount: Int) -> [TimeTrackingProject] {
        guard maxCount > 0 else {
            return []
        }

        return Array(activeProjects.suffix(maxCount).reversed())
    }

    public func recommendedProjects(maxCount: Int) -> [TimeTrackingProject] {
        guard maxCount > 0 else {
            return []
        }

        return Array(recentProjects.prefix(maxCount))
    }

    public func headerCompactConfigurations(maxProjectCount: Int) -> [TimeTrackingHeaderCompactConfiguration] {
        let resolvedProjectCount = max(0, min(maxProjectCount, recentProjects.count))
        var configurations: [TimeTrackingHeaderCompactConfiguration] = []

        func appendConfiguration(projectCount: Int, includesOtherChip: Bool) {
            let projectChips = recommendedProjects(maxCount: projectCount).map {
                TimeTrackingQuickBucketChip(bucket: .project($0.id), title: $0.trimmedName)
            }
            let otherChip = includesOtherChip ? [TimeTrackingQuickBucketChip(bucket: .other, title: otherChipTitle)] : []
            let configuration = TimeTrackingHeaderCompactConfiguration(chips: projectChips + otherChip)

            if configurations.contains(configuration) == false {
                configurations.append(configuration)
            }
        }

        appendConfiguration(projectCount: resolvedProjectCount, includesOtherChip: true)
        if resolvedProjectCount > 0 {
            for projectCount in stride(from: resolvedProjectCount - 1, through: 0, by: -1) {
                appendConfiguration(projectCount: projectCount, includesOtherChip: true)
            }
        }
        appendConfiguration(projectCount: 0, includesOtherChip: false)

        return configurations
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

    public static func activityTitle(for activityState: TimeTrackingActivityState) -> String {
        switch activityState {
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .stopped:
            "Stopped"
        }
    }

    public static func primaryControlTitle(for activityState: TimeTrackingActivityState) -> String {
        switch activityState {
        case .running:
            "Pause"
        case .paused:
            "Resume"
        case .stopped:
            "Play"
        }
    }

    public static func primaryControlSystemImage(for activityState: TimeTrackingActivityState) -> String {
        switch activityState {
        case .running:
            "pause.fill"
        case .paused, .stopped:
            "play.fill"
        }
    }
}
