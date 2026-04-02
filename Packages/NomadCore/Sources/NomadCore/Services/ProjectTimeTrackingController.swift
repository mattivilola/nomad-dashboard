import AppKit
import Combine
import Foundation

@MainActor
public final class ProjectTimeTrackingController: ObservableObject {
    @Published public private(set) var entries: [TimeTrackingEntry] = []
    @Published public private(set) var runtimeState = TimeTrackingRuntimeState()
    @Published public private(set) var dashboardState: TimeTrackingDashboardState = .disabled
    @Published public private(set) var isLoaded = false
    @Published public private(set) var lastErrorMessage: String?

    public let settingsStore: AppSettingsStore

    private let ledgerStore: any TimeTrackingLedgerStore
    private let now: @Sendable () -> Date
    private var calendar: Calendar
    private let systemNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter?
    private let enableSystemObservers: Bool
    private let startBackgroundTasks: Bool

    private var settingsObservation: AnyCancellable?
    private var systemObservers: [NSObjectProtocol] = []
    private var tickerTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    private var ledger = TimeTrackingLedger.empty
    private var appliedSettings: AppSettings
    private var isMachineAwake = true

    public init(
        settingsStore: AppSettingsStore,
        ledgerStore: any TimeTrackingLedgerStore,
        calendar: Calendar? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        systemNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        enableSystemObservers: Bool = true,
        startBackgroundTasks: Bool = true
    ) {
        self.settingsStore = settingsStore
        self.ledgerStore = ledgerStore
        self.calendar = calendar ?? Self.makeMondayCalendar()
        self.now = now
        self.systemNotificationCenter = systemNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.enableSystemObservers = enableSystemObservers
        self.startBackgroundTasks = startBackgroundTasks
        appliedSettings = settingsStore.settings

        configureSettingsObservation()

        if enableSystemObservers {
            registerSystemObservers()
        }

        Task { [weak self] in
            await self?.loadPersistedLedger()
        }
    }

    deinit {
        tickerTask?.cancel()
        heartbeatTask?.cancel()
    }

    public var activeProjects: [TimeTrackingProject] {
        settingsStore.settings.activeTimeTrackingProjects
    }

    public func waitUntilLoaded() async {
        while isLoaded == false {
            await Task.yield()
        }
    }

    public func synchronize() async {
        guard isLoaded else {
            return
        }

        let currentNow = now()
        do {
            try normalizeLedgerForCurrentTime(currentNow)
            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func play() async {
        await setActivityState(.running)
    }

    public func pause() async {
        await setActivityState(.paused)
    }

    public func resume() async {
        await setActivityState(.running)
    }

    public func stop() async {
        await setActivityState(.stopped)
    }

    public func allocateCurrentDayPending(to bucket: TimeTrackingBucket) async {
        guard isLoaded else {
            return
        }

        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)

            let wasRunning = runtimeState.activityState == .running && settingsStore.settings.projectTimeTrackingEnabled
            if wasRunning {
                closeOpenEntry(at: currentNow)
            }

            let dayInterval = try dayInterval(containing: currentNow)
            var didChange = false

            for index in ledger.entries.indices {
                let entry = ledger.entries[index]
                guard entry.bucket == .unallocated,
                      entry.startAt >= dayInterval.start,
                      entry.startAt < dayInterval.end
                else {
                    continue
                }

                ledger.entries[index].bucket = bucket
                didChange = true
            }

            ledger.entries = mergeAdjacentEntries(ledger.entries)
            ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)

            if wasRunning {
                openUnallocatedEntry(at: currentNow)
            }

            if didChange || wasRunning {
                try await persistLedger()
            }

            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func quickAllocateEntry(id: UUID, to bucket: TimeTrackingBucket) async {
        guard isLoaded else {
            return
        }

        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)

            guard let index = ledger.entries.firstIndex(where: { $0.id == id }) else {
                return
            }

            let entry = ledger.entries[index]
            let shouldRestartPendingTimer = entry.isOpen &&
                entry.bucket == .unallocated &&
                bucket != .unallocated &&
                runtimeState.activityState == .running &&
                settingsStore.settings.projectTimeTrackingEnabled &&
                openEntryIndex() == index

            if shouldRestartPendingTimer {
                ledger.entries[index].endAt = max(currentNow, entry.startAt)
                ledger.entries[index].bucket = bucket
                runtimeState.openEntryID = nil
                runtimeState.lastHeartbeatAt = currentNow
                ledger.entries = mergeAdjacentEntries(ledger.entries)
                ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)
                openUnallocatedEntry(at: currentNow)
                try await persistLedger()
                clearLastErrorMessage()
                refreshPublishedState(now: currentNow)
                return
            }

