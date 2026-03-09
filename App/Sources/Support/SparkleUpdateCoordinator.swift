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

        do {
            try updater.start()
            state = UpdateStateSnapshot(
                kind: .idle,
                detail: automaticChecksEnabled ? "Sparkle ready" : "Automatic update checks disabled",
                lastCheckedAt: nil
            )
        } catch {
            state = UpdateStateSnapshot(
                kind: .unavailable,
                detail: error.localizedDescription,
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

    fileprivate func handleUpdateFound(version: String) {
        state = UpdateStateSnapshot(
            kind: .updateAvailable,
            detail: "Update available: \(version)",
            lastCheckedAt: Date()
        )
    }

    fileprivate func handleNoUpdateFound() {
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: "You're up to date",
            lastCheckedAt: Date()
        )
    }

    fileprivate func handleUpdateFailure(description: String) {
        state = UpdateStateSnapshot(
            kind: .unavailable,
            detail: description,
            lastCheckedAt: Date()
        )
    }

    fileprivate func handleFinishedCycle(errorDescription: String?) {
        if let errorDescription {
            handleUpdateFailure(description: errorDescription)
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

private final class SparkleUpdateDelegateProxy: NSObject, SPUUpdaterDelegate {
    weak var owner: SparkleUpdateCoordinator?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor [weak owner] in
            owner?.handleUpdateFound(version: version)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        Task { @MainActor [weak owner] in
            owner?.handleNoUpdateFound()
        }
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        let description = error.localizedDescription
        Task { @MainActor [weak owner] in
            owner?.handleUpdateFailure(description: description)
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let description = error.localizedDescription
        Task { @MainActor [weak owner] in
            owner?.handleUpdateFailure(description: description)
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let errorDescription = error?.localizedDescription
        Task { @MainActor [weak owner] in
            owner?.handleFinishedCycle(errorDescription: errorDescription)
        }
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
