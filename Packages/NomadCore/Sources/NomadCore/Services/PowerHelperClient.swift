import Foundation
import NomadPowerHelperKit
import ServiceManagement

/// Where the privileged power helper stands, from the app's point of view.
public enum LidClosedHelperStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case unavailable(String)
}

public enum LidClosedHelperEvent: Equatable, Sendable {
    /// The helper ended the session on its own (deadline, low battery, heat). The text is a short reason.
    case sessionEnded(reason: String)
    /// The connection to the helper dropped. The helper puts sleep back by itself when that happens.
    case connectionLost
}

public struct LidClosedSleepError: Error, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

/// Keeps the Mac running with the lid closed. `KeepAwakeController` talks to this so it can be tested.
@MainActor
public protocol LidClosedSleepControlling: AnyObject {
    var status: LidClosedHelperStatus { get }
    var eventHandler: (@MainActor (LidClosedHelperEvent) -> Void)? { get set }

    /// Registers the helper with the system when that has not happened yet, then reports the status.
    func prepare() -> LidClosedHelperStatus
    /// Starts a lid-closed session, or moves the deadline of the running one. Nil `endsAt` runs until `end()`.
    func begin(endsAt: Date?) async throws
    func end() async
    func openApprovalSettings()
}

/// The registration boundary, kept separate so tests never register a real root daemon.
@MainActor
protocol PowerHelperServiceManaging {
    var status: SMAppService.Status { get }
    func register() throws
}

extension SMAppService: PowerHelperServiceManaging {}

/// The app's side of the privileged power helper: registers the launchd daemon (`SMAppService`) and talks to it
/// over one XPC connection that lives as long as the session, because the helper ends a session when its
/// owner disconnects.
@MainActor
public final class PowerHelperClient: LidClosedSleepControlling {
    public var eventHandler: (@MainActor (LidClosedHelperEvent) -> Void)?

    private let helperLabel: String
    private let teamIdentifier: String
    private let service: any PowerHelperServiceManaging
    private var connection: NSXPCConnection?
    private var connectionID: UUID?

    /// - Parameters:
    ///   - appBundleIdentifier: The app's bundle identifier; the helper's label is derived from it.
    ///   - teamIdentifier: The team the app and helper are signed with. Without one there is nothing to trust.
    public convenience init(
        appBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        teamIdentifier: String? = Bundle.main.object(forInfoDictionaryKey: "NomadTeamIdentifier") as? String
    ) {
        let label = NomadPowerHelperIdentity.label(appBundleIdentifier: appBundleIdentifier ?? "")
        self.init(
            appBundleIdentifier: appBundleIdentifier,
            teamIdentifier: teamIdentifier,
            service: SMAppService.daemon(plistName: NomadPowerHelperIdentity.launchdPlistName(label: label))
        )
    }

    init(
        appBundleIdentifier: String?,
        teamIdentifier: String?,
        service: any PowerHelperServiceManaging
    ) {
        helperLabel = NomadPowerHelperIdentity.label(appBundleIdentifier: appBundleIdentifier ?? "")
        self.teamIdentifier = teamIdentifier ?? ""
        self.service = service
    }

