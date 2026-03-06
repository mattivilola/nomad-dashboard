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
}

private struct FixedVPNServiceStatusSource: VPNServiceStatusSource {
    let output: String

    func connectionListOutput() throws -> String {
        output
    }
}