            ledger.entries[index].bucket = bucket
            ledger.entries = mergeAdjacentEntries(ledger.entries)
            ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)
            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func reassignEntry(id: UUID, to bucket: TimeTrackingBucket) async {
        await mutateLedger {
            guard let index = ledger.entries.firstIndex(where: { $0.id == id }) else {
                return
            }

            ledger.entries[index].bucket = bucket
            ledger.entries = mergeAdjacentEntries(ledger.entries)
        }
    }

    public func updateEntry(id: UUID, startAt: Date, endAt: Date) async {
        await mutateLedger {
            try resizeEntry(id: id, startAt: startAt, endAt: endAt)
        }
    }

    public func splitEntry(id: UUID, at splitAt: Date, secondBucket: TimeTrackingBucket) async {
        await mutateLedger {
            guard let index = ledger.entries.firstIndex(where: { $0.id == id }) else {
                throw TimeTrackingControllerError.entryNotFound
            }

            let entry = ledger.entries[index]
            let resolvedEnd = entry.resolvedEnd(at: now())
            guard splitAt > entry.startAt, splitAt < resolvedEnd else {
                throw TimeTrackingControllerError.invalidSplitPoint
            }

            ledger.entries.remove(at: index)
            ledger.entries.insert(
                TimeTrackingEntry(
                    id: UUID(),
                    startAt: splitAt,
                    endAt: resolvedEnd,
                    bucket: secondBucket
                ),
                at: index
            )
            ledger.entries.insert(
                TimeTrackingEntry(
                    id: UUID(),
                    startAt: entry.startAt,
                    endAt: splitAt,
                    bucket: entry.bucket
                ),
                at: index
            )
            ledger.entries = mergeAdjacentEntries(ledger.entries)
        }
    }

    public func daySummary(for day: Date) -> TimeTrackingDaySummary {
        makeDaySummary(for: day, now: now())
    }

    public func weekSummary(containing date: Date) -> TimeTrackingWeekSummary {
        makeWeekSummary(containing: date, now: now())
    }

    public func monthSummary(containing date: Date) -> TimeTrackingMonthSummary {
        makeMonthSummary(containing: date, now: now())
    }

    public func entries(forDay day: Date) -> [TimeTrackingEntry] {
        guard let interval = try? dayInterval(containing: day) else {
            return []
        }

        return TimeTrackingLedger.normalizedEntries(
            ledger.entries.filter { $0.startAt >= interval.start && $0.startAt < interval.end }
        )
    }

    public func days(for period: TimeTrackingPeriod, containing date: Date) -> [Date] {
        switch period {
        case .day:
            return [calendar.startOfDay(for: date)]
        case .week:
            guard let interval = weekInterval(containing: date) else {
                return []
            }

            return dayStarts(in: interval)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: date) else {
                return []
            }

            return dayStarts(in: interval)
        }
    }

    public func title(for bucket: TimeTrackingBucket) -> String {
        switch bucket {
        case let .project(id):
            return settingsStore.settings.timeTrackingProjects.first(where: { $0.id == id })?.trimmedName.nilIfEmpty
                ?? "Archived Project"
        case .other:
            return "Other"
        case .unallocated:
            return "Unallocated"
        }
    }

    public func monthExportText(containing date: Date) -> String {
        let summary = monthSummary(containing: date)
        var lines = [
            "Project Time Tracking \(monthTitle(for: summary.monthStart))",
            "Total tracked: \(formattedDuration(summary.totalTrackedDuration))"
        ]

        if summary.bucketDurations.isEmpty == false {
            lines.append("")
            lines.append("Month summary:")
            lines.append(contentsOf: summary.bucketDurations.map { bucketDuration in
                "- \(title(for: bucketDuration.bucket)): \(formattedDuration(bucketDuration.duration))"
            })
        }

        for week in summary.weekSummaries {
            lines.append("")
            lines.append("Week of \(week.weekStart.formatted(date: .abbreviated, time: .omitted))")
            lines.append("Total: \(formattedDuration(week.totalTrackedDuration))")

            if week.bucketDurations.isEmpty == false {
                lines.append(contentsOf: week.bucketDurations.map { bucketDuration in
                    "- \(title(for: bucketDuration.bucket)): \(formattedDuration(bucketDuration.duration))"
                })
            }

            let trackedDays = week.daySummaries.filter { $0.totalTrackedDuration > 0 }
            for daySummary in trackedDays {
                lines.append("")
                lines.append("\(daySummary.dayStart.formatted(date: .abbreviated, time: .omitted))")
                for bucketDuration in daySummary.bucketDurations where bucketDuration.duration > 0 {
                    if bucketDuration.bucket == .unallocated, daySummary.unallocatedDuration == 0 {
                        continue
                    }

                    lines.append("- \(title(for: bucketDuration.bucket)): \(formattedDuration(bucketDuration.duration))")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    public func handleSystemWillSleep() async {
        guard isLoaded else {
            return
        }

        isMachineAwake = false
        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)
            closeOpenEntry(at: currentNow)
            runtimeState.lastShutdownKind = .sleep
            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func handleSystemDidWake() async {
        guard isLoaded else {
            return
        }

        isMachineAwake = true
        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)
            if settingsStore.settings.projectTimeTrackingEnabled, runtimeState.activityState == .running {
                openUnallocatedEntry(at: currentNow)
            }

            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    public func handleApplicationWillTerminate() async {
        guard isLoaded else {
            return
        }

        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)
            closeOpenEntry(at: currentNow)
            runtimeState.lastShutdownKind = .terminated
            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func configureSettingsObservation() {
        settingsObservation = settingsStore.$settings.sink { [weak self] newSettings in
            Task { @MainActor [weak self] in
                await self?.handleSettingsChange(newSettings)
            }
        }
    }

    private func registerSystemObservers() {
        if let workspaceNotificationCenter {
            systemObservers.append(
                workspaceNotificationCenter.addObserver(
                    forName: NSWorkspace.willSleepNotification,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    Task { @MainActor in
                        await self?.handleSystemWillSleep()
                    }
                }
            )
            systemObservers.append(
                workspaceNotificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    Task { @MainActor in
                        await self?.handleSystemDidWake()
                    }
                }
            )
        }

        systemObservers.append(
            systemNotificationCenter.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleApplicationWillTerminate()
                }
            }
        )
    }

    private func loadPersistedLedger() async {
        let currentNow = now()
        var recoveryErrorMessage: String?

        do {
            ledger = try await ledgerStore.load()
        } catch {
            ledger = .empty
            recoveryErrorMessage = error.localizedDescription
            runtimeState = TimeTrackingRuntimeState(
                activityState: settingsStore.settings.projectTimeTrackingEnabled ? .running : .stopped
            )
        }

        appliedSettings = settingsStore.settings

        do {
            runtimeState = ledger.runtimeState
            if recoveryErrorMessage != nil {
                runtimeState = TimeTrackingRuntimeState(
                    activityState: settingsStore.settings.projectTimeTrackingEnabled ? .running : .stopped
                )
            }

            try reconcileLoadedLedger(at: currentNow)
            try await persistLedger()
            lastErrorMessage = recoveryErrorMessage
        } catch {
            lastErrorMessage = combinedErrorMessage(primary: recoveryErrorMessage, secondary: error.localizedDescription)
        }

        refreshPublishedState(now: currentNow)
        isLoaded = true

        if startBackgroundTasks {
            startTickerTask()
            startHeartbeatTask()
        }
    }

    private func handleSettingsChange(_ newSettings: AppSettings) async {
        guard isLoaded else {
            appliedSettings = newSettings
            return
        }

        let previousSettings = appliedSettings
        appliedSettings = newSettings
        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)

            if previousSettings.projectTimeTrackingEnabled != newSettings.projectTimeTrackingEnabled {
                if newSettings.projectTimeTrackingEnabled {
                    runtimeState.activityState = .running
                    if isMachineAwake {
                        openUnallocatedEntry(at: currentNow)
                    }
                } else {
                    closeOpenEntry(at: currentNow)
                    runtimeState.activityState = .stopped
                    runtimeState.lastShutdownKind = .stopped
                }
            }

            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func startTickerTask() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(1))
                await self?.handleTicker()
            }
        }
    }

    private func startHeartbeatTask() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(10))
                await self?.handleHeartbeat()
            }
        }
    }

    private func handleTicker() async {
        guard isLoaded else {
            return
        }

        let currentNow = now()
        do {
            let didChange = try normalizeLedgerForCurrentTime(currentNow)
            if didChange {
                try await persistLedger()
                clearLastErrorMessage()
            }
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleHeartbeat() async {
        guard isLoaded else {
            return
        }

        let currentNow = now()
        do {
            let didChange = try normalizeLedgerForCurrentTime(currentNow)
            if runtimeState.activityState == .running, openEntryIndex() != nil {
                runtimeState.lastHeartbeatAt = currentNow
                runtimeState.lastShutdownKind = .none
            }

            if didChange || runtimeState.activityState == .running {
                try await persistLedger()
                clearLastErrorMessage()
            }
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func setActivityState(_ newState: TimeTrackingActivityState) async {
        guard isLoaded else {
            return
        }

        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)
            switch newState {
            case .running:
                guard settingsStore.settings.projectTimeTrackingEnabled else {
                    refreshPublishedState(now: currentNow)
                    return
                }

                runtimeState.activityState = .running
                if isMachineAwake {
                    openUnallocatedEntry(at: currentNow)
                } else {
                    runtimeState.lastShutdownKind = .none
                }
            case .paused:
                closeOpenEntry(at: currentNow)
                runtimeState.activityState = .paused
                runtimeState.lastShutdownKind = .paused
            case .stopped:
                closeOpenEntry(at: currentNow)
                runtimeState.activityState = .stopped
                runtimeState.lastShutdownKind = .stopped
            }

            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func mutateLedger(_ mutation: () throws -> Void) async {
        guard isLoaded else {
            return
        }

        let currentNow = now()

        do {
            try normalizeLedgerForCurrentTime(currentNow)
            try mutation()
            ledger.entries = mergeAdjacentEntries(ledger.entries)
            ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)
            try await persistLedger()
            clearLastErrorMessage()
            refreshPublishedState(now: currentNow)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func normalizeLedgerForCurrentTime(_ currentNow: Date) throws -> Bool {
        splitOpenEntryAtMidnightIfNeeded(at: currentNow)
    }

    private func reconcileLoadedLedger(at currentNow: Date) throws {
        if settingsStore.settings.projectTimeTrackingEnabled == false {
            closeOpenEntry(at: currentNow)
            runtimeState.activityState = .stopped
            runtimeState.lastShutdownKind = .stopped
            return
        }

        if runtimeState.activityState != .paused {
            runtimeState.activityState = .running
        }

        if runtimeState.activityState == .running {
            _ = reconcileStaleOpenEntry(at: currentNow)
            if isMachineAwake {
                openUnallocatedEntry(at: currentNow)
            }
            return
        }

        closeOpenEntry(at: currentNow)
    }

    @discardableResult
    private func reconcileStaleOpenEntry(at currentNow: Date) -> Bool {
        guard let index = openEntryIndex() else {
            runtimeState.openEntryID = nil
            return false
        }

        let openEntry = ledger.entries[index]
        let recoveredEnd: Date
        switch runtimeState.lastShutdownKind {
        case .none:
            recoveredEnd = max(openEntry.startAt, currentNow)
        case .paused, .stopped, .sleep, .terminated:
            let heartbeat = runtimeState.lastHeartbeatAt ?? runtimeState.lastPersistedAt ?? openEntry.startAt
            recoveredEnd = max(openEntry.startAt, min(heartbeat, currentNow))
        }

        ledger.entries[index].endAt = recoveredEnd
        runtimeState.openEntryID = nil
        runtimeState.lastHeartbeatAt = recoveredEnd
        ledger.entries = mergeAdjacentEntries(ledger.entries)
        return true
    }

    @discardableResult
    private func splitOpenEntryAtMidnightIfNeeded(at currentNow: Date) -> Bool {
        guard let index = openEntryIndex() else {
            return false
        }

        let entry = ledger.entries[index]
        let entryDayStart = calendar.startOfDay(for: entry.startAt)
        let currentDayStart = calendar.startOfDay(for: currentNow)
        guard entryDayStart < currentDayStart else {
            return false
        }

        ledger.entries[index].endAt = currentDayStart
        runtimeState.openEntryID = nil
        ledger.entries.append(
            TimeTrackingEntry(
                startAt: currentDayStart,
                endAt: nil,
                bucket: .unallocated
            )
        )
        ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)
        runtimeState.openEntryID = openEntryIndex().flatMap { ledger.entries[$0].id }
        runtimeState.lastHeartbeatAt = currentNow
        return true
    }

    private func openUnallocatedEntry(at currentNow: Date) {
        guard openEntryIndex() == nil else {
            runtimeState.lastHeartbeatAt = currentNow
            runtimeState.lastShutdownKind = .none
            return
        }

        let newEntry = TimeTrackingEntry(startAt: currentNow, endAt: nil, bucket: .unallocated)
        ledger.entries.append(newEntry)
        ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)
        runtimeState.openEntryID = newEntry.id
        runtimeState.lastHeartbeatAt = currentNow
        runtimeState.lastShutdownKind = .none
    }

    private func closeOpenEntry(at currentNow: Date) {
        guard let index = openEntryIndex() else {
            runtimeState.openEntryID = nil
            runtimeState.lastHeartbeatAt = currentNow
            return
        }

        ledger.entries[index].endAt = max(currentNow, ledger.entries[index].startAt)
        runtimeState.openEntryID = nil
        runtimeState.lastHeartbeatAt = currentNow
        ledger.entries = mergeAdjacentEntries(ledger.entries)
    }

    private func refreshPublishedState(now currentNow: Date) {
        let nextEntries = TimeTrackingLedger.normalizedEntries(ledger.entries)
        if entries != nextEntries {
            entries = nextEntries
        }

        let nextRuntimeState = ledger.runtimeState
        if runtimeState != nextRuntimeState {
            runtimeState = nextRuntimeState
        }

        if settingsStore.settings.projectTimeTrackingEnabled == false {
            if dashboardState != .disabled {
                dashboardState = .disabled
            }
            return
        }

        let nextDashboardState = TimeTrackingDashboardState(
            isEnabled: true,
            activityState: nextRuntimeState.activityState,
            activeProjects: activeProjects,
            recentProjects: recentDashboardProjects(),
            todaySummary: makeDaySummary(for: currentNow, now: currentNow),
            openUnallocatedEntryStartAt: openEntry()?.bucket == .unallocated ? openEntry()?.startAt : nil
        )
        if dashboardState != nextDashboardState {
            dashboardState = nextDashboardState
        }
    }

    private func recentDashboardProjects() -> [TimeTrackingProject] {
        let projectsByID = Dictionary(uniqueKeysWithValues: activeProjects.map { ($0.id, $0) })
        var orderedProjects: [TimeTrackingProject] = []
        var seenProjectIDs = Set<UUID>()

        for entry in ledger.entries.reversed() {
            guard case let .project(projectID) = entry.bucket else {
                continue
            }

            guard seenProjectIDs.insert(projectID).inserted,
                  let project = projectsByID[projectID]
            else {
                continue
            }

            orderedProjects.append(project)
        }

        return orderedProjects
    }

    private func persistLedger() async throws {
        runtimeState.lastPersistedAt = now()
        ledger.runtimeState = runtimeState
        ledger.entries = TimeTrackingLedger.normalizedEntries(ledger.entries)
        try await ledgerStore.save(ledger)
    }

    private func clearLastErrorMessage() {
        if lastErrorMessage != nil {
            lastErrorMessage = nil
        }
    }

    private func combinedErrorMessage(primary: String?, secondary: String) -> String {
        guard let primary, primary.isEmpty == false else {
            return secondary
        }

        return "\(primary) \(secondary)"
    }

    private func openEntry() -> TimeTrackingEntry? {
        openEntryIndex().map { ledger.entries[$0] }
    }

    private func openEntryIndex() -> Int? {
        if let openEntryID = runtimeState.openEntryID,
           let index = ledger.entries.firstIndex(where: { $0.id == openEntryID && $0.endAt == nil })
        {
            return index
        }

        return ledger.entries.firstIndex(where: \.isOpen)
    }

    private func resizeEntry(id: UUID, startAt: Date, endAt: Date) throws {
        guard startAt < endAt else {
            throw TimeTrackingControllerError.invalidEntryRange
        }

        guard let index = ledger.entries.firstIndex(where: { $0.id == id }) else {
            throw TimeTrackingControllerError.entryNotFound
        }

        let entry = ledger.entries[index]
        let originalEnd = entry.resolvedEnd(at: now())
        let dayStart = calendar.startOfDay(for: entry.startAt)
        guard calendar.startOfDay(for: startAt) == dayStart,
              calendar.startOfDay(for: endAt.addingTimeInterval(-1)) == dayStart
        else {
            throw TimeTrackingControllerError.crossDayEditNotAllowed
        }

        if startAt < entry.startAt {
            try consumePreviousUnallocated(index: index, toStart: startAt)
        } else if startAt > entry.startAt {
            insertOrExtendUnallocated(start: entry.startAt, end: startAt)
        }

        if endAt > originalEnd {
            try consumeNextUnallocated(index: index, toEnd: endAt)
        } else if endAt < originalEnd {
            insertOrExtendUnallocated(start: endAt, end: originalEnd)
        }

        guard let refreshedIndex = ledger.entries.firstIndex(where: { $0.id == id }) else {
            throw TimeTrackingControllerError.entryNotFound
        }

        ledger.entries[refreshedIndex].startAt = startAt
        ledger.entries[refreshedIndex].endAt = endAt
    }

    private func consumePreviousUnallocated(index: Int, toStart newStart: Date) throws {
        guard index > 0 else {
            throw TimeTrackingControllerError.expansionRequiresAdjacentUnallocatedTime
        }

        let previousIndex = index - 1
        let previous = ledger.entries[previousIndex]
        let entry = ledger.entries[index]
        guard previous.bucket == .unallocated,
              previous.resolvedEnd(at: now()) == entry.startAt,
              newStart >= previous.startAt
        else {
            throw TimeTrackingControllerError.expansionRequiresAdjacentUnallocatedTime
        }

        if newStart == previous.startAt {
            ledger.entries.remove(at: previousIndex)
        } else {
            ledger.entries[previousIndex].endAt = newStart
        }
    }

    private func consumeNextUnallocated(index: Int, toEnd newEnd: Date) throws {
        let entry = ledger.entries[index]
        let originalEnd = entry.resolvedEnd(at: now())
        let nextIndex = index + 1

        guard nextIndex < ledger.entries.count else {
            throw TimeTrackingControllerError.expansionRequiresAdjacentUnallocatedTime
        }

        let next = ledger.entries[nextIndex]
        guard next.bucket == .unallocated,
              next.startAt == originalEnd,
              newEnd <= next.resolvedEnd(at: now())
        else {
            throw TimeTrackingControllerError.expansionRequiresAdjacentUnallocatedTime
        }

        if newEnd == next.resolvedEnd(at: now()) {
            ledger.entries.remove(at: nextIndex)
        } else {
            ledger.entries[nextIndex].startAt = newEnd
        }
    }

    private func insertOrExtendUnallocated(start: Date, end: Date) {
        guard start < end else {
            return
        }

        if let previousIndex = ledger.entries.firstIndex(where: {
            $0.bucket == .unallocated && $0.endAt == start
        }) {
            ledger.entries[previousIndex].endAt = end
            return
        }

        if let nextIndex = ledger.entries.firstIndex(where: {
            $0.bucket == .unallocated && $0.startAt == end
        }) {
            ledger.entries[nextIndex].startAt = start
            return
        }

        ledger.entries.append(
            TimeTrackingEntry(
                startAt: start,
                endAt: end,
                bucket: .unallocated
            )
        )
    }

    private func mergeAdjacentEntries(_ entries: [TimeTrackingEntry]) -> [TimeTrackingEntry] {
        let sortedEntries = TimeTrackingLedger.normalizedEntries(entries)
        guard sortedEntries.isEmpty == false else {
            return []
        }

        var merged: [TimeTrackingEntry] = [sortedEntries[0]]

        for entry in sortedEntries.dropFirst() {
            guard var previous = merged.last else {
                merged.append(entry)
                continue
            }

            if previous.bucket == entry.bucket,
               previous.endAt == entry.startAt,
               previous.isOpen == false,
               entry.isOpen == false
            {
                previous.endAt = entry.endAt
                merged[merged.count - 1] = previous
            } else {
                merged.append(entry)
            }
        }

        return merged
    }

    private func makeDaySummary(for day: Date, now currentNow: Date) -> TimeTrackingDaySummary {
        guard let interval = try? dayInterval(containing: day) else {
            return TimeTrackingDaySummary(
                dayStart: calendar.startOfDay(for: day),
                bucketDurations: [],
                totalTrackedDuration: 0,
                totalAllocatedDuration: 0,
                unallocatedDuration: 0
            )
        }

        let totals = bucketDurations(in: interval, now: currentNow)
        let totalTrackedDuration = totals.reduce(0) { $0 + $1.duration }
        let unallocatedDuration = totals.first(where: { $0.bucket == .unallocated })?.duration ?? 0
        let totalAllocatedDuration = totalTrackedDuration - unallocatedDuration

        return TimeTrackingDaySummary(
            dayStart: interval.start,
            bucketDurations: totals,
            totalTrackedDuration: totalTrackedDuration,
            totalAllocatedDuration: totalAllocatedDuration,
            unallocatedDuration: unallocatedDuration
        )
    }

    private func makeWeekSummary(containing date: Date, now currentNow: Date) -> TimeTrackingWeekSummary {
        let interval = weekInterval(containing: date) ?? DateInterval(
            start: calendar.startOfDay(for: date),
            end: calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: date)) ?? calendar.startOfDay(for: date)
        )
        let daySummaries = dayStarts(in: interval).map { makeDaySummary(for: $0, now: currentNow) }
        let totals = bucketDurations(in: interval, now: currentNow)

        return TimeTrackingWeekSummary(
            weekStart: interval.start,
            weekEnd: interval.end,
            daySummaries: daySummaries,
            bucketDurations: totals,
            totalTrackedDuration: totals.reduce(0) { $0 + $1.duration }
        )
    }

    private func makeMonthSummary(containing date: Date, now currentNow: Date) -> TimeTrackingMonthSummary {
        let monthInterval = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 31 * 86_400)
        let totals = bucketDurations(in: monthInterval, now: currentNow)
        var weekSummaries: [TimeTrackingWeekSummary] = []

        var cursor = startOfWeek(containing: monthInterval.start)
        while cursor < monthInterval.end {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor
            let fullWeekInterval = DateInterval(start: cursor, end: weekEnd)
            let clippedInterval = fullWeekInterval.intersection(with: monthInterval) ?? fullWeekInterval
            let daySummaries = dayStarts(in: clippedInterval).map { makeDaySummary(for: $0, now: currentNow) }
            let weekTotals = bucketDurations(in: clippedInterval, now: currentNow)
            weekSummaries.append(
                TimeTrackingWeekSummary(
                    weekStart: clippedInterval.start,
                    weekEnd: clippedInterval.end,
                    daySummaries: daySummaries,
                    bucketDurations: weekTotals,
                    totalTrackedDuration: weekTotals.reduce(0) { $0 + $1.duration }
                )
            )
            cursor = fullWeekInterval.end
        }

        return TimeTrackingMonthSummary(
            monthStart: monthInterval.start,
            monthEnd: monthInterval.end,
            weekSummaries: weekSummaries,
            bucketDurations: totals,
            totalTrackedDuration: totals.reduce(0) { $0 + $1.duration }
        )
    }

    private func bucketDurations(in interval: DateInterval, now currentNow: Date) -> [TimeTrackingBucketDuration] {
        let relevantEntries = ledger.entries.filter { entry in
            let entryInterval = DateInterval(start: entry.startAt, end: entry.resolvedEnd(at: currentNow))
            return entryInterval.intersects(interval)
        }

        let durationsByBucket = relevantEntries.reduce(into: [TimeTrackingBucket: TimeInterval]()) { result, entry in
            let entryInterval = DateInterval(start: entry.startAt, end: entry.resolvedEnd(at: currentNow))
            guard let overlap = entryInterval.intersection(with: interval) else {
                return
            }

            result[entry.bucket, default: 0] += overlap.duration
        }

        return durationsByBucket
            .map { TimeTrackingBucketDuration(bucket: $0.key, duration: $0.value) }
            .sorted { lhs, rhs in
                if lhs.duration == rhs.duration {
                    return title(for: lhs.bucket).localizedCaseInsensitiveCompare(title(for: rhs.bucket)) == .orderedAscending
                }

                return lhs.duration > rhs.duration
            }
    }

    private func weekInterval(containing date: Date) -> DateInterval? {
        let weekStart = startOfWeek(containing: date)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return nil
        }

        return DateInterval(start: weekStart, end: weekEnd)
    }

    private func startOfWeek(containing date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func dayInterval(containing date: Date) throws -> DateInterval {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            throw TimeTrackingControllerError.invalidDateInterval
        }

        return interval
    }

    private func dayStarts(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var cursor = interval.start

        while cursor < interval.end {
            days.append(cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = nextDay
        }

        return days
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

    private func monthTitle(for monthStart: Date) -> String {
        monthStart.formatted(.dateTime.year().month(.wide))
    }

    static func makeMondayCalendar() -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}

private enum TimeTrackingControllerError: LocalizedError {
    case entryNotFound
    case invalidEntryRange
    case invalidSplitPoint
    case crossDayEditNotAllowed
    case expansionRequiresAdjacentUnallocatedTime
    case invalidDateInterval

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            "The selected time entry could not be found."
        case .invalidEntryRange:
            "The updated entry range is invalid."
        case .invalidSplitPoint:
            "Choose a split point inside the selected entry."
        case .crossDayEditNotAllowed:
            "Entries can only be edited inside a single day."
        case .expansionRequiresAdjacentUnallocatedTime:
            "Entries can only expand into adjacent unallocated time."
        case .invalidDateInterval:
            "The requested date interval is invalid."
        }
    }
}

private extension DateInterval {
    func intersection(with other: DateInterval) -> DateInterval? {
        let start = max(self.start, other.start)
        let end = min(self.end, other.end)
        guard start < end else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
