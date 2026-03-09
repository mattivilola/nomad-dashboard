import Foundation
import NomadCore

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SparkleUpdateCoordinator: NSObject, UpdateCoordinator, @unchecked Sendable {
    private let userDriver: SPUStandardUserDriver
    private let updater: SPUUpdater
    private let delegateProxy: SparkleUpdateDelegateProxy
    private var state: UpdateStateSnapshot
    private var automaticChecksEnabled: Bool

    init(automaticChecksEnabled: Bool) {
        delegateProxy = SparkleUpdateDelegateProxy()
        userDriver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: delegateProxy)
        self.automaticChecksEnabled = automaticChecksEnabled
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: automaticChecksEnabled ? "Sparkle ready" : "Automatic update checks disabled",
            lastCheckedAt: nil
        )
        super.init()
        delegateProxy.owner = self

        updater.automaticallyChecksForUpdates = automaticChecksEnabled

        var startError: NSError?
        if updater.startUpdater(&startError) {
            state = UpdateStateSnapshot(
                kind: .idle,
                detail: automaticChecksEnabled ? "Sparkle ready" : "Automatic update checks disabled",
                lastCheckedAt: nil
            )
        } else {
            state = UpdateStateSnapshot(
                kind: .unavailable,
                detail: startError?.localizedDescription ?? "Unable to start Sparkle updater",
                lastCheckedAt: nil
            )
        }
    }

    func currentState() async -> UpdateStateSnapshot {
        state
    }

    func checkForUpdates() async {
        guard updater.canCheckForUpdates else {
            state = UpdateStateSnapshot(kind: .unavailable, detail: "Another update session is already in progress", lastCheckedAt: state.lastCheckedAt)
            return
        }

        state = UpdateStateSnapshot(kind: .checking, detail: "Checking for updates", lastCheckedAt: Date())
        updater.checkForUpdates()
    }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) async {
        automaticChecksEnabled = isEnabled
        updater.automaticallyChecksForUpdates = isEnabled
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: isEnabled ? "Automatic update checks enabled" : "Automatic update checks disabled",
            lastCheckedAt: state.lastCheckedAt
        )
    }

    fileprivate func handleUpdateFound(_ item: SUAppcastItem) {
        state = UpdateStateSnapshot(
            kind: .updateAvailable,
            detail: "Update available: \(item.displayVersionString)",
            lastCheckedAt: Date()
        )
    }

    fileprivate func handleNoUpdateFound(_ error: Error) {
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: "You're up to date",
            lastCheckedAt: Date()
        )
    }

    fileprivate func handleUpdateFailure(_ error: Error) {
        state = UpdateStateSnapshot(
            kind: .unavailable,
            detail: error.localizedDescription,
            lastCheckedAt: Date()
        )
    }

    fileprivate func handleFinishedCycle(error: Error?) {
        if let error {
            handleUpdateFailure(error)
            return
        }

        guard state.kind == .checking else {
            return
        }

        state = UpdateStateSnapshot(
            kind: .idle,
            detail: automaticChecksEnabled ? "Sparkle ready" : "Automatic update checks disabled",
            lastCheckedAt: state.lastCheckedAt
        )
    }
}

@MainActor
private final class SparkleUpdateDelegateProxy: NSObject, SPUUpdaterDelegate {
    weak var owner: SparkleUpdateCoordinator?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        owner?.handleUpdateFound(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        owner?.handleNoUpdateFound(error)
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        owner?.handleUpdateFailure(error)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        owner?.handleUpdateFailure(error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        owner?.handleFinishedCycle(error: error)
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
