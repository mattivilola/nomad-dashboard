import NomadCore
import SwiftUI

/// The right side of the Trip Planner: what to know about the selected trip, one tile per topic. Sections the
/// data does not cover are left out.
struct TripPreviewView: View {
    let presentation: TripPreviewPresentation
    let checklistActions: TripChecklistActions
    let editAction: () -> Void
    let refreshOnlineAction: () -> Void
    let openURLAction: (URL) -> Void
    let copyTextAction: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                TripTile(
                    title: TripChecklistPresentation.title,
                    systemImage: "checklist.checked",
                    accessory: {
                        Text(presentation.checklist.progressText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NomadTheme.secondaryText)
                    }
                ) {
                    TripChecklistSection(checklist: presentation.checklist, actions: checklistActions)
                }

                if presentation.basics.isEmpty == false {
                    TripTile(title: TripPreviewPresentation.basicsTitle, systemImage: "checklist") {
                        rows(presentation.basics)
                    }
                }

                if let embassy = presentation.embassy {
                    TripTile(title: TripPreviewPresentation.embassyTitle, systemImage: "building.columns.fill") {
                        embassySection(embassy)
                    }
                }

                if let map = presentation.map {
                    TripTile(title: TripMapPresentation.title, systemImage: "map") {
                        TripMapView(map: map, openURLAction: openURLAction)
                    }
                }

                if presentation.rhythm.isEmpty == false {
                    TripTile(title: TripPreviewPresentation.rhythmTitle, systemImage: "calendar.badge.clock") {
                        rows(presentation.rhythm)
                    }
                }

                onlineTile

                if let prices = presentation.prices {
                    TripTile(title: TripPreviewPresentation.pricesTitle, systemImage: "tag.fill") {
                        pricesSection(prices)
                    }
                }

                if let visa = presentation.visa {
                    TripTile(title: TripPreviewPresentation.visaTitle, systemImage: "calendar.badge.clock") {
                        visaSection(visa)
                    }
                }

                Text(presentation.footer)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(2)

                Text(presentation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = presentation.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(NomadTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.headerLine)

            Spacer(minLength: 8)

            Button(TripPreviewPresentation.editTitle, action: editAction)
                .buttonStyle(.dashboardInline)
                .help("Edit this trip")
        }
    }

    // MARK: Rows

    private func rows(_ rows: [TripPreviewPresentation.Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                ArrivalBriefingRowView(row: row)
            }
        }
    }

    // MARK: Embassy

    private func embassySection(_ embassy: TripPreviewPresentation.Embassy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hotline = embassy.hotline {
                EmbassyHotlineRow(hotline: hotline, isCompact: false, copyAction: { copyTextAction(hotline.phone) })
            }

            ForEach(embassy.missions) { mission in
                EmbassyMissionRowView(mission: mission, isCompact: false, openURLAction: openURLAction, copyTextAction: copyTextAction)
            }

            if let notice = embassy.notice {
                EmbassyNoticeRow(systemImage: embassy.fallbackMissions.isEmpty ? "mappin.slash" : "info.circle", text: notice)
            }

            ForEach(embassy.fallbackMissions) { mission in
                EmbassyMissionRowView(mission: mission, isCompact: false, openURLAction: openURLAction, copyTextAction: copyTextAction)
            }

            ForEach(embassy.links) { group in
                EmbassyLinkRow(group: group, showsCountryName: false, openURLAction: openURLAction)
            }

            Text(embassy.footer)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Holidays and advisory

    private var onlineTile: some View {
        TripTile(
            title: TripPreviewPresentation.onlineTitle,
            systemImage: "calendar",
            accessory: {
                if presentation.online.status != .loading {
                    Button(action: refreshOnlineAction) {
                        DashboardIconChip(systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Check again")
                    .accessibilityLabel("Check holidays and advisory again")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                rows(presentation.online.holidays)

                if let advisory = presentation.online.advisory {
                    ArrivalBriefingRowView(row: advisory)
                }

                statusLine(presentation.online.status)
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ status: TripPreviewPresentation.OnlineStatus) -> some View {
        switch status {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(TripPreviewPresentation.loadingText)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
            }
        case let .updated(text):
            Text(text)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
        case let .unavailable(text):
            Label(text, systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
        }
    }

    // MARK: Prices

    private func pricesSection(_ prices: TripPreviewPresentation.Prices) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(prices.lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(prices.caption)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .padding(.top, 2)
        }
    }

    // MARK: Visa

    private func visaSection(_ visa: TripPreviewPresentation.Visa) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visa.items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    if let progress = item.progress {
                        UsageProgressBar(progress: progress, tint: item.tone.barTint, height: 4)
                    }

                    Text(item.text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.tone.textTint)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(NomadTheme.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Text(visa.footer)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A titled tile of the preview, in the card style of the other windows.
private struct TripTile<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Spacer(minLength: 8)

                accessory()
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NomadTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
        )
    }
}

extension TripTile where Accessory == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}
