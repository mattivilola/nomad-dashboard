import Foundation
import NomadCore

/// Gives an intent the dashboard state to answer from.
///
/// Siri and Shortcuts start the app in the background when it is not running, and a freshly started
/// app has not collected anything yet (it only has what it saved offline). During the first seconds
/// the reader therefore waits briefly for the readings the answer needs; once the app has been up for
/// a while it answers at once from what it knows, because waiting longer would not change anything.
@MainActor
enum IntentSnapshotReader {
    /// How long after launch the app still counts as warming up.
    static let warmUpWindow: TimeInterval = 30
    /// The longest an intent waits for a warming-up app.
    static let maximumWait: Duration = .seconds(8)
    private static let pollInterval: Duration = .milliseconds(200)

    private static var launchUptime: TimeInterval?

    /// Call once when the app starts.
    static func registerLaunch() {
        launchUptime = ProcessInfo.processInfo.systemUptime
    }

    private static var isWarmingUp: Bool {
        guard let launchUptime else { return false }
        return ProcessInfo.processInfo.systemUptime - launchUptime < warmUpWindow
    }

    /// The current snapshot, once `isReady` holds for it or the wait is over.
    static func snapshot(
        from store: DashboardSnapshotStore,
        until isReady: (DashboardSnapshot) -> Bool
    ) async -> DashboardSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumWait)
        while isReady(store.snapshot) == false, isWarmingUp, clock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
        return store.snapshot
    }
}

extension DashboardSnapshot {
    /// The first local readings (network, power) have been collected, so the verdict is real.
    var hasLiveReadings: Bool {
        appState.lastRefresh != nil
    }

    /// The country the user is in is known, from the device, the IP location or saved local info.
    var knowsCountry: Bool {
        currentCountryCode != nil
    }

    /// There is a location with coordinates to compute daylight from.
    var knowsDaylightLocation: Bool {
        DaylightReference(travelContext: travelContext) != nil
    }
}
