import AppKit
import Foundation
import NomadCore
import Testing

@MainActor
struct KeepAwakeControllerTests {
    @Test
    func startAcquiresDisplayAssertionByDefault() throws {
        let harness = try makeHarness()

        harness.controller.start(.oneHour)

        #expect(harness.assertions.acquiredKeepsDisplayOn == [true])
        #expect(harness.assertions.activeCount == 1)
        #expect(harness.controller.isActive)
        #expect(harness.controller.session?.keepsDisplayOn == true)
        #expect(harness.controller.session?.duration == .oneHour)
        #expect(harness.controller.session?.startedAt == harness.clock.current)
        #expect(harness.controller.session?.endsAt == harness.clock.current.addingTimeInterval(3_600))
        #expect(harness.controller.lastErrorMessage == nil)
    }

    @Test
    func startUsesSystemSleepAssertionWhenDisplayIsNotKeptOn() throws {
        let harness = try makeHarness(settings: AppSettings(keepAwakeKeepsDisplayOn: false))

        harness.controller.start(.thirtyMinutes)

        #expect(harness.assertions.acquiredKeepsDisplayOn == [false])
        #expect(harness.controller.session?.keepsDisplayOn == false)
    }

    @Test
    func stopReleasesTheAssertionAndClearsTheSession() throws {
        let harness = try makeHarness()
        harness.controller.start(.twoHours)

        harness.controller.stop()

        #expect(harness.controller.session == nil)
        #expect(harness.controller.isActive == false)
        #expect(harness.assertions.activeCount == 0)
        #expect(harness.assertions.releasedCount == 1)
    }

    @Test
    func stopWithoutASessionDoesNothing() throws {
        let harness = try makeHarness()

        harness.controller.stop()

        #expect(harness.assertions.releasedCount == 0)
        #expect(harness.controller.session == nil)
    }

    @Test
    func startWhileActiveReplacesTheSessionWithoutLeaking() throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        harness.clock.current = harness.clock.current.addingTimeInterval(600)

        harness.controller.start(.fourHours)

