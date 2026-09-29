import AppKit
import CoreWLAN
import Foundation
import IPsoFactoCore

/// A button-backed menu row used only for the in-progress speed test. AppKit
/// dismisses a menu after a normal menu-item action; a view-backed button lets
/// the test update its status in the open menu instead.
private final class PersistentMenuActionRowView: NSView {
    private let button: NSButton
    private var isMouseInside = false
    private var trackingArea: NSTrackingArea?

    init(button: NSButton, frame: NSRect) {
        self.button = button
        super.init(frame: frame)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let isHighlighted = isMouseInside && button.isEnabled
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        button.contentTintColor = isHighlighted ? .white : .labelColor
        super.draw(dirtyRect)
    }
}

/// Owns the NSStatusItem and its dropdown menu. Pure AppKit,
/// no custom drawing, so light/dark, tinted menu bars and Reduce
/// Transparency are all handled by the system for free.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let loginItemManager: LoginItemManager
    private let preferencesStore: PreferencesStore
    private let wifiInfoProvider: WiFiInfoProvider
    private let hotKeyManager: GlobalHotKeyManager
    private lazy var preferencesWindowController = PreferencesWindowController(preferencesStore: preferencesStore, wifiInfoProvider: wifiInfoProvider, hotKeyManager: hotKeyManager)

    private var resolvedAddress: ResolvedAddress?
    private var interfaceDescription: String = "Not connected"
    private var displayedFamily: AddressFamily = .ipv4
    private var allInterfaces: [ResolvedAddress] = []
    private var speedTestState: SpeedTestState = .idle
    private var developmentPorts: [DevelopmentPort] = []
    private lazy var developmentPortsWindowController = DevelopmentPortsWindowController(
        portsProvider: { [weak self] in
            let ports = DevelopmentPortDiscovery.scan()
            self?.developmentPorts = ports
            return ports
        }
    )

    private enum SpeedTestState {
        case idle
        case running(SpeedTestPhase)
        case completed(SpeedTestResult)
        case failed
    }

    /// Set by AppDelegate; called when the user picks IPv4 or IPv6 from
    /// the dropdown. The controller doesn't own the family preference
    /// itself -- NetworkMonitor does, since it's the one that persists and
    /// re-resolves it.
    var onFamilyToggle: ((AddressFamily) -> Void)?

    init(loginItemManager: LoginItemManager, preferencesStore: PreferencesStore, wifiInfoProvider: WiFiInfoProvider, hotKeyManager: GlobalHotKeyManager) {
        self.loginItemManager = loginItemManager
        self.preferencesStore = preferencesStore
        self.wifiInfoProvider = wifiInfoProvider
        self.hotKeyManager = hotKeyManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        preferencesStore.onChange = { [weak self] in self?.render() }
        wifiInfoProvider.onAuthorizationChange = { [weak self] in self?.render() }
        render()
    }

    /// Called by NetworkMonitor on every resolved change (main thread).
    func update(snapshot: NetworkSnapshot) {
        self.resolvedAddress = snapshot.resolved
        self.interfaceDescription = snapshot.interfaceDescription
        self.displayedFamily = snapshot.family
        self.allInterfaces = snapshot.allInterfaces
        render()
    }

    /// Recompute the Launch at Login row's live status every time
    /// the menu opens, not just on network change.
    func menuWillOpen(_ menu: NSMenu) {
        developmentPorts = DevelopmentPortDiscovery.scan()
        rebuildMenu()
    }

    /// Repaints the button (four states) and rebuilds the menu. The
    /// button's text is always shown in full, never truncated -- the user
    /// picked the format (and whether Wi-Fi info is included), so the
    /// status item grows to fit it.
    private func render() {
        guard let button = statusItem.button else { return }
        let familyLabel = displayedFamily == .ipv4 ? "IPv4" : "IPv6"
        guard let address = resolvedAddress else {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "No local \(familyLabel) address")
            button.image?.isTemplate = true
            button.toolTip = "No local \(familyLabel) address"
            rebuildMenu()
            return
        }
        button.image = nil
        button.toolTip = address.address

        var format = preferencesStore.menuBarTextFormat
        if format == .custom && preferencesStore.menuBarCustomTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
            format = .ipOnly
        }
        let displayText = MenuBarTextFormatter.render(
            format: format,
            resolved: address,
            hostname: Self.currentHostname(),
            customTemplate: preferencesStore.menuBarCustomTemplate,
            wifiDescription: currentWiFiDescription()
        )
        let usesRawAddressText = format == .ipOnly || format == .ipAndInterface || format == .ipAndWiFi
        if address.category == .linkLocal && usesRawAddressText {
            button.attributedTitle = NSAttributedString(
                string: displayText,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: displayText)
        }
        rebuildMenu()
    }

    private static func currentHostname() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// "<SSID> (<RSSI> dBm)" when the user has opted into Wi-Fi info
    /// (either the checkbox or the "IP Address + Wi-Fi" menu bar format),
    /// the currently displayed address is on a Wi-Fi interface, and
    /// CoreWLAN has data -- empty string otherwise (used both for the
    /// dropdown's Wi-Fi row and the {wifi} menu bar text placeholder).
    private func currentWiFiDescription() -> String {
        guard preferencesStore.showWiFiInfo || preferencesStore.menuBarTextFormat == .ipAndWiFi,
              let resolvedAddress,
              wifiInfoProvider.isWiFiInterface(resolvedAddress.interfaceName),
              let info = wifiInfoProvider.currentInfo() else { return "" }
        return "\(info.ssid) (\(info.rssi) dBm)"
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let headerItem = NSMenuItem(title: interfaceDescription, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let wifiDescription = currentWiFiDescription()
        if !wifiDescription.isEmpty {
            let wifiItem = NSMenuItem(title: "Wi-Fi: \(wifiDescription)", action: nil, keyEquivalent: "")
            wifiItem.isEnabled = false
            menu.addItem(wifiItem)
        }

        let ipv4Item = NSMenuItem(title: "Show IPv4 Address", action: #selector(selectIPv4), keyEquivalent: "")
        ipv4Item.target = self
        ipv4Item.state = displayedFamily == .ipv4 ? .on : .off
        menu.addItem(ipv4Item)

        let ipv6Item = NSMenuItem(title: "Show IPv6 Address", action: #selector(selectIPv6), keyEquivalent: "")
        ipv6Item.target = self
        ipv6Item.state = displayedFamily == .ipv6 ? .on : .off
        menu.addItem(ipv6Item)

        menu.addItem(.separator())

        if allInterfaces.count > 1 {
            let allInterfacesItem = NSMenuItem(title: "All Interfaces", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for entry in allInterfaces {
                let label = NetworkMonitor.friendlyInterfaceDescription(bsdName: entry.interfaceName)
                let row = NSMenuItem(title: "\(label): \(entry.address)", action: nil, keyEquivalent: "")
                row.isEnabled = false
                row.state = entry.isPrimary ? .on : .off
                submenu.addItem(row)
            }
            allInterfacesItem.submenu = submenu
            menu.addItem(allInterfacesItem)
            menu.addItem(.separator())
        }

        if let resolvedAddress, let qrItem = makeQRCodeMenuItem(address: resolvedAddress.address) {
            menu.addItem(qrItem)
        }

        menu.addItem(makeActionMenuItem(title: "Copy IP Address", action: #selector(copyIPAddress), keyEquivalent: "c", enabled: resolvedAddress != nil))

        menu.addItem(makeSpeedTestMenuItem())

        menu.addItem(makeDevelopmentPortsMenuItem())

        menu.addItem(.separator())

        switch loginItemManager.currentStatus {
        case .enabled:
            let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            item.target = self
            item.state = .on
            menu.addItem(item)
        case .disabled, .notFound:
            let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            item.target = self
            item.state = .off
            menu.addItem(item)
        case .requiresApproval:
            let item = NSMenuItem(title: "Launch at Login (needs approval in System Settings)", action: #selector(openLoginItemsSettings), keyEquivalent: "")
            item.target = self
            item.state = .off
            menu.addItem(item)
        }

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        // Route these through our own actions so AppKit does not add system
        // icons that indent only these titles relative to the other rows.
        let aboutItem = NSMenuItem(title: "About IPso Facto", action: #selector(showAboutPanel), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit IPso Facto", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Custom rows keep their own widths. Give the QR block and speed
        // test the same width so the QR stays centered in the wider menu.
        let customViews = menu.items.compactMap(\.view)
        if let width = customViews.map({ $0.frame.width }).max() {
            for view in customViews {
                view.setFrameSize(NSSize(width: width, height: view.frame.height))
            }
        }
    }

    private func makeQRCodeMenuItem(address: String) -> NSMenuItem? {
        let imageSize: CGFloat = 160
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 12
        let labelHeight: CGFloat = 16

        guard let qrImage = QRCodeImageGenerator.image(forPayload: address, sizePoints: imageSize) else { return nil }

        // The full address is shown under the QR code; a long IPv6 address
        // (up to ~45 chars with a %zone-id suffix) widens the row to fit it
        // rather than being cut short.
        let label = NSTextField(labelWithString: address)
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let containerWidth = max(imageSize, ceil(label.fittingSize.width)) + horizontalPadding * 2
        let containerHeight = imageSize + verticalPadding * 2 + labelHeight

        // Whatever ends up resizing this row wider for a long IPv6 address
        // (AppKit's exact custom-view menu-row sizing is undocumented and
        // wasn't reliably reproducible outside a live menu), .minXMargin +
        // .maxXMargin is the standard, general-purpose AppKit answer:
        // if the superview's frame is resized for any reason, flexible
        // margins on both sides keep a subview centered rather than
        // pinned to its original left-anchored offset.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        container.autoresizesSubviews = true

        let imageView = NSImageView(frame: NSRect(x: (containerWidth - imageSize) / 2, y: verticalPadding + labelHeight, width: imageSize, height: imageSize))
        imageView.image = qrImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(imageView)

        label.frame = NSRect(x: 0, y: verticalPadding - 2, width: containerWidth, height: labelHeight)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(label)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func makeDevelopmentPortsMenuItem() -> NSMenuItem {
        let title = developmentPorts.isEmpty ? "Ports & Processes" : "Ports & Processes (\(developmentPorts.count))"
        // A standard menu item lets AppKit keep this row aligned with the
        // rest of the menu; no custom insets or view-backed menu row needed.
        let item = NSMenuItem(title: title, action: #selector(openDevelopmentPorts), keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openDevelopmentPorts() {
        developmentPortsWindowController.showModal()
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    @objc private func copyIPAddress() {
        copyCurrentAddressToClipboard()
    }

    /// Also invoked by the global hotkey (Phase 4), outside the menu.
    /// Same silent-copy behavior as the menu item (Decision #13).
    func copyCurrentAddressToClipboard() {
        guard let address = resolvedAddress else { return }
        copyToPasteboard(address.address)
    }

    @objc private func selectIPv4() {
        onFamilyToggle?(.ipv4)
    }

    @objc private func selectIPv6() {
        onFamilyToggle?(.ipv6)
    }

    @objc private func toggleLaunchAtLogin() {
        loginItemManager.toggle()
        rebuildMenu()
    }

    @objc private func openLoginItemsSettings() {
        loginItemManager.openLoginItemsSettings()
    }

    @objc private func openPreferences() {
        preferencesWindowController.show()
    }

    @objc private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeActionMenuItem(title: String, action: Selector, keyEquivalent: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func makeSpeedTestMenuItem() -> NSMenuItem {
        let isRunning: Bool = { if case .running = speedTestState { return true } else { return false } }()
        return makePersistentMenuActionItem(title: speedTestMenuTitle(), action: #selector(runSpeedTest), enabled: !isRunning)
    }

    private func makePersistentMenuActionItem(title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let height: CGFloat = 22
        // Match the native menu title column (including its checkmark gutter).
        let leadingInset: CGFloat = 23
        let trailingInset: CGFloat = 14
        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.alignment = .left
        button.font = .menuFont(ofSize: 0)
        button.isEnabled = enabled
        let width = max(260, ceil(button.fittingSize.width) + leadingInset + trailingInset)
        button.frame = NSRect(x: leadingInset, y: 0, width: width - leadingInset - trailingInset, height: height)
        button.autoresizingMask = [.width, .height]

        let container = PersistentMenuActionRowView(button: button, frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.autoresizesSubviews = true
        container.autoresizingMask = [.width]
        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func speedTestMenuTitle() -> String {
        switch speedTestState {
        case .idle: return "Run Speed Test"
        case .running(.downloading): return "Speed Test: Downloading…"
        case .running(.uploading): return "Speed Test: Uploading…"
        case .completed(let result): return String(format: "Speed Test: ↓ %.1f / ↑ %.1f Mbps", result.downloadMbps, result.uploadMbps)
        case .failed: return "Speed Test Failed — Click to Retry"
        }
    }

    @objc private func runSpeedTest() {
        if case .running = speedTestState { return }
        speedTestState = .running(.downloading)
        rebuildMenu()
        SpeedTestRunner.run(onPhaseChange: { [weak self] phase in
            guard let self else { return }
            self.speedTestState = .running(phase)
            self.rebuildMenu()
        }, completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value): self.speedTestState = .completed(value)
            case .failure: self.speedTestState = .failed
            }
            self.rebuildMenu()
        })
    }
}
