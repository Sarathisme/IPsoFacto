import AppKit
import Foundation
import IPsoFactoCore

/// Keeps lengthy commands readable without making the panel wider. The
/// collapsed label uses the system ellipsis; clicking it reveals the complete
/// command, wrapped within the row's existing width.
private final class ExpandableCommandTextField: NSTextField {
    private let command: String
    private var isExpanded = false

    init(command: String) {
        self.command = command
        super.init(frame: .zero)
        stringValue = command
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textColor = .tertiaryLabelColor
        lineBreakMode = .byTruncatingMiddle
        maximumNumberOfLines = 1
        toolTip = "Click to show the full command"
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        isExpanded.toggle()
        if let cell = cell as? NSTextFieldCell {
            cell.usesSingleLineMode = !isExpanded
            cell.wraps = isExpanded
            cell.isScrollable = false
        }
        lineBreakMode = isExpanded ? .byWordWrapping : .byTruncatingMiddle
        maximumNumberOfLines = isExpanded ? 0 : 1
        toolTip = isExpanded ? "Click to collapse the command" : "Click to show the full command"
        invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }

    override func layout() {
        super.layout()
        // AppKit needs the current constrained width to measure wrapped text.
        // Refresh it after both expansion and a window resize.
        if abs(preferredMaxLayoutWidth - bounds.width) > 0.5 {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class PortsListStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// A compact, refreshable view of the development servers discovered on this
/// Mac. It is deliberately a panel rather than a submenu: process details and
/// URLs remain readable without navigating a stack of transient menus.
@MainActor
final class DevelopmentPortsWindowController: NSWindowController, NSWindowDelegate {
    private let portsProvider: () -> [DevelopmentPort]

    private let countLabel = NSTextField(labelWithString: "")
    private let listStack = PortsListStackView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private var ports: [DevelopmentPort] = []

    init(portsProvider: @escaping () -> [DevelopmentPort]) {
        self.portsProvider = portsProvider

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Ports & Processes"
        panel.contentMinSize = NSSize(width: 380, height: 300)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.center()
        super.init(window: panel)
        panel.delegate = self
        buildInterface(in: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showModal() {
        refresh()
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.stopModal()
        return true
    }

    @objc private func refresh() {
        ports = portsProvider()
        applyFilter()
    }

    @objc private func filterPorts() {
        applyFilter()
    }

    private func buildInterface(in window: NSWindow) {
        let root = NSView(frame: window.contentLayoutRect)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        let title = NSTextField(labelWithString: "Ports & Processes")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Servers available on this Mac")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 12)

        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 2

        let headingRow = NSView()
        headingRow.translatesAutoresizingMaskIntoConstraints = false
        heading.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        headingRow.addSubview(heading)
        headingRow.addSubview(countLabel)

        searchField.placeholderString = "Filter by process or port"
        searchField.target = self
        searchField.action = #selector(filterPorts)
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let listeningLabel = NSTextField(labelWithString: "LISTENING NOW")
        listeningLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        listeningLabel.textColor = .secondaryLabelColor
        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .inline
        let sectionHeader = NSView()
        sectionHeader.translatesAutoresizingMaskIntoConstraints = false
        listeningLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        sectionHeader.addSubview(listeningLabel)
        sectionHeader.addSubview(refreshButton)

        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.distribution = .fill
        listStack.spacing = 0
        listStack.setHuggingPriority(.required, for: .vertical)
        listStack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = listStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSTextField(labelWithString: "Only supported development runtimes are shown")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        footer.setContentHuggingPriority(.required, for: .vertical)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)
        footer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(headingRow)
        root.addSubview(searchField)
        root.addSubview(sectionHeader)
        root.addSubview(scrollView)
        root.addSubview(emptyLabel)
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            headingRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            headingRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            headingRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            heading.topAnchor.constraint(equalTo: headingRow.topAnchor),
            heading.bottomAnchor.constraint(equalTo: headingRow.bottomAnchor),
            heading.leadingAnchor.constraint(equalTo: headingRow.leadingAnchor),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
            countLabel.trailingAnchor.constraint(equalTo: headingRow.trailingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: headingRow.centerYAnchor),
            searchField.topAnchor.constraint(equalTo: headingRow.bottomAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sectionHeader.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            sectionHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            sectionHeader.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            listeningLabel.leadingAnchor.constraint(equalTo: sectionHeader.leadingAnchor),
            listeningLabel.centerYAnchor.constraint(equalTo: sectionHeader.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: sectionHeader.trailingAnchor),
            refreshButton.topAnchor.constraint(equalTo: sectionHeader.topAnchor),
            refreshButton.bottomAnchor.constraint(equalTo: sectionHeader.bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: sectionHeader.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            listStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            listStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            listStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -15)
        ])
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visiblePorts = ports.filter { port in
            query.isEmpty || "\(port.displayName) \(port.command) \(port.port) \(port.pid)".lowercased().contains(query)
        }
        countLabel.stringValue = "\(ports.count) active"
        emptyLabel.stringValue = ports.isEmpty ? "No development servers listening" : "No matching development servers"
        emptyLabel.isHidden = !visiblePorts.isEmpty

        listStack.arrangedSubviews.forEach { view in
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for port in visiblePorts {
            let row = makePortRow(port)
            listStack.addArrangedSubview(row)
            // Stack alignment alone can use a row's fitting width, which
            // depends on its labels. Every row must fill the same viewport.
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    private func makePortRow(_ port: DevelopmentPort) -> NSView {
        let name = NSTextField(labelWithString: processName(for: port))
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        let badge = NSTextField(labelWithString: ":\(port.port)")
        badge.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        badge.layer?.cornerRadius = 5
        let openButton = NSButton(title: "Open", target: self, action: #selector(openPort(_:)))
        openButton.bezelStyle = .inline
        openButton.identifier = NSUserInterfaceItemIdentifier(port.id)

        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        openButton.setContentHuggingPriority(.required, for: .horizontal)
        openButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let details = NSTextField(labelWithString: "\(port.runtime.rawValue) · PID \(port.pid)")
        details.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        details.textColor = .secondaryLabelColor
        let command = ExpandableCommandTextField(command: port.command)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        for view in [name, badge, openButton, details, command] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            name.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -8),
            badge.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -10),
            openButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            openButton.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            details.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            details.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            details.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 4),
            command.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            command.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            command.topAnchor.constraint(equalTo: details.bottomAnchor, constant: 4),
            command.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10)
        ])
        return row
    }

    private func processName(for port: DevelopmentPort) -> String {
        guard let executable = port.command.split(whereSeparator: \.isWhitespace).first else { return port.displayName }
        return URL(fileURLWithPath: String(executable)).lastPathComponent
    }

    @objc private func openPort(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let port = ports.first(where: { $0.id == identifier }),
              let url = URL(string: "http://localhost:\(port.port)") else { return }
        NSWorkspace.shared.open(url)
    }
}
