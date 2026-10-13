import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

/// An opaque handle to one held power assertion.
public struct PowerAssertionToken: Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Holds and releases the OS power assertion that keeps the Mac awake.
public protocol PowerAssertionManaging: Sendable {
    /// Returns nil when the OS refuses the assertion.
    func acquire(keepsDisplayOn: Bool) -> PowerAssertionToken?
    func release(_ token: PowerAssertionToken)
}

/// Uses IOKit power assertions: no admin rights, no helper, and macOS drops the assertion on its own if the
/// process exits. Visible in `pmset -g assertions`.
public struct IOKitPowerAssertionManager: PowerAssertionManaging {
    public static let assertionName = "Nomad Dashboard Keep Awake"

    public init() {}

    public func acquire(keepsDisplayOn: Bool) -> PowerAssertionToken? {
        let assertionType = keepsDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            return nil
        }
        return PowerAssertionToken(rawValue: assertionID)
    }

    public func release(_ token: PowerAssertionToken) {
        IOPMAssertionRelease(IOPMAssertionID(token.rawValue))
    }
}

/// Keeps the Mac awake for a chosen duration. A power assertion covers an open lid; the optional privileged
/// helper (`LidClosedSleepControlling`) also keeps the Mac running with the lid closed.
@MainActor
public final class KeepAwakeController: ObservableObject {
    @Published public private(set) var session: KeepAwakeSession?
    @Published public private(set) var lastErrorMessage: String?
    /// How the lid-closed part of the running session is doing; `.off` when no session runs.
    @Published public private(set) var lidClosedState: KeepAwakeLidClosedState = .off
    /// Why the last session ended on its own, such as "Keep Awake ended: battery low". Cleared on the next start.
    @Published public private(set) var lastEndReason: String?

    public let settingsStore: AppSettingsStore

    private let assertions: any PowerAssertionManaging
    private let lidClosed: any LidClosedSleepControlling
    private let now: @Sendable () -> Date
    private let workspaceNotificationCenter: NotificationCenter?
    private let startBackgroundTasks: Bool

    private var token: PowerAssertionToken?
    private var expiryTask: Task<Void, Never>?
    /// Helper calls run one after another, so a stop can never overtake the start before it.
    private var lidClosedTask: Task<Void, Never>?
    private var lidClosedGeneration = 0
    /// Only written during `init` and read during `deinit`, so it never races.
    private nonisolated(unsafe) var wakeObserver: NSObjectProtocol?

