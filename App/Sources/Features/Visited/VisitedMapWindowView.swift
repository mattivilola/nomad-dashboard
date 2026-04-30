import AppKit
import NomadCore
import NomadUI
import SwiftUI

struct VisitedMapWindowView: View {
    @ObservedObject var snapshotStore: DashboardSnapshotStore
    @ObservedObject var settingsStore: AppSettingsStore

    @Environment(\.openWindow) private var openWindow
    @State private var mapMode: VisitedMapMode = .footprint
    @State private var selectedCountryDaysYear: Int?
    @State private var selectedTravelYear: Int?
    @State private var expandedMonthIDs = Set<String>()
    @State private var exportStatusMessage: String?

    var body: some View {
        ZStack {
            NomadTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if settingsStore.settings.visitedPlacesEnabled == false {
                        disabledState
                    } else if hasAnyVisitedHistory == false {
                        emptyState
                    } else {
                        metrics
                        mapCard
                        if mapMode == .travelPath, selectedTravelStops.isEmpty == false {
                            travelLogCard
                        }
                        countryDaysCard
                        guidanceCard
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 940, minHeight: 720)
        .onAppear(perform: syncSelectedCountryDaysYear)
        .onChange(of: availableCountryDayYears) { _, _ in
            syncSelectedCountryDaysYear()
        }
        .onChange(of: availableTravelYears) { _, _ in
            syncSelectedTravelYear()
        }
        .onChange(of: resolvedSelectedCountryDaysYear) { _, _ in
            exportStatusMessage = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Visited Map")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                actionButton(
                    title: "Settings",
                    systemImage: "slider.horizontal.3",
                    action: { openAndActivateWindow(.settings, with: openWindow) }
                )

                actionButton(
                    title: "Clear History",
                    systemImage: "trash",
                    role: .destructive,
                    isEnabled: hasAnyVisitedHistory
                ) {
                    snapshotStore.clearVisitedPlaces()
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metricCard(title: "Cities", value: "\(snapshotStore.visitedPlaceSummary.citiesVisited)", tint: NomadTheme.teal)
            metricCard(title: "Countries", value: "\(snapshotStore.visitedPlaceSummary.countriesVisited)", tint: NomadTheme.sand)
            metricCard(title: "Tracked Days", value: "\(snapshotStore.visitedCountryDays.count)", tint: NomadTheme.sand)
            metricCard(title: "Sources", value: trackingModeLabel, tint: NomadTheme.coral)
        }
    }

    private var mapCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mapMode.title)
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(mapMode.description)
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 10) {
                            if availableTravelYears.isEmpty == false {
                                HStack(spacing: 6) {
                                    Text("Map View")
                                        .font(.callout)
                                        .foregroundStyle(NomadTheme.primaryText)

                                    Picker("Map View", selection: $mapMode) {
                                        ForEach(VisitedMapMode.allCases) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.segmented)
                                    .frame(width: 260)
                                }
                            }

                            if mapMode == .travelPath, availableTravelYears.isEmpty == false {
                                HStack(spacing: 6) {
                                    Text("Year")
                                        .font(.callout)
                                        .foregroundStyle(NomadTheme.primaryText)

                                    Picker("Year", selection: selectedTravelYearBinding) {
                                        ForEach(availableTravelYears, id: \.self) { year in
                                            Text("\(year)").tag(year)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 110)
                                }
                            }
                        }

                        legend
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                VisitedWorldMapView(places: places, travelStops: mapMode == .travelPath ? selectedTravelStops : [])
                    .frame(minHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                    )
            }
        }
    }

    private var travelLogCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Travel Log")
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(travelLogDescription)
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                    Spacer()

                    Text("\(selectedTravelStops.count) \(selectedTravelStops.count == 1 ? "stop" : "stops")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                VStack(spacing: 0) {
                    ForEach(selectedTravelStops) { stop in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(stop.sequenceNumber)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(NomadTheme.teal))

                            VStack(alignment: .leading, spacing: 5) {
                                Text(stop.displayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(NomadTheme.primaryText)

                                Text(travelStopDateText(for: stop))
                                    .font(.caption)
                                    .foregroundStyle(NomadTheme.secondaryText)
                            }

                            Spacer(minLength: 24)

                            VStack(alignment: .trailing, spacing: 5) {
                                Text(stop.dayCount == 1 ? "1 day" : "\(stop.dayCount) days")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(NomadTheme.primaryText)

                                Text(sourceLabel(for: stop.sources))
                                    .font(.caption)
                                    .foregroundStyle(NomadTheme.secondaryText)

                                if stop.coordinate == nil {
                                    Text("No map coordinate")
                                        .font(.caption)
                                        .foregroundStyle(NomadTheme.tertiaryText)
                                }
                            }
                        }
                        .padding(.vertical, 10)

                        if stop.id != selectedTravelStops.last?.id {
                            Divider()
                                .overlay(NomadTheme.cardBorder.opacity(0.65))
                        }
                    }
                }
            }
        }
    }

    private var guidanceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Label("How capture works", systemImage: "location.circle.fill")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Text("Pins, travel paths, and country days are stored locally on this Mac only. When device location is available, visited history uses it and ignores IP geolocation for that capture. IP geolocation is used only as a fallback when device location cannot be resolved, and country-day gaps can be estimated from surrounding captures.")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var countryDaysCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Country Days")
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(countryDaysDescription)
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        if availableCountryDayYears.isEmpty == false {
                            Picker("Year", selection: selectedYearBinding) {
                                ForEach(availableCountryDayYears, id: \.self) { year in
                                    Text("\(year)").tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                        }

                        if selectedCountryDaySummary != nil {
                            Button {
                                copySelectedYearSummaryToClipboard()
                            } label: {
                                Label("Copy Summary", systemImage: "doc.on.doc")
                                    .font(.callout.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                            }
                            .buttonStyle(.bordered)
                            .tint(NomadTheme.teal)
                        }
                    }
                }

                if let summary = selectedCountryDaySummary {
                    Text("Based on \(summary.totalTrackedDays) tracked \(summary.totalTrackedDays == 1 ? "day" : "days") stored locally on this Mac.")
                        .font(.caption)
                        .foregroundStyle(NomadTheme.secondaryText)

                    VStack(spacing: 10) {
                        ForEach(summary.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.country)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(NomadTheme.primaryText)

                                Spacer(minLength: 24)

                                Text(countryDayValueText(for: item))
                                    .font(.callout)
                                    .foregroundStyle(NomadTheme.secondaryText)
                            }
                            .padding(.vertical, 8)

                            if item.id != summary.items.last?.id {
                                Divider()
                                    .overlay(NomadTheme.cardBorder.opacity(0.65))
                            }
                        }
                    }
                    .padding(.top, 2)

                    if let exportStatusMessage {
                        Text(exportStatusMessage)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                    if selectedYearMonthlySummaries.isEmpty == false {
                        Divider()
                            .overlay(NomadTheme.cardBorder.opacity(0.65))
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Monthly Breakdown")
                                .font(.headline)
                                .foregroundStyle(NomadTheme.primaryText)

                            ForEach(selectedYearMonthlySummaries) { monthSummary in
                                DisclosureGroup(
                                    isExpanded: monthExpansionBinding(for: monthSummary.id)
                                ) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        VStack(spacing: 8) {
                                            ForEach(monthSummary.items) { item in
                                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                                    Text(item.country)
                                                        .font(.callout.weight(.semibold))
                                                        .foregroundStyle(NomadTheme.primaryText)

                                                    Spacer(minLength: 24)

                                                    Text(countryDayValueText(for: item))
                                                        .font(.caption)
                                                        .foregroundStyle(NomadTheme.secondaryText)
                                                }
                                            }
                                        }

                                        Divider()
                                            .overlay(NomadTheme.cardBorder.opacity(0.65))

                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Days")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(NomadTheme.secondaryText)

                                            ForEach(monthSummary.days) { day in
                                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                                    Text(dayLabel(for: day))
                                                        .font(.caption.monospacedDigit())
                                                        .foregroundStyle(NomadTheme.secondaryText)

                                                    Text(day.country)
                                                        .font(.callout)
                                                        .foregroundStyle(NomadTheme.primaryText)

                                                    Spacer(minLength: 24)

                                                    if day.isInferred {
                                                        Text("Estimated")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(NomadTheme.tertiaryText)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 10)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(monthLabel(for: monthSummary.month))
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(NomadTheme.primaryText)

                                        Spacer(minLength: 24)

                                        Text("\(monthSummary.totalTrackedDays) \(monthSummary.totalTrackedDays == 1 ? "day" : "days")")
                                            .font(.caption)
                                            .foregroundStyle(NomadTheme.secondaryText)
                                    }
                                }
                                .tint(NomadTheme.primaryText)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                } else {
                    Text("Country-day summaries will start appearing here after new daily captures are recorded.")
                        .font(.subheadline)
                        .foregroundStyle(NomadTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var disabledState: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Visited history is off", systemImage: "globe.badge.chevron.backward")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Text("Turn on local visited-place storage in Settings to start building your travel map and country-day diary on this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                actionButton(
                    title: "Open Settings",
                    systemImage: "slider.horizontal.3",
                    action: { openAndActivateWindow(.settings, with: openWindow) }
                )
            }
        }
    }

    private var emptyState: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Label("No saved places yet", systemImage: "mappin.slash")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                Text("Saved cities and country days will appear here after location updates are recorded. Keep external IP location or current location enabled, then refresh once you have a place to save.")
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    actionButton(
                        title: "Open Settings",
                        systemImage: "slider.horizontal.3",
                        action: { openAndActivateWindow(.settings, with: openWindow) }
                    )

                    actionButton(
                        title: "Refresh Dashboard",
                        systemImage: "arrow.clockwise",
                        action: {
                            Task {
                                await snapshotStore.refresh(manual: true)
                            }
                        }
                    )
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(title: "Visited Country", tint: NomadTheme.teal)
            legendItem(title: mapMode == .travelPath ? "Travel Stop" : "Saved City", tint: mapMode == .travelPath ? NomadTheme.teal : NomadTheme.coral)
        }
    }

    private func legendItem(title: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.secondaryText)
        }
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.secondaryText)

                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                Capsule(style: .continuous)
                    .fill(tint.opacity(0.22))
                    .frame(width: 58, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(role == .destructive ? NomadTheme.coral : NomadTheme.teal)
        .disabled(isEnabled == false)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(NomadTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
            )
    }

    private var places: [VisitedPlace] {
        snapshotStore.visitedPlaces
    }

    private var countryDays: [VisitedCountryDay] {
        snapshotStore.visitedCountryDays
    }

    private var travelEvents: [VisitedPlaceEvent] {
        snapshotStore.visitedPlaceEvents
    }

    private var visitedCountryCodes: Set<String> {
        Set(places.compactMap { $0.countryCode?.uppercased() })
    }

    private var headerSubtitle: String {
        if settingsStore.settings.visitedPlacesEnabled == false {
            return "Local place history is currently disabled."
        }

        if hasAnyVisitedHistory == false {
            return "Your saved travel footprint will appear here."
        }

        if countryDays.isEmpty == false {
            return "\(snapshotStore.visitedPlaceSummary.citiesVisited) saved cities across \(snapshotStore.visitedPlaceSummary.countriesVisited) countries, plus \(countryDays.count) tracked country days."
        }

        return "\(snapshotStore.visitedPlaceSummary.citiesVisited) saved cities across \(snapshotStore.visitedPlaceSummary.countriesVisited) countries."
    }

    private var trackingModeLabel: String {
        let sources = [
            settingsStore.settings.publicIPGeolocationEnabled ? "IP" : nil,
            settingsStore.settings.usesDeviceLocation ? "Device" : nil
        ].compactMap(\.self)

        if sources.isEmpty {
            return "None"
        }

        return sources.joined(separator: " + ")
    }

    private var hasAnyVisitedHistory: Bool {
        places.isEmpty == false || countryDays.isEmpty == false
    }

    private var availableCountryDayYears: [Int] {
        snapshotStore.visitedCountryDayYears
    }

    private var availableTravelYears: [Int] {
        snapshotStore.visitedPlaceEventYears
    }

    private var selectedTravelStops: [VisitedPlaceTravelStop] {
        guard let selectedYear = resolvedSelectedTravelYear else {
            return []
        }

        return snapshotStore.visitedPlaceTravelStops(for: selectedYear)
    }

    private var selectedCountryDaySummary: VisitedCountryDayYearSummary? {
        guard let selectedYear = resolvedSelectedCountryDaysYear else {
            return nil
        }

        return snapshotStore.visitedCountryDaySummary(for: selectedYear)
    }

    private var selectedYearMonthlySummaries: [VisitedCountryDayMonthSummary] {
        guard let selectedYear = resolvedSelectedCountryDaysYear else {
            return []
        }

        return countryDays.monthlySummaries(for: selectedYear)
    }

    private var travelLogDescription: String {
        guard let selectedYear = resolvedSelectedTravelYear else {
            return "Your chronological city-level travel log will appear here after new captures are recorded."
        }

        return "Your saved chronological path for \(selectedYear), based on local device captures with IP used only when device location was unavailable."
    }

    private var countryDaysDescription: String {
        guard let selectedYear = resolvedSelectedCountryDaysYear else {
            return "Yearly country totals will appear here as daily travel history is captured."
        }

        return "In year \(selectedYear), you have been in the following countries this many days."
    }

    private var selectedYearBinding: Binding<Int> {
        Binding(
            get: { resolvedSelectedCountryDaysYear ?? currentYear },
            set: { selectedCountryDaysYear = $0 }
        )
    }

    private var selectedTravelYearBinding: Binding<Int> {
        Binding(
            get: { resolvedSelectedTravelYear ?? currentYear },
            set: { selectedTravelYear = $0 }
        )
    }

    private var resolvedSelectedCountryDaysYear: Int? {
        if let selectedCountryDaysYear, availableCountryDayYears.contains(selectedCountryDaysYear) {
            return selectedCountryDaysYear
        }

        if availableCountryDayYears.contains(currentYear) {
            return currentYear
        }

        return availableCountryDayYears.first
    }

    private var resolvedSelectedTravelYear: Int? {
        if let selectedTravelYear, availableTravelYears.contains(selectedTravelYear) {
            return selectedTravelYear
        }

        if availableTravelYears.contains(currentYear) {
            return currentYear
        }

        return availableTravelYears.first
    }

    private var currentYear: Int {
        Calendar.autoupdatingCurrent.component(.year, from: .now)
    }

    private func syncSelectedCountryDaysYear() {
        selectedCountryDaysYear = resolvedSelectedCountryDaysYear
    }

    private func syncSelectedTravelYear() {
        selectedTravelYear = resolvedSelectedTravelYear
    }

    private func countryDayValueText(for item: VisitedCountryDaySummaryItem) -> String {
        let dayLabel = item.dayCount == 1 ? "day" : "days"
        let percentText = item.percentage.formatted(.percent.precision(.fractionLength(0)))
        return "\(item.dayCount) \(dayLabel) · \(percentText)"
    }

    private func monthExpansionBinding(for monthID: String) -> Binding<Bool> {
        Binding(
            get: { expandedMonthIDs.contains(monthID) },
            set: { isExpanded in
                if isExpanded {
                    expandedMonthIDs.insert(monthID)
                } else {
                    expandedMonthIDs.remove(monthID)
                }
            }
        )
    }

    private func monthLabel(for month: Int) -> String {
        guard month >= 1, month <= Calendar.autoupdatingCurrent.monthSymbols.count else {
            return "Month \(month)"
        }

        return Calendar.autoupdatingCurrent.monthSymbols[month - 1]
    }

    private func dayLabel(for day: VisitedCountryDay) -> String {
        String(format: "%02d", day.day.day)
    }

    private func travelStopDateText(for stop: VisitedPlaceTravelStop) -> String {
        guard let firstObservedAt = stop.firstObservedAt else {
            return "Date unknown"
        }

        guard let lastObservedAt = stop.lastObservedAt, !Calendar.autoupdatingCurrent.isDate(firstObservedAt, inSameDayAs: lastObservedAt) else {
            return firstObservedAt.formatted(date: .abbreviated, time: .omitted)
        }

        return "\(firstObservedAt.formatted(date: .abbreviated, time: .omitted)) - \(lastObservedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func sourceLabel(for sources: [VisitedPlaceSource]) -> String {
        let labels = sources.map { source in
            switch source {
            case .deviceLocation:
                return "Device"
            case .publicIPGeolocation:
                return "IP"
            }
        }

        return labels.joined(separator: " + ")
    }

    private func copySelectedYearSummaryToClipboard() {
        guard let selectedYear = resolvedSelectedCountryDaysYear else {
            return
        }

        let exportText = exportText(for: selectedYear)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exportText, forType: .string)
        exportStatusMessage = "Copied \(selectedYear) summary to the clipboard."
    }

    private func exportText(for year: Int) -> String {
        let yearSummary = snapshotStore.visitedCountryDaySummary(for: year)
        let monthlySummaries = countryDays.monthlySummaries(for: year)

        var lines = ["Visited Country Days \(year)"]

        if let yearSummary {
            lines.append("Tracked days: \(yearSummary.totalTrackedDays)")
            lines.append("")
            lines.append("Year summary:")
            lines.append(contentsOf: yearSummary.items.map { item in
                "- \(item.country): \(item.dayCount) \(item.dayCount == 1 ? "day" : "days") (\(item.percentage.formatted(.percent.precision(.fractionLength(0)))))"
            })
        }

        if monthlySummaries.isEmpty == false {
            lines.append("")
            lines.append("Monthly summary:")

            for monthSummary in monthlySummaries {
                lines.append("")
                lines.append("\(monthLabel(for: monthSummary.month)) (\(monthSummary.totalTrackedDays) \(monthSummary.totalTrackedDays == 1 ? "day" : "days"))")
                lines.append(contentsOf: monthSummary.items.map { item in
                    "- \(item.country): \(item.dayCount) \(item.dayCount == 1 ? "day" : "days") (\(item.percentage.formatted(.percent.precision(.fractionLength(0)))))"
                })
            }
        }

        return lines.joined(separator: "\n")
    }
}

private enum VisitedMapMode: String, CaseIterable, Identifiable {
    case footprint
    case travelPath

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .footprint:
            return "World Footprint"
        case .travelPath:
            return "Travel Path"
        }
    }

    var description: String {
        switch self {
        case .footprint:
            return "Drag, zoom, and inspect the saved cities. Countries with at least one saved place are tinted."
        case .travelPath:
            return "Follow your chronological city-level path for the selected year."
        }
    }
}