    public var status: LidClosedHelperStatus {
        guard helperRequirement != nil else {
            return .unavailable("This build isn't signed with a team, so the lid-closed helper can't run.")
        }
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            // A service lookup is not a bundle-content check. In particular, a new helper can be
            // absent from Service Management until register() submits its bundled plist. Let that
            // call validate the install and report its real error instead of skipping registration.
            return .notRegistered
        @unknown default:
            return .unavailable("The lid-closed helper is in an unknown state.")
        }
    }

    public func prepare() -> LidClosedHelperStatus {
        let current = status
        guard current == .notRegistered else {
            return current
        }
        do {
            try service.register()
        } catch {
            // Registering can report an error while the approval is still pending; the status tells which.
            let afterwards = status
            if afterwards == .notRegistered {
                return .unavailable(error.localizedDescription)
            }
            return afterwards
        }
        let afterwards = status
        if afterwards == .notRegistered {
            return .unavailable("macOS couldn't find the lid-closed helper after registration. Quit and reopen Nomad Dashboard, then try again.")
        }
        return afterwards
    }

    public func begin(endsAt: Date?) async throws {
        let proxy = try makeProxy()
        let result: (Bool, String?) = try await proxy.call { proxy, reply in
            proxy.beginLidClosedSession(endsAt: endsAt) { success, message in
                reply(.success((success, message)))
            }
        }
        guard result.0 else {
            throw LidClosedSleepError(result.1 ?? "The helper couldn't keep the Mac awake.")
        }
    }

    public func end() async {
        guard let connection else {
            return
        }
        // Closing the connection is what ends a session for good, even if the polite request never arrives.
        defer {
            self.connection = nil
            connectionID = nil
            connection.invalidate()
        }
        guard let proxy = try? makeProxy(existing: connection) else {
            return
        }
        let _: Void? = try? await proxy.call { proxy, reply in
            proxy.endLidClosedSession {
                reply(.success(()))
            }
        }
    }

    public func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: Connection

    private var helperRequirement: String? {
        NomadPowerHelperIdentity.helperCodeSigningRequirement(helperLabel: helperLabel, teamIdentifier: teamIdentifier)
    }

    private func makeProxy(existing: NSXPCConnection? = nil) throws -> HelperProxy {
        let activeConnection: NSXPCConnection
        if let existing {
            activeConnection = existing
        } else if let connection {
            activeConnection = connection
        } else {
            activeConnection = try openConnection()
            connection = activeConnection
        }
        return HelperProxy(connection: activeConnection)
    }

    private func openConnection() throws -> NSXPCConnection {
        guard let requirement = helperRequirement else {
            throw LidClosedSleepError("This build isn't signed with a team, so the lid-closed helper can't run.")
        }
        let newConnection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: NomadPowerHelperProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: NomadPowerHelperClientProtocol.self)
        newConnection.exportedObject = ClientCallbacks { [weak self] reason in
            Task { @MainActor in
                self?.eventHandler?(.sessionEnded(reason: reason))
            }
        }
        newConnection.setCodeSigningRequirement(requirement)

        // Older SDKs do not mark NSXPCConnection as Sendable. Carry a value identifying this
        // connection across the callback boundary and only touch the connection on the main actor.
        let connectionID = UUID()
        self.connectionID = connectionID
        let dropped: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionID == connectionID, self.connection != nil else {
                    return
                }
                self.connection = nil
                self.connectionID = nil
                self.eventHandler?(.connectionLost)
            }
        }
        newConnection.invalidationHandler = dropped
        newConnection.interruptionHandler = dropped
        newConnection.resume()
        return newConnection
    }
}

/// Receives the helper's "I ended the session" call on the app's side of the connection.
private final class ClientCallbacks: NSObject, NomadPowerHelperClientProtocol, @unchecked Sendable {
    private let onSessionEnded: @Sendable (String) -> Void

    init(onSessionEnded: @escaping @Sendable (String) -> Void) {
        self.onSessionEnded = onSessionEnded
    }

    func lidClosedSessionEnded(reason: String) {
        onSessionEnded(reason)
    }
}

/// Turns one helper call into an async call that finishes exactly once, with the reply or the connection error.
@MainActor
private struct HelperProxy {
    let connection: NSXPCConnection

    func call<Value: Sendable>(
        _ body: (any NomadPowerHelperProtocol, @escaping @Sendable (Result<Value, any Error>) -> Void) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeOnce(continuation)
            // XPC delivers failures on its own queue. Without @Sendable this closure inherits
            // HelperProxy's main-actor isolation and traps before it can report the error.
            let object = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
                gate.resume(.failure(LidClosedSleepError("Couldn't reach the lid-closed helper: \(error.localizedDescription)")))
            }
            guard let proxy = object as? any NomadPowerHelperProtocol else {
                gate.resume(.failure(LidClosedSleepError("Couldn't reach the lid-closed helper.")))
                return
            }
            body(proxy) { gate.resume($0) }
        }
    }
}

/// XPC calls its error handler or its reply, never both for one call, but a continuation must never resume twice.
private final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Value, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
