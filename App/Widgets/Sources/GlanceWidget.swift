import NomadCore
import NomadUI
import SwiftUI
import WidgetKit

/// The verdict, the place and the top heads-up, at a glance.
struct GlanceWidget: Widget {
    static let kind = "com.iloapps.NomadDashboard.widget.glance"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NomadWidgetProvider()) { entry in
            GlanceWidgetView(entry: entry)
                .nomadWidgetChrome()
        }
        .configurationDisplayName("Glance")
        .description("Your travel verdict, where you are and the most important heads-up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GlanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NomadWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 0) {
                content(snapshot)
                    .opacity(entry.isStale ? 0.6 : 1)
                Spacer(minLength: 4)
                WidgetUpdatedFooter(savedAt: snapshot.savedAt, isStale: entry.isStale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyState()
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                verdictColumn(snapshot)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    headsUps(snapshot, emptyText: "Nothing needs your attention")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                verdictColumn(snapshot)
                headsUps(snapshot, limit: 1, emptyText: "No heads-ups")
            }
        }
    }

    private func verdictColumn(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: snapshot.verdict.symbolName)
                .font(WidgetFont.rounded(20, .semibold))
                .foregroundStyle(snapshot.verdict.level.tint)
                .widgetAccentable()
            Text(snapshot.verdict.title)
                .font(WidgetFont.rounded(26, .bold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let place = snapshot.placeName {
                Text(place)
                    .font(WidgetFont.rounded(12, .medium))
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func headsUps(_ snapshot: WidgetSnapshot, limit: Int = WidgetSnapshot.maximumHeadsUps, emptyText: String) -> some View {
        if snapshot.headsUp.isEmpty {
            Text(emptyText)
                .font(WidgetFont.rounded(12, .medium))
                .foregroundStyle(NomadTheme.tertiaryText)
        } else {
            ForEach(Array(snapshot.headsUp.prefix(limit).enumerated()), id: \.offset) { _, headsUp in
                WidgetHeadsUpRow(headsUp: headsUp, lineLimit: family == .systemMedium ? 3 : 2)
            }
        }
    }
}
