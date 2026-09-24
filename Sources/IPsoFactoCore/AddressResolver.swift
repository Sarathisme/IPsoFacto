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
    ///   - candidates: every address currently seen on every interface,
    ///     unfiltered (may include loopback, utun, other families, etc.).
    ///   - primaryInterfaceName: the BSD name of the interface the OS
    ///     currently uses for `family`'s default route (from
    ///     State:/Network/Global/IPv4 or IPv6's PrimaryInterface key), or
    ///     nil if unknown/no default route.
    ///   - family: which address family to resolve. Candidates of any
    ///     other family are ignored.
    /// - Returns: the address to display, or nil if none qualifies.
    public static func resolve(
        candidates: [NetworkInterfaceAddress],
        primaryInterfaceName: String?,
        family: AddressFamily
    ) -> ResolvedAddress? {
        let eligible = candidates.filter { candidate in
            candidate.family == family &&
            !excludedInterfacePrefixes.contains { candidate.interfaceName.hasPrefix($0) }
        }
        guard !eligible.isEmpty else { return nil }

        let chosenInterfaceName: String
        if let primaryInterfaceName,
           eligible.contains(where: { $0.interfaceName == primaryInterfaceName }) {
            chosenInterfaceName = primaryInterfaceName
        } else {
            // No usable primary-interface signal: fall back to the
            // lowest-interfaceOrder eligible interface (FR-2's "OS order").
            chosenInterfaceName = eligible
                .min(by: { $0.interfaceOrder < $1.interfaceOrder })!
                .interfaceName
        }

        // Among the chosen interface's addresses, prefer a normal (routable)
        // one over a link-local one, falling back to system order only to
        // break ties within the same category. This matters far more for
        // IPv6 than IPv4: a link-local address (fe80::/10) coexists with a
        // global address on essentially every interface and is frequently
        // enumerated first, so a plain "first in system order" pick would
        // often surface the less useful link-local address instead of the
        // actual routable one. IPv4 link-local is rare (DHCP failure only),
        // so this preference is a no-op there in practice.
        guard let chosen = eligible
            .filter({ $0.interfaceName == chosenInterfaceName })
            .min(by: { lhs, rhs in
                let lhsLinkLocal = isLinkLocal(lhs.address, family: family)
                let rhsLinkLocal = isLinkLocal(rhs.address, family: family)
                if lhsLinkLocal != rhsLinkLocal { return !lhsLinkLocal }
                return lhs.addressOrderWithinInterface < rhs.addressOrderWithinInterface
            })
        else { return nil }

        return ResolvedAddress(
            interfaceName: chosen.interfaceName,
            address: chosen.address,
            family: family,
            category: isLinkLocal(chosen.address, family: family) ? .linkLocal : .normal
        )
    }

    /// True for a link-local address in `address`'s family: any IPv4
    /// address in 169.254.0.0/16, or an IPv6 address in fe80::/10
    /// (matched by its first three hex digits, fe8/fe9/fea/feb, which
    /// together cover the whole /10 range regardless of the fourth digit).
    public static func isLinkLocal(_ address: String, family: AddressFamily) -> Bool {
        switch family {
        case .ipv4:
            return address.hasPrefix("169.254.")
        case .ipv6:
            let prefix = address.lowercased().prefix(3)
            return prefix == "fe8" || prefix == "fe9" || prefix == "fea" || prefix == "feb"
        }
    }
}
