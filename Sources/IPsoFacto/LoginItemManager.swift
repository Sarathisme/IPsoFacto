import Foundation
import AppKit
import ServiceManagement

/// The live launch-at-login status shown in the menu, mapped from
/// SMAppService.Status.
enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case notFound
}

/// Wraps SMAppService.mainApp. The only thing persisted locally
/// is the one-time "did we already attempt first-run registration" flag;
/// the on/off state itself always comes live from the system.
@MainActor
final class LoginItemManager {
    private static let hasAttemptedFirstRunKey = "com.sarath.ipsofacto.hasAttemptedFirstRunLoginRegistration"
    private static let loginItemsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    private let service: SMAppService
    private let defaults: UserDefaults

    init(service: SMAppService = .mainApp, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    var currentStatus: LoginItemStatus {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .disabled
        @unknown default: return .disabled
        }
    }

    /// Registers once, on the first launch ever. Never re-registers
    /// after that, even if the user (or System Settings) later turns it
    /// off -- the flag is set regardless of whether register()
    /// succeeds, so a failed first attempt is not silently retried on
    /// every launch.
    func registerOnFirstLaunchIfNeeded() {
        guard !defaults.bool(forKey: Self.hasAttemptedFirstRunKey) else { return }
        defaults.set(true, forKey: Self.hasAttemptedFirstRunKey)
        try? service.register()
    }

    /// Toggles between enabled and disabled. Only called when the menu's
    /// Launch at Login item is in the enabled/disabled state, never in
    /// requiresApproval.
    func toggle() {
        switch currentStatus {
        case .enabled:
            try? service.unregister()
        case .disabled, .notFound, .requiresApproval:
            try? service.register()
        }
    }

    func openLoginItemsSettings() {
        NSWorkspace.shared.open(Self.loginItemsSettingsURL)
    }
}
