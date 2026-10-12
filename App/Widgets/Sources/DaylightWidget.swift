import NomadCore
import NomadUI
import SwiftUI
import WidgetKit

/// Sunset and the daylight left, or when it gets light again.
struct DaylightWidget: Widget {
    static let kind = "com.iloapps.NomadDashboard.widget.daylight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NomadWidgetProvider(includesDaylightTransitions: true)) { entry in
            DaylightWidgetView(entry: entry)
                .nomadWidgetChrome()
        }
        .configurationDisplayName("Daylight")
        .description("When the sun sets and how much daylight is left, or when it gets light again.")
        .supportedFamilies([.systemSmall])
    }
}

struct DaylightWidgetView: View {
    /// Daylight left at which the symbol turns to the caution colour, like the dashboard's daylight heads-up.
    private static let cautionInterval: TimeInterval = 60 * 60

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
        if let outlook = snapshot.daylight, let phase = outlook.phase(at: entry.date) {
            switch phase {
            case let .daylight(sunset):
                let remaining = sunset.timeIntervalSince(entry.date)
                card(
                    symbol: "sunset.fill",
                    tint: remaining <= Self.cautionInterval ? HealthLevel.caution.tint : NomadTheme.secondaryText,
                    title: "Sunset \(outlook.clockTime(sunset))",
                    detail: AnyView(Text("\(DurationText.hoursAndMinutes(remaining)) of daylight left"))
                )
            case let .dark(sunrise?):
                card(
                    symbol: "moon.stars.fill",
                    tint: NomadTheme.secondaryText,
                    title: "Dark until \(outlook.clockTime(sunrise))",
                    detail: AnyView(Text(outlook.isSameDay(sunrise, as: entry.date) ? "Sunrise today" : "Sunrise tomorrow"))
                )
            case .dark(nil):
                card(symbol: "moon.stars.fill", tint: NomadTheme.secondaryText, title: "Dark", detail: AnyView(Text("The sun has set")))
            case .midnightSun:
                card(symbol: "sun.max.fill", tint: NomadTheme.secondaryText, title: "Midnight sun", detail: AnyView(Text("The sun stays up today")))
            case .polarNight:
                card(symbol: "moon.stars.fill", tint: NomadTheme.secondaryText, title: "Polar night", detail: AnyView(Text("The sun stays down today")))
            }
        } else if snapshot.daylight == nil {
            card(
                symbol: "location.slash",
                tint: NomadTheme.secondaryText,
                title: "Location needed",
                detail: AnyView(Text("Open Nomad Dashboard to find where you are"))
            )
        } else {
            // The saved day has run out before the app refreshed it.
            card(
                symbol: "clock.badge.exclamationmark",
                tint: HealthLevel.caution.tint,
                title: "Out of date",
                detail: AnyView(Text("Open Nomad Dashboard to update"))
            )
        }
    }

    private func card(symbol: String, tint: Color, title: String, detail: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(WidgetFont.rounded(26, .semibold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(title)
                .font(WidgetFont.rounded(22, .bold))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            detail
                .font(WidgetFont.rounded(12, .medium))
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
