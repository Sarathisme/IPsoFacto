import Foundation

public enum ResolvedAddressCategory: Equatable, Sendable {
    /// Any IPv4 address outside 169.254.0.0/16.
    case normal
    /// A DHCP-failure self-assigned address, 169.254.0.0/16.
    case linkLocal
}

public struct ResolvedAddress: Equatable, Sendable {
    public let interfaceName: String
    public let ipv4Address: String
    public let category: ResolvedAddressCategory

    public init(interfaceName: String, ipv4Address: String, category: ResolvedAddressCategory) {
        self.interfaceName = interfaceName
        self.ipv4Address = ipv4Address
        self.category = category
    }
}
