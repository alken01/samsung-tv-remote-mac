import SwiftUI
import AppKit

@main struct SamsungTVRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings {
            InfoWindow(remote: delegate.remote) { delegate.openRemote() }
        }
        .windowResizability(.contentSize)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let remote = Remote()
    private var panel: StatusPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateDefaults()
        panel = StatusPanel(remote: remote)
        remote.start()
    }

    // Opening the app again from Finder or Spotlight shows the remote rather than an empty window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openRemote()
        return false
    }

    func openRemote() {
        if let window = NSApp.keyWindow, window !== panel?.panel { window.close() }
        panel?.show()
    }

    // Carry favourites and preferences over from the app's former bundle identifier.
    private func migrateDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromMenuRemote"),
              let old = UserDefaults(suiteName: "local.samsung-menu-remote") else { return }
        for key in ["favoriteApps", "customApps"] where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migratedFromMenuRemote")
    }
}