        #expect(harness.assertions.acquiredCount == 2)
        #expect(harness.assertions.releasedCount == 1)
        #expect(harness.assertions.activeCount == 1)
        #expect(harness.controller.session?.duration == .fourHours)
        #expect(harness.controller.session?.startedAt == harness.clock.current)
        #expect(harness.controller.session?.endsAt == harness.clock.current.addingTimeInterval(4 * 3_600))
    }

    @Test
    func indefiniteSessionHasNoDeadlineAndNeverExpires() throws {
        let harness = try makeHarness()
        harness.controller.start(.indefinite)

        harness.clock.current = harness.clock.current.addingTimeInterval(30 * 24 * 3_600)
        harness.controller.expireIfNeeded()

        #expect(harness.controller.session?.endsAt == nil)
        #expect(harness.controller.session?.remaining(at: harness.clock.current) == nil)
        #expect(harness.controller.isActive)
        #expect(harness.assertions.activeCount == 1)
    }

    @Test
    func expireIfNeededBeforeTheDeadlineKeepsTheSession() throws {
        let harness = try makeHarness()
        harness.controller.start(.fifteenMinutes)

        harness.clock.current = harness.clock.current.addingTimeInterval(14 * 60)
        harness.controller.expireIfNeeded()

        #expect(harness.controller.isActive)
        #expect(harness.assertions.releasedCount == 0)
    }

    @Test
    func expireIfNeededAfterTheDeadlineReleasesAndClears() throws {
        let harness = try makeHarness()
        harness.controller.start(.fifteenMinutes)

        harness.clock.current = harness.clock.current.addingTimeInterval(15 * 60)
        harness.controller.expireIfNeeded()

        #expect(harness.controller.session == nil)
        #expect(harness.assertions.activeCount == 0)
        #expect(harness.assertions.releasedCount == 1)
    }

    @Test
    func togglingDisplayWhileActiveSwapsTheAssertionAndKeepsTheDeadline() throws {
        let harness = try makeHarness()
        harness.controller.start(.twoHours)
        let original = try #require(harness.controller.session)
        harness.clock.current = harness.clock.current.addingTimeInterval(300)

        harness.controller.setKeepsDisplayOn(false)

        #expect(harness.assertions.acquiredKeepsDisplayOn == [true, false])
        #expect(harness.assertions.releasedCount == 1)
        #expect(harness.assertions.activeCount == 1)
        #expect(harness.controller.session?.keepsDisplayOn == false)
        #expect(harness.controller.session?.startedAt == original.startedAt)
        #expect(harness.controller.session?.endsAt == original.endsAt)
        #expect(harness.controller.session?.duration == .twoHours)
        #expect(harness.settingsStore.settings.keepAwakeKeepsDisplayOn == false)
    }

    @Test
    func togglingDisplayWithoutASessionOnlyPersistsThePreference() throws {
        let harness = try makeHarness()

        harness.controller.setKeepsDisplayOn(false)

        #expect(harness.assertions.acquiredCount == 0)
        #expect(harness.controller.session == nil)
        #expect(harness.settingsStore.settings.keepAwakeKeepsDisplayOn == false)

        harness.controller.start(.oneHour)
        #expect(harness.assertions.acquiredKeepsDisplayOn == [false])
    }

    @Test
    func failedTogglePersistsThePreferenceKeepsTheSessionAndReportsTheError() throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        harness.assertions.shouldFailAcquire = true

        harness.controller.setKeepsDisplayOn(false)

        #expect(harness.controller.session?.keepsDisplayOn == true)
        #expect(harness.settingsStore.settings.keepAwakeKeepsDisplayOn == false)
        #expect(harness.assertions.activeCount == 1)
        #expect(harness.assertions.releasedCount == 0)
        #expect(harness.controller.lastErrorMessage != nil)
    }

    @Test
    func failedAcquisitionLeavesNoSessionAndSetsTheError() throws {
        let harness = try makeHarness()
        harness.assertions.shouldFailAcquire = true

        harness.controller.start(.oneHour)

        #expect(harness.controller.session == nil)
        #expect(harness.controller.lastErrorMessage != nil)
        #expect(harness.assertions.activeCount == 0)
    }

    @Test
    func failedReplacementKeepsTheRunningSession() throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        harness.assertions.shouldFailAcquire = true

        harness.controller.start(.eightHours)

        #expect(harness.controller.session?.duration == .oneHour)
        #expect(harness.assertions.activeCount == 1)
        #expect(harness.controller.lastErrorMessage != nil)
    }

    @Test
    func successfulStartClearsThePreviousError() throws {
        let harness = try makeHarness()
        harness.assertions.shouldFailAcquire = true
        harness.controller.start(.oneHour)
        harness.assertions.shouldFailAcquire = false

        harness.controller.start(.oneHour)

        #expect(harness.controller.lastErrorMessage == nil)
        #expect(harness.controller.isActive)
    }

    @Test
    func wakeNotificationExpiresASessionThatEndedWhileAsleep() async throws {
        let notificationCenter = NotificationCenter()
        let harness = try makeHarness(workspaceNotificationCenter: notificationCenter)
        harness.controller.start(.thirtyMinutes)

        harness.clock.current = harness.clock.current.addingTimeInterval(45 * 60)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitUntil { harness.controller.isActive == false }

        #expect(harness.controller.session == nil)
        #expect(harness.assertions.activeCount == 0)
    }

    @Test
    func wakeNotificationBeforeTheDeadlineKeepsTheSession() async throws {
        let notificationCenter = NotificationCenter()
        let harness = try makeHarness(workspaceNotificationCenter: notificationCenter)
        harness.controller.start(.thirtyMinutes)

        harness.clock.current = harness.clock.current.addingTimeInterval(10 * 60)
        notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 {
            await Task.yield()
        }

        #expect(harness.controller.isActive)
    }

    @Test
    func sessionReportsRemainingAndElapsedTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let timed = KeepAwakeSession(
            startedAt: start,
            endsAt: start.addingTimeInterval(600),
            keepsDisplayOn: true,
            duration: .fifteenMinutes
        )

        #expect(timed.remaining(at: start.addingTimeInterval(100)) == 500)
        #expect(timed.remaining(at: start.addingTimeInterval(900)) == 0)
        #expect(timed.elapsed(at: start.addingTimeInterval(100)) == 100)
        #expect(timed.elapsed(at: start.addingTimeInterval(-5)) == 0)
    }

    @Test
    func durationsExposeTitlesAndIntervals() {
        #expect(KeepAwakeDuration.allCases.count == 7)
        #expect(KeepAwakeDuration.fifteenMinutes.interval == 900)
        #expect(KeepAwakeDuration.eightHours.interval == 28_800)
        #expect(KeepAwakeDuration.indefinite.interval == nil)
        #expect(KeepAwakeDuration.oneHour.title == "1 hour")
        #expect(KeepAwakeDuration.indefinite.title == "Until I stop it")
    }

    @Test
    func settingsWithoutTheKeepAwakeKeyDecodeToKeepingTheDisplayOn() throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings(keepAwakeKeepsDisplayOn: false))) as? [String: Any]
        )
        #expect(object.removeValue(forKey: "keepAwakeKeepsDisplayOn") != nil)
        let payload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: payload)

        #expect(decoded.keepAwakeKeepsDisplayOn == true)
    }

    @Test
    func keepAwakeDisplayPreferenceSurvivesAnEncodeDecodeRoundTrip() throws {
        let settings = AppSettings(keepAwakeKeepsDisplayOn: false)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.keepAwakeKeepsDisplayOn == false)
    }

    // MARK: Lid closed

    @Test
    func lidClosedIsOnByDefaultAndBeginsWithTheSessionDeadline() async throws {
        let harness = try makeHarness()

        harness.controller.start(.twoHours)
        #expect(harness.controller.lidClosedState == .starting)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.beginEndsAt == [harness.clock.current.addingTimeInterval(2 * 3_600)])
        #expect(harness.controller.lidClosedState == .active)
    }

    @Test
    func lidClosedIndefiniteSessionBeginsWithoutADeadline() async throws {
        let harness = try makeHarness()

        harness.controller.start(.indefinite)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.beginEndsAt.count == 1)
        #expect(harness.lidClosed.beginEndsAt.first == .some(nil))
    }

    @Test
    func lidClosedNeedingApprovalKeepsTheSessionRunning() async throws {
        let harness = try makeHarness()
        harness.lidClosed.status = .requiresApproval

        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.controller.lidClosedState == .needsApproval)
        #expect(harness.controller.isActive)
        #expect(harness.assertions.activeCount == 1)
        #expect(harness.lidClosed.beginEndsAt.isEmpty)
    }

    @Test
    func lidClosedUnavailableKeepsTheSessionRunningAndExplainsWhy() async throws {
        let harness = try makeHarness()
        harness.lidClosed.status = .unavailable("Not signed")

        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.controller.lidClosedState == .unavailable("Not signed"))
        #expect(harness.controller.isActive)
    }

    @Test
    func failedHelperBeginReportsUnavailable() async throws {
        let harness = try makeHarness()
        harness.lidClosed.beginError = LidClosedSleepError("Helper refused")

        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.controller.lidClosedState == .unavailable("Helper refused"))
        #expect(harness.controller.isActive)
    }

    @Test
    func stopEndsTheHelperSession() async throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()

        harness.controller.stop()
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.endCount == 1)
        #expect(harness.controller.lidClosedState == .off)
    }

    @Test
    func stopRightAfterStartStillEndsTheHelperSessionInOrder() async throws {
        let harness = try makeHarness()

        harness.controller.start(.oneHour)
        harness.controller.stop()
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.beginEndsAt.count == 1)
        #expect(harness.lidClosed.endCount == 1)
        #expect(harness.controller.lidClosedState == .off)
    }

    @Test
    func expiryEndsTheHelperSession() async throws {
        let harness = try makeHarness()
        harness.controller.start(.fifteenMinutes)
        await harness.controller.waitUntilLidClosedSettled()

        harness.clock.current = harness.clock.current.addingTimeInterval(15 * 60)
        harness.controller.expireIfNeeded()
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.endCount == 1)
        #expect(harness.controller.isActive == false)
    }

    @Test
    func replacingASessionBeginsAgainWithTheNewDeadline() async throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()
        harness.clock.current = harness.clock.current.addingTimeInterval(60)

        harness.controller.start(.fourHours)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.beginEndsAt.count == 2)
        #expect(harness.lidClosed.beginEndsAt.last == .some(harness.clock.current.addingTimeInterval(4 * 3_600)))
        #expect(harness.lidClosed.endCount == 0)
        #expect(harness.controller.lidClosedState == .active)
    }

    @Test
    func turningLidClosedOffMidSessionEndsTheHelperAndOnBeginsAgain() async throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()

        harness.controller.setKeepsAwakeWhileLidClosed(false)
        await harness.controller.waitUntilLidClosedSettled()
        #expect(harness.lidClosed.endCount == 1)
        #expect(harness.controller.lidClosedState == .off)
        #expect(harness.settingsStore.settings.keepAwakeWhileLidClosed == false)
        #expect(harness.controller.isActive)

        harness.controller.setKeepsAwakeWhileLidClosed(true)
        await harness.controller.waitUntilLidClosedSettled()
        #expect(harness.lidClosed.beginEndsAt.count == 2)
        #expect(harness.lidClosed.beginEndsAt.last == .some(harness.controller.session?.endsAt))
        #expect(harness.controller.lidClosedState == .active)
        #expect(harness.settingsStore.settings.keepAwakeWhileLidClosed == true)
    }

    @Test
    func lidClosedPreferenceWithoutASessionOnlyPersists() async throws {
        let harness = try makeHarness()

        harness.controller.setKeepsAwakeWhileLidClosed(false)
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.settingsStore.settings.keepAwakeWhileLidClosed == false)
        #expect(harness.lidClosed.touchedCount == 0)
    }

    @Test
    func lidClosedSettingOffNeverTouchesTheHelper() async throws {
        let harness = try makeHarness(settings: AppSettings(keepAwakeWhileLidClosed: false))

        harness.controller.start(.oneHour)
        harness.controller.refreshLidClosedStatus()
        harness.controller.stop()
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.controller.lidClosedState == .off)
        #expect(harness.lidClosed.touchedCount == 0)
    }

    @Test
    func helperEndedSessionStopsEverythingAndRecordsTheReason() async throws {
        let harness = try makeHarness()
        harness.controller.start(.eightHours)
        await harness.controller.waitUntilLidClosedSettled()

        harness.lidClosed.eventHandler?(.sessionEnded(reason: "battery low"))
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.controller.isActive == false)
        #expect(harness.assertions.activeCount == 0)
        #expect(harness.controller.lastEndReason == "Keep Awake ended: battery low")
        #expect(harness.lidClosed.endCount == 0)

        harness.controller.start(.oneHour)
        #expect(harness.controller.lastEndReason == nil)
    }

    @Test
    func lostHelperConnectionMarksLidClosedUnavailableButKeepsTheSession() async throws {
        let harness = try makeHarness()
        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()

        harness.lidClosed.eventHandler?(.connectionLost)

        #expect(harness.controller.isActive)
        guard case .unavailable = harness.controller.lidClosedState else {
            Issue.record("Expected unavailable, got \(harness.controller.lidClosedState)")
            return
        }
    }

    @Test
    func refreshAfterApprovalBeginsLidClosedForTheRunningSession() async throws {
        let harness = try makeHarness()
        harness.lidClosed.status = .requiresApproval
        harness.controller.start(.oneHour)
        await harness.controller.waitUntilLidClosedSettled()
        #expect(harness.lidClosed.beginEndsAt.isEmpty)

        harness.controller.refreshLidClosedStatus()
        #expect(harness.lidClosed.beginEndsAt.isEmpty)

        harness.lidClosed.status = .enabled
        harness.controller.refreshLidClosedStatus()
        await harness.controller.waitUntilLidClosedSettled()

        #expect(harness.lidClosed.beginEndsAt.count == 1)
        #expect(harness.controller.lidClosedState == .active)
    }

    @Test
    func refreshWithoutASessionDoesNothing() throws {
        let harness = try makeHarness()

        harness.controller.refreshLidClosedStatus()

        #expect(harness.lidClosed.touchedCount == 0)
    }

    @Test
    func approvalSettingsAreOpenedThroughTheHelperClient() throws {
        let harness = try makeHarness()

        harness.controller.openLidClosedApprovalSettings()

        #expect(harness.lidClosed.approvalSettingsOpened == 1)
    }

    @Test
    func lidClosedPreferenceDefaultsToOnAndSurvivesAnEncodeDecodeRoundTrip() throws {
        #expect(AppSettings().keepAwakeWhileLidClosed == true)

        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings(keepAwakeWhileLidClosed: false))) as? [String: Any]
        )
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(roundTripped.keepAwakeWhileLidClosed == false)

        #expect(object.removeValue(forKey: "keepAwakeWhileLidClosed") != nil)
        let legacy = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.keepAwakeWhileLidClosed == true)
    }

    private func makeHarness(
        settings: AppSettings = AppSettings(),
        workspaceNotificationCenter: NotificationCenter? = nil
    ) throws -> Harness {
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = AppSettingsStore(defaults: defaults)
        settingsStore.settings = settings

        let clock = TestClock(current: Date(timeIntervalSince1970: 1_800_000_000))
        let assertions = FakePowerAssertions()
        let lidClosed = FakeLidClosedSleep()
        let controller = KeepAwakeController(
            settingsStore: settingsStore,
            lidClosed: lidClosed,
            assertions: assertions,
            now: { clock.current },
            workspaceNotificationCenter: workspaceNotificationCenter,
            startBackgroundTasks: false
        )
        return Harness(
            controller: controller,
            settingsStore: settingsStore,
            assertions: assertions,
            lidClosed: lidClosed,
            clock: clock
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where condition() == false {
            await Task.yield()
        }
    }
}

