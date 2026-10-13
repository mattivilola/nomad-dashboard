import Foundation

/// The predefined lengths the user can keep the Mac awake for.
public enum KeepAwakeDuration: String, CaseIterable, Sendable, Identifiable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case indefinite

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        case .eightHours: "8 hours"
        case .indefinite: "Until I stop it"
        }
    }

    /// Nil for `indefinite`: the Mac stays awake until the user stops it.
    public var interval: TimeInterval? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .fourHours: 4 * 60 * 60
        case .eightHours: 8 * 60 * 60
        case .indefinite: nil
        }
    }
}

/// A running Keep Awake session. Sessions live only in memory: macOS releases the power assertion when
/// the app exits, so nothing is restored on the next launch.
public struct KeepAwakeSession: Equatable, Sendable {
    public var startedAt: Date
    /// Nil for an indefinite session.
    public var endsAt: Date?
    public var keepsDisplayOn: Bool
    public var duration: KeepAwakeDuration

    public init(startedAt: Date, endsAt: Date?, keepsDisplayOn: Bool, duration: KeepAwakeDuration) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.keepsDisplayOn = keepsDisplayOn
        self.duration = duration
    }

    /// Time left until the session ends, never negative. Nil for an indefinite session.
    public func remaining(at date: Date) -> TimeInterval? {
        guard let endsAt else {
            return nil
        }
        return max(endsAt.timeIntervalSince(date), 0)
    }

    /// Time since the session started, never negative.
    public func elapsed(at date: Date) -> TimeInterval {
        max(date.timeIntervalSince(startedAt), 0)
    }
}

/// How the lid-closed part of a Keep Awake session is doing. Only meaningful while a session runs.
public enum KeepAwakeLidClosedState: Equatable, Sendable {
    /// The user turned lid-closed mode off.
    case off
    /// Asking the helper to start.
    case starting
    /// The Mac stays awake with the lid closed.
    case active
    /// The helper is installed but the user has not allowed it in System Settings yet.
    case needsApproval
    /// Lid-closed mode cannot work right now; the text says why.
    case unavailable(String)
}
