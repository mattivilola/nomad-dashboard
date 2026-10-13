import NomadCore
import SwiftUI

/// The "Your Embassy" dashboard card: the foreign ministry's consular line, the nearest own
/// missions (or the EU/Nordic fallback) and the official links.
struct EmbassySectionView: View {
    let presentation: EmbassyCardPresentation
    let widthMode: DashboardCardWidthMode
    let accessory: AnyView?
    let collapse: DashboardCardCollapse
    /// Opens Settings on the citizenship group.
    let openCitizenshipSettingsAction: () -> Void
    let openSettingsAction: () -> Void
    let openURLAction: (URL) -> Void
    let copyTextAction: (String) -> Void

    private var isCompact: Bool {
        widthMode == .narrow
    }

    var body: some View {
        DashboardCard(
            title: DashboardCardID.embassy.displayTitle,
            subtitle: presentation.subtitle,
            badge: presentation.badge,
            accessory: accessory,
            collapse: collapse,
            isCompact: isCompact
        ) {
            VStack(alignment: .leading, spacing: 8) {
                switch presentation.state {
                case .off:
                    WeatherEmptyState(
                        title: EmbassyCardPresentation.offTitle,
                        systemImage: "building.columns",
                        message: EmbassyCardPresentation.offMessage,
                        actionTitle: "Open Settings",
                        action: openCitizenshipSettingsAction
                    )
                case .atHome:
                    hotlineRows
                    if let message = presentation.atHomeMessage {
                        EmbassyNoticeRow(systemImage: "house", text: message)
                    }
                case .locationNeeded:
                    hotlineRows
                    WeatherEmptyState(
                        title: EmbassyCardPresentation.locationNeededTitle,
                        systemImage: "location.slash.fill",
                        message: EmbassyCardPresentation.locationNeededMessage,
                        actionTitle: "Open Settings",
                        action: openSettingsAction
                    )
                    linkRows
                case .abroad:
                    hotlineRows
                    missionRows
                    linkRows
                    footer
                }
            }
        }
    }

    private var hotlineRows: some View {
        ForEach(presentation.hotlines) { hotline in
            EmbassyHotlineRow(
                hotline: hotline,
                isCompact: isCompact,
                copyAction: { copyTextAction(hotline.phone) }
            )
        }
    }

    @ViewBuilder
    private var missionRows: some View {
        if presentation.missions.isEmpty == false {
            ForEach(presentation.missions) { mission in
                EmbassyMissionRowView(mission: mission, isCompact: isCompact, openURLAction: openURLAction, copyTextAction: copyTextAction)
            }
        } else {
            if let notice = presentation.fallbackNotice {
                EmbassyNoticeRow(systemImage: "info.circle", text: notice)
            }

            ForEach(presentation.fallbackMissions) { mission in
                EmbassyMissionRowView(mission: mission, isCompact: isCompact, openURLAction: openURLAction, copyTextAction: copyTextAction)
            }

            if let message = presentation.noMissionMessage {
                EmbassyNoticeRow(systemImage: "mappin.slash", text: message)
            }
        }
    }

