import AppKit
import Network
import SystemConfiguration
import IPsoFactoCore

/// Re-evaluates the address on every path change, every
/// same-path address change, and every wake, debounced so a
/// burst of events collapses into one final update, plus a 60 s
/// safety-net re-check. Never polls faster than that.
@MainActor
final class NetworkMonitor {
    private static let preferredFamilyKey = "com.sarath.ipsofacto.preferredAddressFamily"

    /// Called on the main thread with the newly resolved address (or nil),
    /// a human-readable interface description for the menu header, and the
    /// family that was just resolved (so the caller can render the right
    /// toggle state even when `resolved` is nil).
    var onChange: ((ResolvedAddress?, String, AddressFamily) -> Void)?

    /// Which family to resolve and display, persisted across launches.
    /// Defaults to IPv4 the first time the app ever runs.
    private(set) var preferredFamily: AddressFamily

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.sarath.ipsofacto.pathmonitor")
    private var dynamicStore: SCDynamicStore?
    private var dynamicStoreRunLoopSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?
    private var safetyNetTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private let defaults: UserDefaults

    private let debounceInterval: TimeInterval = 0.3
    private let safetyNetInterval: TimeInterval = 60.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Self.preferredFamilyKey), let family = AddressFamily(rawValue: stored) {
            preferredFamily = family
        } else {
            preferredFamily = .ipv4
        }
    }

    /// Switches which family is resolved and displayed, persists the
    /// choice, and immediately re-resolves so the menu bar updates without
    /// waiting for the next network event.
    func setPreferredFamily(_ family: AddressFamily) {
        guard family != preferredFamily else { return }
        preferredFamily = family
        defaults.set(family.rawValue, forKey: Self.preferredFamilyKey)
        performRecheck()
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleRecheck() }
        }
        pathMonitor.start(queue: pathMonitorQueue)

        startDynamicStoreObserving()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.scheduleRecheck() }

        safetyNetTimer = Timer.scheduledTimer(withTimeInterval: safetyNetInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleRecheck() }
        }

        performRecheck()
    }

    func stop() {
        pathMonitor.cancel()
        if let source = dynamicStoreRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        dynamicStore = nil
        dynamicStoreRunLoopSource = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        safetyNetTimer?.invalidate()
        debounceWorkItem?.cancel()
    }

    private func startDynamicStoreObserving() {
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<NetworkMonitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in monitor.scheduleRecheck() }
        }
        guard let store = SCDynamicStoreCreate(nil, "IPsoFacto" as CFString, callback, &context) else { return }
        dynamicStore = store

        // Watch both families' global and per-interface state, regardless
        // of which one is currently displayed: the user can toggle
        // families at any time, and the newly selected family needs live
        // updates too without re-subscribing.
        let globalIPv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4) as String
        let globalIPv6Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv6) as String
        let interfaceIPv4Pattern = SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv4) as String
        let interfaceIPv6Pattern = SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv6) as String
        SCDynamicStoreSetNotificationKeys(
            store,
            [globalIPv4Key, globalIPv6Key] as CFArray,
            [interfaceIPv4Pattern, interfaceIPv6Pattern] as CFArray
        )

        guard let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else { return }
        dynamicStoreRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func scheduleRecheck() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.performRecheck() }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func performRecheck() {
        let candidates = LiveInterfaceAddressSource.currentCandidates(family: preferredFamily)
        let primaryInterfaceName = LiveInterfaceAddressSource.primaryInterfaceName(family: preferredFamily)
        let resolved = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: primaryInterfaceName, family: preferredFamily)
        let description = Self.friendlyInterfaceDescription(bsdName: resolved?.interfaceName)
        onChange?(resolved, description, preferredFamily)
    }

    /// Maps a BSD interface name to the name System Settings uses for it
    /// (e.g. "en0" -> "Wi-Fi"), via SCNetworkInterface.
    static func friendlyInterfaceDescription(bsdName: String?) -> String {
        guard let bsdName else { return "Not connected" }
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return bsdName }
        guard let match = interfaces.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == bsdName }) else { return bsdName }
        let displayName = SCNetworkInterfaceGetLocalizedDisplayName(match) as String? ?? bsdName
        return "\(displayName) (\(bsdName))"
    }
}
