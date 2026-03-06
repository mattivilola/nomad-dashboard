import Foundation
import Network

public protocol LatencyConnecting: Sendable {
    func measureLatency(to endpoint: LatencyEndpoint, timeout: TimeInterval) async -> Double?
}

public struct TCPConnectionLatencyConnector: LatencyConnecting {
    public init() {}

    public func measureLatency(to endpoint: LatencyEndpoint, timeout: TimeInterval) async -> Double? {
        let state = ConnectionState()

        return await withCheckedContinuation { continuation in
            guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
                continuation.resume(returning: nil)
                return
            }

            let connection = NWConnection(host: .init(endpoint.host), port: port, using: .tcp)
            let start = DispatchTime.now()
            let queue = DispatchQueue(label: "NomadDashboard.LatencyProbe")

            state.onFinish = { value in
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { currentState in
                switch currentState {
                case .ready:
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    state.finish(with: elapsed)
                    connection.cancel()
                case .failed, .cancelled:
                    state.finish(with: nil)
                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                state.finish(with: nil)
                connection.cancel()
            }
        }
    }
}

public actor LiveLatencyProbe: LatencyProbe {
    private let endpoints: [LatencyEndpoint]
    private let connector: any LatencyConnecting
    private var previousLatencyByHost: [String: Double] = [:]

    public init(
        endpoints: [LatencyEndpoint],
        connector: any LatencyConnecting = TCPConnectionLatencyConnector()
    ) {
        self.endpoints = endpoints.isEmpty ? [LatencyEndpoint(host: "1.1.1.1", port: 443)] : endpoints
        self.connector = connector
    }

    public func currentSample() async -> LatencySample? {
        for endpoint in endpoints {
            guard let latency = await connector.measureLatency(to: endpoint, timeout: 2.5) else {
                continue
            }

            let jitter = previousLatencyByHost[endpoint.host].map { abs($0 - latency) }
            previousLatencyByHost[endpoint.host] = latency

            return LatencySample(
                host: endpoint.host,
                milliseconds: latency,
                jitterMilliseconds: jitter,
                collectedAt: Date()
            )
        }

        return nil
    }
}

private final class ConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasFinished = false

    var onFinish: ((Double?) -> Void)?

    func finish(with value: Double?) {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !hasFinished else {
            return
        }

        hasFinished = true
        onFinish?(value)
    }
}
