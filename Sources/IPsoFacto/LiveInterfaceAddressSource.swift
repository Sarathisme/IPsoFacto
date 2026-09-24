import Foundation
import SystemConfiguration
import IPsoFactoCore

/// Live OS interface/address reads. Not unit-tested: a thin,
/// I/O-only wrapper around getifaddrs(3) and SCDynamicStore. All decision
/// logic lives in AddressResolver, which is pure and tested (Phase 1).
enum LiveInterfaceAddressSource {

    /// Every IPv4 address on every up interface, in getifaddrs(3)
    /// enumeration order, unfiltered by interface name.
    static func currentCandidates() -> [NetworkInterfaceAddress] {
        var result: [NetworkInterfaceAddress] = []
        var interfaceOrderByName: [String: Int] = [:]
        var addressCountByName: [String: Int] = [:]
        var nextInterfaceOrder = 0

        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return [] }
        defer { freeifaddrs(ifaddrPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard (Int32(current.pointee.ifa_flags) & IFF_UP) != 0 else { continue }
            guard let sockaddr = current.pointee.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            var addr = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ipv4Address = String(cString: buffer)

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
                ipv4Address: ipv4Address,
                interfaceOrder: interfaceOrder,
                addressOrderWithinInterface: addressOrder
            ))
        }
        return result
    }

    /// The BSD name of the interface currently carrying the default
    /// route, from State:/Network/Global/IPv4's PrimaryInterface key,
    /// or nil if there is no default route right now.
    static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "IPsoFacto" as CFString, nil, nil) else { return nil }
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)
        guard let value = SCDynamicStoreCopyValue(store, key) as? [String: Any] else { return nil }
        return value[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }
}
