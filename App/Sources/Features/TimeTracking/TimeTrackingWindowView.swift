import AppKit
import Combine
import NomadCore
import NomadUI
import SwiftUI

struct TimeTrackingWindowView: View {
    let settingsStore: AppSettingsStore
    let controller: ProjectTimeTrackingController

    @State private var selectedPeriod: TimeTrackingPeriod = .day
    @State private var anchorDate = Date()
    @State private var selectedDay: Date?
    @State private var expandedEntryIDs = Set<UUID>()
    @State private var entryAttentionStateByID: [UUID: Bool] = [:]
    @State private var renderState = TimeTrackingWindowRenderState.empty
    @State private var lastRenderedMinute = Date.distantPast
    @State private var exportStatusMessage: String?

    private let minuteTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    var body: some View {
        ZStack {
            NomadTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    summaryCard

                    if selectedPeriod != .day {
                        dayListCard
                    }

                    entryEditorCard
                }
                .padding(20)
            }
        }
        .frame(minWidth: 960, minHeight: 760)
        .onAppear {
            syncSelectedDay()
            lastRenderedMinute = roundedDownToMinute(Date())
            refreshRenderState(force: true)
        }
        .onChange(of: selectedPeriod) { _, _ in
            syncSelectedDay()
            exportStatusMessage = nil
            refreshRenderState(force: true)
        }
        .onChange(of: anchorDate) { _, _ in
            syncSelectedDay()
            exportStatusMessage = nil
            refreshRenderState(force: true)
        }
        .onChange(of: selectedDay) { _, _ in
            refreshRenderState(force: true)
        }
        .onReceive(controller.$entries.dropFirst()) { _ in
            refreshRenderState(force: true)
        }
        .onReceive(controller.$lastErrorMessage.dropFirst()) { _ in
            refreshRenderState(force: true)
        }
        .onReceive(controller.$runtimeState.dropFirst()) { runtimeState in
            guard renderState.activityState != runtimeState.activityState else {
                return
            }

            refreshRenderState(force: true)
        }
        .onReceive(settingsStore.$settings.dropFirst()) { _ in
            refreshRenderState(force: true)
        }
        .onReceive(minuteTicker) { currentDate in
            handleMinuteTick(currentDate)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Time Tracking")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(NomadTheme.primaryText)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(NomadTheme.secondaryText)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 10) {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(TimeTrackingPeriod.allCases) { period in
                        Text(periodTitle(period))
                            .tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                HStack(spacing: 10) {
                    actionButton(title: "Previous", systemImage: "chevron.left") {
                        shiftPeriod(by: -1)
                    }

                    Text(periodLabel)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)
                        .frame(minWidth: 190)

                    actionButton(title: "Next", systemImage: "chevron.right") {
                        shiftPeriod(by: 1)
                    }
                }

                HStack(spacing: 10) {
                    actionButton(title: primaryControlTitle, systemImage: primaryControlSymbol) {
                        Task {
                            await performPrimaryControl()
                        }
                    }

                    actionButton(title: "Stop", systemImage: "stop.fill") {
                        Task {
                            await controller.stop()
                        }
                    }

                    actionButton(title: "Copy Month Export", systemImage: "doc.on.doc") {
                        copyMonthExport()
                    }
                    .disabled(settingsStore.settings.projectTimeTrackingEnabled == false)
                }
            }
        }
    }

    private var summaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summary")
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(summarySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                    Spacer()

                    statusBadge
                }

                HStack(spacing: 12) {
                    metricCard(title: "Tracked", value: formattedDuration(summaryTotalDuration), tint: NomadTheme.teal)
                    metricCard(title: "Allocated", value: formattedDuration(summaryAllocatedDuration), tint: NomadTheme.sand)
                    metricCard(title: "Pending", value: formattedDuration(summaryUnallocatedDuration), tint: NomadTheme.coral)
                }

                VStack(spacing: 10) {
                    ForEach(summaryBucketDurations) { bucketDuration in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(controller.title(for: bucketDuration.bucket))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(NomadTheme.primaryText)

                            Spacer(minLength: 20)

                            Text(formattedDuration(bucketDuration.duration))
                                .font(.callout)
                                .foregroundStyle(NomadTheme.secondaryText)
                        }
                    }
                }

                    if let exportStatusMessage {
                        Text(exportStatusMessage)
                            .font(.caption)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                if let lastErrorMessage = renderState.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var dayListCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Days In View")
                    .font(.headline)
                    .foregroundStyle(NomadTheme.primaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(renderState.displayedDaySummaries) { daySummary in
                        Button {
                            selectedDay = daySummary.day
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(daySummary.day.formatted(date: .abbreviated, time: .omitted))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(NomadTheme.primaryText)

                                Text(formattedDuration(daySummary.totalTrackedDuration))
                                    .font(.caption)
                                    .foregroundStyle(NomadTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(resolvedSelectedDay == daySummary.day ? NomadTheme.inlineButtonBackground : NomadTheme.chartBackground.opacity(0.95))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var entryEditorCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Day Detail")
                            .font(.headline)
                            .foregroundStyle(NomadTheme.primaryText)

                        Text(resolvedSelectedDay.formatted(date: .complete, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(NomadTheme.secondaryText)
                    }

                    Spacer()

                    Text("\(dayEntries.count) entries")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                if renderState.dayEntries.isEmpty {
                    Text("No tracked entries for this day yet.")
                        .font(.subheadline)
                        .foregroundStyle(NomadTheme.secondaryText)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(renderState.dayEntries) { entry in
                            TimeTrackingEntryEditorRow(
                                model: entry,
                                selectedDay: resolvedSelectedDay,
                                bucketOptions: renderState.bucketOptions,
                                quickBucketChipsWide: renderState.quickBucketChipsWide,
                                quickBucketChipsCompact: renderState.quickBucketChipsCompact,
                                isExpanded: expandedEntryIDs.contains(entry.id),
                                onToggleExpanded: { isExpanded in
                                    setEntryExpanded(entry.id, isExpanded: isExpanded)
                                },
                                onReassign: { bucket in
                                    await controller.reassignEntry(id: entry.id, to: bucket)
                                },
                                onResize: { startAt, endAt in
                                    await controller.updateEntry(id: entry.id, startAt: startAt, endAt: endAt)
                                },
                                onSplit: { splitAt, bucket in
                                    await controller.splitEntry(id: entry.id, at: splitAt, secondBucket: bucket)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var headerSubtitle: String {
        if settingsStore.settings.projectTimeTrackingEnabled == false {
            return "Project time tracking is currently disabled in Settings."
        }

        return "\(primaryStatusLabel) with \(renderState.activeProjectCount) active project\(renderState.activeProjectCount == 1 ? "" : "s")."
    }

    private var primaryControlTitle: String {
        switch renderState.activityState {
        case .running:
            "Pause"
        case .paused:
            "Resume"
        case .stopped:
            "Play"
        }
    }

    private var primaryControlSymbol: String {
        switch renderState.activityState {
        case .running:
            "pause.fill"
        case .paused:
            "play.fill"
        case .stopped:
            "play.fill"
        }
    }

    private var primaryStatusLabel: String {
        switch renderState.activityState {
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .stopped:
            "Stopped"
        }
    }

    private var periodLabel: String {
        switch selectedPeriod {
        case .day:
            return resolvedSelectedDay.formatted(.dateTime.year().month(.wide).day())
        case .week:
            guard let interval = weekInterval(containing: anchorDate) else {
                return anchorDate.formatted(.dateTime.year().month(.wide).day())
            }

            return "\(interval.start.formatted(date: .abbreviated, time: .omitted)) to \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))"
        case .month:
            return anchorDate.formatted(.dateTime.year().month(.wide))
        }
    }

    private var summarySubtitle: String {
        switch selectedPeriod {
        case .day:
            "Exact totals for the selected day."
        case .week:
            "Monday through Sunday for the selected week."
        case .month:
            "Month totals with weekly breakdowns available in the export."
        }
    }

    private var summaryBucketDurations: [TimeTrackingBucketDuration] {
        renderState.summaryBucketDurations
    }

    private var summaryTotalDuration: TimeInterval {
        renderState.summaryTotalDuration
    }

    private var summaryUnallocatedDuration: TimeInterval {
        renderState.summaryUnallocatedDuration
    }

    private var summaryAllocatedDuration: TimeInterval {
        renderState.summaryAllocatedDuration
    }

    private var displayedDays: [Date] {
        controller.days(for: selectedPeriod, containing: anchorDate)
    }

    private var resolvedSelectedDay: Date {
        if let selectedDay, displayedDays.contains(selectedDay) {
            return selectedDay
        }

        if displayedDays.contains(calendar.startOfDay(for: anchorDate)) {
            return calendar.startOfDay(for: anchorDate)
        }

        return displayedDays.first ?? calendar.startOfDay(for: anchorDate)
    }

    private var dayEntries: [TimeTrackingEntryRowModel] {
        renderState.dayEntries
    }

    private func refreshRenderState(force: Bool) {
        let newState = makeRenderState(referenceDate: Date())
        guard force || newState != renderState else {
            return
        }

        renderState = newState
        reconcileEntryExpansionState(using: newState.dayEntries)
    }

    private func handleMinuteTick(_ currentDate: Date) {
        let currentMinute = roundedDownToMinute(currentDate)
        guard currentMinute != lastRenderedMinute else {
            return
        }

        lastRenderedMinute = currentMinute

        let today = calendar.startOfDay(for: currentDate)
        guard displayedDays.contains(today), renderState.activityState == .running else {
            return
        }

        refreshRenderState(force: true)
    }

    private func makeRenderState(referenceDate: Date) -> TimeTrackingWindowRenderState {
        let activeProjects = settingsStore.settings.activeTimeTrackingProjects
        let bucketOptions = activeProjects.map {
            TimeTrackingBucketOption(bucket: .project($0.id), title: $0.trimmedName)
        } + [
            TimeTrackingBucketOption(bucket: .other, title: "Other"),
            TimeTrackingBucketOption(bucket: .unallocated, title: "Unallocated")
        ]
        let quickActionsPresentation = TimeTrackingQuickActionsPresentation(
            activeProjects: activeProjects,
            pendingDurationText: "",
            activityTitle: "",
            primaryControlTitle: ""
        )

        let summaryBucketDurations: [TimeTrackingBucketDuration]
        let summaryTotalDuration: TimeInterval
        let summaryUnallocatedDuration: TimeInterval

        switch selectedPeriod {
        case .day:
            let summary = controller.daySummary(for: resolvedSelectedDay)
            summaryBucketDurations = summary.bucketDurations
            summaryTotalDuration = summary.totalTrackedDuration
            summaryUnallocatedDuration = summary.unallocatedDuration
        case .week:
            let summary = controller.weekSummary(containing: anchorDate)
            summaryBucketDurations = summary.bucketDurations
            summaryTotalDuration = summary.totalTrackedDuration
            summaryUnallocatedDuration = summary.daySummaries.reduce(0) { $0 + $1.unallocatedDuration }
        case .month:
            let summary = controller.monthSummary(containing: anchorDate)
            summaryBucketDurations = summary.bucketDurations
            summaryTotalDuration = summary.totalTrackedDuration
            summaryUnallocatedDuration = summary.weekSummaries.reduce(0) { partial, week in
                partial + week.daySummaries.reduce(0) { $0 + $1.unallocatedDuration }
            }
        }

        let displayedDaySummaries = displayedDays.map { day in
            TimeTrackingDisplayedDaySummary(
                day: day,
                totalTrackedDuration: controller.daySummary(for: day).totalTrackedDuration
            )
        }

        let dayEntries = controller.entries(forDay: resolvedSelectedDay).map { entry in
            let resolvedEnd = entry.resolvedEnd(at: referenceDate)
            let duration = max(resolvedEnd.timeIntervalSince(entry.startAt), 0)
            let durationLabel = formattedDuration(duration)
            let bucketTitle = controller.title(for: entry.bucket)
            let needsAction = entry.isOpen || entry.bucket == .unallocated

            return TimeTrackingEntryRowModel(
                entry: entry,
                resolvedEndAt: resolvedEnd,
                currentBucketTitle: bucketTitle,
                summaryLabel: "\(formattedTime(entry.startAt)) - \(formattedTime(resolvedEnd)) • \(durationLabel)",
                durationLabel: durationLabel,
                needsAction: needsAction,
                statusLabel: needsAction ? (entry.isOpen ? "Open" : "Pending") : nil
            )
        }

        return TimeTrackingWindowRenderState(
            activityState: controller.runtimeState.activityState,
            activeProjectCount: activeProjects.count,
            summaryBucketDurations: summaryBucketDurations,
            summaryTotalDuration: summaryTotalDuration,
            summaryUnallocatedDuration: summaryUnallocatedDuration,
            displayedDaySummaries: displayedDaySummaries,
            dayEntries: dayEntries,
            bucketOptions: bucketOptions,
            quickBucketChipsWide: quickActionsPresentation.quickBucketChips(maxProjectCount: 4, includeUnallocated: true),
            quickBucketChipsCompact: quickActionsPresentation.quickBucketChips(maxProjectCount: 3, includeUnallocated: true),
            lastErrorMessage: controller.lastErrorMessage
        )
    }

    private func weekInterval(containing date: Date) -> DateInterval? {
        guard let isoWeek = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }

        return isoWeek
    }

    private func roundedDownToMinute(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    private func reconcileEntryExpansionState(using entries: [TimeTrackingEntryRowModel]) {
        let currentIDs = Set(entries.map(\.id))
        var nextExpandedIDs = expandedEntryIDs.intersection(currentIDs)
        var nextAttentionStateByID: [UUID: Bool] = [:]

        for entry in entries {
            let previousNeedsAction = entryAttentionStateByID[entry.id]
            let wasExpanded = expandedEntryIDs.contains(entry.id)

            switch (previousNeedsAction, entry.needsAction) {
            case (.none, true):
                nextExpandedIDs.insert(entry.id)
            case (.some(false), true):
                nextExpandedIDs.insert(entry.id)
            case (.some(true), false):
                nextExpandedIDs.remove(entry.id)
            default:
                if wasExpanded {
                    nextExpandedIDs.insert(entry.id)
                }
            }

            nextAttentionStateByID[entry.id] = entry.needsAction
        }

        expandedEntryIDs = nextExpandedIDs
        entryAttentionStateByID = nextAttentionStateByID
    }

    private func setEntryExpanded(_ entryID: UUID, isExpanded: Bool) {
        if isExpanded {
            expandedEntryIDs.insert(entryID)
        } else {
            expandedEntryIDs.remove(entryID)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private var statusBadge: some View {
        Text(primaryStatusLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(statusTint.opacity(0.12))
            )
    }

    private var statusTint: Color {
        switch renderState.activityState {
        case .running:
            NomadTheme.teal
        case .paused:
            NomadTheme.sand
        case .stopped:
            NomadTheme.secondaryText
        }
    }

    private func syncSelectedDay() {
        selectedDay = resolvedSelectedDay
    }

    private func shiftPeriod(by amount: Int) {
        switch selectedPeriod {
        case .day:
            anchorDate = calendar.date(byAdding: .day, value: amount, to: anchorDate) ?? anchorDate
        case .week:
            anchorDate = calendar.date(byAdding: .day, value: amount * 7, to: anchorDate) ?? anchorDate
        case .month:
            anchorDate = calendar.date(byAdding: .month, value: amount, to: anchorDate) ?? anchorDate
        }
    }

    private func performPrimaryControl() async {
        switch renderState.activityState {
        case .running:
            await controller.pause()
        case .paused:
            await controller.resume()
        case .stopped:
            await controller.play()
        }

        refreshRenderState(force: true)
    }

    private func copyMonthExport() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(controller.monthExportText(containing: anchorDate), forType: .string)
        exportStatusMessage = "Copied \(anchorDate.formatted(.dateTime.year().month(.wide))) export to the clipboard."
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    private func periodTitle(_ period: TimeTrackingPeriod) -> String {
        switch period {
        case .day:
            "Day"
        case .week:
            "Week"
        case .month:
            "Month"
        }
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(NomadTheme.teal)
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
}

private struct TimeTrackingEntryEditorRow: View {
    let model: TimeTrackingEntryRowModel
    let selectedDay: Date
    let bucketOptions: [TimeTrackingBucketOption]
    let quickBucketChipsWide: [TimeTrackingQuickBucketChip]
    let quickBucketChipsCompact: [TimeTrackingQuickBucketChip]
    let isExpanded: Bool
    let onToggleExpanded: (Bool) -> Void
    let onReassign: @Sendable (TimeTrackingBucket) async -> Void
    let onResize: @Sendable (Date, Date) async -> Void
    let onSplit: @Sendable (Date, TimeTrackingBucket) async -> Void

    @State private var selectedBucketID: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var splitAt: Date
    @State private var splitBucketID: String
    @State private var isSplitExpanded = false

    init(
        model: TimeTrackingEntryRowModel,
        selectedDay: Date,
        bucketOptions: [TimeTrackingBucketOption],
        quickBucketChipsWide: [TimeTrackingQuickBucketChip],
        quickBucketChipsCompact: [TimeTrackingQuickBucketChip],
        isExpanded: Bool,
        onToggleExpanded: @escaping (Bool) -> Void,
        onReassign: @escaping @Sendable (TimeTrackingBucket) async -> Void,
        onResize: @escaping @Sendable (Date, Date) async -> Void,
        onSplit: @escaping @Sendable (Date, TimeTrackingBucket) async -> Void
    ) {
        self.model = model
        self.selectedDay = selectedDay
        self.bucketOptions = bucketOptions
        self.quickBucketChipsWide = quickBucketChipsWide
        self.quickBucketChipsCompact = quickBucketChipsCompact
        self.isExpanded = isExpanded
        self.onToggleExpanded = onToggleExpanded
        self.onReassign = onReassign
        self.onResize = onResize
        self.onSplit = onSplit

        let resolvedEnd = model.resolvedEndAt
        _selectedBucketID = State(initialValue: model.entry.bucket.stableID)
        _startAt = State(initialValue: model.entry.startAt)
        _endAt = State(initialValue: resolvedEnd)
        _splitAt = State(initialValue: model.entry.startAt.addingTimeInterval(max(resolvedEnd.timeIntervalSince(model.entry.startAt), 60) / 2))
        _splitBucketID = State(initialValue: TimeTrackingBucket.unallocated.stableID)
    }

    private var dayInterval: DateInterval {
        Calendar.autoupdatingCurrent.dateInterval(of: .day, for: selectedDay) ?? DateInterval(start: selectedDay, duration: 86_400)
    }

    private var bucketOptionTitlesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: bucketOptions.map { ($0.id, $0.title) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                onToggleExpanded(isExpanded == false)
            } label: {
                TimeTrackingEntryHeaderContent(
                    title: displayBucketTitle,
                    summaryLabel: model.summaryLabel,
                    statusLabel: model.statusLabel,
                    isExpanded: isExpanded,
                    needsActionTint: needsActionTint
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(NomadTheme.cardBorder.opacity(0.7))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 8) {
                        compactField("Bucket") {
                            Picker("Bucket", selection: $selectedBucketID) {
                                ForEach(bucketOptions) { option in
                                    Text(option.title)
                                        .tag(option.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        Button("Apply Bucket") {
                            Task {
                                await onReassign(bucket(for: selectedBucketID))
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    ViewThatFits(in: .horizontal) {
                        quickBucketChipRow(chips: quickBucketChipsWide, selectionID: selectedBucketID) { chip in
                            selectedBucketID = chip.bucket.stableID
                            await onReassign(chip.bucket)
                        }
                        quickBucketChipRow(chips: quickBucketChipsCompact, selectionID: selectedBucketID) { chip in
                            selectedBucketID = chip.bucket.stableID
                            await onReassign(chip.bucket)
                        }
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        compactField("Start") {
                            DatePicker(
                                "Start",
                                selection: $startAt,
                                in: dayInterval.start...dayInterval.end,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }

                        compactField("End") {
                            DatePicker(
                                "End",
                                selection: $endAt,
                                in: dayInterval.start...dayInterval.end,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }

                        Button("Save Time") {
                            Task {
                                await onResize(startAt, endAt)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NomadTheme.teal)
                    }

                    splitDisclosureButton

                    if isSplitExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .bottom, spacing: 8) {
                                compactField("Split At") {
                                    DatePicker(
                                        "Split At",
                                        selection: $splitAt,
                                        in: splitRange,
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }

                                compactField("Second Segment") {
                                    Picker("Second Segment", selection: $splitBucketID) {
                                        ForEach(bucketOptions) { option in
                                            Text(option.title)
                                                .tag(option.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .frame(width: 220)
                                }

                                Button("Split Entry") {
                                    Task {
                                        await onSplit(splitAt, bucket(for: splitBucketID))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(canSplit == false)
                            }

                            ViewThatFits(in: .horizontal) {
                                quickBucketChipRow(chips: quickBucketChipsWide, selectionID: splitBucketID) { chip in
                                    splitBucketID = chip.bucket.stableID
                                    await onSplit(splitAt, chip.bucket)
                                }
                                quickBucketChipRow(chips: quickBucketChipsCompact, selectionID: splitBucketID) { chip in
                                    splitBucketID = chip.bucket.stableID
                                    await onSplit(splitAt, chip.bucket)
                                }
                            }
                            .disabled(canSplit == false)
                        }
                    }
                }
            }
        }
        .padding(isExpanded ? 12 : 11)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 14, style: .continuous)
                .fill(NomadTheme.chartBackground.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: isExpanded ? 16 : 14, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
        .onChange(of: model) { _, newModel in
            syncFromModel(newModel)
        }
        .onChange(of: startAt) { _, _ in
            syncSplitAtWithinEditableRange()
        }
        .onChange(of: endAt) { _, _ in
            syncSplitAtWithinEditableRange()
        }
    }

    private var durationLabel: String {
        let duration = max(endAt.timeIntervalSince(startAt), 0)
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes)m"
        }

        if minutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(minutes)m"
    }

    private var displayBucketTitle: String {
        bucketOptionTitlesByID[selectedBucketID] ?? model.currentBucketTitle
    }

    private var needsAction: Bool {
        model.needsAction
    }

    private var needsActionTint: Color {
        if model.entry.isOpen {
            return NomadTheme.teal
        }

        return NomadTheme.coral
    }

    private var canSplit: Bool {
        endAt > startAt
    }

    private var splitRange: ClosedRange<Date> {
        let upperBound = max(startAt, endAt)
        return startAt...upperBound
    }

    private var splitDisclosureButton: some View {
        Button {
            isSplitExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Split Time Frame")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NomadTheme.primaryText)

                    Text(isSplitExpanded ? "Adjust the second segment and split point." : "Show split controls only when needed.")
                        .font(.caption2)
                        .foregroundStyle(NomadTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Image(systemName: isSplitExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NomadTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NomadTheme.inlineButtonBackground.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NomadTheme.cardBorder.opacity(0.85), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func syncFromModel(_ model: TimeTrackingEntryRowModel) {
        let resolvedEnd = model.resolvedEndAt
        selectedBucketID = model.entry.bucket.stableID
        startAt = model.entry.startAt
        endAt = resolvedEnd
        splitAt = model.entry.startAt.addingTimeInterval(max(resolvedEnd.timeIntervalSince(model.entry.startAt), 60) / 2)
    }

    private func syncSplitAtWithinEditableRange() {
        guard endAt > startAt else {
            splitAt = startAt
            return
        }

        if splitAt <= startAt || splitAt >= endAt {
            splitAt = startAt.addingTimeInterval(endAt.timeIntervalSince(startAt) / 2)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func quickBucketChipRow(
        chips: [TimeTrackingQuickBucketChip],
        selectionID: String,
        action: @escaping (TimeTrackingQuickBucketChip) async -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(chips) { chip in
                quickBucketChip(
                    title: chip.title,
                    isSelected: selectionID == chip.bucket.stableID
                ) {
                    Task {
                        await action(chip)
                    }
                }
            }
        }
    }

    private func bucket(for stableID: String) -> TimeTrackingBucket {
        if stableID == TimeTrackingBucket.other.stableID {
            return .other
        }

        if stableID == TimeTrackingBucket.unallocated.stableID {
            return .unallocated
        }

        if stableID.hasPrefix("project:") {
            let rawID = String(stableID.dropFirst("project:".count))
            if let projectID = UUID(uuidString: rawID) {
                return .project(projectID)
            }
        }

        return .unallocated
    }

    private func quickBucketChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? NomadTheme.teal : NomadTheme.primaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: 102)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? NomadTheme.teal.opacity(0.14) : NomadTheme.inlineButtonBackground.opacity(0.95))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isSelected ? NomadTheme.teal.opacity(0.7) : NomadTheme.cardBorder.opacity(0.92), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func compactField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NomadTheme.secondaryText)

            content()
        }
    }
}

private struct TimeTrackingEntryHeaderContent: View {
    let title: String
    let summaryLabel: String
    let statusLabel: String?
    let isExpanded: Bool
    let needsActionTint: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NomadTheme.primaryText)

                Text(summaryLabel)
                    .font(.caption)
                    .foregroundStyle(NomadTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let statusLabel {
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(needsActionTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(needsActionTint.opacity(0.12))
                    )
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(NomadTheme.tertiaryText)
        }
    }
}

private struct TimeTrackingWindowRenderState: Equatable {
    var activityState: TimeTrackingActivityState
    var activeProjectCount: Int
    var summaryBucketDurations: [TimeTrackingBucketDuration]
    var summaryTotalDuration: TimeInterval
    var summaryUnallocatedDuration: TimeInterval
    var displayedDaySummaries: [TimeTrackingDisplayedDaySummary]
    var dayEntries: [TimeTrackingEntryRowModel]
    var bucketOptions: [TimeTrackingBucketOption]
    var quickBucketChipsWide: [TimeTrackingQuickBucketChip]
    var quickBucketChipsCompact: [TimeTrackingQuickBucketChip]
    var lastErrorMessage: String?

    static let empty = TimeTrackingWindowRenderState(
        activityState: .stopped,
        activeProjectCount: 0,
        summaryBucketDurations: [],
        summaryTotalDuration: 0,
        summaryUnallocatedDuration: 0,
        displayedDaySummaries: [],
        dayEntries: [],
        bucketOptions: [],
        quickBucketChipsWide: [],
        quickBucketChipsCompact: [],
        lastErrorMessage: nil
    )

    var summaryAllocatedDuration: TimeInterval {
        max(summaryTotalDuration - summaryUnallocatedDuration, 0)
    }
}

private struct TimeTrackingDisplayedDaySummary: Identifiable, Equatable {
    let day: Date
    let totalTrackedDuration: TimeInterval

    var id: Date {
        day
    }
}

private struct TimeTrackingEntryRowModel: Identifiable, Equatable {
    let entry: TimeTrackingEntry
    let resolvedEndAt: Date
    let currentBucketTitle: String
    let summaryLabel: String
    let durationLabel: String
    let needsAction: Bool
    let statusLabel: String?

    var id: UUID {
        entry.id
    }
}

private struct TimeTrackingBucketOption: Identifiable, Equatable {
    let bucket: TimeTrackingBucket
    let title: String

    var id: String {
        bucket.stableID
    }
}
