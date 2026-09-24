import Foundation

/// Pure address-selection logic. Takes the OS's raw interface
/// address list and the OS's notion of which interface currently carries the
/// default route, and returns the one address to display, or nil.
/// Contains no I/O: safe to unit test without a live network.
public enum AddressResolver {
    /// BSD interface name prefixes to always exclude: loopback and
    /// all virtual/tunnel interface families, so an active VPN's utun
    /// address never displaces the LAN address.
    public static let excludedInterfacePrefixes: [String] = [
        "lo", "utun", "ipsec", "ppp", "gif", "stf", "awdl", "llw", "bridge", "anpi"
    ]

    /// - Parameters:
    ///   - candidates: every IPv4 address currently seen on every
    ///     interface, unfiltered (may include loopback, utun, etc.).
    ///   - primaryInterfaceName: the BSD name of the interface the OS
    ///     currently uses for its default route (from
    ///     State:/Network/Global/IPv4's PrimaryInterface key), or nil
    ///     if unknown/no default route.
    /// - Returns: the address to display, or nil if none qualifies.
    public static func resolve(
        candidates: [NetworkInterfaceAddress],
        primaryInterfaceName: String?
    ) -> ResolvedAddress? {
        let eligible = candidates.filter { candidate in
            !excludedInterfacePrefixes.contains { candidate.interfaceName.hasPrefix($0) }
        }
        guard !eligible.isEmpty else { return nil }

        let chosenInterfaceName: String
        if let primaryInterfaceName,
           eligible.contains(where: { $0.interfaceName == primaryInterfaceName }) {
            chosenInterfaceName = primaryInterfaceName
        } else {
            // No usable primary-interface signal: fall back to the
            // lowest-interfaceOrder eligible interface.
            chosenInterfaceName = eligible
                .min(by: { $0.interfaceOrder < $1.interfaceOrder })!
                .interfaceName
        }

        // First address in system order on the chosen interface.
        guard let chosen = eligible
            .filter({ $0.interfaceName == chosenInterfaceName })
            .min(by: { $0.addressOrderWithinInterface < $1.addressOrderWithinInterface })
        else { return nil }

        return ResolvedAddress(
            interfaceName: chosen.interfaceName,
            ipv4Address: chosen.ipv4Address,
            category: isLinkLocal(chosen.ipv4Address) ? .linkLocal : .normal
        )
    }

    /// True for any address in 169.254.0.0/16.
    public static func isLinkLocal(_ ipv4Address: String) -> Bool {
        ipv4Address.hasPrefix("169.254.")
    }
}
