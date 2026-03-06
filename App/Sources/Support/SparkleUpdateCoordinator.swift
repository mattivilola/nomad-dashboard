import Foundation
import NomadCore

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SparkleUpdateCoordinator: NSObject, UpdateCoordinator, @unchecked Sendable {
    private let updaterController: SPUStandardUpdaterController
    private var state: UpdateStateSnapshot

    init(automaticChecksEnabled: Bool) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: automaticChecksEnabled ? "Sparkle ready" : "Automatic update checks disabled",
            lastCheckedAt: nil
        )
        super.init()
        updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
    }

    func currentState() async -> UpdateStateSnapshot {
        state
    }

    func checkForUpdates() async {
        state = UpdateStateSnapshot(kind: .checking, detail: "Checking for updates", lastCheckedAt: Date())
        updaterController.checkForUpdates(nil)
        state = UpdateStateSnapshot(kind: .idle, detail: "Update check requested", lastCheckedAt: Date())
    }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) async {
        updaterController.updater.automaticallyChecksForUpdates = isEnabled
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: isEnabled ? "Automatic update checks enabled" : "Automatic update checks disabled",
            lastCheckedAt: state.lastCheckedAt
        )
    }
}
#else
actor SparkleUpdateCoordinator: UpdateCoordinator {
    private let coordinator: NoopUpdateCoordinator

    init(automaticChecksEnabled: Bool) {
        coordinator = NoopUpdateCoordinator(automaticChecksEnabled: automaticChecksEnabled)
    }

    func currentState() async -> UpdateStateSnapshot {
        await coordinator.currentState()
    }

    func checkForUpdates() async {
        await coordinator.checkForUpdates()
    }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) async {
        await coordinator.setAutomaticChecksEnabled(isEnabled)
    }
}
#endif
