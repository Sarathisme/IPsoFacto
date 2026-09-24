import AppKit
import IPsoFactoCore

/// Owns the NSStatusItem and its dropdown menu. Pure AppKit,
/// no custom drawing, so light/dark, tinted menu bars and Reduce
/// Transparency are all handled by the system for free.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let loginItemManager: LoginItemManager

    private var resolvedAddress: ResolvedAddress?
    private var interfaceDescription: String = "Not connected"

    init(loginItemManager: LoginItemManager) {
        self.loginItemManager = loginItemManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.menu = menu
        menu.delegate = self
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        render()
    }

    /// Called by NetworkMonitor on every resolved change (main thread).
    func update(resolved: ResolvedAddress?, interfaceDescription: String) {
        self.resolvedAddress = resolved
        self.interfaceDescription = interfaceDescription
        render()
    }

    /// Recompute the Launch at Login row's live status every time
    /// the menu opens, not just on network change.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    /// Repaints the button (four states) and rebuilds the menu.
    private func render() {
        guard let button = statusItem.button else { return }
        switch resolvedAddress {
        case .none:
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "No local IPv4 address")
            button.image?.isTemplate = true
            button.toolTip = "No local IPv4 address"
        case .some(let address) where address.category == .linkLocal:
            button.image = nil
            button.toolTip = nil
            button.attributedTitle = NSAttributedString(
                string: address.ipv4Address,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        case .some(let address):
            button.image = nil
            button.toolTip = nil
            button.attributedTitle = NSAttributedString(string: address.ipv4Address)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let headerItem = NSMenuItem(title: interfaceDescription, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if let resolvedAddress, let qrItem = makeQRCodeMenuItem(ipv4Address: resolvedAddress.ipv4Address) {
            menu.addItem(qrItem)
        }

        let copyItem = NSMenuItem(title: "Copy IP Address", action: #selector(copyIPAddress), keyEquivalent: "c")
        copyItem.target = self
        copyItem.isEnabled = resolvedAddress != nil
        menu.addItem(copyItem)

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

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About IPso Facto", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit IPso Facto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
    }

    private func makeQRCodeMenuItem(ipv4Address: String) -> NSMenuItem? {
        let imageSize: CGFloat = 160
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 12
        let labelHeight: CGFloat = 16
        let containerWidth = imageSize + horizontalPadding * 2
        let containerHeight = imageSize + verticalPadding * 2 + labelHeight

        guard let qrImage = QRCodeImageGenerator.image(forPayload: ipv4Address, sizePoints: imageSize) else { return nil }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))

        let imageView = NSImageView(frame: NSRect(x: horizontalPadding, y: verticalPadding + labelHeight, width: imageSize, height: imageSize))
        imageView.image = qrImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(imageView)

        let label = NSTextField(labelWithString: ipv4Address)
        label.frame = NSRect(x: 0, y: verticalPadding - 2, width: containerWidth, height: labelHeight)
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        container.addSubview(label)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func copyIPAddress() {
        guard let address = resolvedAddress else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address.ipv4Address, forType: .string)
    }

    @objc private func toggleLaunchAtLogin() {
        loginItemManager.toggle()
        rebuildMenu()
    }

    @objc private func openLoginItemsSettings() {
        loginItemManager.openLoginItemsSettings()
    }
}
