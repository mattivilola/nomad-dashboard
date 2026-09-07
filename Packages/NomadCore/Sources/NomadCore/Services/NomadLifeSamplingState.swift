import Foundation

struct NomadLifeSamplingState {
    private(set) var connectivityAt: Date?
    private(set) var latencyAt: Date?
    mutating func accept(connectivity: Date?, latency: Date?) -> (accepted: Bool, hasNewLatency: Bool) {
        guard connectivity != connectivityAt || latency != latencyAt else { return (false, false) }
        let hasNewLatency = latency != latencyAt
        connectivityAt = connectivity
        latencyAt = latency
        return (true, hasNewLatency)
    }
}
