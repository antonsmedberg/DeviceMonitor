import Foundation
import Darwin

nonisolated struct LocalInterface: Sendable, Hashable {
    let name: String
    let address: IPv4Host
    let netmask: IPv4Host

    init(name: String, address: IPv4Host, netmask: IPv4Host) {
        self.name = name
        self.address = address
        self.netmask = netmask
    }

    var subnet: IPv4Subnet? {
        IPv4Subnet(address: address, netmask: netmask)
    }
}

/// Reads IPv4 interfaces with `getifaddrs`. The Wi‑Fi interface name comes from `NWPath`, never hard-coded.
nonisolated enum LocalInterfaceEnumerator {
    static func ipv4Interfaces() -> [LocalInterface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var result: [LocalInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next

            guard let addressPointer = current.pointee.ifa_addr,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET),
                  let netmaskPointer = current.pointee.ifa_netmask else { continue }

            let flags = Int32(truncatingIfNeeded: current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            let name = String(cString: current.pointee.ifa_name)
            let address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                IPv4Host(rawValue: UInt32(bigEndian: pointer.pointee.sin_addr.s_addr))
            }
            let netmask = netmaskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                IPv4Host(rawValue: UInt32(bigEndian: pointer.pointee.sin_addr.s_addr))
            }
            result.append(LocalInterface(name: name, address: address, netmask: netmask))
        }
        return result
    }

    /// The interface named by the path monitor, or the best private-address candidate.
    static func wifiInterface(named name: String?) -> LocalInterface? {
        let interfaces = ipv4Interfaces()
        if let name, let match = interfaces.first(where: { $0.name == name && !$0.address.isLinkLocal }) {
            return match
        }
        return interfaces.first { $0.name.hasPrefix("en") && $0.address.isPrivate && !$0.address.isLinkLocal }
            ?? interfaces.first { $0.address.isPrivate && !$0.address.isLinkLocal }
    }
}
