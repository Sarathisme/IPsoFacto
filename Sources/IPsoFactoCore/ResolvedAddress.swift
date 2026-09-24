import Foundation

public enum ResolvedAddressCategory: Equatable, Sendable {
    /// A routable address for its family (outside the link-local range).
    case normal
    /// A self-assigned, non-routable address: 169.254.0.0/16 for IPv4,
    /// fe80::/10 for IPv6.
    case linkLocal
}

public struct ResolvedAddress: Equatable, Sendable {
    public let interfaceName: String
    public let address: String
    public let family: AddressFamily
    public let category: ResolvedAddressCategory
    /// True for the one entry `AddressResolver.resolveAll()` marks as the
    /// same address `AddressResolver.resolve()` would have chosen alone.
    /// Always true for a `ResolvedAddress` returned by `resolve()`.
    public let isPrimary: Bool

    public init(interfaceName: String, address: String, family: AddressFamily, category: ResolvedAddressCategory, isPrimary: Bool = true) {
        self.interfaceName = interfaceName
        self.address = address
        self.family = family
        self.category = category
        self.isPrimary = isPrimary
    }
}
