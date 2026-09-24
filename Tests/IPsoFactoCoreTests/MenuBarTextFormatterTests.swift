import Testing
@testable import IPsoFactoCore

@Suite("MenuBarTextFormatter")
struct MenuBarTextFormatterTests {
    static let address = ResolvedAddress(interfaceName: "en0", address: "192.168.1.4", family: .ipv4, category: .normal)

    @Test("ipOnly renders the bare address")
    func ipOnly() {
        #expect(MenuBarTextFormatter.render(format: .ipOnly, resolved: Self.address, hostname: "MyMac", customTemplate: "") == "192.168.1.4")
    }

    @Test("ipOnly with no resolved address renders empty")
    func ipOnlyNilAddress() {
        #expect(MenuBarTextFormatter.render(format: .ipOnly, resolved: nil, hostname: "MyMac", customTemplate: "") == "")
    }

    @Test("ipAndInterface renders address and interface name")
    func ipAndInterface() {
        #expect(MenuBarTextFormatter.render(format: .ipAndInterface, resolved: Self.address, hostname: "MyMac", customTemplate: "") == "192.168.1.4 (en0)")
    }

    @Test("ipAndWiFi renders address with Wi-Fi name and signal strength")
    func ipAndWiFi() {
        let result = MenuBarTextFormatter.render(format: .ipAndWiFi, resolved: Self.address, hostname: "MyMac", customTemplate: "", wifiDescription: "HomeNet (-45 dBm)")
        #expect(result == "192.168.1.4 · HomeNet (-45 dBm)")
    }

    @Test("ipAndWiFi falls back to the bare address when no Wi-Fi description is available")
    func ipAndWiFiWithoutWiFi() {
        #expect(MenuBarTextFormatter.render(format: .ipAndWiFi, resolved: Self.address, hostname: "MyMac", customTemplate: "") == "192.168.1.4")
    }

    @Test("ipAndWiFi with no resolved address renders empty")
    func ipAndWiFiNilAddress() {
        #expect(MenuBarTextFormatter.render(format: .ipAndWiFi, resolved: nil, hostname: "MyMac", customTemplate: "", wifiDescription: "HomeNet (-45 dBm)") == "")
    }

    @Test("hostname renders the supplied hostname regardless of address")
    func hostname() {
        #expect(MenuBarTextFormatter.render(format: .hostname, resolved: nil, hostname: "MyMac", customTemplate: "") == "MyMac")
    }

    @Test("custom substitutes all three placeholders")
    func customAllPlaceholders() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "{hostname}: {ip} on {interface}")
        #expect(result == "MyMac: 192.168.1.4 on en0")
    }

    @Test("custom with nil resolved substitutes empty string for ip/interface placeholders")
    func customNilAddress() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: nil, hostname: "MyMac", customTemplate: "ip={ip} if={interface}")
        #expect(result == "ip= if=")
    }

    @Test("custom template with no placeholders is returned verbatim")
    func customTemplateWithNoPlaceholders() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "Static Label")
        #expect(result == "Static Label")
    }

    @Test("custom template with an empty string renders empty")
    func customTemplateEmptyString() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "")
        #expect(result == "")
    }

    @Test("custom template with a repeated placeholder substitutes every occurrence")
    func customTemplateRepeatedPlaceholder() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "{ip} = {ip}")
        #expect(result == "192.168.1.4 = 192.168.1.4")
    }

    @Test("custom template text that merely resembles a placeholder (wrong braces/name) is left as-is, not substituted")
    func customTemplateUnknownPlaceholderLeftAsIs() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "{ip} {unknown} {Interface} {ip forgot brace")
        #expect(result == "192.168.1.4 {unknown} {Interface} {ip forgot brace")
    }

    @Test("ipAndInterface with a link-local resolved address still renders both fields; formatting doesn't depend on category")
    func ipAndInterfaceRendersLinkLocalAddress() {
        let linkLocal = ResolvedAddress(interfaceName: "en0", address: "169.254.3.2", family: .ipv4, category: .linkLocal)
        #expect(MenuBarTextFormatter.render(format: .ipAndInterface, resolved: linkLocal, hostname: "MyMac", customTemplate: "") == "169.254.3.2 (en0)")
    }

    @Test("hostname format ignores the custom template entirely")
    func hostnameFormatIgnoresCustomTemplate() {
        let result = MenuBarTextFormatter.render(format: .hostname, resolved: Self.address, hostname: "MyMac", customTemplate: "{ip}")
        #expect(result == "MyMac")
    }

    @Test("custom template substitutes the {wifi} placeholder when supplied")
    func customTemplateSubstitutesWiFi() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "{ip} on {wifi}", wifiDescription: "HomeNet (-45 dBm)")
        #expect(result == "192.168.1.4 on HomeNet (-45 dBm)")
    }

    @Test("custom template's {wifi} placeholder becomes empty when no Wi-Fi description is supplied")
    func customTemplateWiFiDefaultsToEmpty() {
        let result = MenuBarTextFormatter.render(format: .custom, resolved: Self.address, hostname: "MyMac", customTemplate: "wifi={wifi}")
        #expect(result == "wifi=")
    }
}
