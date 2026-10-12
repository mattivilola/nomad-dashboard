import NomadCore
import SwiftUI

/// The first glance: a verdict, two clocks, four vital tiles and at most three heads-up items.
public struct NomadWorkReadinessView: View {
    let snapshot: DashboardSnapshot
    let policy: DashboardResourcePolicy
    let homeTimeZoneIdentifier: String
    let dataUsageMode: DataUsageMode
    let travelProfile: TravelProfile
    let weatherAvailabilityExplanation: String?
    let settings: AppSettings
    let visitedCountryDays: [VisitedCountryDay]
    let reopenedArrival: ArrivalEvent?
    let changeDataUsage: @Sendable (DataUsageMode) -> Void
    let openDiary: () -> Void
    let openPreferences: () -> Void
    let openOfflineEssentials: () -> Void
    let openExploreCities: () -> Void
    let acknowledgeArrival: (String) -> Void
    let startDataGuardMonitoring: () -> Void

    @Environment(\.dashboardScrollToCard) private var scrollToCard

    public init(
        snapshot: DashboardSnapshot,
        policy: DashboardResourcePolicy,
        homeTimeZoneIdentifier: String,
        dataUsageMode: DataUsageMode,
        travelProfile: TravelProfile = .nomad,
        weatherAvailabilityExplanation: String? = nil,
        settings: AppSettings = AppSettings(),
        visitedCountryDays: [VisitedCountryDay] = [],
        reopenedArrival: ArrivalEvent? = nil,
        changeDataUsage: @escaping @Sendable (DataUsageMode) -> Void,
        openDiary: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        openOfflineEssentials: @escaping () -> Void,
        openExploreCities: @escaping () -> Void = {},
        acknowledgeArrival: @escaping (String) -> Void = { _ in },
        startDataGuardMonitoring: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.policy = policy
        self.homeTimeZoneIdentifier = homeTimeZoneIdentifier
        self.dataUsageMode = dataUsageMode
        self.travelProfile = travelProfile
        self.weatherAvailabilityExplanation = weatherAvailabilityExplanation
        self.settings = settings
        self.visitedCountryDays = visitedCountryDays
        self.reopenedArrival = reopenedArrival
        self.changeDataUsage = changeDataUsage
        self.openDiary = openDiary
        self.openPreferences = openPreferences
        self.openOfflineEssentials = openOfflineEssentials
        self.openExploreCities = openExploreCities
        self.acknowledgeArrival = acknowledgeArrival
        self.startDataGuardMonitoring = startDataGuardMonitoring
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            arrivalCard
            verdictRow
            clocksLine
            vitalTiles
            headsUpList
            linksRow
        }
        .padding(12)
        .background(NomadTheme.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(NomadTheme.teal.opacity(0.16)))
    }

    private var stayInsightInput: StayInsightInput {
        StayInsightInput(
            countryDays: visitedCountryDays,
            settings: settings,
            currentCountryCode: snapshot.currentCountryCode
        )
    }

    // MARK: Arrival briefing

    @ViewBuilder
    private var arrivalCard: some View {
        // Decided once per render so no empty slot (and spacing) is left when there is no arrival.
        if ArrivalBriefingEvents.event(
            reopened: reopenedArrival,
            countryDays: visitedCountryDays,
            currentCountryCode: snapshot.currentCountryCode,
            settings: settings,
            now: .now,
            calendar: .current
        ) != nil {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                if let event = ArrivalBriefingEvents.event(
                    reopened: reopenedArrival,
                    countryDays: visitedCountryDays,
                    currentCountryCode: snapshot.currentCountryCode,
                    settings: settings,
                    now: timeline.date,
                    calendar: .current
                ) {
                    ArrivalBriefingCardView(
                        presentation: ArrivalBriefingPresentation(
                            briefing: ArrivalBriefing.make(
                                event: event,
                                snapshot: snapshot,
                                settings: settings,
                                homeTimeZoneIdentifier: homeTimeZoneIdentifier,
                                now: timeline.date
                            ),
                            previousCountryCode: event.previousCountryCode,
                            now: timeline.date
                        ),
                        acknowledge: { acknowledgeArrival(event.countryCode) },
                        startDataGuardMonitoring: startDataGuardMonitoring
                    )
                    .id(event.countryCode)
                }
            }
        }
    }

    private var isOffline: Bool {
        GlanceVerdictPresentation.isOffline(snapshot: snapshot, policy: policy)
    }

    // MARK: Verdict

    private var verdictRow: some View {
        let verdict = GlanceVerdictPresentation(snapshot: snapshot, isOffline: isOffline)
        let tint = verdict.level.tint

        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: verdict.symbolName)
                .font(.title3.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)
                    .lineLimit(1)
                Text(verdict.detail)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            dataUsageMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.22))
                )
        )
        .accessibilityElement(children: .contain)
    }

    private var dataUsageMenu: some View {
        Menu {
            Picker("Data usage", selection: Binding(get: { dataUsageMode }, set: changeDataUsage)) {
                ForEach(DataUsageMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } label: {
            Label(policy.isLowData ? "Low Data" : dataUsageMode == .standard ? "Normal" : "Auto", systemImage: policy.isLowData ? "leaf" : "network")
                .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(policy.reason ?? "Choose how Nomad uses your connection")
        .accessibilityLabel("Data usage: \(dataUsageMode.title)")
    }

    // MARK: Clocks

    private var clocksLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let zones = NomadLifeTimeZonePresentation(
                homeTimeZoneIdentifier: homeTimeZoneIdentifier,
                currentTimeZoneIdentifier: snapshot.travelContext.timeZoneIdentifier,
                date: timeline.date
            )
            let here = clockText(
                label: "Here",
                city: GlanceClockPresentation.hereCity(
                    deviceLocation: snapshot.travelContext.deviceLocation,
                    timeZoneIdentifier: snapshot.travelContext.timeZoneIdentifier
                ),
                identifier: snapshot.travelContext.timeZoneIdentifier,
                date: timeline.date
            )
            let home = clockText(
                label: "Home",
                city: GlanceClockPresentation.cityName(forTimeZoneIdentifier: homeTimeZoneIdentifier),
                identifier: homeTimeZoneIdentifier,
                date: timeline.date
            )
            let relativeDay = Text(zones.relativeDayDescription)
                .font(.caption2)
                .foregroundStyle(NomadTheme.secondaryText)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    here.fixedSize()
                    separator
                    home.fixedSize()
                    Spacer(minLength: 0)
                    relativeDay.fixedSize()
                    preferencesButton
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        here.fixedSize()
                        separator
                        home.fixedSize()
                        Spacer(minLength: 0)
                        preferencesButton
                    }
                    relativeDay
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        here.lineLimit(1)
                        Spacer(minLength: 0)
                        preferencesButton
                    }
                    home.lineLimit(1)
                    relativeDay
                }
            }
        }
    }

    private var separator: some View {
        Text("·")
            .font(.caption)
            .foregroundStyle(NomadTheme.tertiaryText)
    }

    private var preferencesButton: some View {
        Button(action: openPreferences) { Image(systemName: "slider.horizontal.3") }
            .buttonStyle(.plain)
            .foregroundStyle(NomadTheme.secondaryText)
            .help("Set your home time zone")
            .accessibilityLabel("Set home time zone")
    }

    private func clockText(label: String, city: String, identifier: String, date: Date) -> Text {
        let zone = TimeZone(identifier: identifier) ?? .current
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        let labelText = Text(label).fontWeight(.semibold).foregroundStyle(NomadTheme.primaryText)
        let cityText = Text(city).foregroundStyle(NomadTheme.secondaryText)
        let timeText = Text(time).fontWeight(.semibold).monospacedDigit().foregroundStyle(NomadTheme.primaryText)

        return Text("\(labelText) \(cityText) \(timeText)").font(.caption)
    }

    // MARK: Vital tiles

    private var vitalTiles: some View {
        let tiles = GlanceVitalTilePresentation.tiles(
            snapshot: snapshot,
            isOffline: isOffline,
            weatherAvailabilityExplanation: weatherAvailabilityExplanation
        )

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
            spacing: 10
        ) {
            ForEach(tiles) { tile in
                GlanceVitalTile(tile: tile) {
                    scrollToCard(tile.scrollTarget)
                }
            }
        }
    }

    // MARK: Heads-up

    private var headsUpList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let rows = DashboardInsightEngine.insights(
                for: snapshot,
                now: timeline.date,
                profile: travelProfile,
                stays: stayInsightInput
            )
                .map(GlanceHeadsUpRowPresentation.init(insight:))

            if rows.isEmpty == false {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heads-up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.tertiaryText)

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().overlay(NomadTheme.cardBorder)
                            }
                            headsUpRow(row)
                        }
                    }
                }
            }
        }
    }

    private func headsUpRow(_ row: GlanceHeadsUpRowPresentation) -> some View {
        Button {
            scrollToCard(row.relatedCard)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.symbolName)
                    .font(.system(size: 15))
                    .foregroundStyle(row.level.tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detail = row.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(NomadTheme.tertiaryText)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.accessibilityHint)
    }

    // MARK: Links

    private var linksRow: some View {
        let workplaces = Button(action: openDiary) { Label("Workplaces", systemImage: "mappin.and.ellipse") }
        let essentials = Button(action: openOfflineEssentials) {
            Label(isOffline ? "Offline essentials" : "Saved essentials", systemImage: "tray.and.arrow.down")
        }
        let explore = Button(action: openExploreCities) { Label("Explore cities", systemImage: "globe.europe.africa") }

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                workplaces
                essentials
                explore
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    workplaces
                    essentials
                    Spacer(minLength: 0)
                }
                explore
            }
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(NomadTheme.teal)
        .lineLimit(1)
    }
}

