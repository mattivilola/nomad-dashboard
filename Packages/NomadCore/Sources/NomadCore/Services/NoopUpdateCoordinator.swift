import Foundation

public actor NoopUpdateCoordinator: UpdateCoordinator {
    private var state = UpdateStateSnapshot(kind: .idle, detail: "Update system inactive", lastCheckedAt: nil)
    private var automaticChecksEnabled = true

    public init(automaticChecksEnabled: Bool = true) {
        self.automaticChecksEnabled = automaticChecksEnabled
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: automaticChecksEnabled ? "Automatic update checks enabled" : "Automatic update checks disabled",
            lastCheckedAt: nil
        )
    }

    public func currentState() async -> UpdateStateSnapshot {
        state
    }

    public func checkForUpdates() async {
        state = UpdateStateSnapshot(kind: .unavailable, detail: "Sparkle not wired", lastCheckedAt: Date())
    }

    public func setAutomaticChecksEnabled(_ isEnabled: Bool) async {
        automaticChecksEnabled = isEnabled
        state = UpdateStateSnapshot(
            kind: .idle,
            detail: isEnabled ? "Automatic update checks enabled" : "Automatic update checks disabled",
            lastCheckedAt: state.lastCheckedAt
        )
    }
}
