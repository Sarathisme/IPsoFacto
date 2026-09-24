import AppKit
import IPsoFactoCore

/// The Preferences window: menu bar text format (Phase 2), Wi-Fi info
/// toggle (Phase 3), and global hotkey recorder (Phase 4). Programmatic
/// AppKit, no XIB, matching the rest of the app shell (Decision #5).
@MainActor
final class PreferencesWindowController: NSWindowController {
    private let preferencesStore: PreferencesStore
    private let wifiInfoProvider: WiFiInfoProvider
    private let hotKeyManager: GlobalHotKeyManager

    private let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let customTemplateField = NSTextField(string: "")
    private let contentStack = NSStackView()
    private var wifiCheckbox: NSButton!
    private var hotkeyButton: NSButton!
    private var localMonitor: Any?

    init(preferencesStore: PreferencesStore, wifiInfoProvider: WiFiInfoProvider, hotKeyManager: GlobalHotKeyManager) {
        self.preferencesStore = preferencesStore
        self.wifiInfoProvider = wifiInfoProvider
        self.hotKeyManager = hotKeyManager
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "IPso Facto Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        loadFromStore()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let formatLabel = NSTextField(labelWithString: "Menu Bar Text:")
        MenuBarTextFormat.allCases.forEach { formatPopUp.addItem(withTitle: Self.displayTitle(for: $0)) }
        formatPopUp.target = self
        formatPopUp.action = #selector(formatChanged)

        customTemplateField.placeholderString = "e.g. {ip} on {interface}"
        customTemplateField.target = self
        customTemplateField.action = #selector(customTemplateChanged)

        let customHelpLabel = NSTextField(labelWithString: "Custom format uses {ip}, {interface}, {hostname}, {wifi}.")
        customHelpLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        customHelpLabel.textColor = .secondaryLabelColor

        contentStack.addArrangedSubview(formatLabel)
        contentStack.addArrangedSubview(formatPopUp)
        contentStack.addArrangedSubview(customTemplateField)
        contentStack.addArrangedSubview(customHelpLabel)

        wifiCheckbox = NSButton(checkboxWithTitle: "Show Wi-Fi Network Name & Signal Strength", target: self, action: #selector(wifiToggleChanged))
        wifiCheckbox.state = preferencesStore.showWiFiInfo ? .on : .off
        contentStack.addArrangedSubview(wifiCheckbox)

        let hotkeyLabel = NSTextField(labelWithString: "Global Hotkey (Copy IP):")
        hotkeyButton = NSButton(title: hotkeyButtonTitle(), target: self, action: #selector(hotkeyButtonClicked))
        contentStack.addArrangedSubview(hotkeyLabel)
        contentStack.addArrangedSubview(hotkeyButton)

        let contentView = NSView(frame: window!.contentLayoutRect)
        contentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        window?.contentView = contentView
        window?.setContentSize(NSSize(width: 380, height: contentStack.fittingSize.height))
    }

    private func loadFromStore() {
        let format = preferencesStore.menuBarTextFormat
        formatPopUp.selectItem(at: MenuBarTextFormat.allCases.firstIndex(of: format) ?? 0)
        customTemplateField.stringValue = preferencesStore.menuBarCustomTemplate
        customTemplateField.isEnabled = format == .custom
    }

    @objc private func formatChanged() {
        let index = formatPopUp.indexOfSelectedItem
        guard MenuBarTextFormat.allCases.indices.contains(index) else { return }
        let format = MenuBarTextFormat.allCases[index]
        preferencesStore.menuBarTextFormat = format
        customTemplateField.isEnabled = format == .custom
        // Same Location Services gate as the Wi-Fi checkbox: SSID/RSSI
        // can't be read without it.
        if format == .ipAndWiFi { wifiInfoProvider.requestAuthorizationIfNeeded() }
    }

    @objc private func customTemplateChanged() {
        preferencesStore.menuBarCustomTemplate = customTemplateField.stringValue
    }

    @objc private func wifiToggleChanged() {
        let isOn = wifiCheckbox.state == .on
        preferencesStore.showWiFiInfo = isOn
        if isOn { wifiInfoProvider.requestAuthorizationIfNeeded() }
    }

    private func hotkeyButtonTitle() -> String {
        if let hotkey = preferencesStore.hotkey { return "\(hotkey.displayString)  (click to change, ⌫ to clear)" }
        return "Click to Record…"
    }

    @objc private func hotkeyButtonClicked() {
        hotkeyButton.title = "Press keys… (Esc to cancel)"
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handleRecorderKeyDown(event)
            return nil
        }
    }

    private func handleRecorderKeyDown(_ event: NSEvent) {
        let escapeKeyCode: UInt16 = 53
        let deleteKeyCode: UInt16 = 51
        if event.keyCode == escapeKeyCode {
            stopRecording()
            hotkeyButton.title = hotkeyButtonTitle()
            return
        }
        if event.keyCode == deleteKeyCode {
            preferencesStore.hotkey = nil
            hotKeyManager.unregister()
            stopRecording()
            hotkeyButton.title = hotkeyButtonTitle()
            return
        }
        guard GlobalHotKey.keyCodeDisplayNames[UInt32(event.keyCode)] != nil else {
            // Not A-Z/0-9 (Decision #11) -- ignore and keep recording, monitor stays installed.
            return
        }
        let carbonModifiers = GlobalHotKey.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else {
            // No modifier held (Decision #11) -- ignore and keep recording, monitor stays installed.
            return
        }
        let newHotkey = GlobalHotKey(keyCode: UInt32(event.keyCode), modifierFlags: carbonModifiers)
        preferencesStore.hotkey = newHotkey
        hotKeyManager.register(newHotkey)
        stopRecording()
        hotkeyButton.title = hotkeyButtonTitle()
    }

    private func stopRecording() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
    }

    private static func displayTitle(for format: MenuBarTextFormat) -> String {
        switch format {
        case .ipOnly: return "IP Address Only"
        case .ipAndInterface: return "IP Address + Interface"
        case .ipAndWiFi: return "IP Address + Wi-Fi Name & Strength"
        case .hostname: return "Hostname"
        case .custom: return "Custom Format…"
        }
    }
}
