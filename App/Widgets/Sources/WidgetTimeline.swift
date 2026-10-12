import NomadCore
import WidgetKit

/// What a widget shows at one moment: the snapshot the app saved, and the time to judge it against.
struct NomadWidgetEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has written one, or when the group container is unavailable.
    let snapshot: WidgetSnapshot?

    var isStale: Bool {
        snapshot?.isStale(at: date) ?? false
    }
}

/// Reads the snapshot the app keeps in the App Group container.
///
/// The app reloads the timelines whenever it writes a new snapshot, so the timeline only has to cover
/// what changes without the app: the moment the content turns out of date and, for the Daylight
/// widget, sunrise and sunset. It also asks for a refresh on its own as a safety net.
struct NomadWidgetProvider: TimelineProvider {
    /// Extra moments to render, for the Daylight widget.
    var includesDaylightTransitions = false

    private static let fallbackRefreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> NomadWidgetEntry {
        NomadWidgetEntry(date: .now, snapshot: .sample(savedAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NomadWidgetEntry) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.appGroup()?.load()
        // The gallery shows believable sample data until the app has saved something real.
        completion(NomadWidgetEntry(date: now, snapshot: snapshot ?? (context.isPreview ? .sample(savedAt: now) : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NomadWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.appGroup()?.load()
        let moments = WidgetSnapshot.renderingMoments(of: snapshot, now: now, includesDaylightTransitions: includesDaylightTransitions)
        let entries = moments.map { NomadWidgetEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.fallbackRefreshInterval))))
    }
}
