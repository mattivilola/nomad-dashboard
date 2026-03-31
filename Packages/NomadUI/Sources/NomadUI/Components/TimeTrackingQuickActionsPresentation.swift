import NomadCore

struct TimeTrackingQuickActionsPresentation: Equatable {
    let pendingDurationText: String
    let activityTitle: String
    let primaryControlTitle: String
    let stopControlTitle: String
    let otherChipTitle: String
    let openTitle: String
    let openSystemImage: String
    private let activeProjects: [TimeTrackingProject]

    init(
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

    func latestProjects(maxCount: Int) -> [TimeTrackingProject] {
        guard maxCount > 0 else {
            return []
        }

        return Array(activeProjects.suffix(maxCount).reversed())
    }
}
