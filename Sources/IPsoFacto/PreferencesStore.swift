import Foundation
import IPsoFactoCore

/// Centralizes persistence for every preference introduced by the
/// Preferences window (Phases 2-4). Does NOT own the pre-existing
/// IPv4/IPv6 or Launch-at-Login preferences -- those remain owned by
/// NetworkMonitor and LoginItemManager respectively, unchanged
/// (Decision #6).
@MainActor
final class PreferencesStore {
    private static let menuBarTextFormatKey = "com.sarath.ipsofacto.menuBarTextFormat"
    private static let menuBarCustomTemplateKey = "com.sarath.ipsofacto.menuBarCustomTemplate"
    private static let showWiFiInfoKey = "com.sarath.ipsofacto.showWiFiInfo"
    private static let hotkeyKeyCodeKey = "com.sarath.ipsofacto.hotkeyKeyCode"
    private static let hotkeyModifiersKey = "com.sarath.ipsofacto.hotkeyModifiers"

    private let defaults: UserDefaults

    /// Fires whenever any stored preference changes via this store's own
    /// setters, so open observers (StatusItemController) can react
    /// immediately without polling.
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var menuBarTextFormat: MenuBarTextFormat {
        get {
            guard let raw = defaults.string(forKey: Self.menuBarTextFormatKey),
                  let format = MenuBarTextFormat(rawValue: raw) else { return .ipOnly }
            return format
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.menuBarTextFormatKey)
            onChange?()
        }
    }

    var menuBarCustomTemplate: String {
        get { defaults.string(forKey: Self.menuBarCustomTemplateKey) ?? "" }
        set {
            defaults.set(newValue, forKey: Self.menuBarCustomTemplateKey)
            onChange?()
        }
    }

    /// Off by default (Decision #10) -- reading Wi-Fi info requires a
    /// Location Services permission prompt the user shouldn't see
    /// unless they've opted in.
    var showWiFiInfo: Bool {
        get { defaults.bool(forKey: Self.showWiFiInfoKey) }
        set {
            defaults.set(newValue, forKey: Self.showWiFiInfoKey)
            onChange?()
        }
    }

    /// nil if no hotkey has been configured (Decision #12: no default).
    var hotkey: GlobalHotKey? {
        get {
            guard defaults.object(forKey: Self.hotkeyKeyCodeKey) != nil else { return nil }
            let keyCode = UInt32(defaults.integer(forKey: Self.hotkeyKeyCodeKey))
            let modifiers = UInt32(defaults.integer(forKey: Self.hotkeyModifiersKey))
            return GlobalHotKey(keyCode: keyCode, modifierFlags: modifiers)
        }
        set {
            if let newValue {
                defaults.set(Int(newValue.keyCode), forKey: Self.hotkeyKeyCodeKey)
                defaults.set(Int(newValue.modifierFlags), forKey: Self.hotkeyModifiersKey)
            } else {
                defaults.removeObject(forKey: Self.hotkeyKeyCodeKey)
                defaults.removeObject(forKey: Self.hotkeyModifiersKey)
            }
            onChange?()
        }
    }
}
