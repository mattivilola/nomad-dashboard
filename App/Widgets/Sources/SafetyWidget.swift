import NomadCore
import NomadUI
import SwiftUI
import WidgetKit

/// The emergency number where you are, and your foreign ministry's consular line.
struct SafetyWidget: Widget {
    static let kind = "com.iloapps.NomadDashboard.widget.safety"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NomadWidgetProvider()) { entry in
            SafetyWidgetView(entry: entry)
                .nomadWidgetChrome()
        }
        .configurationDisplayName("Safety")
        .description("The emergency number where you are, and your embassy's consular hotline.")
        .supportedFamilies([.systemSmall])
    }
}

struct SafetyWidgetView: View {
    let entry: NomadWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    emergency(snapshot)
                    embassy(snapshot)
                }
                .opacity(entry.isStale ? 0.6 : 1)
                Spacer(minLength: 4)
                WidgetUpdatedFooter(savedAt: snapshot.savedAt, isStale: entry.isStale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            WidgetEmptyState()
        }
    }

    private func emergency(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Emergency", systemImage: "phone.fill")
                .font(WidgetFont.rounded(11, .semibold))
                .foregroundStyle(NomadTheme.secondaryText)
            if let emergency = snapshot.emergency {
                Text(emergency.generalNumber)
                    .font(WidgetFont.rounded(40, .bold))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(emergency.countryName)
                    .font(WidgetFont.rounded(12, .medium))
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
            } else {
                Text("Unknown here")
                    .font(WidgetFont.rounded(17, .bold))
                    .foregroundStyle(NomadTheme.primaryText)
                    .padding(.top, 4)
                Text("No verified number for where you are")
                    .font(WidgetFont.rounded(11))
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(snapshot))
    }

    @ViewBuilder
    private func embassy(_ snapshot: WidgetSnapshot) -> some View {
        if let hotline = snapshot.embassy?.hotline {
            VStack(alignment: .leading, spacing: 1) {
                Label("Consular line", systemImage: "building.columns")
                    .font(WidgetFont.rounded(10, .semibold))
                    .foregroundStyle(NomadTheme.tertiaryText)
                Text(hotline)
                    .font(WidgetFont.rounded(13, .semibold))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        } else if snapshot.embassy == nil {
            Text("Add your citizenship in Settings for your consular line")
                .font(WidgetFont.rounded(10))
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accessibilityLabel(_ snapshot: WidgetSnapshot) -> String {
        guard let emergency = snapshot.emergency else {
            return "No verified emergency number for where you are"
        }
        return "Emergency number in \(emergency.countryName): \(emergency.generalNumber)"
    }
}
