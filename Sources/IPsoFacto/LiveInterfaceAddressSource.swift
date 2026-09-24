import Foundation
import SystemConfiguration
import IPsoFactoCore

/// Live OS interface/address reads. Not unit-tested: a thin,
/// I/O-only wrapper around getifaddrs(3) and SCDynamicStore. All decision
/// logic lives in AddressResolver, which is pure and tested (Phase 1).
enum LiveInterfaceAddressSource {

    /// Every address of `family` on every up interface, in getifaddrs(3)
    /// enumeration order, unfiltered by interface name. IPv6 link-local
    /// addresses (fe80::/10) get their interface appended as a zone ID
    /// (e.g. "fe80::1%en0"), matching how the OS itself represents them --
    /// a link-local address is only meaningful together with the
    /// interface it was observed on.
    static func currentCandidates(family: AddressFamily) -> [NetworkInterfaceAddress] {
        var result: [NetworkInterfaceAddress] = []
        var interfaceOrderByName: [String: Int] = [:]
        var addressCountByName: [String: Int] = [:]
        var nextInterfaceOrder = 0

        let wantedFamily: sa_family_t = family == .ipv4 ? sa_family_t(AF_INET) : sa_family_t(AF_INET6)

        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return [] }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard (Int32(current.pointee.ifa_flags) & IFF_UP) != 0 else { continue }
            guard let sockaddr = current.pointee.ifa_addr, sockaddr.pointee.sa_family == wantedFamily else { continue }

            let name = String(cString: current.pointee.ifa_name)
            guard let addressString = Self.addressString(from: sockaddr, family: family, interfaceName: name) else { continue }

            let interfaceOrder = interfaceOrderByName[name] ?? {
                let order = nextInterfaceOrder
                interfaceOrderByName[name] = order
                nextInterfaceOrder += 1
                return order
            }()
            let addressOrder = addressCountByName[name] ?? 0
            addressCountByName[name] = addressOrder + 1

            result.append(NetworkInterfaceAddress(
                interfaceName: name,
                address: addressString,
                family: family,
                interfaceOrder: interfaceOrder,
                addressOrderWithinInterface: addressOrder
            ))
        }
        return result
    }

    private static func addressString(from sockaddr: UnsafeMutablePointer<sockaddr>, family: AddressFamily, interfaceName: String) -> String? {
        switch family {
        case .ipv4:
            var addr = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        case .ipv6:
            var addr = sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            let address = String(cString: buffer)
            return AddressResolver.isLinkLocal(address, family: .ipv6) ? "\(address)%\(interfaceName)" : address
        }
    }

    /// The BSD name of the interface currently carrying `family`'s default
    /// route, from State:/Network/Global/<IPv4 or IPv6>'s PrimaryInterface
    /// key, or nil if there is no default route right now.
    static func primaryInterfaceName(family: AddressFamily) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "IPsoFacto" as CFString, nil, nil) else { return nil }
        let entity = family == .ipv4 ? kSCEntNetIPv4 : kSCEntNetIPv6
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, entity)
        guard let value = SCDynamicStoreCopyValue(store, key) as? [String: Any] else { return nil }
        return value[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }
}
