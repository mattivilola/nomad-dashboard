import Darwin
import Foundation

public struct LiveVPNStatusProvider: VPNStatusProvider {
    private let statusSource: any VPNServiceStatusSource

    public init() {
        self.init(statusSource: ScutilVPNServiceStatusSource())
    }

    init(statusSource: any VPNServiceStatusSource) {
        self.statusSource = statusSource
    }

    public func currentStatus() async -> VPNStatusSnapshot {
        let output = await (try? statusSource.connectionListOutput()) ?? ""
        let serviceNames = Self.connectedServiceNames(from: output)

        return VPNStatusSnapshot(
            isActive: serviceNames.isEmpty == false,
            interfaceNames: [],
            serviceNames: serviceNames
        )
    }

    static func connectedServiceNames(from output: String) -> [String] {
        let names = output
            .split(whereSeparator: \.isNewline)
            .compactMap { connectedServiceName(from: String($0)) }

        return Array(Set(names)).sorted()
    }

    private static func connectedServiceName(from line: String) -> String? {
        let trimmedLine = line.drop(while: \.isWhitespace)
        let statusLine: Substring = if trimmedLine.first == "*" {
            trimmedLine.dropFirst().drop(while: \.isWhitespace)
        } else {
            trimmedLine
        }

        let connectedMarker = "(Connected)"
        guard statusLine.hasPrefix(connectedMarker) else {
            return nil
        }

        let serviceDetails = statusLine.dropFirst(connectedMarker.count)
        guard let firstQuote = serviceDetails.firstIndex(of: "\"") else {
            return nil
        }

        let remainder = serviceDetails[serviceDetails.index(after: firstQuote)...]
        guard let secondQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }

        let name = String(remainder[..<secondQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

protocol VPNServiceStatusSource: Sendable {
    func connectionListOutput() async throws -> String
}

private struct ScutilVPNServiceStatusSource: VPNServiceStatusSource {
    func connectionListOutput() async throws -> String {
        let execution = try VPNCommandExecution(
            executableURL: URL(fileURLWithPath: "/usr/sbin/scutil"),
            arguments: ["--nc", "list"]
        )
        let result = try await execution.run()

        guard result.terminationStatus == 0 else {
            let message = String(data: result.stderr, encoding: .utf8) ?? "scutil --nc list failed"
            throw VPNServiceStatusSourceError.commandFailed(message)
        }

        return String(data: result.stdout, encoding: .utf8) ?? ""
    }
}

enum VPNServiceStatusSourceError: Error {
    case commandFailed(String)
    case commandTimedOut
    case pipeConfigurationFailed
}

struct VPNCommandResult: Sendable {
    let terminationStatus: Int32
    let stdout: Data
    let stderr: Data
}

/// Drains a child-process pipe without blocking the process's output path.
private final class VPNCommandPipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var contents = Data()
    private var isClosed = false
    private var reachedEOF = false

    init(pipe: Pipe) throws {
        fileHandle = pipe.fileHandleForReading
        let descriptor = fileHandle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw VPNServiceStatusSourceError.pipeConfigurationFailed
        }
    }

    func beginDraining() {
        fileHandle.readabilityHandler = { [weak self] _ in
            self?.drainAvailable()
        }
    }

    func finishAndRead() -> Data {
        fileHandle.readabilityHandler = nil
        lock.lock()
        drainAvailableWhileLocked()
        isClosed = true
        let result = contents
        try? fileHandle.close()
        lock.unlock()
        return result
    }

    func discard() {
        fileHandle.readabilityHandler = nil
        lock.lock()
        isClosed = true
        try? fileHandle.close()
        lock.unlock()
    }

    private func drainAvailable() {
        lock.lock()
        drainAvailableWhileLocked()
        lock.unlock()
    }

    private func drainAvailableWhileLocked() {
        guard !isClosed, !reachedEOF else { return }

        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { bufferPointer in
                Darwin.read(fileHandle.fileDescriptor, bufferPointer.baseAddress!, bufferPointer.count)
            }
            if bytesRead > 0 {
                contents.append(contentsOf: buffer.prefix(bytesRead))
                continue
            }
            if bytesRead == 0 {
                reachedEOF = true
                return
            }
            if errno == EINTR {
                continue
            }
            // O_NONBLOCK makes EAGAIN the normal signal that the pipe is currently empty.
            return
        }
    }
}

/// Owns the command until it exits, is cancelled, or exceeds its deadline.
final class VPNCommandExecution: @unchecked Sendable {
    static let defaultTimeout: TimeInterval = 5

    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let stdoutReader: VPNCommandPipeReader
    private let stderrReader: VPNCommandPipeReader
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var continuation: CheckedContinuation<VPNCommandResult, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var isFinished = false

    init(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = VPNCommandExecution.defaultTimeout
    ) throws {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.timeout = max(0, timeout)
        stdoutReader = try VPNCommandPipeReader(pipe: stdoutPipe)
        stderrReader = try VPNCommandPipeReader(pipe: stderrPipe)
    }

    func run() async throws -> VPNCommandResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    var isRunning: Bool {
        process.isRunning
    }

    func cancel() {
        finishWithError(CancellationError(), terminateProcess: true)
    }

    private func start(_ continuation: CheckedContinuation<VPNCommandResult, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        stdoutReader.beginDraining()
        stderrReader.beginDraining()
        process.terminationHandler = { [weak self] process in
            self?.processDidTerminate(status: process.terminationStatus)
        }

        do {
            try process.run()
            closeParentWriteHandles()
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.finishWithError(VPNServiceStatusSourceError.commandTimedOut, terminateProcess: true)
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutWorkItem
            )
            lock.unlock()
        } catch {
            lock.unlock()
            finishWithError(error, terminateProcess: false)
        }
    }

    private func processDidTerminate(status: Int32) {
        guard let finishState = claimFinish() else { return }
        finishState.timeoutWorkItem?.cancel()
        guard let continuation = finishState.continuation else {
            discardReaders()
            return
        }
        let result = VPNCommandResult(
            terminationStatus: status,
            stdout: stdoutReader.finishAndRead(),
            stderr: stderrReader.finishAndRead()
        )
        continuation.resume(returning: result)
    }

    private func finishWithError(_ error: Error, terminateProcess: Bool) {
        guard let finishState = claimFinish() else { return }
        finishState.timeoutWorkItem?.cancel()
        if terminateProcess {
            terminateOwnedProcessIfRunning()
        }
        discardReaders()
        finishState.continuation?.resume(throwing: error)
    }

    private func claimFinish() -> (
        continuation: CheckedContinuation<VPNCommandResult, Error>?,
        timeoutWorkItem: DispatchWorkItem?
    )? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return nil }
        isFinished = true
        process.terminationHandler = nil
        let timeoutWorkItem = timeoutWorkItem
        self.timeoutWorkItem = nil
        let continuation = continuation
        self.continuation = nil
        return (continuation, timeoutWorkItem)
    }

    private func discardReaders() {
        stdoutReader.discard()
        stderrReader.discard()
        closeParentWriteHandles()
    }

    private func closeParentWriteHandles() {
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
    }

    private func terminateOwnedProcessIfRunning() {
        guard process.isRunning else { return }
        let processIdentifier = process.processIdentifier
        process.terminate()
        if processIdentifier > 0, process.isRunning {
            _ = Darwin.kill(processIdentifier, SIGKILL)
        }
    }
}
