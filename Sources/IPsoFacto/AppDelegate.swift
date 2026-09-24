import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let loginItemManager = LoginItemManager()
    private let preferencesStore = PreferencesStore()
    private let wifiInfoProvider = WiFiInfoProvider()
    private let hotKeyManager = GlobalHotKeyManager()
    private var statusItemController: StatusItemController?
    private var networkMonitor: NetworkMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Runtime stand-in for LSUIElement during `swift run` (no bundle,
        // no Info.plist yet). Harmless once the real Info.plist sets
        // LSUIElement=true in the Phase 3 assembled .app.
        NSApp.setActivationPolicy(.accessory)

        loginItemManager.registerOnFirstLaunchIfNeeded()

        let controller = StatusItemController(loginItemManager: loginItemManager, preferencesStore: preferencesStore, wifiInfoProvider: wifiInfoProvider, hotKeyManager: hotKeyManager)
        statusItemController = controller

        hotKeyManager.onHotKeyPressed = { [weak controller] in controller?.copyCurrentAddressToClipboard() }
        if let hotkey = preferencesStore.hotkey {
            hotKeyManager.register(hotkey)
        }

        let monitor = NetworkMonitor()
        monitor.onChange = { [weak controller] snapshot in
            controller?.update(snapshot: snapshot)
        }
        controller.onFamilyToggle = { [weak monitor] family in
            monitor?.setPreferredFamily(family)
        }
        networkMonitor = monitor
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        networkMonitor?.stop()
    }
}
