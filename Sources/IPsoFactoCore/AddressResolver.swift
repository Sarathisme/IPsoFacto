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
        let eligible = eligibleCandidates(candidates, family: family)
        guard !eligible.isEmpty else { return nil }

        let chosenInterfaceName = choosePrimaryInterfaceName(eligible: eligible, primaryInterfaceName: primaryInterfaceName)
        guard let chosen = chooseAddress(interfaceName: chosenInterfaceName, among: eligible, family: family) else { return nil }

        return ResolvedAddress(
            interfaceName: chosen.interfaceName,
            address: chosen.address,
            family: family,
            category: isLinkLocal(chosen.address, family: family) ? .linkLocal : .normal
        )
    }

    /// Same eligibility rules as `resolve()`, but returns one
    /// `ResolvedAddress` per active, eligible interface (FR-6: "all
    /// interfaces" view) instead of just the single best one, ordered by
    /// `NetworkInterfaceAddress.interfaceOrder`. Exactly one entry (the
    /// same interface `resolve()` would have chosen) has `isPrimary ==
    /// true`; all others have `isPrimary == false`. Returns `[]` if no
    /// interface is eligible.
    public static func resolveAll(
        candidates: [NetworkInterfaceAddress],
        primaryInterfaceName: String?,
        family: AddressFamily
    ) -> [ResolvedAddress] {
        let eligible = eligibleCandidates(candidates, family: family)
        guard !eligible.isEmpty else { return [] }

        let chosenInterfaceName = choosePrimaryInterfaceName(eligible: eligible, primaryInterfaceName: primaryInterfaceName)

        var interfaceOrderByName: [String: Int] = [:]
        for candidate in eligible where interfaceOrderByName[candidate.interfaceName] == nil {
            interfaceOrderByName[candidate.interfaceName] = candidate.interfaceOrder
        }
        let orderedInterfaceNames = interfaceOrderByName.keys.sorted { interfaceOrderByName[$0]! < interfaceOrderByName[$1]! }

        return orderedInterfaceNames.compactMap { name -> ResolvedAddress? in
            guard let chosen = chooseAddress(interfaceName: name, among: eligible, family: family) else { return nil }
            return ResolvedAddress(
                interfaceName: chosen.interfaceName,
                address: chosen.address,
                family: family,
                category: isLinkLocal(chosen.address, family: family) ? .linkLocal : .normal,
                isPrimary: name == chosenInterfaceName
            )
        }
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

    private static func eligibleCandidates(_ candidates: [NetworkInterfaceAddress], family: AddressFamily) -> [NetworkInterfaceAddress] {
        candidates.filter { candidate in
            candidate.family == family &&
            !excludedInterfacePrefixes.contains { candidate.interfaceName.hasPrefix($0) }
        }
    }

    /// FR-2's "OS order" fallback: the primary-route interface if it's
    /// eligible, else the lowest-`interfaceOrder` eligible interface.
    /// `eligible` must be non-empty.
    private static func choosePrimaryInterfaceName(eligible: [NetworkInterfaceAddress], primaryInterfaceName: String?) -> String {
        if let primaryInterfaceName, eligible.contains(where: { $0.interfaceName == primaryInterfaceName }) {
            return primaryInterfaceName
        }
        return eligible.min(by: { $0.interfaceOrder < $1.interfaceOrder })!.interfaceName
    }

    /// Among `interfaceName`'s addresses within `eligible`, prefer a
    /// normal (routable) one over a link-local one, falling back to
    /// system order only to break ties within the same category. See
    /// `resolve()`'s original doc comment for why this matters more for
    /// IPv6 than IPv4.
    private static func chooseAddress(interfaceName: String, among eligible: [NetworkInterfaceAddress], family: AddressFamily) -> NetworkInterfaceAddress? {
        eligible
            .filter { $0.interfaceName == interfaceName }
            .min(by: { lhs, rhs in
                let lhsLinkLocal = isLinkLocal(lhs.address, family: family)
                let rhsLinkLocal = isLinkLocal(rhs.address, family: family)
                if lhsLinkLocal != rhsLinkLocal { return !lhsLinkLocal }
                return lhs.addressOrderWithinInterface < rhs.addressOrderWithinInterface
            })
    }
}
