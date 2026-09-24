import Testing
@testable import IPsoFactoCore

@Suite("AddressResolver")
struct AddressResolverTests {

    @Test("en0-only: single interface, single address, no primary-interface signal")
    func en0Only() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: nil, family: .ipv4)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, category: .normal))
    }

    @Test("Ethernet+Wi-Fi: primaryInterfaceName picks en5's address over en0's, regardless of enumeration order")
    func ethernetAndWiFiPriority() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en5", address: "10.0.0.9", family: .ipv4, interfaceOrder: 1, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en5", family: .ipv4)
        #expect(result == ResolvedAddress(interfaceName: "en5", address: "10.0.0.9", family: .ipv4, category: .normal))
    }

    @Test("utun present: a VPN utun0 address is excluded even when it is the primary interface; en0's LAN address wins")
    func utunExcludedEvenAsPrimary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "utun0", address: "10.8.0.2", family: .ipv4, interfaceOrder: 1, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "utun0", family: .ipv4)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, category: .normal))
    }

    @Test("loopback-only: only excluded interfaces present yields no address")
    func loopbackOnlyYieldsNil() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "lo0", address: "127.0.0.1", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: nil, family: .ipv4)
        #expect(result == nil)
    }

    @Test("link-local: a 169.254.x.x address on the primary interface is returned, categorised as linkLocal")
    func linkLocalCategorised() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "169.254.3.2", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv4)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "169.254.3.2", family: .ipv4, category: .linkLocal))
    }

    @Test("multiple IPv4 on one interface: the lowest addressOrderWithinInterface wins")
    func multipleAddressesOnOneInterface() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.50", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 1),
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv4)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, category: .normal))
    }

    @Test("no interfaces: empty candidate list yields no address")
    func noInterfacesYieldsNil() {
        let result = AddressResolver.resolve(candidates: [], primaryInterfaceName: nil, family: .ipv4)
        #expect(result == nil)
    }

    @Test("private/CGNAT/hotspot ranges pass through unfiltered")
    func rangesPassThroughUnfiltered() {
        let tenDotCandidate = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "10.0.0.5", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: tenDotCandidate, primaryInterfaceName: "en0", family: .ipv4)?.address == "10.0.0.5")

        let hotspotCandidate = [
            NetworkInterfaceAddress(interfaceName: "en7", address: "172.20.10.5", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: hotspotCandidate, primaryInterfaceName: "en7", family: .ipv4)?.address == "172.20.10.5")
    }

    @Test("stale primary-interface signal: primaryInterfaceName names an interface absent from candidates entirely (not merely excluded); falls back to lowest interfaceOrder (FR-2's \"OS order\" fallback)")
    func stalePrimaryInterfaceFallsBackToLowestOrder() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en5", address: "10.0.0.9", family: .ipv4, interfaceOrder: 1, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        // "en9" does not appear in candidates at all (e.g. a disconnected
        // adapter still reported as primary by a stale route table entry).
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en9", family: .ipv4)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, category: .normal))
    }

    @Test("link-local lower boundary: 169.254.0.0, the first address in the /16 range, is categorised linkLocal (FR-4/D-4)")
    func linkLocalLowerBoundary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "169.254.0.0", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv4)
        #expect(result?.category == .linkLocal)
    }

    @Test("link-local upper boundary: 169.254.255.255, the last address in the /16 range, is categorised linkLocal (FR-4/D-4)")
    func linkLocalUpperBoundary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "169.254.255.255", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv4)
        #expect(result?.category == .linkLocal)
    }

    @Test("addresses just outside the 169.254.0.0/16 range are categorised normal, not linkLocal (FR-4/D-4 boundary)")
    func addressesJustOutsideLinkLocalRangeAreNormal() {
        let justBelow = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "169.253.255.255", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: justBelow, primaryInterfaceName: "en0", family: .ipv4)?.category == .normal)

        let justAbove = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "169.255.0.0", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: justAbove, primaryInterfaceName: "en0", family: .ipv4)?.category == .normal)
    }

    @Test("a superficially similar address (169.25.4.1) is not mistaken for link-local by a loose prefix match")
    func similarLookingAddressIsNotLinkLocal() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "169.25.4.1", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv4)
        #expect(result?.category == .normal)
    }

    @Test(
        "each FR-3 excluded interface family is excluded even as the sole candidate, yielding no address",
        arguments: ["lo0", "utun1", "ipsec0", "ppp0", "gif0", "stf0", "awdl0", "llw0", "bridge0", "anpi0"]
    )
    func excludedInterfaceFamiliesYieldNil(interfaceName: String) {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: interfaceName, address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: interfaceName, family: .ipv4)
        #expect(result == nil)
    }

    // MARK: - IPv6 / family selection

    @Test("family selection: a candidate list with both IPv4 and IPv6 addresses on the same interface only returns the requested family")
    func familySelectionFiltersOutOtherFamily() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let ipv4Result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv4)
        #expect(ipv4Result == ResolvedAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, category: .normal))

        let ipv6Result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv6)
        #expect(ipv6Result == ResolvedAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, category: .normal))
    }

    @Test("IPv6 requested but only IPv4 candidates exist: yields no address rather than falling back to the other family")
    func ipv6RequestedWithOnlyIPv4CandidatesYieldsNil() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv6)
        #expect(result == nil)
    }

    @Test("IPv6 utun is excluded even as primary interface, same as IPv4")
    func ipv6UtunExcludedEvenAsPrimary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "utun0", address: "fd00::1", family: .ipv6, interfaceOrder: 1, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "utun0", family: .ipv6)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, category: .normal))
    }

    @Test(
        "IPv6 link-local (fe80::/10) is categorised linkLocal across the range's first-hex-digit-group boundaries",
        arguments: ["fe80::1%en0", "fe94::1%en0", "fea1::1%en0", "febf::ffff%en0"]
    )
    func ipv6LinkLocalRangeCategorised(address: String) {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: address, family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv6)
        #expect(result?.category == .linkLocal)
    }

    @Test("an IPv6 global address just outside fe80::/10 (fec0::, historically site-local) is categorised normal, not linkLocal")
    func ipv6AddressJustOutsideLinkLocalRangeIsNormal() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "fec0::1", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv6)
        #expect(result?.category == .normal)
    }

    @Test("IPv6 uppercase-hex link-local address is still recognised (case-insensitive match)")
    func ipv6LinkLocalUppercaseIsCategorised() {
        #expect(AddressResolver.isLinkLocal("FE80::1", family: .ipv6))
    }

    @Test("an interface's global IPv6 address is preferred over its link-local one, even when link-local is enumerated first (the common real-world order)")
    func ipv6GlobalAddressPreferredOverLinkLocalRegardlessOfOrder() {
        let linkLocalFirst = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "fe80::1%en0", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 1)
        ]
        #expect(AddressResolver.resolve(candidates: linkLocalFirst, primaryInterfaceName: "en0", family: .ipv6) == ResolvedAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, category: .normal))

        // Order reversed: still picks the global address, not just "first".
        let globalFirst = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en0", address: "fe80::1%en0", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 1)
        ]
        #expect(AddressResolver.resolve(candidates: globalFirst, primaryInterfaceName: "en0", family: .ipv6) == ResolvedAddress(interfaceName: "en0", address: "2601:441:4200:1234::1", family: .ipv6, category: .normal))
    }

    @Test("when an interface has only a link-local IPv6 address, it's returned as a fallback rather than yielding nil")
    func ipv6LinkLocalOnlyIsReturnedAsFallback() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", address: "fe80::1%en0", family: .ipv6, interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0", family: .ipv6)
        #expect(result == ResolvedAddress(interfaceName: "en0", address: "fe80::1%en0", family: .ipv6, category: .linkLocal))
    }
}
