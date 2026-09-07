import Foundation
@testable import NomadCore
import Testing

@Suite("Provider request budget and deadlines")
struct ProviderRequestBudgetTests {
    @Test func cancelledQueuedAcquisitionDoesNotLeakASlot() async throws {
        let budget = ProviderRequestBudget(limit: 1)
        let gate = TestGate()
        let first = Task { try await budget.run { await gate.wait()
            return 1
        } }
        await gate.waitUntilWaiting()
        let queued = Task { try await budget.run { 2 } }
        queued.cancel()
        await gate.release()
        #expect(try await first.value == 1)
        await #expect(throws: CancellationError.self) { try await queued.value }
        #expect(try await budget.run { 3 } == 3)
    }

    @Test func budgetNeverExceedsConfiguredConcurrency() async throws {
        let budget = ProviderRequestBudget(limit: 2)
        let tracker = ConcurrencyTracker()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { try await budget.run { await tracker.enter()
                    try? await Task.sleep(for: .milliseconds(30))
                    await tracker.leave()
                } }
            }
            try await group.waitForAll()
        }
        #expect(await tracker.maximum == 2)
    }

    @Test func deadlineReturnsAndDiscardsLateCancellationIgnoringValue() async {
        let gate = TestGate()
        await #expect(throws: ProviderDeadlineError.self) {
            try await withProviderDeadline(seconds: 0.02) { await gate.wait()
                return "late"
            }
        }
        await gate.release() // Explicitly release fixture; it intentionally ignores cancellation.
    }

    @Test func cancellationBeforeAndDuringDeadlineReturnsCancellation() async {
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withProviderDeadline(seconds: 1) { 1 }
        }
        await #expect(throws: CancellationError.self) { try await before.value }

        let gate = TestGate()
        let during = Task { try await withProviderDeadline(seconds: 1) { await gate.wait()
            return 1
        } }
        await gate.waitUntilWaiting()
        during.cancel()
        await #expect(throws: CancellationError.self) { try await during.value }
        await gate.release()
    }
}

private actor TestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var waiters = 0
    private var isReleased = false
    func wait() async {
        waiters += 1
        guard !isReleased else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func waitUntilWaiting() async {
        while waiters == 0 {
            await Task.yield()
        }
    }

    func release() {
        isReleased = true
        let pending = continuations
        continuations = []
        pending.forEach { $0.resume() }
    }
}

private actor ConcurrencyTracker {
    private var active = 0
    private(set) var maximum = 0
    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }
}