    @ViewBuilder
    private var linkRows: some View {
        ForEach(presentation.links) { group in
            EmbassyLinkRow(
                group: group,
                showsCountryName: presentation.links.count > 1,
                openURLAction: openURLAction
            )
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let footer = presentation.footer {
            Text(footer)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

/// The tile background shared by the card's rows, matching the Emergency Care rows.
struct EmbassyRowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NomadTheme.chartBackground.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func embassyRowBackground() -> some View {
        modifier(EmbassyRowBackground())
    }
}

/// The foreign ministry's consular line. The number is selectable and can be copied.
struct EmbassyHotlineRow: View {
    let hotline: EmbassyCardPresentation.Hotline
    let isCompact: Bool
    let copyAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // A half-width card has no room to spare for the icon next to a full phone number.
            if isCompact == false {
                Image(systemName: "phone.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.tertiaryText)
                    .frame(width: 14)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(hotline.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(hotline.phone)
                        .font(.system(size: isCompact ? 13 : 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(NomadTheme.primaryText)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Button(action: copyAction) {
                        DashboardIconChip(systemImage: "document.on.document")
                    }
                    .buttonStyle(.plain)
                    .help("Copy phone number")
                    .accessibilityLabel("Copy \(hotline.title) phone number")
                }

                Text(hotline.detail)
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .embassyRowBackground()
        .help(hotline.help)
    }
}

/// One mission. The whole row opens Apple Maps; the trailing menu holds the secondary actions.
struct EmbassyMissionRowView: View {
    let mission: EmbassyCardPresentation.MissionRow
    let isCompact: Bool
    let openURLAction: (URL) -> Void
    let copyTextAction: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let mapsURL = mission.mapsURL {
                Button {
                    openURLAction(mapsURL)
                } label: {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mission.accessibilityLabel)
                .accessibilityHint("Opens the mission in Apple Maps")
            } else {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasMenuActions {
                moreMenu
            }
        }
        .embassyRowBackground()
    }

    @ViewBuilder
    private var content: some View {
        if isCompact {
            compactContent
        } else {
            wideContent
        }
    }

    private var wideContent: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                nameText

                HStack(spacing: 6) {
                    NeutralChip(title: mission.kindTitle)
                        .fixedSize()

                    locationText
                }

                reasonText
            }

            Spacer(minLength: 8)

            distanceText
        }
    }

    /// In a half-width card the name, chip, city and distance stack instead of sharing lines.
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameText

            HStack(spacing: 6) {
                NeutralChip(title: mission.kindTitle)
                    .fixedSize()

                Spacer(minLength: 4)

                distanceText
            }

            locationText
            reasonText
        }
    }

    private var nameText: some View {
        Text(mission.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(NomadTheme.primaryText)
            .lineLimit(isCompact ? 3 : 2)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var locationText: some View {
        if mission.locationText.isEmpty == false {
            Text(mission.locationText)
                .font(.caption2)
                .foregroundStyle(NomadTheme.secondaryText)
                .lineLimit(isCompact ? 2 : 1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var reasonText: some View {
        if let reasonCaption = mission.reasonCaption {
            Text(reasonCaption)
                .font(.caption2)
                .foregroundStyle(NomadTheme.tertiaryText)
        }
    }

    @ViewBuilder
    private var distanceText: some View {
        if let distance = mission.distanceText {
            Text(distance)
                .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(NomadTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var hasMenuActions: Bool {
        mission.mapsURL != nil || mission.websiteURL != nil || mission.address != nil
    }

    private var moreMenu: some View {
        Menu {
            if let mapsURL = mission.mapsURL {
                Button("Show in Maps", systemImage: "map") { openURLAction(mapsURL) }
            }

            if let websiteURL = mission.websiteURL {
                Button("Open website", systemImage: "arrow.up.right.square") { openURLAction(websiteURL) }
            }

            if let address = mission.address {
                Button("Copy address", systemImage: "document.on.document") { copyTextAction(address) }
            }
        } label: {
            DashboardIconChip(systemImage: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
        .accessibilityLabel("More actions for \(mission.name)")
    }
}

/// A short explanation inside the card, such as the EU fallback notice.
struct EmbassyNoticeRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.tertiaryText)
                .frame(width: 14)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
                .foregroundStyle(NomadTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The ministry's trip-registration service and its list of missions, as inline buttons.
struct EmbassyLinkRow: View {
    let group: EmbassyCardPresentation.LinkGroup
    let showsCountryName: Bool
    let openURLAction: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsCountryName {
                Text(group.countryName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NomadTheme.tertiaryText)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 6) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if let registration = group.registration {
            Button(registration.title) { openURLAction(registration.url) }
                .buttonStyle(.dashboardInline(isCompact: true))
        }

        if let directory = group.missionsDirectory {
            Button(directory.title) { openURLAction(directory.url) }
                .buttonStyle(.dashboardInline(role: .neutral, isCompact: true))
        }
    }
}
