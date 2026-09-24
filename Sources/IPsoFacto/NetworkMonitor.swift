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
    /// Called on the main thread with the newly resolved address (or nil)
    /// and a human-readable interface description for the menu header.
    var onChange: ((ResolvedAddress?, String) -> Void)?

    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.sarath.ipsofacto.pathmonitor")
    private var dynamicStore: SCDynamicStore?
    private var dynamicStoreRunLoopSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?
    private var safetyNetTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?

    private let debounceInterval: TimeInterval = 0.3
    private let safetyNetInterval: TimeInterval = 60.0

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

        let globalIPv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4) as String
        let interfaceIPv4Pattern = SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv4) as String
        SCDynamicStoreSetNotificationKeys(store, [globalIPv4Key] as CFArray, [interfaceIPv4Pattern] as CFArray)

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
        let candidates = LiveInterfaceAddressSource.currentCandidates()
        let primaryInterfaceName = LiveInterfaceAddressSource.primaryInterfaceName()
        let resolved = AddressResolver.resolve(candidates: candidates, primaryInterfaceName: primaryInterfaceName)
        let description = Self.friendlyInterfaceDescription(bsdName: resolved?.interfaceName)
        onChange?(resolved, description)
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
