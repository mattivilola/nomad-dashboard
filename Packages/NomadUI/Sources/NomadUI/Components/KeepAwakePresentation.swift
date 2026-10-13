import Foundation
import NomadCore

/// The wording of the Keep Awake pill: time left for a timed session, time elapsed for an open-ended one.
struct KeepAwakePresentation: Equatable {
    let session: KeepAwakeSession

    func statusText(at date: Date) -> String {
        if let remaining = session.remaining(at: date) {
            return "Awake · \(DurationText.countdown(remaining)) left"
        }
        return "Awake until stopped · \(DurationText.countdown(session.elapsed(at: date)))"
    }
}

/// What the Keep Awake pill shows for the lid-closed part of a session.
struct KeepAwakeLidClosedPresentation: Equatable {
    enum Indicator: Equatable {
        /// A small status icon; `isHighlighted` tints it teal, otherwise it is dimmed.
        case icon(systemImage: String, isHighlighted: Bool, help: String)
        /// The helper waits for the user's approval in System Settings.
        case allowButton
    }

    static let allowButtonTitle = "Allow Lid Closed"
    static let allowButtonHelp = "Open System Settings to allow Keep Awake with the lid closed"

    let indicator: Indicator?

    init(state: KeepAwakeLidClosedState) {
        switch state {
        case .off:
            indicator = nil
        case .starting:
            indicator = .icon(systemImage: "laptopcomputer", isHighlighted: false, help: "Starting lid-closed mode")
        case .active:
            indicator = .icon(systemImage: "laptopcomputer", isHighlighted: true, help: "Stays awake with the lid closed")
        case .needsApproval:
            indicator = .allowButton
        case let .unavailable(reason):
            indicator = .icon(systemImage: "laptopcomputer.slash", isHighlighted: false, help: reason)
        }
    }

    /// The line shown at the top of the Keep Awake menu: why the last session ended, or what went wrong.
    static func menuNotice(endReason: String?, errorMessage: String?) -> String? {
        endReason ?? errorMessage
    }
}
