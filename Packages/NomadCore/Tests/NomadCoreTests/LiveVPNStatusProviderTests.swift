import Foundation
@testable import NomadCore
import Testing

struct LiveVPNStatusProviderTests {
    @Test
    func connectedServiceProducesActiveVPNStatus() async {
        let provider = LiveVPNStatusProvider(
            statusSource: FixedVPNServiceStatusSource(
                output: #"""
                Available network connection services in the current set (*=enabled):
                * (Connected)   2EE97DCA-F635-4B99-88E9-A5805B1D56C5 VPN (com.nordvpn.NordVPN) "NordVPN NordLynx"               [VPN:com.nordvpn.NordVPN]
                """#
            )
        )

        let status = await provider.currentStatus()

        #expect(status.isActive == true)
        #expect(status.serviceNames == ["NordVPN NordLynx"])
        #expect(status.interfaceNames.isEmpty)
    }

    @Test
    func disconnectedServiceStaysInactive() async {
        let provider = LiveVPNStatusProvider(
            statusSource: FixedVPNServiceStatusSource(
                output: #"""
                Available network connection services in the current set (*=enabled):
                * (Disconnected)   2EE97DCA-F635-4B99-88E9-A5805B1D56C5 VPN (com.nordvpn.NordVPN) "NordVPN NordLynx"               [VPN:com.nordvpn.NordVPN]
                """#
            )
        )

        let status = await provider.currentStatus()

        #expect(status.isActive == false)
        #expect(status.serviceNames.isEmpty)
    }

    @Test
    func onlyRowsWhoseStatusIsConnectedAreIncluded() async {
        let provider = LiveVPNStatusProvider(
            statusSource: FixedVPNServiceStatusSource(
                output: #"""
                Available network connection services in the current set (*=enabled):
                * (Disconnected)   8A VPN "VPN (Connected) name"               [VPN:com.example.vpn]
                * (Connecting)     63B VPN "Connecting service"                 [VPN:com.example.vpn]
                * (Connected)      2EE VPN "Active service"                     [VPN:com.example.vpn]
                """#
            )
        )

        let status = await provider.currentStatus()

        #expect(status.isActive == true)
        #expect(status.serviceNames == ["Active service"])
        #expect(status.interfaceNames.isEmpty)
    }

    @Test
    func emptyServiceListProducesInactiveStatus() async {
        let provider = LiveVPNStatusProvider(
            statusSource: FixedVPNServiceStatusSource(
                output: "Available network connection services in the current set (*=enabled):"
            )
        )

        let status = await provider.currentStatus()

        #expect(status.isActive == false)
        #expect(status.serviceNames.isEmpty)
    }

    @Test
    func processRunnerDrainsLargeStandardOutputAndErrorConcurrently() async throws {
        let lineCount = 12_000
        let script = #"""
        BEGIN {
            for (i = 0; i < 12000; i++) {
                printf("out-%05d\n", i)
                printf("err-%05d\n", i) > "/dev/stderr"
            }
        }
        """#
        let execution = try VPNCommandExecution(
            executableURL: URL(fileURLWithPath: "/usr/bin/awk"),
            arguments: [script],
            timeout: 5
        )

        let result = try await withProviderDeadline(seconds: 3) {
            try await execution.run()
        }
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        let stderr = String(decoding: result.stderr, as: UTF8.self)

        #expect(result.terminationStatus == 0)
        #expect(stdout.utf8.count > 64 * 1_024)
        #expect(stderr.utf8.count > 64 * 1_024)
        #expect(stdout.split(whereSeparator: \.isNewline).count == lineCount)
        #expect(stderr.split(whereSeparator: \.isNewline).count == lineCount)
        #expect(stdout.hasPrefix("out-00000\n"))
        #expect(stderr.hasPrefix("err-00000\n"))
    }

    @Test
    func processRunnerKillsChildWhenItsDeadlineExpires() async throws {
        let execution = try VPNCommandExecution(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["3"],
            timeout: 0.05
        )

        do {
            _ = try await withProviderDeadline(seconds: 1) {
                try await execution.run()
            }
            Issue.record("The process runner returned before its deadline.")
        } catch VPNServiceStatusSourceError.commandTimedOut {
            // Expected: the runner's own deadline terminates its child.
        } catch {
            Issue.record("Unexpected process runner error: \(error)")
        }

        #expect(await waitForVPNProcess(execution, running: false, timeout: .seconds(1)))
    }

    @Test
    func processRunnerKillsOwnedChildOnTaskCancellation() async throws {
        let execution = try VPNCommandExecution(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["3"],
            timeout: 10
        )
        let task = Task { try await execution.run() }
        let didStart = await waitForVPNProcess(execution, running: true, timeout: .seconds(1))
        #expect(didStart)

        task.cancel()
        do {
            _ = try await withProviderDeadline(seconds: 1) {
                try await task.value
            }
            Issue.record("The cancelled process runner returned a value.")
        } catch is CancellationError {
            // Expected: cancellation terminates the owned child and resumes the caller.
        } catch {
            Issue.record("Unexpected cancellation result: \(error)")
        }

        #expect(await waitForVPNProcess(execution, running: false, timeout: .seconds(1)))
    }
}

private struct FixedVPNServiceStatusSource: VPNServiceStatusSource {
    let output: String

    func connectionListOutput() async throws -> String {
        output
    }
}

private func waitForVPNProcess(
    _ execution: VPNCommandExecution,
    running expectedState: Bool,
    timeout: Duration
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while execution.isRunning != expectedState, clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return execution.isRunning == expectedState
}
