import Foundation

/// A single IPv4 address observed on one network interface, as read from
/// the OS interface list. This is the raw input to AddressResolver.resolve.
public struct NetworkInterfaceAddress: Equatable, Sendable {
    /// BSD interface name, e.g. "en0", "utun0", "lo0".
    public let interfaceName: String
    /// Dotted-quad IPv4 address, e.g. "192.168.1.4".
    public let ipv4Address: String
    /// 0-based position of this interface's first-seen address among all
    /// interfaces, in OS enumeration order. Each interface gets exactly
    /// one value, assigned the first time any of its addresses is seen.
    public let interfaceOrder: Int
    /// 0-based position of this address among addresses already seen on
    /// the same interface (0 = first IPv4 address on that interface).
    public let addressOrderWithinInterface: Int

    public init(
        interfaceName: String,
        ipv4Address: String,
        interfaceOrder: Int,
        addressOrderWithinInterface: Int
    ) {
        self.interfaceName = interfaceName
        self.ipv4Address = ipv4Address
        self.interfaceOrder = interfaceOrder
        self.addressOrderWithinInterface = addressOrderWithinInterface
    }
}