    /// `lidClosed` has no default on purpose: the live client registers a system daemon, which tests must never do.
    public init(
        settingsStore: AppSettingsStore,
        lidClosed: any LidClosedSleepControlling,
        assertions: any PowerAssertionManaging = IOKitPowerAssertionManager(),
        now: @escaping @Sendable () -> Date = Date.init,
        workspaceNotificationCenter: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        startBackgroundTasks: Bool = true
    ) {
        self.settingsStore = settingsStore
        self.lidClosed = lidClosed
        self.assertions = assertions
        self.now = now
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.startBackgroundTasks = startBackgroundTasks

        lidClosed.eventHandler = { [weak self] event in
            self?.handleHelperEvent(event)
        }

        // The Mac can still sleep (lid closed), so a deadline may pass while asleep.
        wakeObserver = workspaceNotificationCenter?.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.expireIfNeeded()
            }
        }
    }

    deinit {
        expiryTask?.cancel()
        lidClosedTask?.cancel()
        if let token {
            assertions.release(token)
        }
        if let wakeObserver {
            workspaceNotificationCenter?.removeObserver(wakeObserver)
        }
    }

    public var isActive: Bool {
        session != nil
    }

    public var keepsDisplayOn: Bool {
        settingsStore.settings.keepAwakeKeepsDisplayOn
    }

    /// Starts a session, replacing a running one.
    public func start(_ duration: KeepAwakeDuration) {
        let keepsDisplayOn = keepsDisplayOn
        guard let newToken = assertions.acquire(keepsDisplayOn: keepsDisplayOn) else {
            lastErrorMessage = Self.acquisitionFailureMessage
            return
        }

        // The new assertion is held before the old one is released so the Mac never gets a gap to sleep in.
        if let oldToken = token {
            assertions.release(oldToken)
        }
        token = newToken

        let startedAt = now()
        session = KeepAwakeSession(
            startedAt: startedAt,
            endsAt: duration.interval.map { startedAt.addingTimeInterval($0) },
            keepsDisplayOn: keepsDisplayOn,
            duration: duration
        )
        lastErrorMessage = nil
        lastEndReason = nil
        scheduleExpiry()
        startLidClosedIfWanted()
    }

    public func stop() {
        expiryTask?.cancel()
        expiryTask = nil
        if let token {
            assertions.release(token)
            self.token = nil
        }
        session = nil
        endLidClosed()
    }

    /// Persists the lid-closed preference and, while a session runs, starts or ends the helper's part of it.
    public func setKeepsAwakeWhileLidClosed(_ keepsAwake: Bool) {
        settingsStore.settings.keepAwakeWhileLidClosed = keepsAwake

        guard session != nil else {
            return
        }
        if keepsAwake {
            startLidClosedIfWanted()
        } else {
            endLidClosed()
        }
    }

    /// Re-reads whether the user has allowed the helper in System Settings, and starts lid-closed mode right away if
    /// a running session was waiting for that. Cheap, so call it whenever the user may have just come back.
    public func refreshLidClosedStatus() {
        guard session != nil, lidClosedState == .needsApproval else {
            return
        }
        switch lidClosed.status {
        case .enabled:
            beginLidClosed()
        case .requiresApproval, .notRegistered:
            break
        case let .unavailable(message):
            lidClosedState = .unavailable(message)
        }
    }

    public func openLidClosedApprovalSettings() {
        lidClosed.openApprovalSettings()
    }

    /// Waits for the helper calls started so far. For tests and for quitting.
    public func waitUntilLidClosedSettled() async {
        await lidClosedTask?.value
    }

    /// Persists the preference and, while a session runs, swaps the assertion type without changing its deadline.
    public func setKeepsDisplayOn(_ keepsDisplayOn: Bool) {
        settingsStore.settings.keepAwakeKeepsDisplayOn = keepsDisplayOn

        guard var activeSession = session, activeSession.keepsDisplayOn != keepsDisplayOn else {
            return
        }
        guard let newToken = assertions.acquire(keepsDisplayOn: keepsDisplayOn) else {
            lastErrorMessage = Self.acquisitionFailureMessage
            return
        }

        if let oldToken = token {
            assertions.release(oldToken)
        }
        token = newToken
        activeSession.keepsDisplayOn = keepsDisplayOn
        session = activeSession
        lastErrorMessage = nil
    }

    /// Stops the session once its deadline has passed. Indefinite sessions never expire.
    public func expireIfNeeded() {
        guard let endsAt = session?.endsAt, now() >= endsAt else {
            return
        }
        stop()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil

        guard startBackgroundTasks, let endsAt = session?.endsAt else {
            return
        }

        let remaining = max(endsAt.timeIntervalSince(now()), 0)
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            self?.expireIfNeeded()
        }
    }

    // MARK: Lid closed

    private var wantsLidClosed: Bool {
        settingsStore.settings.keepAwakeWhileLidClosed
    }

    private func startLidClosedIfWanted() {
        guard wantsLidClosed else {
            endLidClosed()
            return
        }
        switch lidClosed.prepare() {
        case .enabled:
            beginLidClosed()
        case .requiresApproval:
            lidClosedGeneration += 1
            lidClosedState = .needsApproval
        case .notRegistered:
            lidClosedGeneration += 1
            lidClosedState = .unavailable("The lid-closed helper couldn't be registered.")
        case let .unavailable(message):
            lidClosedGeneration += 1
            lidClosedState = .unavailable(message)
        }
    }

    /// Asks the helper to keep the Mac running until the session's deadline. Asking again only moves the deadline.
    private func beginLidClosed() {
        guard let activeSession = session else {
            return
        }
        lidClosedGeneration += 1
        let generation = lidClosedGeneration
        lidClosedState = .starting
        enqueueLidClosedWork { [weak self] in
            guard let self else { return }
            do {
                try await lidClosed.begin(endsAt: activeSession.endsAt)
                if generation == lidClosedGeneration {
                    lidClosedState = .active
                }
            } catch {
                if generation == lidClosedGeneration {
                    lidClosedState = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    private func endLidClosed() {
        lidClosedGeneration += 1
        let hadHelperWork = lidClosedState == .active || lidClosedState == .starting
        lidClosedState = .off
        guard hadHelperWork else {
            return
        }
        enqueueLidClosedWork { [weak self] in
            await self?.lidClosed.end()
        }
    }

    private func enqueueLidClosedWork(_ work: @escaping @MainActor () async -> Void) {
        let previous = lidClosedTask
        lidClosedTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    private func handleHelperEvent(_ event: LidClosedHelperEvent) {
        switch event {
        case let .sessionEnded(reason):
            guard session != nil else {
                return
            }
            // The helper already put sleep back; stop the whole session without another round trip to it.
            lidClosedGeneration += 1
            lidClosedState = .off
            stop()
            lastEndReason = "Keep Awake ended: \(reason)"
        case .connectionLost:
            guard lidClosedState == .active || lidClosedState == .starting else {
                return
            }
            lidClosedGeneration += 1
            lidClosedState = .unavailable("Lost the connection to the lid-closed helper.")
        }
    }

    private static let acquisitionFailureMessage = "Couldn't keep your Mac awake. macOS declined the request."
}
