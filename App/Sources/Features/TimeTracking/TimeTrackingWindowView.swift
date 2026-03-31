import AppKit
import NomadCore
import NomadUI
import SwiftUI

struct TimeTrackingWindowView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var controller: ProjectTimeTrackingController

    @State private var selectedPeriod: TimeTrackingPeriod = .day
    @State private var anchorDate = Date()
    @State private var selectedDay: Date?
    @State private var exportStatusMessage: String?

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
        }
        .onChange(of: selectedPeriod) { _, _ in
            syncSelectedDay()
            exportStatusMessage = nil
        }
        .onChange(of: anchorDate) { _, _ in
            syncSelectedDay()
            exportStatusMessage = nil
        }
        .onChange(of: displayedDays) { _, _ in
            syncSelectedDay()
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

                if let lastErrorMessage = controller.lastErrorMessage {
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
                    ForEach(displayedDays, id: \.self) { day in
                        let daySummary = controller.daySummary(for: day)

                        Button {
                            selectedDay = day
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.formatted(date: .abbreviated, time: .omitted))
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
                                    .fill(resolvedSelectedDay == day ? NomadTheme.inlineButtonBackground : NomadTheme.chartBackground.opacity(0.95))
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

                if dayEntries.isEmpty {
                    Text("No tracked entries for this day yet.")
                        .font(.subheadline)
                        .foregroundStyle(NomadTheme.secondaryText)
                } else {
                    VStack(spacing: 12) {
                        ForEach(dayEntries) { entry in
                            TimeTrackingEntryEditorRow(
                                entry: entry,
                                selectedDay: resolvedSelectedDay,
                                projects: settingsStore.settings.timeTrackingProjects,
                                bucketTitle: { controller.title(for: $0) },
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

        return "\(primaryStatusLabel) with \(settingsStore.settings.activeTimeTrackingProjects.count) active project\(settingsStore.settings.activeTimeTrackingProjects.count == 1 ? "" : "s")."
    }

    private var primaryControlTitle: String {
        switch controller.runtimeState.activityState {
        case .running:
            "Pause"
        case .paused:
            "Resume"
        case .stopped:
            "Play"
        }
    }

    private var primaryControlSymbol: String {
        switch controller.runtimeState.activityState {
        case .running:
            "pause.fill"
        case .paused:
            "play.fill"
        case .stopped:
            "play.fill"
        }
    }

    private var primaryStatusLabel: String {
        switch controller.runtimeState.activityState {
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
            let summary = controller.weekSummary(containing: anchorDate)
            return "\(summary.weekStart.formatted(date: .abbreviated, time: .omitted)) to \(summary.weekEnd.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))"
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
        switch selectedPeriod {
        case .day:
            controller.daySummary(for: resolvedSelectedDay).bucketDurations
        case .week:
            controller.weekSummary(containing: anchorDate).bucketDurations
        case .month:
            controller.monthSummary(containing: anchorDate).bucketDurations
        }
    }

    private var summaryTotalDuration: TimeInterval {
        switch selectedPeriod {
        case .day:
            controller.daySummary(for: resolvedSelectedDay).totalTrackedDuration
        case .week:
            controller.weekSummary(containing: anchorDate).totalTrackedDuration
        case .month:
            controller.monthSummary(containing: anchorDate).totalTrackedDuration
        }
    }

    private var summaryUnallocatedDuration: TimeInterval {
        switch selectedPeriod {
        case .day:
            controller.daySummary(for: resolvedSelectedDay).unallocatedDuration
        case .week:
            controller.weekSummary(containing: anchorDate).daySummaries.reduce(0) { $0 + $1.unallocatedDuration }
        case .month:
            controller.monthSummary(containing: anchorDate).weekSummaries.reduce(0) { partial, week in
                partial + week.daySummaries.reduce(0) { $0 + $1.unallocatedDuration }
            }
        }
    }

    private var summaryAllocatedDuration: TimeInterval {
        max(summaryTotalDuration - summaryUnallocatedDuration, 0)
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

    private var dayEntries: [TimeTrackingEntry] {
        controller.entries(forDay: resolvedSelectedDay)
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
        switch controller.runtimeState.activityState {
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
        switch controller.runtimeState.activityState {
        case .running:
            await controller.pause()
        case .paused:
            await controller.resume()
        case .stopped:
            await controller.play()
        }
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
    let entry: TimeTrackingEntry
    let selectedDay: Date
    let projects: [TimeTrackingProject]
    let bucketTitle: (TimeTrackingBucket) -> String
    let onReassign: @Sendable (TimeTrackingBucket) async -> Void
    let onResize: @Sendable (Date, Date) async -> Void
    let onSplit: @Sendable (Date, TimeTrackingBucket) async -> Void

    @State private var selectedBucketID: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var splitAt: Date
    @State private var splitBucketID: String

    init(
        entry: TimeTrackingEntry,
        selectedDay: Date,
        projects: [TimeTrackingProject],
        bucketTitle: @escaping (TimeTrackingBucket) -> String,
        onReassign: @escaping @Sendable (TimeTrackingBucket) async -> Void,
        onResize: @escaping @Sendable (Date, Date) async -> Void,
        onSplit: @escaping @Sendable (Date, TimeTrackingBucket) async -> Void
    ) {
        self.entry = entry
        self.selectedDay = selectedDay
        self.projects = projects
        self.bucketTitle = bucketTitle
        self.onReassign = onReassign
        self.onResize = onResize
        self.onSplit = onSplit

        let resolvedEnd = entry.endAt ?? entry.startAt
        _selectedBucketID = State(initialValue: entry.bucket.stableID)
        _startAt = State(initialValue: entry.startAt)
        _endAt = State(initialValue: resolvedEnd)
        _splitAt = State(initialValue: entry.startAt.addingTimeInterval(max(resolvedEnd.timeIntervalSince(entry.startAt), 60) / 2))
        _splitBucketID = State(initialValue: TimeTrackingBucket.unallocated.stableID)
    }

    private var dayInterval: DateInterval {
        Calendar.autoupdatingCurrent.dateInterval(of: .day, for: selectedDay) ?? DateInterval(start: selectedDay, duration: 86_400)
    }

    private var bucketOptions: [TimeTrackingBucket] {
        projects.filter(\.isActive).map { .project($0.id) } + [.other, .unallocated]
    }

    private var quickActionsPresentation: TimeTrackingQuickActionsPresentation {
        TimeTrackingQuickActionsPresentation(
            activeProjects: projects,
            pendingDurationText: "",
            activityTitle: "",
            primaryControlTitle: ""
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(bucketTitle(bucket(for: selectedBucketID)))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(NomadTheme.primaryText)

                Spacer()

                Text(durationLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NomadTheme.secondaryText)
            }

            HStack(spacing: 10) {
                Picker("Bucket", selection: $selectedBucketID) {
                    ForEach(bucketOptions, id: \.stableID) { bucket in
                        Text(bucketTitle(bucket))
                            .tag(bucket.stableID)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)

                Button("Apply Bucket") {
                    Task {
                        await onReassign(bucket(for: selectedBucketID))
                    }
                }
                .buttonStyle(.bordered)
            }

            ViewThatFits(in: .horizontal) {
                quickBucketChipRow(maxProjectCount: 4, selectionID: selectedBucketID) { chip in
                    selectedBucketID = chip.bucket.stableID
                    await onReassign(chip.bucket)
                }
                quickBucketChipRow(maxProjectCount: 3, selectionID: selectedBucketID) { chip in
                    selectedBucketID = chip.bucket.stableID
                    await onReassign(chip.bucket)
                }
            }

            HStack(spacing: 10) {
                DatePicker("Start", selection: $startAt, in: dayInterval.start...dayInterval.end, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $endAt, in: dayInterval.start...dayInterval.end, displayedComponents: .hourAndMinute)

                Button("Save Time") {
                    Task {
                        await onResize(startAt, endAt)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NomadTheme.teal)
            }

            HStack(spacing: 10) {
                DatePicker("Split At", selection: $splitAt, in: startAt...endAt, displayedComponents: .hourAndMinute)

                Picker("Second Segment", selection: $splitBucketID) {
                    ForEach(bucketOptions, id: \.stableID) { bucket in
                        Text(bucketTitle(bucket))
                            .tag(bucket.stableID)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)

                Button("Split Entry") {
                    Task {
                        await onSplit(splitAt, bucket(for: splitBucketID))
                    }
                }
                .buttonStyle(.bordered)
            }

            ViewThatFits(in: .horizontal) {
                quickBucketChipRow(maxProjectCount: 4, selectionID: splitBucketID) { chip in
                    splitBucketID = chip.bucket.stableID
                    await onSplit(splitAt, chip.bucket)
                }
                quickBucketChipRow(maxProjectCount: 3, selectionID: splitBucketID) { chip in
                    splitBucketID = chip.bucket.stableID
                    await onSplit(splitAt, chip.bucket)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NomadTheme.chartBackground.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(NomadTheme.cardBorder.opacity(0.9), lineWidth: 1)
                )
        )
        .onChange(of: entry.startAt) { _, _ in
            syncFromEntry()
        }
        .onChange(of: entry.endAt) { _, _ in
            syncFromEntry()
        }
        .onChange(of: entry.bucket.stableID) { _, _ in
            syncFromEntry()
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

    private func syncFromEntry() {
        let resolvedEnd = entry.endAt ?? entry.startAt
        selectedBucketID = entry.bucket.stableID
        startAt = entry.startAt
        endAt = resolvedEnd
        splitAt = entry.startAt.addingTimeInterval(max(resolvedEnd.timeIntervalSince(entry.startAt), 60) / 2)
    }

    private func quickBucketChipRow(
        maxProjectCount: Int,
        selectionID: String,
        action: @escaping @Sendable (TimeTrackingQuickBucketChip) async -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(quickActionsPresentation.quickBucketChips(maxProjectCount: maxProjectCount, includeUnallocated: true)) { chip in
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
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: 110)
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
}
