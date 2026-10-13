import Foundation
@testable import NomadPowerHelperKit
import Testing

struct LidClosedSessionEngineTests {
    @Test
    func beginWritesTheJournalBeforeChangingTheSetting() throws {
        let harness = Harness(sleepDisabled: false)

        try harness.engine.begin(endsAt: nil)

        #expect(harness.events == ["isSleepDisabled", "journal.save(prior: false)", "set(true)"])
        #expect(harness.setting.value == true)
        #expect(harness.journal.record == LidClosedJournalRecord(priorSleepDisabled: false, endsAt: nil))
        #expect(harness.engine.isActive)
    }

    @Test
    func endRestoresTheSettingAndDeletesTheJournal() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.end(reason: nil)

        #expect(harness.setting.value == false)
        #expect(harness.journal.record == nil)
        #expect(harness.engine.isActive == false)
        #expect(harness.notifications.isEmpty)
    }

    @Test
    func endNotifiesTheClientOfAReasonItDidNotRequest() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.end(reason: "battery low")

        #expect(harness.notifications == ["battery low"])
    }

    @Test
    func priorSleepDisabledIsNeverResetToFalse() throws {
        let harness = Harness(sleepDisabled: true)
        try harness.engine.begin(endsAt: nil)
        #expect(harness.journal.record?.priorSleepDisabled == true)

        harness.engine.end(reason: nil)

        #expect(harness.setting.value == true)
        #expect(harness.setting.writes == [true])
        #expect(harness.journal.record == nil)
    }

    @Test
    func beginWhileActiveOnlyMovesTheDeadlineAndKeepsTheOriginalPriorValue() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: harness.now.addingTimeInterval(600))
        let later = harness.now.addingTimeInterval(7_200)

        try harness.engine.begin(endsAt: later)

        #expect(harness.engine.endsAt == later)
        #expect(harness.setting.writes == [true])
        #expect(harness.journal.record == LidClosedJournalRecord(priorSleepDisabled: false, endsAt: later))
        harness.engine.end(reason: nil)
        #expect(harness.setting.value == false)
    }

    @Test
    func beginWithAPassedDeadlineIsRejected() {
        let harness = Harness(sleepDisabled: false)

        #expect(throws: LidClosedSessionError.deadlineAlreadyPassed) {
            try harness.engine.begin(endsAt: harness.now)
        }
        #expect(harness.setting.writes.isEmpty)
        #expect(harness.journal.record == nil)
    }

    @Test
    func failedSettingWriteLeavesNoJournalAndNoSession() {
        let harness = Harness(sleepDisabled: false)
        harness.setting.failWrites = true

        #expect(throws: LidClosedSessionError.self) {
            try harness.engine.begin(endsAt: nil)
        }
        #expect(harness.journal.record == nil)
        #expect(harness.engine.isActive == false)
    }

    @Test
    func failedJournalWriteNeverChangesTheSetting() {
        let harness = Harness(sleepDisabled: false)
        harness.journal.failSaves = true

        #expect(throws: LidClosedSessionError.self) {
            try harness.engine.begin(endsAt: nil)
        }
        #expect(harness.setting.writes.isEmpty)
        #expect(harness.engine.isActive == false)
    }

    @Test
    func recoverAtLaunchRestoresAfterACrashedSession() {
        let harness = Harness(sleepDisabled: true)
        harness.journal.record = LidClosedJournalRecord(priorSleepDisabled: false, endsAt: nil)

        harness.engine.recoverAtLaunch()

        #expect(harness.setting.value == false)
        #expect(harness.journal.record == nil)
    }

    @Test
    func recoverAtLaunchLeavesAUsersOwnDisableSleepAlone() {
        let harness = Harness(sleepDisabled: true)
        harness.journal.record = LidClosedJournalRecord(priorSleepDisabled: true, endsAt: nil)

        harness.engine.recoverAtLaunch()

        #expect(harness.setting.writes.isEmpty)
        #expect(harness.journal.record == nil)
    }

    @Test
    func recoverAtLaunchWithoutAJournalNeverTouchesTheSetting() {
        let harness = Harness(sleepDisabled: true)

        harness.engine.recoverAtLaunch()

        #expect(harness.setting.writes.isEmpty)
        #expect(harness.setting.value == true)
    }

    @Test
    func failedRestoreKeepsTheJournalForTheNextLaunch() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)
        harness.setting.failWrites = true

        harness.engine.end(reason: nil)

        #expect(harness.journal.record != nil)
        harness.setting.failWrites = false
        harness.engine.recoverAtLaunch()
        #expect(harness.setting.value == false)
        #expect(harness.journal.record == nil)
    }

    @Test
    func deadlineEndsTheSessionAndNotifiesTheClient() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: harness.now.addingTimeInterval(600))

        harness.clock.advance(599)
        harness.engine.expireIfNeeded()
        #expect(harness.engine.isActive)

        harness.clock.advance(1)
        harness.engine.expireIfNeeded()
        #expect(harness.engine.isActive == false)
        #expect(harness.setting.value == false)
        #expect(harness.notifications == [LidClosedSessionEndReason.timeIsUp])
    }

    @Test
    func sessionWithoutADeadlineNeverExpires() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.clock.advance(365 * 24 * 3_600)
        harness.engine.expireIfNeeded()

        #expect(harness.engine.isActive)
    }

    @Test
    func clientDisconnectEndsTheSessionWithoutANotification() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.clientDisconnected()

        #expect(harness.engine.isActive == false)
        #expect(harness.setting.value == false)
        #expect(harness.notifications.isEmpty)
    }

    @Test
    func lowBatteryOnBatteryEndsTheSession() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.evaluate(batteryPercent: 11, isOnAC: false, thermalState: .nominal)
        #expect(harness.engine.isActive)

        harness.engine.evaluate(batteryPercent: NomadPowerHelperIdentity.batteryFloorPercent, isOnAC: false, thermalState: .nominal)
        #expect(harness.engine.isActive == false)
        #expect(harness.notifications == [LidClosedSessionEndReason.batteryLow])
        #expect(harness.setting.value == false)
    }

    @Test
    func lowBatteryWhileChargingDoesNotEndTheSession() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.evaluate(batteryPercent: 4, isOnAC: true, thermalState: .nominal)

        #expect(harness.engine.isActive)
        #expect(harness.notifications.isEmpty)
    }

    @Test
    func unknownBatteryLevelDoesNotEndTheSession() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.evaluate(batteryPercent: nil, isOnAC: false, thermalState: .fair)

        #expect(harness.engine.isActive)
    }

    @Test
    func criticalHeatEndsTheSessionEvenOnAC() throws {
        let harness = Harness(sleepDisabled: false)
        try harness.engine.begin(endsAt: nil)

        harness.engine.evaluate(batteryPercent: 90, isOnAC: true, thermalState: .serious)
        #expect(harness.engine.isActive)

        harness.engine.evaluate(batteryPercent: 90, isOnAC: true, thermalState: .critical)
        #expect(harness.engine.isActive == false)
        #expect(harness.notifications == [LidClosedSessionEndReason.tooHot])
    }

    @Test
    func evaluateWithoutASessionDoesNothing() {
        let harness = Harness(sleepDisabled: false)

        harness.engine.evaluate(batteryPercent: 1, isOnAC: false, thermalState: .critical)

        #expect(harness.notifications.isEmpty)
        #expect(harness.setting.writes.isEmpty)
    }
}

