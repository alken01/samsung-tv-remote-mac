import SwiftUI
import AppKit
import ServiceManagement

/// The app's window: what it is, where the remote lives, its keys and app-wide preferences.
/// The remote itself stays in the menu bar panel.
struct InfoWindow: View {
    @ObservedObject var remote: Remote
    var openRemote: () -> Void
    @NativeState private var login = SMAppService.mainApp.status == .enabled

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            HStack(spacing: Design.Space.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Samsung TV Remote").font(.system(size: 17, weight: .semibold))
                    Text("Version \(version)").font(Design.Font.detail).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Open Remote", action: openRemote).glassControl(prominent: true)
            }

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "Television")
                ListCard {
                    if let tv = remote.television {
                        RowLabel(symbol: "tv", title: tv.name, detail: "\(tv.model) · \(tv.host)") { status }
                    } else {
                        RowLabel(symbol: "tv", title: "No TV yet", detail: "Open the remote to find one") { EmptyView() }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "Keys while the remote is open")
                ListCard {
                    shortcut("arrow.up.and.down.and.arrow.left.and.right", "Move", "← ↑ → ↓")
                    RowDivider()
                    shortcut("return", "OK", "Return")
                    RowDivider()
                    shortcut("arrow.uturn.backward", "Back", "Esc  or  Delete")
                    RowDivider()
                    shortcut("speaker.wave.2", "Volume", "+  −")
                    RowDivider()
                    shortcut("keyboard", "Type on TV", "Any letter")
                }
            }

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "General")
                ListCard {
                    RowLabel(symbol: "power", title: "Open at login") {
                        Toggle("Open at login", isOn: $login).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }

            HStack(spacing: Design.Space.s) {
                Image(systemName: "appletvremote.gen1").foregroundStyle(.secondary)
                Text("The remote lives in the menu bar. Click its icon to open it.")
                    .font(Design.Font.detail).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Quit") { NSApplication.shared.terminate(nil) }.glassControl()
            }
            .padding(.leading, Design.Space.xs)
        }
        .padding(Design.Space.l + Design.Space.s)
        .frame(width: 440)
        .fixedSize()
        .onChange(of: login) { _, value in
            do {
                if value { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                remote.notice = "Login setting could not be changed: \(error.localizedDescription)"
                login = SMAppService.mainApp.status == .enabled
            }
        }
        // The panel can change this too; pick it up when the window comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            login = SMAppService.mainApp.status == .enabled
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle().fill(remote.connected ? Color.green : remote.busy ? .orange : .secondary).frame(width: 6, height: 6)
            Text(remote.poweredOff && !remote.connected && !remote.busy ? "TV off" : remote.state.title)
                .font(Design.Font.detail).foregroundStyle(.secondary)
        }
    }

    private func shortcut(_ symbol: String, _ title: String, _ keys: String) -> some View {
        RowLabel(symbol: symbol, title: title) {
            Text(keys).font(Design.Font.detail.monospaced()).foregroundStyle(.secondary)
        }
    }
}
