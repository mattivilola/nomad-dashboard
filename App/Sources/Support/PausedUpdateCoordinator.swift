import Foundation
import NomadCore

actor PausedUpdateCoordinator: UpdateCoordinator {
    private let reason: String

    init(reason: String = UpdateFeatureConfiguration.pausedReason) {
        self.reason = reason
    }

    func currentState() async -> UpdateStateSnapshot {
        UpdateStateSnapshot(kind: .unavailable, detail: reason, lastCheckedAt: nil)
    }

    func checkForUpdates() async {}

    func setAutomaticChecksEnabled(_ isEnabled: Bool) async {}
}
