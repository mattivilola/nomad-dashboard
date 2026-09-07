import Foundation

/// A cancellation-aware per-refresh limit. Waiting for prerequisites does not occupy a request slot.
actor ProviderRequestBudget {
    private var available: Int
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []

    init(limit: Int) {
        available = max(1, limit)
    }

    func run<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().1.resume()
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
}

enum ProviderDeadlineError: Error { case timedOut }

/// The caller stops waiting at its deadline, even when an OS provider ignores cancellation.
/// Late values are discarded; the provider never owns presentation state.
func withProviderDeadline<Value: Sendable>(
    seconds: TimeInterval = 25,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let state = ProviderDeadlineState<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            state.start(continuation, seconds: seconds, operation: operation)
        }
    } onCancel: {
        state.finish(.failure(CancellationError()))
    }
}

private final class ProviderDeadlineState<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var finished = false
    private var tasks: [Task<Void, Never>] = []

    func start(
        _ continuation: CheckedContinuation<Value, Error>,
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        lock.lock()
        guard !finished else { lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        // These operations never mutate UI. A late result has no effect after finish wins.
        tasks = [Task {
            do { try await self.finish(.success(operation())) }
            catch { self.finish(.failure(error)) }
        }, Task {
            do { try await Task.sleep(for: .seconds(seconds))
                self.finish(.failure(ProviderDeadlineError.timedOut))
            } catch { /* winner cancelled the timer */ }
        }]
        lock.unlock()
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock()
            return
        }
        finished = true
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
