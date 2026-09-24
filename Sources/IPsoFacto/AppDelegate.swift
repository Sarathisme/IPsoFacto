import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let loginItemManager = LoginItemManager()
    private var statusItemController: StatusItemController?
    private var networkMonitor: NetworkMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Runtime stand-in for LSUIElement during `swift run` (no bundle,
        // no Info.plist yet). Harmless once the real Info.plist sets
        // LSUIElement=true in the Phase 3 assembled .app.
        NSApp.setActivationPolicy(.accessory)

        loginItemManager.registerOnFirstLaunchIfNeeded()

        let controller = StatusItemController(loginItemManager: loginItemManager)
        statusItemController = controller

        let monitor = NetworkMonitor()
        monitor.onChange = { [weak controller] resolved, description, family in
            controller?.update(resolved: resolved, interfaceDescription: description, family: family)
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
