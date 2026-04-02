import Foundation
import NomadCore
import Testing

@MainActor
struct ProjectTimeTrackingControllerTests {
    @Test
    func fileLedgerStorePersistsAndLoadsLedger() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("time-tracking.json")
        let store = FileTimeTrackingLedgerStore(fileURL: fileURL)
        let projectID = UUID()
        let entry = TimeTrackingEntry(
            startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
            bucket: .project(projectID)
        )
        let ledger = TimeTrackingLedger(
            entries: [entry],
            runtimeState: TimeTrackingRuntimeState(activityState: .paused, openEntryID: nil, lastHeartbeatAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0))
        )

        try await store.save(ledger)
        let loaded = try await store.load()

        #expect(loaded == ledger)
    }

    @Test
    func enablingTrackingStartsOpenUnallocatedEntry() async throws {
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )

        await harness.controller.waitUntilLoaded()

        #expect(harness.controller.runtimeState.activityState == .running)
        #expect(harness.controller.entries.count == 1)
        #expect(harness.controller.entries.first?.bucket == .unallocated)
        #expect(harness.controller.entries.first?.isOpen == true)
    }

    @Test
    func pauseResumeAllocateAndStopPreservePendingTime() async throws {
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )
        await harness.controller.waitUntilLoaded()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30)
        await harness.controller.synchronize()
        await harness.controller.pause()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 45)
        await harness.controller.resume()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 15)
        await harness.controller.synchronize()
        await harness.controller.allocateCurrentDayPending(to: .other)

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 30)
        await harness.controller.synchronize()
        await harness.controller.stop()

        let summary = harness.controller.daySummary(for: harness.clock.current)
        #expect(harness.controller.runtimeState.activityState == .stopped)
        #expect(summary.totalTrackedDuration == TimeInterval(75 * 60))
        #expect(summary.bucketDurations.first(where: { $0.bucket == .other })?.duration == TimeInterval(60 * 60))
        #expect(summary.unallocatedDuration == TimeInterval(15 * 60))
    }

    @Test
    func runningAllocationStartsFreshPendingIntervalImmediately() async throws {
        let project = TimeTrackingProject(id: UUID(), name: "Client A")
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true, timeTrackingProjects: [project]),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )
        await harness.controller.waitUntilLoaded()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30)
        await harness.controller.synchronize()
        await harness.controller.allocateCurrentDayPending(to: .project(project.id))

        #expect(harness.controller.runtimeState.activityState == .running)
        #expect(harness.controller.entries.count == 2)
        #expect(harness.controller.entries[0].bucket == .project(project.id))
        #expect(harness.controller.entries[0].endAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30))
        #expect(harness.controller.entries[1].bucket == .unallocated)
        #expect(harness.controller.entries[1].startAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30))
        #expect(harness.controller.entries[1].isOpen == true)
        #expect(harness.controller.dashboardState.todaySummary.unallocatedDuration == 0)
    }

    @Test
    func quickAllocatingOpenEntryRestartsPendingTimerImmediately() async throws {
        let project = TimeTrackingProject(id: UUID(), name: "Client A")
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true, timeTrackingProjects: [project]),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )
        await harness.controller.waitUntilLoaded()

        let openEntryID = try #require(harness.controller.entries.first?.id)
        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30)
        await harness.controller.synchronize()
        await harness.controller.quickAllocateEntry(id: openEntryID, to: .project(project.id))

        #expect(harness.controller.runtimeState.activityState == .running)
        #expect(harness.controller.entries.count == 2)
        #expect(harness.controller.entries[0].id == openEntryID)
        #expect(harness.controller.entries[0].bucket == .project(project.id))
        #expect(harness.controller.entries[0].startAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0))
        #expect(harness.controller.entries[0].endAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30))
        #expect(harness.controller.entries[1].bucket == .unallocated)
        #expect(harness.controller.entries[1].startAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30))
        #expect(harness.controller.entries[1].isOpen == true)
        #expect(harness.controller.runtimeState.openEntryID == harness.controller.entries[1].id)
        #expect(harness.controller.dashboardState.todaySummary.unallocatedDuration == 0)
    }

    @Test
    func pausedAllocationClearsPendingWithoutRestartingTimer() async throws {
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )
        await harness.controller.waitUntilLoaded()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 20)
        await harness.controller.synchronize()
        await harness.controller.pause()
        await harness.controller.allocateCurrentDayPending(to: .other)

        #expect(harness.controller.runtimeState.activityState == .paused)
        #expect(harness.controller.entries.allSatisfy { $0.isOpen == false })
        #expect(harness.controller.entries.last?.bucket == .other)
        #expect(harness.controller.dashboardState.todaySummary.unallocatedDuration == 0)
    }

    @Test
    func stoppedAllocationClearsPendingWithoutRestartingTimer() async throws {
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )
        await harness.controller.waitUntilLoaded()
        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 25)
        await harness.controller.synchronize()
        await harness.controller.stop()
        await harness.controller.allocateCurrentDayPending(to: .other)

        #expect(harness.controller.runtimeState.activityState == .stopped)
        #expect(harness.controller.entries.count == 1)
        #expect(harness.controller.entries[0].bucket == .other)
        #expect(harness.controller.entries[0].isOpen == false)
        #expect(harness.controller.dashboardState.todaySummary.unallocatedDuration == 0)
    }

    @Test
    func dashboardRecentProjectsUseNewestDistinctProjectAllocations() async throws {
        let projectA = TimeTrackingProject(id: UUID(), name: "Alpha")
        let projectB = TimeTrackingProject(id: UUID(), name: "Bravo")
        let projectC = TimeTrackingProject(id: UUID(), name: "Charlie")
        let ledger = TimeTrackingLedger(entries: [
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
                bucket: .project(projectA.id)
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
                bucket: .other
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 30),
                bucket: .project(projectB.id)
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 30),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 0),
                bucket: .project(projectA.id)
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 0),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 30),
                bucket: .project(projectC.id)
            )
        ])
        let harness = try makeHarness(
            settings: AppSettings(
                projectTimeTrackingEnabled: true,
                timeTrackingProjects: [projectA, projectB, projectC]
            ),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 12, minute: 0),
            initialLedger: ledger
        )
        await harness.controller.waitUntilLoaded()

        #expect(harness.controller.dashboardState.recentProjects.map(\.trimmedName) == ["Charlie", "Alpha", "Bravo"])
    }

    @Test
    func dashboardRecentProjectsExcludeArchivedAndNonProjectBuckets() async throws {
        let activeProject = TimeTrackingProject(id: UUID(), name: "Active")
        let archivedProject = TimeTrackingProject(id: UUID(), name: "Archived", isArchived: true)
        let ledger = TimeTrackingLedger(entries: [
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
                bucket: .project(activeProject.id)
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
                bucket: .unallocated
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 30),
                bucket: .project(archivedProject.id)
            ),
            TimeTrackingEntry(
                startAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 30),
                endAt: makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 0),
                bucket: .other
            )
        ])
        let harness = try makeHarness(
            settings: AppSettings(
                projectTimeTrackingEnabled: true,
                timeTrackingProjects: [activeProject, archivedProject]
            ),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 0),
            initialLedger: ledger
        )
        await harness.controller.waitUntilLoaded()

        #expect(harness.controller.dashboardState.recentProjects.map(\.trimmedName) == ["Active"])
    }

    @Test
    func sleepAndWakeExcludeSleepGapFromTrackedTime() async throws {
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0)
        )
        await harness.controller.waitUntilLoaded()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 20)
        await harness.controller.synchronize()
        await harness.controller.handleSystemWillSleep()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0)
        await harness.controller.handleSystemDidWake()

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 30)
        await harness.controller.synchronize()

        let summary = harness.controller.daySummary(for: harness.clock.current)
        #expect(summary.totalTrackedDuration == TimeInterval(50 * 60))
        #expect(summary.unallocatedDuration == TimeInterval(50 * 60))
    }

    @Test
    func relaunchReconcilesStaleOpenEntryAtLastHeartbeat() async throws {
        let openEntry = TimeTrackingEntry(
            id: UUID(),
            startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0),
            endAt: nil,
            bucket: .unallocated
        )
        let ledger = TimeTrackingLedger(
            entries: [openEntry],
            runtimeState: TimeTrackingRuntimeState(
                activityState: .running,
                openEntryID: openEntry.id,
                lastHeartbeatAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 20)
            )
        )
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 0),
            initialLedger: ledger
        )
        await harness.controller.waitUntilLoaded()

        #expect(harness.controller.entries.count == 2)
        #expect(harness.controller.entries[0].endAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 20))
        #expect(harness.controller.entries[1].startAt == makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 0))
        #expect(harness.controller.entries[1].isOpen == true)

        harness.clock.current = makeDate(year: 2026, month: 3, day: 31, hour: 11, minute: 30)
        await harness.controller.synchronize()

        let summary = harness.controller.daySummary(for: harness.clock.current)
        #expect(summary.totalTrackedDuration == TimeInterval(50 * 60))
    }

    @Test
    func editingSupportsReassignResizeAndSplit() async throws {
        let projectA = TimeTrackingProject(id: UUID(), name: "Client A")
        let projectB = TimeTrackingProject(id: UUID(), name: "Client B")
        let entry = TimeTrackingEntry(
            id: UUID(),
            startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
            bucket: .project(projectA.id)
        )
        let harness = try makeHarness(
            settings: AppSettings(
                projectTimeTrackingEnabled: true,
                timeTrackingProjects: [projectA, projectB]
            ),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
            initialLedger: TimeTrackingLedger(entries: [entry])
        )
        await harness.controller.waitUntilLoaded()

        await harness.controller.reassignEntry(id: entry.id, to: .other)
        await harness.controller.updateEntry(
            id: entry.id,
            startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 15),
            endAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 45)
        )
        await harness.controller.splitEntry(
            id: entry.id,
            at: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
            secondBucket: .project(projectB.id)
        )

        let summary = harness.controller.daySummary(for: harness.clock.current)
        #expect(summary.totalTrackedDuration == TimeInterval(60 * 60))
        #expect(summary.bucketDurations.first(where: { $0.bucket == .other })?.duration == TimeInterval(15 * 60))
        #expect(summary.bucketDurations.first(where: { $0.bucket == .project(projectB.id) })?.duration == TimeInterval(15 * 60))
        #expect(summary.unallocatedDuration == TimeInterval(30 * 60))
    }

    @Test
    func quickAllocatingClosedEntryFallsBackToPlainReassign() async throws {
        let projectA = TimeTrackingProject(id: UUID(), name: "Client A")
        let projectB = TimeTrackingProject(id: UUID(), name: "Client B")
        let historicalEntry = TimeTrackingEntry(
            id: UUID(),
            startAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 0),
            endAt: makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30),
            bucket: .project(projectA.id)
        )
        let harness = try makeHarness(
            settings: AppSettings(
                projectTimeTrackingEnabled: true,
                timeTrackingProjects: [projectA, projectB]
            ),
            now: makeDate(year: 2026, month: 3, day: 31, hour: 10, minute: 0),
            initialLedger: TimeTrackingLedger(entries: [historicalEntry])
        )
        await harness.controller.waitUntilLoaded()

        let openEntryIDBefore = harness.controller.runtimeState.openEntryID
        let openEntryStartBefore = harness.controller.entries.last?.startAt

        await harness.controller.quickAllocateEntry(id: historicalEntry.id, to: .project(projectB.id))

        #expect(harness.controller.entries.count == 2)
        #expect(harness.controller.entries[0].id == historicalEntry.id)
        #expect(harness.controller.entries[0].bucket == .project(projectB.id))
        #expect(harness.controller.entries[0].endAt == makeDate(year: 2026, month: 3, day: 31, hour: 9, minute: 30))
        #expect(harness.controller.entries[1].bucket == .unallocated)
        #expect(harness.controller.entries[1].isOpen == true)
        #expect(harness.controller.entries[1].startAt == openEntryStartBefore)
        #expect(harness.controller.runtimeState.activityState == .running)
        #expect(harness.controller.runtimeState.openEntryID == openEntryIDBefore)
    }

    @Test
    func weekSummaryUsesMondayWeekBoundariesAndMonthExportIncludesBreakdowns() async throws {
        let project = TimeTrackingProject(id: UUID(), name: "Client A")
        let projectDay = makeDate(year: 2026, month: 4, day: 1, hour: 9, minute: 0)
        let sunday = makeDate(year: 2026, month: 4, day: 5, hour: 14, minute: 0)
        let harness = try makeHarness(
            settings: AppSettings(projectTimeTrackingEnabled: true, timeTrackingProjects: [project]),
            now: makeDate(year: 2026, month: 4, day: 5, hour: 18, minute: 0),
            initialLedger: TimeTrackingLedger(
                entries: [
                    TimeTrackingEntry(
                        startAt: projectDay,
                        endAt: makeDate(year: 2026, month: 4, day: 1, hour: 11, minute: 0),
                        bucket: .project(project.id)
                    ),
                    TimeTrackingEntry(
                        startAt: sunday,
                        endAt: makeDate(year: 2026, month: 4, day: 5, hour: 15, minute: 0),
                        bucket: .other
                    )
                ]
            )
        )
        await harness.controller.waitUntilLoaded()

        let weekSummary = harness.controller.weekSummary(containing: sunday)
        #expect(mondayCalendar.component(.weekday, from: weekSummary.weekStart) == 2)
        #expect(weekSummary.totalTrackedDuration == TimeInterval(3 * 60 * 60))

        let exportText = harness.controller.monthExportText(containing: sunday)
        #expect(exportText.contains("Month summary:"))
        #expect(exportText.contains("Week of"))
        #expect(exportText.contains("Client A"))
        #expect(exportText.contains("Other"))
    }

    private func makeHarness(
        settings: AppSettings,
        now: Date,
        initialLedger: TimeTrackingLedger = .empty
    ) throws -> TimeTrackingHarness {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let settingsStore = AppSettingsStore(defaults: defaults)
        settingsStore.settings = settings
        let clock = TestClock(current: now)
        let store = InMemoryTimeTrackingLedgerStore(ledger: initialLedger)
        let controller = ProjectTimeTrackingController(
            settingsStore: settingsStore,
            ledgerStore: store,
            calendar: mondayCalendar,
            now: { clock.current },
            systemNotificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter(),
            enableSystemObservers: false,
            startBackgroundTasks: false
        )

        return TimeTrackingHarness(
            settingsStore: settingsStore,
            store: store,
            controller: controller,
            clock: clock
        )
    }
}

private struct TimeTrackingHarness {
    let settingsStore: AppSettingsStore
    let store: InMemoryTimeTrackingLedgerStore
    let controller: ProjectTimeTrackingController
    let clock: TestClock
}

private final class TestClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

private actor InMemoryTimeTrackingLedgerStore: TimeTrackingLedgerStore {
    private var ledger: TimeTrackingLedger

    init(ledger: TimeTrackingLedger) {
        self.ledger = ledger
    }

    func load() async throws -> TimeTrackingLedger {
        ledger
    }

    func save(_ ledger: TimeTrackingLedger) async throws {
        self.ledger = ledger
    }

    func reset() async throws {
        ledger = .empty
    }
}

private let mondayCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    return calendar
}()

private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    mondayCalendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
    )!
}
