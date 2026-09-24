import Testing
@testable import IPsoFactoCore

@Suite("AddressResolver")
struct AddressResolverTests {

    @Test("en0-only: single interface, single address, no primary-interface signal")
    func en0Only() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: nil)
        #expect(result == ResolvedAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", category: .normal))
    }

    @Test("Ethernet+Wi-Fi: primaryInterfaceName picks en5's address over en0's, regardless of enumeration order")
    func ethernetAndWiFiPriority() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en5", ipv4Address: "10.0.0.9", interfaceOrder: 1, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en5")
        #expect(result == ResolvedAddress(interfaceName: "en5", ipv4Address: "10.0.0.9", category: .normal))
    }

    @Test("utun present: a VPN utun0 address is excluded even when it is the primary interface; en0's LAN address wins")
    func utunExcludedEvenAsPrimary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", interfaceOrder: 0, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "utun0", ipv4Address: "10.8.0.2", interfaceOrder: 1, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "utun0")
        #expect(result == ResolvedAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", category: .normal))
    }

    @Test("loopback/IPv6-only: only excluded interfaces present yields no address")
    func loopbackOnlyYieldsNil() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "lo0", ipv4Address: "127.0.0.1", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: nil)
        #expect(result == nil)
    }

    @Test("link-local: a 169.254.x.x address on the primary interface is returned, categorised as linkLocal")
    func linkLocalCategorised() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "169.254.3.2", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0")
        #expect(result == ResolvedAddress(interfaceName: "en0", ipv4Address: "169.254.3.2", category: .linkLocal))
    }

    @Test("multiple IPv4 on one interface: the lowest addressOrderWithinInterface wins")
    func multipleAddressesOnOneInterface() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "192.168.1.50", interfaceOrder: 0, addressOrderWithinInterface: 1),
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0")
        #expect(result == ResolvedAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", category: .normal))
    }

    @Test("no interfaces: empty candidate list yields no address")
    func noInterfacesYieldsNil() {
        let result = AddressResolver.resolve(candidates: [], primaryInterfaceName: nil)
        #expect(result == nil)
    }

    @Test("private/CGNAT/hotspot ranges pass through unfiltered")
    func rangesPassThroughUnfiltered() {
        let tenDotCandidate = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "10.0.0.5", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: tenDotCandidate, primaryInterfaceName: "en0")?.ipv4Address == "10.0.0.5")

        let hotspotCandidate = [
            NetworkInterfaceAddress(interfaceName: "en7", ipv4Address: "172.20.10.5", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: hotspotCandidate, primaryInterfaceName: "en7")?.ipv4Address == "172.20.10.5")
    }

    @Test("stale primary-interface signal: primaryInterfaceName names an interface absent from candidates entirely (not merely excluded); falls back to lowest interfaceOrder (FR-2's \"OS order\" fallback)")
    func stalePrimaryInterfaceFallsBackToLowestOrder() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en5", ipv4Address: "10.0.0.9", interfaceOrder: 1, addressOrderWithinInterface: 0),
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        // "en9" does not appear in candidates at all (e.g. a disconnected
        // adapter still reported as primary by a stale route table entry).
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en9")
        #expect(result == ResolvedAddress(interfaceName: "en0", ipv4Address: "192.168.1.4", category: .normal))
    }

    @Test("link-local lower boundary: 169.254.0.0, the first address in the /16 range, is categorised linkLocal (FR-4/D-4)")
    func linkLocalLowerBoundary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "169.254.0.0", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0")
        #expect(result?.category == .linkLocal)
    }

    @Test("link-local upper boundary: 169.254.255.255, the last address in the /16 range, is categorised linkLocal (FR-4/D-4)")
    func linkLocalUpperBoundary() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "169.254.255.255", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0")
        #expect(result?.category == .linkLocal)
    }

    @Test("addresses just outside the 169.254.0.0/16 range are categorised normal, not linkLocal (FR-4/D-4 boundary)")
    func addressesJustOutsideLinkLocalRangeAreNormal() {
        let justBelow = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "169.253.255.255", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: justBelow, primaryInterfaceName: "en0")?.category == .normal)

        let justAbove = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "169.255.0.0", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        #expect(AddressResolver.resolve(candidates: justAbove, primaryInterfaceName: "en0")?.category == .normal)
    }

    @Test("a superficially similar address (169.25.4.1) is not mistaken for link-local by a loose prefix match")
    func similarLookingAddressIsNotLinkLocal() {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: "en0", ipv4Address: "169.25.4.1", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: "en0")
        #expect(result?.category == .normal)
    }

    @Test(
        "each FR-3 excluded interface family is excluded even as the sole candidate, yielding no address",
        arguments: ["lo0", "utun1", "ipsec0", "ppp0", "gif0", "stf0", "awdl0", "llw0", "bridge0", "anpi0"]
    )
    func excludedInterfaceFamiliesYieldNil(interfaceName: String) {
        let candidates = [
            NetworkInterfaceAddress(interfaceName: interfaceName, ipv4Address: "192.168.1.4", interfaceOrder: 0, addressOrderWithinInterface: 0)
        ]
        let result = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: interfaceName)
        #expect(result == nil)
    }
}
