import Foundation

/// Which IP address family to resolve and display. The user picks one via
/// the menu bar dropdown; the resolver only ever considers candidates of
/// the requested family.
public enum AddressFamily: String, CaseIterable, Equatable, Sendable {
    case ipv4
    case ipv6
}
