import AppKit

/// A second launch exits itself, leaving the first instance
/// running. Only meaningful once the app has a bundle identifier (i.e.
/// running from the assembled .app, not a bare `swift run` executable,
/// which has none).
enum SingleInstanceGuard {
    static func terminateIfAlreadyRunning() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard runningInstances.count > 1 else { return }
        exit(0)
    }
}
