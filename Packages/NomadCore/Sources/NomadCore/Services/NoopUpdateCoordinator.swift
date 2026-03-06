import Foundation

public actor NoopUpdateCoordinator: UpdateCoordinator {
    private var state = UpdateStateSnapshot(kind: .idle, detail: "Update system inactive", lastCheckedAt: nil)

    public init() {}

    public func currentState() async -> UpdateStateSnapshot {
        state
    }

    public func checkForUpdates() async {
        state = UpdateStateSnapshot(kind: .unavailable, detail: "Sparkle not wired", lastCheckedAt: Date())
    }
}