private final class Clock {
    private(set) var current = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(_ seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

private final class EventLog {
    var events: [String] = []
}

private final class FakeSleepSetting: SleepDisabledSetting {
    struct WriteFailure: Error {}

    var value: Bool
    var writes: [Bool] = []
    var failWrites = false
    private let log: EventLog

    init(value: Bool, log: EventLog) {
        self.value = value
        self.log = log
    }

    func isSleepDisabled() throws -> Bool {
        log.events.append("isSleepDisabled")
        return value
    }

    func setSleepDisabled(_ isDisabled: Bool) throws {
        if failWrites {
            throw WriteFailure()
        }
        log.events.append("set(\(isDisabled))")
        writes.append(isDisabled)
        value = isDisabled
    }
}

private final class FakeJournal: LidClosedJournal {
    struct SaveFailure: Error {}

    var record: LidClosedJournalRecord?
    var failSaves = false
    private let log: EventLog

    init(log: EventLog) {
        self.log = log
    }

    func load() throws -> LidClosedJournalRecord? {
        record
    }

    func save(_ record: LidClosedJournalRecord) throws {
        if failSaves {
            throw SaveFailure()
        }
        log.events.append("journal.save(prior: \(record.priorSleepDisabled))")
        self.record = record
    }

    func delete() throws {
        record = nil
    }
}

private final class Harness {
    let clock = Clock()
    let log = EventLog()
    let setting: FakeSleepSetting
    let journal: FakeJournal
    var notifications: [String] = []
    private(set) var engine: LidClosedSessionEngine!

    var now: Date {
        clock.current
    }

    var events: [String] {
        log.events
    }

    init(sleepDisabled: Bool) {
        setting = FakeSleepSetting(value: sleepDisabled, log: log)
        journal = FakeJournal(log: log)
        engine = LidClosedSessionEngine(
            sleepSetting: setting,
            journal: journal,
            now: { [clock] in clock.current },
            notifyClient: { [weak self] reason in self?.notifications.append(reason) }
        )
    }
}
