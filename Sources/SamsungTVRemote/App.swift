import SwiftUI
import AppKit

@main struct SamsungTVRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let remote = Remote()
    private var panel: StatusPanel?
    private let mediaKeys = MediaKeys()

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateDefaults()
        panel = StatusPanel(remote: remote)
        remote.start()
        // Only while the panel is on screen; otherwise the keys keep controlling the Mac.
        mediaKeys.active = { [weak self, remote] in remote.connected && self?.panel?.panel.isVisible == true }
        mediaKeys.send = { [remote] key in remote.send(key) }
        mediaKeys.update(prompt: false)
        var enabled = MediaKeys.enabled
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard MediaKeys.enabled != enabled else { return }
                enabled = MediaKeys.enabled
                self?.mediaKeys.update(prompt: enabled)
            }
        }
    }

    // Carry favourites and preferences over from the app's former bundle identifier.
    private func migrateDefaults() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromMenuRemote"),
              let old = UserDefaults(suiteName: "local.samsung-menu-remote") else { return }
        for key in ["favoriteApps", "customApps", MediaKeys.defaultsKey] where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migratedFromMenuRemote")
    }
}