private struct GlanceVitalTile: View {
    let tile: GlanceVitalTilePresentation
    let action: () -> Void

    var body: some View {
        let tint = tile.level?.tint ?? NomadTheme.primaryText
        let border = tile.level.map { $0.tint.opacity(0.18) } ?? NomadTheme.cardBorder

        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: tile.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                    Text(tile.title)
                        .fixedSize()
                    if let titleDetail = tile.titleDetail {
                        Text("· \(titleDetail)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NomadTheme.tertiaryText)

                HStack(spacing: 5) {
                    Text(tile.value)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let valueSymbolName = tile.valueSymbolName {
                        Image(systemName: valueSymbolName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NomadTheme.secondaryText)
                    }
                }

                if let progress = tile.progress {
                    UsageProgressBar(progress: progress, tint: tint)
                        .padding(.vertical, 1)
                }

                Text(tile.secondary)
                    .font(.caption2)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NomadTheme.tileBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show \(tile.scrollTarget.displayTitle)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.accessibilityLabel)
        .accessibilityHint("Shows the \(tile.scrollTarget.displayTitle) card")
    }
}

public struct DashboardCardRefreshFooter: View {
    let section: DashboardDataSection
    let state: DashboardSectionActivity
    let isOffline: Bool
    let retry: () -> Void
    public init(section: DashboardDataSection, state: DashboardSectionActivity, isOffline: Bool, retry: @escaping () -> Void) {
        self.section = section
        self.state = state
        self.isOffline = isOffline
        self.retry = retry
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(label, systemImage: isOffline || state.isSaved ? "clock.arrow.circlepath" : state.isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark")
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(state.message == nil ? "Refresh" : "Retry", action: retry)
                .buttonStyle(.plain).foregroundStyle(NomadTheme.teal)
                .disabled(isOffline || state.isRefreshing)
                .help("Refresh only \(section.title.lowercased())")
        }
        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 3)
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        if state.isRefreshing {
            return state.lastSuccessAt == nil ? "Updating…" : "Updating · saved information stays available"
        }
        if let date = state.lastSuccessAt {
            let prefix = isOffline ? "Offline · saved" : state.message != nil || state.isSaved ? "Saved" : "Updated"
            return "\(prefix) \(date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened))"
        }
        if isOffline {
            return "Available when you're online"
        }
        return state.message ?? "Waiting for first update"
    }
}
