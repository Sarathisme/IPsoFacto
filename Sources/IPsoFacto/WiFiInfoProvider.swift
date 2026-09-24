import Foundation
import CoreLocation
import CoreWLAN

/// Live SSID/RSSI reads via CoreWLAN, gated behind Location Services
/// authorization -- required on modern macOS for any non-sandboxed,
/// non-App-Store app to read CWInterface.ssid() (Decision #9). Not unit
/// tested: thin wrapper around system frameworks, matching
/// LiveInterfaceAddressSource's approach.
@MainActor
final class WiFiInfoProvider: NSObject, CLLocationManagerDelegate {
    struct WiFiInfo: Equatable {
        let ssid: String
        let rssi: Int
    }

    /// Called on the main thread whenever authorization status changes.
    /// The caller re-reads `currentInfo()` in response.
    var onAuthorizationChange: (() -> Void)?

    private let locationManager = CLLocationManager()
    private let wifiClient = CWWiFiClient.shared()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    /// True once the user has granted Location Services to this app.
    var isAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: return true
        default: return false
        }
    }

    /// Triggers the system Location Services permission prompt if not yet
    /// determined. No-op if already determined (granted or denied) --
    /// if denied, the user must re-enable it via
    /// System Settings > Privacy & Security > Location Services.
    func requestAuthorizationIfNeeded() {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        locationManager.requestAlwaysAuthorization()
    }

    /// True if `bsdName` (e.g. "en0") is a Wi-Fi interface. Does not
    /// require authorization -- interface *names* are not
    /// location-gated, only SSID/RSSI values.
    func isWiFiInterface(_ bsdName: String) -> Bool {
        wifiClient.interfaceNames()?.contains(bsdName) ?? false
    }

    /// Current Wi-Fi SSID and signal strength (dBm), or nil if not
    /// connected to Wi-Fi, not authorized, or CoreWLAN has no data.
    func currentInfo() -> WiFiInfo? {
        guard isAuthorized, let interface = wifiClient.interface(), let ssid = interface.ssid() else { return nil }
        return WiFiInfo(ssid: ssid, rssi: interface.rssiValue())
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onAuthorizationChange?() }
    }
}
