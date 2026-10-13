import Foundation

/// The global macOS `SleepDisabled` setting (`pmset disablesleep`).
public protocol SleepDisabledSetting {
    func isSleepDisabled() throws -> Bool
    func setSleepDisabled(_ isDisabled: Bool) throws
}

/// What the helper writes to disk before it changes the setting, so it can put it back after a crash or reboot.
public struct LidClosedJournalRecord: Codable, Equatable, Sendable {
    public var priorSleepDisabled: Bool
    public var endsAt: Date?

    public init(priorSleepDisabled: Bool, endsAt: Date?) {
        self.priorSleepDisabled = priorSleepDisabled
        self.endsAt = endsAt
    }
}

public protocol LidClosedJournal {
    func load() throws -> LidClosedJournalRecord?
    func save(_ record: LidClosedJournalRecord) throws
    func delete() throws
}

public enum LidClosedSessionError: Error, Equatable, LocalizedError {
    case deadlineAlreadyPassed
    case sleepSettingUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .deadlineAlreadyPassed:
            "The time for keeping the Mac awake has already passed."
        case let .sleepSettingUnavailable(detail):
            "The Mac's sleep setting could not be changed: \(detail)"
        }
    }
}

/// Short, user-facing reasons the helper gives when it ends a session on its own.
public enum LidClosedSessionEndReason {
    public static let batteryLow = "battery low"
    public static let tooHot = "Mac too hot"
    public static let timeIsUp = "time is up"
}

/// The helper's whole decision logic, free of XPC, launchd and `pmset`, so it can be tested.
/// Not thread-safe: call it from one serial queue.
public final class LidClosedSessionEngine {
    public private(set) var endsAt: Date?

    private let sleepSetting: any SleepDisabledSetting
    private let journal: any LidClosedJournal
    private let now: () -> Date
    private let notifyClient: (String) -> Void
    private let log: (String) -> Void
    /// The setting's value before the session began. Non-nil exactly while a session is active.
    private var priorSleepDisabled: Bool?

    public init(
        sleepSetting: any SleepDisabledSetting,
        journal: any LidClosedJournal,
        now: @escaping () -> Date = Date.init,
        notifyClient: @escaping (String) -> Void,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.sleepSetting = sleepSetting
        self.journal = journal
        self.now = now
        self.notifyClient = notifyClient
        self.log = log
    }

    public var isActive: Bool {
        priorSleepDisabled != nil
    }

    /// Starts a session. While one is active this only moves the deadline, and the journal keeps the
    /// value the setting had before the first begin.
    public func begin(endsAt: Date?) throws {
        if let endsAt, endsAt <= now() {
            throw LidClosedSessionError.deadlineAlreadyPassed
        }

        if let priorSleepDisabled {
            try journal.save(LidClosedJournalRecord(priorSleepDisabled: priorSleepDisabled, endsAt: endsAt))
            self.endsAt = endsAt
            return
        }

        do {
            let prior = try sleepSetting.isSleepDisabled()
            // The journal goes first: if we are killed right after changing the setting, the next launch can undo it.
            try journal.save(LidClosedJournalRecord(priorSleepDisabled: prior, endsAt: endsAt))
            do {
                try sleepSetting.setSleepDisabled(true)
            } catch {
                try? journal.delete()
                throw error
            }
            priorSleepDisabled = prior
            self.endsAt = endsAt
        } catch let error as LidClosedSessionError {
            throw error
        } catch {
            throw LidClosedSessionError.sleepSettingUnavailable(error.localizedDescription)
        }
    }

    /// Ends the active session. A nil `reason` means the client asked for it and needs no notification.
    public func end(reason: String?) {
        guard let prior = priorSleepDisabled else {
            return
        }
        priorSleepDisabled = nil
        endsAt = nil

        restore(prior: prior)
        if let reason {
            notifyClient(reason)
        }
    }

    /// Undoes a session a crash or reboot left behind. Without a journal the setting is never touched, which
    /// respects a user's own `disablesleep 1`.
    public func recoverAtLaunch() {
        let record: LidClosedJournalRecord?
        do {
            record = try journal.load()
        } catch {
            log("Could not read the journal: \(error.localizedDescription)")
            return
        }
        guard let record else {
            return
        }
        restore(prior: record.priorSleepDisabled)
    }

    /// The app quit or crashed, so nothing is left to keep awake for.
    public func clientDisconnected() {
        end(reason: nil)
    }

    /// Ends the session once its deadline has passed.
    public func expireIfNeeded() {
        guard let endsAt, now() >= endsAt else {
            return
        }
        end(reason: LidClosedSessionEndReason.timeIsUp)
    }

    /// Why a session may not run (or must end) right now: a low battery that is not charging, or critical heat.
    /// Nil when it is fine to keep going. A missing battery level (a desktop Mac) never counts as low.
    public static func endReason(
        batteryPercent: Int?,
        isOnAC: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> String? {
        if thermalState == .critical {
            return LidClosedSessionEndReason.tooHot
        }
        if isOnAC == false, let batteryPercent, batteryPercent <= NomadPowerHelperIdentity.batteryFloorPercent {
            return LidClosedSessionEndReason.batteryLow
        }
        return nil
    }

    /// Ends the session when the battery is low (and not charging) or the Mac is critically hot.
    public func evaluate(batteryPercent: Int?, isOnAC: Bool, thermalState: ProcessInfo.ThermalState) {
        guard isActive,
              let reason = Self.endReason(batteryPercent: batteryPercent, isOnAC: isOnAC, thermalState: thermalState)
        else {
            return
        }
        end(reason: reason)
    }

    /// Puts the setting back unless it was already on before the session. The journal is only deleted once the
    /// setting is safe, so a failed restore is retried at the next launch.
    private func restore(prior: Bool) {
        if prior == false {
            do {
                try sleepSetting.setSleepDisabled(false)
            } catch {
                log("Could not restore the sleep setting: \(error.localizedDescription)")
                return
            }
        }
        do {
            try journal.delete()
        } catch {
            log("Could not delete the journal: \(error.localizedDescription)")
        }
    }
}
