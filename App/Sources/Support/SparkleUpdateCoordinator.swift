import Foundation
import NomadCore

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SparkleUpdateCoordinator: NSObject, UpdateCoordinator, @unchecked Sendable {
    private let updaterController: SPUStandardUpdaterController
    private var state = UpdateStateSnapshot(kind: .idle, detail: "Sparkle ready", lastCheckedAt: nil)

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func currentState() async -> UpdateStateSnapshot {
        state
    }

    func checkForUpdates() async {
        state = UpdateStateSnapshot(kind: .checking, detail: "Checking for updates", lastCheckedAt: Date())
        updaterController.checkForUpdates(nil)
        state = UpdateStateSnapshot(kind: .idle, detail: "Update check requested", lastCheckedAt: Date())
    }
}
#else
actor SparkleUpdateCoordinator: UpdateCoordinator {
    private let coordinator = NoopUpdateCoordinator()

    func currentState() async -> UpdateStateSnapshot {
        await coordinator.currentState()
    }

    func checkForUpdates() async {
        await coordinator.checkForUpdates()
    }
}
#endif
