import NomadCore
import NomadUI
import SwiftUI
import WidgetKit

/// The widget's rounded type scale, matching the dashboard.
enum WidgetFont {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Opens the dashboard popover in the app.
struct DashboardLink: ViewModifier {
    func body(content: Content) -> some View {
        if let scheme = NomadDeepLink.scheme(), let url = NomadDeepLink.dashboard.url(scheme: scheme) {
            content.widgetURL(url)
        } else {
            content
        }
    }
}

extension View {
    /// The shared look of every Nomad widget: the dashboard's gradient behind the content, and a tap that
    /// opens the dashboard.
    func nomadWidgetChrome() -> some View {
        modifier(DashboardLink())
            .containerBackground(for: .widget) {
                NomadTheme.background
            }
    }
}

/// "Updated 12:40", or "Out of date · 12:40" in the caution colour once the app has been silent for 6 hours.
struct WidgetUpdatedFooter: View {
    let savedAt: Date
    let isStale: Bool

    var body: some View {
        let time = savedAt.formatted(date: .omitted, time: .shortened)
        HStack(spacing: 3) {
            if isStale {
                Image(systemName: "clock.badge.exclamationmark")
                    .widgetAccentable()
                Text("Out of date \u{B7} \(time)")
            } else {
                Text("Updated \(time)")
            }
        }
        .font(WidgetFont.rounded(10, .medium))
        .foregroundStyle(isStale ? NomadTheme.sand : NomadTheme.tertiaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel(isStale ? "Out of date. Last updated \(time)" : "Updated \(time)")
    }
}

/// Shown until the app has saved its first snapshot.
struct WidgetEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "suitcase.rolling.fill")
                .font(WidgetFont.rounded(22, .semibold))
                .foregroundStyle(NomadTheme.secondaryText)
            Text("Open Nomad Dashboard")
                .font(WidgetFont.rounded(15, .bold))
                .foregroundStyle(NomadTheme.primaryText)
            Text("Your travel info appears here once the app has run.")
                .font(WidgetFont.rounded(11))
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A heads-up: its symbol in the severity's status colour, then its title.
struct WidgetHeadsUpRow: View {
    let headsUp: WidgetSnapshot.HeadsUp
    var lineLimit = 2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: headsUp.symbolName)
                .font(WidgetFont.rounded(12, .semibold))
                .foregroundStyle(headsUp.severity.level.tint)
                .widgetAccentable()
                .frame(width: 16)
            Text(headsUp.title)
                .font(WidgetFont.rounded(12, .medium))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
