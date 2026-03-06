import Darwin
import Foundation

public struct LiveVPNStatusProvider: VPNStatusProvider {
    public init() {}

    public func currentStatus() async -> VPNStatusSnapshot {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return VPNStatusSnapshot(isActive: false, interfaceNames: [])
        }

        defer {
            freeifaddrs(addressPointer)
        }

        let vpnPrefixes = ["utun", "ppp", "ipsec", "tun", "tap", "wg"]
        var interfaceNames = Set<String>()

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interfaceName = String(cString: pointer.pointee.ifa_name)

            if vpnPrefixes.contains(where: { interfaceName.hasPrefix($0) }) {
                interfaceNames.insert(interfaceName)
            }
        }

        let sortedInterfaces = interfaceNames.sorted()
        return VPNStatusSnapshot(isActive: !sortedInterfaces.isEmpty, interfaceNames: sortedInterfaces)
    }
}

