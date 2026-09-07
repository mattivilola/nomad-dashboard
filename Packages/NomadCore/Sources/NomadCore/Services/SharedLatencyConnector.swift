import Foundation

/// Connectivity and latency share recent probes instead of opening duplicate sockets.
public actor SharedLatencyConnector: LatencyConnecting {
    private let base: any LatencyConnecting
    private var cache: [String: (value: Double?, date: Date)] = [:]
    private var inFlight: [String: Task<Double?, Never>] = [:]
    public init(base: any LatencyConnecting = TCPConnectionLatencyConnector()) {
        self.base = base
    }

    public func measureLatency(to endpoint: LatencyEndpoint, timeout: TimeInterval) async -> Double? {
        guard !Task.isCancelled else { return nil }
        let key = "\(endpoint.host):\(endpoint.port)"
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < 5 {
            return cached.value
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let base = base
        let task = Task { await base.measureLatency(to: endpoint, timeout: timeout) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = (result, Date())
        return result
    }
}
