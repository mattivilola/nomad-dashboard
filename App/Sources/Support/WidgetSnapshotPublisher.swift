import Combine
import Foundation
import NomadCore
import OSLog
import WidgetKit

/// Keeps the widgets up to date: after each dashboard refresh it builds the compact `WidgetSnapshot`,
/// writes it to the App Group container when it is worth writing, and asks WidgetKit to reload.
///
/// Builds without the App Group entitlement (unsigned local and CI builds) have nowhere to write, so
/// the publisher does nothing there.
@MainActor
final class WidgetSnapshotPublisher {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "NomadDashboard",
        category: "Widgets"
    )
    /// The dashboard snapshot changes every few seconds; the widgets only need a look this often.
    private static let evaluationInterval: DispatchQueue.SchedulerTimeType.Stride = .seconds(5)

    private let store: WidgetSnapshotStore?
    private let reloadTimelines: @MainActor () -> Void
    private var lastWritten: WidgetSnapshot?
    private var subscription: AnyCancellable?

    init(
        snapshotStore: DashboardSnapshotStore,
        settingsStore: AppSettingsStore,
        store: WidgetSnapshotStore? = .appGroup(),
        reloadTimelines: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.store = store
        self.reloadTimelines = reloadTimelines

        guard let store else {
            Self.logger.info("Widgets are off: this build has no App Group.")
            return
        }

        lastWritten = store.load()
        subscription = Publishers.CombineLatest(snapshotStore.$snapshot, settingsStore.$settings)
            .throttle(for: Self.evaluationInterval, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] snapshot, settings in
                self?.publish(snapshot: snapshot, settings: settings, now: .now)
            }
    }

    func publish(snapshot: DashboardSnapshot, settings: AppSettings, now: Date) {
        // Until the first local readings arrive the snapshot is a placeholder, not something to show.
        guard let store, snapshot.hasLiveReadings else { return }

        let candidate = WidgetSnapshot(snapshot: snapshot, settings: settings, now: now)
        guard WidgetSnapshotPublishPolicy.shouldPublish(candidate, previous: lastWritten) else { return }

        do {
            try store.save(candidate)
            lastWritten = candidate
            Self.logger.info("Saved the widget snapshot and reloaded the widgets")
            reloadTimelines()
        } catch {
            Self.logger.error("Could not save the widget snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}
