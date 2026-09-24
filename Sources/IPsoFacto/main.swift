import AppKit

SingleInstanceGuard.terminateIfAlreadyRunning()

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
