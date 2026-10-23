import SwiftUI
import AppKit

@main struct SamsungMenuRemoteApp: App {
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
}
