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
            VStack(alignment: .leading, spacing: Design.Space.m) {
                HStack(spacing: Design.Space.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Samsung TV Remote").font(Design.Font.title).lineLimit(1)
                        Text("Version \(version)").font(Design.Font.detail).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Open", action: openRemote).glassControl(prominent: true).help("Open remote")
                }
                RowDivider()
                if let tv = remote.television {
                    HStack {
                        Text(tv.name).font(Design.Font.body).lineLimit(1)
                        Spacer(minLength: Design.Space.s)
                        status
                    }
                    Text("\(tv.model) · \(tv.host)")
                        .font(Design.Font.detail.monospacedDigit()).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Open the remote to choose a TV.")
                        .font(Design.Font.detail).foregroundStyle(.secondary)
                }
            }
            .padding(Design.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "Shortcuts")
                ListCard {
                    shortcut("arrow.up.and.down.and.arrow.left.and.right", "Move", "← ↑ → ↓")
                    RowDivider()
                    shortcut("return", "OK", "Return")
                    RowDivider()
                    shortcut("arrow.uturn.backward", "Back", "Backspace")
                    RowDivider()
                    shortcut("playpause", "Play / pause", "Space")
                    RowDivider()
                    shortcut("speaker.wave.2", "Volume", "+  −")
                    RowDivider()
                    shortcut("house", "Home", "H")
                    RowDivider()
                    shortcut("slider.horizontal.3", "TV menu", "M")
                    RowDivider()
                    shortcut("rectangle.on.rectangle", "Inputs", "I")
                    RowDivider()
                    shortcut("speaker.slash", "Mute", "U")
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
                Spacer(minLength: 0)
                Button("Quit") { NSApplication.shared.terminate(nil) }.glassControl()
            }
            .padding(.leading, Design.Space.xs)
        }
        .padding(Design.Space.l)
        .frame(width: 360)
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
