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
    private var displayedFamily: AddressFamily = .ipv4

    /// Set by AppDelegate; called when the user picks IPv4 or IPv6 from
    /// the dropdown. The controller doesn't own the family preference
    /// itself -- NetworkMonitor does, since it's the one that persists and
    /// re-resolves it.
    var onFamilyToggle: ((AddressFamily) -> Void)?

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
    func update(resolved: ResolvedAddress?, interfaceDescription: String, family: AddressFamily) {
        self.resolvedAddress = resolved
        self.interfaceDescription = interfaceDescription
        self.displayedFamily = family
        render()
    }

    /// Recompute the Launch at Login row's live status every time
    /// the menu opens, not just on network change.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    /// Repaints the button (four states) and rebuilds the menu.
    ///
    /// An IPv6 address (up to ~45 chars with a %zone-id suffix) shown in
    /// full would balloon the status item to an impractical width for a
    /// menu bar, and -- since AppKit anchors a status item's dropdown menu
    /// to the button rather than centering it -- also makes the much
    /// narrower dropdown (QR code included) look shifted left relative to
    /// that very wide button. Truncating the button's displayed text (the
    /// full address stays available via the tooltip, Copy IP Address, and
    /// the QR code itself) avoids both problems.
    private func render() {
        guard let button = statusItem.button else { return }
        let familyLabel = displayedFamily == .ipv4 ? "IPv4" : "IPv6"
        switch resolvedAddress {
        case .none:
            button.attributedTitle = NSAttributedString(string: "")
            button.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "No local \(familyLabel) address")
            button.image?.isTemplate = true
            button.toolTip = "No local \(familyLabel) address"
        case .some(let address) where address.category == .linkLocal:
            button.image = nil
            button.toolTip = address.address
            button.attributedTitle = NSAttributedString(
                string: Self.truncatedForDisplay(address.address),
                attributes: [.foregroundColor: NSColor.secondaryLabelColor]
            )
        case .some(let address):
            button.image = nil
            button.toolTip = address.address
            button.attributedTitle = NSAttributedString(string: Self.truncatedForDisplay(address.address))
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let headerItem = NSMenuItem(title: interfaceDescription, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let ipv4Item = NSMenuItem(title: "Show IPv4 Address", action: #selector(selectIPv4), keyEquivalent: "")
        ipv4Item.target = self
        ipv4Item.state = displayedFamily == .ipv4 ? .on : .off
        menu.addItem(ipv4Item)

        let ipv6Item = NSMenuItem(title: "Show IPv6 Address", action: #selector(selectIPv6), keyEquivalent: "")
        ipv6Item.target = self
        ipv6Item.state = displayedFamily == .ipv6 ? .on : .off
        menu.addItem(ipv6Item)

        menu.addItem(.separator())

        if let resolvedAddress, let qrItem = makeQRCodeMenuItem(address: resolvedAddress.address) {
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

    private func makeQRCodeMenuItem(address: String) -> NSMenuItem? {
        let imageSize: CGFloat = 160
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 12
        let labelHeight: CGFloat = 16
        let containerWidth = imageSize + horizontalPadding * 2
        let containerHeight = imageSize + verticalPadding * 2 + labelHeight

        guard let qrImage = QRCodeImageGenerator.image(forPayload: address, sizePoints: imageSize) else { return nil }

        // Whatever ends up resizing this row wider for a long IPv6 address
        // (AppKit's exact custom-view menu-row sizing is undocumented and
        // wasn't reliably reproducible outside a live menu), .minXMargin +
        // .maxXMargin is the standard, general-purpose AppKit answer:
        // if the superview's frame is resized for any reason, flexible
        // margins on both sides keep a subview centered rather than
        // pinned to its original left-anchored offset.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        container.autoresizesSubviews = true

        let imageView = NSImageView(frame: NSRect(x: horizontalPadding, y: verticalPadding + labelHeight, width: imageSize, height: imageSize))
        imageView.image = qrImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(imageView)

        // Also bound the label's own intrinsic content size: it's based on
        // the full, untruncated text regardless of frame or lineBreakMode,
        // and a long IPv6 address (up to ~45 chars with a %zone-id suffix)
        // reports a far wider intrinsic size than this container -- worth
        // avoiding regardless of whether it's what was driving the resize.
        // The QR code still encodes the full, untruncated address.
        let label = NSTextField(labelWithString: Self.truncatedForDisplay(address))
        label.frame = NSRect(x: 0, y: verticalPadding - 2, width: containerWidth, height: labelHeight)
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.autoresizingMask = [.minXMargin, .maxXMargin]
        container.addSubview(label)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    /// Shortens `address` for display under the QR code if it's long
    /// enough to overflow the fixed-width container (IPv6 addresses,
    /// especially with a %zone-id suffix, routinely are; IPv4 addresses
    /// never are). Keeps both ends visible via a middle ellipsis, since
    /// the prefix and suffix are usually what's most recognisable.
    private static func truncatedForDisplay(_ address: String, maxLength: Int = 24) -> String {
        guard address.count > maxLength else { return address }
        let headCount = 10
        let tailCount = 10
        let head = address.prefix(headCount)
        let tail = address.suffix(tailCount)
        return "\(head)…\(tail)"
    }

    @objc private func copyIPAddress() {
        guard let address = resolvedAddress else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address.address, forType: .string)
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
}
