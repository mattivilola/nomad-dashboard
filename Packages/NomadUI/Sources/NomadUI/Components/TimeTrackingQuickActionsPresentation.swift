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

public struct TimeTrackingQuickControlIcon: Equatable, Sendable {
    public let title: String
    public let systemImage: String

    public init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
}

public struct TimeTrackingHeaderCompactConfiguration: Equatable, Sendable {
    public let showsActivityTitle: Bool
    public let chips: [TimeTrackingQuickBucketChip]

    public init(showsActivityTitle: Bool, chips: [TimeTrackingQuickBucketChip]) {
        self.showsActivityTitle = showsActivityTitle
        self.chips = chips
    }
}

public struct TimeTrackingQuickActionsPresentation: Equatable {
    public let pendingDurationText: String
    public let activityTitle: String
    public let primaryControlTitle: String
    public let primaryControlSystemImage: String
    public let stopControlTitle: String
    public let stopControlSystemImage: String
    public let otherChipTitle: String
    public let openTitle: String
    public let openSystemImage: String
    private let activeProjects: [TimeTrackingProject]

    public init(
        activeProjects: [TimeTrackingProject],
        pendingDurationText: String,
        activityState: TimeTrackingActivityState,
        otherChipTitle: String = "Other",
        openTitle: String = "Open",
        openSystemImage: String = "clock.badge.checkmark"
    ) {
        self.init(
            activeProjects: activeProjects,
            pendingDurationText: pendingDurationText,
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
        pendingDurationText: String,
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
        self.pendingDurationText = pendingDurationText
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
        TimeTrackingQuickControlIcon(title: primaryControlTitle, systemImage: primaryControlSystemImage)
    }

    public var stopControlIcon: TimeTrackingQuickControlIcon {
        TimeTrackingQuickControlIcon(title: stopControlTitle, systemImage: stopControlSystemImage)
    }

    public var openControlIcon: TimeTrackingQuickControlIcon {
        TimeTrackingQuickControlIcon(title: openTitle, systemImage: openSystemImage)
    }

    public func latestProjects(maxCount: Int) -> [TimeTrackingProject] {
        guard maxCount > 0 else {
            return []
        }

        return Array(activeProjects.suffix(maxCount).reversed())
    }

    public func headerCompactConfigurations(maxProjectCount: Int) -> [TimeTrackingHeaderCompactConfiguration] {
        let resolvedProjectCount = max(0, min(maxProjectCount, activeProjects.count))
        var configurations: [TimeTrackingHeaderCompactConfiguration] = []

        func appendConfiguration(showsActivityTitle: Bool, projectCount: Int) {
            let configuration = TimeTrackingHeaderCompactConfiguration(
                showsActivityTitle: showsActivityTitle,
                chips: quickBucketChips(maxProjectCount: projectCount, includeUnallocated: false)
            )

            if configurations.last != configuration {
                configurations.append(configuration)
            }
        }

        appendConfiguration(showsActivityTitle: true, projectCount: resolvedProjectCount)
        appendConfiguration(showsActivityTitle: false, projectCount: resolvedProjectCount)

        if resolvedProjectCount > 0 {
            for projectCount in stride(from: resolvedProjectCount - 1, through: 0, by: -1) {
                appendConfiguration(showsActivityTitle: false, projectCount: projectCount)
            }
        }

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