@MainActor
private struct Harness {
    let controller: KeepAwakeController
    let settingsStore: AppSettingsStore
    let assertions: FakePowerAssertions
    let lidClosed: FakeLidClosedSleep
    let clock: TestClock
}

@MainActor
private final class FakeLidClosedSleep: LidClosedSleepControlling {
    var status: LidClosedHelperStatus = .enabled
    var eventHandler: (@MainActor (LidClosedHelperEvent) -> Void)?
    var beginError: LidClosedSleepError?
    private(set) var prepareCount = 0
    private(set) var beginEndsAt: [Date?] = []
    private(set) var endCount = 0
    private(set) var approvalSettingsOpened = 0

    var touchedCount: Int {
        prepareCount + beginEndsAt.count + endCount
    }

    func prepare() -> LidClosedHelperStatus {
        prepareCount += 1
        return status
    }

    func begin(endsAt: Date?) async throws {
        beginEndsAt.append(endsAt)
        if let beginError {
            throw beginError
        }
    }

    func end() async {
        endCount += 1
    }

    func openApprovalSettings() {
        approvalSettingsOpened += 1
    }
}

private final class TestClock: @unchecked Sendable {
    var current: Date

    init(current: Date) {
        self.current = current
    }
}

private final class FakePowerAssertions: PowerAssertionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: UInt32 = 1
    private var active = Set<UInt32>()
    private var acquiredTypes: [Bool] = []
    private var releases = 0
    private var failing = false

    var shouldFailAcquire: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    var acquiredKeepsDisplayOn: [Bool] {
        lock.withLock { acquiredTypes }
    }

    var acquiredCount: Int {
        lock.withLock { acquiredTypes.count }
    }

    var releasedCount: Int {
        lock.withLock { releases }
    }

    var activeCount: Int {
        lock.withLock { active.count }
    }

    func acquire(keepsDisplayOn: Bool) -> PowerAssertionToken? {
        lock.withLock {
            guard failing == false else {
                return nil
            }
            let id = nextID
            nextID += 1
            active.insert(id)
            acquiredTypes.append(keepsDisplayOn)
            return PowerAssertionToken(rawValue: id)
        }
    }

    func release(_ token: PowerAssertionToken) {
        lock.withLock {
            if active.remove(token.rawValue) != nil {
                releases += 1
            }
        }
    }
}
