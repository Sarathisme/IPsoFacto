import Foundation

/// Which preset (or custom template) the user picked for the menu bar
/// button's text, persisted by PreferencesStore in the app target. This
/// enum only names the choice; MenuBarTextFormatter does the rendering.
public enum MenuBarTextFormat: String, CaseIterable, Equatable, Sendable {
    case ipOnly
    case ipAndInterface
    case ipAndWiFi
    case hostname
    case custom
}

/// Pure formatting of the menu bar button's text. No AppKit, no I/O --
/// unit tested like AddressResolver. Live inputs (the resolved address,
/// interface description, hostname) are all read by the app target and
/// passed in.
public enum MenuBarTextFormatter {
    /// Placeholders substituted into a `.custom` template: `{ip}` ->
    /// `resolved.address`, `{interface}` -> `resolved.interfaceName`,
    /// `{hostname}` -> the supplied hostname, `{wifi}` -> the supplied
    /// Wi-Fi description (e.g. "MyNetwork (-45 dBm)"). A placeholder with
    /// no available value (e.g. `{ip}` when `resolved` is nil, or `{wifi}`
    /// when Wi-Fi info isn't available/enabled) becomes an empty string.
    ///
    /// For the built-in presets (everything but `.custom`, which already
    /// has `{wifi}` for this), a non-empty `wifiDescription` is appended
    /// so the "Show Wi-Fi Network Name & Signal Strength" preference is
    /// visible in the menu bar text itself, not just the dropdown.
    /// `.ipAndWiFi` is the dedicated preset for exactly that pairing; with
    /// no Wi-Fi description available it falls back to the bare address.
    public static func render(
        format: MenuBarTextFormat,
        resolved: ResolvedAddress?,
        hostname: String,
        customTemplate: String,
        wifiDescription: String = ""
    ) -> String {
        switch format {
        case .ipOnly:
            guard let resolved else { return "" }
            return appendingWiFi(resolved.address, wifiDescription)
        case .ipAndInterface:
            guard let resolved else { return "" }
            return appendingWiFi("\(resolved.address) (\(resolved.interfaceName))", wifiDescription)
        case .ipAndWiFi:
            guard let resolved else { return "" }
            return appendingWiFi(resolved.address, wifiDescription)
        case .hostname:
            return appendingWiFi(hostname, wifiDescription)
        case .custom:
            return customTemplate
                .replacingOccurrences(of: "{ip}", with: resolved?.address ?? "")
                .replacingOccurrences(of: "{interface}", with: resolved?.interfaceName ?? "")
                .replacingOccurrences(of: "{hostname}", with: hostname)
                .replacingOccurrences(of: "{wifi}", with: wifiDescription)
        }
    }

    private static func appendingWiFi(_ base: String, _ wifiDescription: String) -> String {
        guard !wifiDescription.isEmpty else { return base }
        return "\(base) · \(wifiDescription)"
    }
}
