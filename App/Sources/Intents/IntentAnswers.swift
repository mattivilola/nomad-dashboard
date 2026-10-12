import NomadCore

/// What each intent says, read from the app's live stores. The intents only fetch their dependencies
/// and hand them here.
@MainActor
enum IntentAnswers {
    static func emergencyNumber(snapshotStore: DashboardSnapshotStore) async -> String {
        let snapshot = await IntentSnapshotReader.snapshot(from: snapshotStore) { $0.knowsCountry }
        return QuickAnswers.emergencyNumbers(snapshot: snapshot).sentence
    }

    static func dashboardStatus(snapshotStore: DashboardSnapshotStore, settingsStore: AppSettingsStore) async -> String {
        _ = await IntentSnapshotReader.snapshot(from: snapshotStore) { $0.hasLiveReadings }
        // Latency is only probed while the dashboard is open; without a reading the verdict would say "Waiting".
        await snapshotStore.probeLatencyIfStale()
        return QuickAnswers.dashboardStatus(snapshot: snapshotStore.snapshot, settings: settingsStore.settings, now: .now).sentence
    }

    static func nearestEmbassy(snapshotStore: DashboardSnapshotStore, settingsStore: AppSettingsStore) async -> String {
        let snapshot = await IntentSnapshotReader.snapshot(from: snapshotStore) { $0.knowsCountry }
        return QuickAnswers.nearestEmbassy(snapshot: snapshot, settings: settingsStore.settings).sentence
    }

    static func daylight(snapshotStore: DashboardSnapshotStore) async -> String {
        let snapshot = await IntentSnapshotReader.snapshot(from: snapshotStore) { $0.knowsDaylightLocation }
        return QuickAnswers.daylight(snapshot: snapshot, now: .now).sentence
    }

    /// Switches the profile and says what happened.
    static func setTravelProfile(_ profile: TravelProfile, settingsStore: AppSettingsStore) -> String {
        guard settingsStore.settings.travelProfile != profile else {
            return "Nomad Dashboard is already on the \(profile.title) profile."
        }

        settingsStore.settings.applyTravelProfile(profile)
        return "Switched Nomad Dashboard to the \(profile.title) profile. \(profile.summary)"
    }
}
