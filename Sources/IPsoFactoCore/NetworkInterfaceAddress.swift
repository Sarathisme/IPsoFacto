import Foundation

/// A single address observed on one network interface, as read from the
/// OS interface list. This is the raw input to AddressResolver.resolve.
public struct NetworkInterfaceAddress: Equatable, Sendable {
    /// BSD interface name, e.g. "en0", "utun0", "lo0".
    public let interfaceName: String
    /// The address in its family's string form, e.g. "192.168.1.4" or
    /// "fe80::1%en0".
    public let address: String
    /// Which family `address` belongs to.
    public let family: AddressFamily
    /// 0-based position of this interface's first-seen address (within its
    /// family) among all interfaces, in OS enumeration order. Each
    /// interface gets exactly one value per family, assigned the first
    /// time any of its addresses of that family is seen.
    public let interfaceOrder: Int
    /// 0-based position of this address among addresses of the same family
    /// already seen on the same interface (0 = first seen on that
    /// interface).
    public let addressOrderWithinInterface: Int

    public init(
        interfaceName: String,
        address: String,
        family: AddressFamily,
        interfaceOrder: Int,
        addressOrderWithinInterface: Int
    ) {
        self.interfaceName = interfaceName
        self.address = address
        self.family = family
        self.interfaceOrder = interfaceOrder
        self.addressOrderWithinInterface = addressOrderWithinInterface
    }
}
