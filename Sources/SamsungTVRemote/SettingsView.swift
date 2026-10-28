import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var remote: Remote
    @NativeState private var login = SMAppService.mainApp.status == .enabled

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            if let tv = remote.television {
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    SectionLabel(title: "Television")
                    ListCard {
                        RowLabel(symbol: "tv", title: tv.name, detail: "\(tv.model) · \(tv.host)")
                            .textSelection(.enabled)
                        RowDivider()
                        if remote.connected {
                            RowButton(symbol: "bolt.horizontal.circle", title: "Disconnect") { remote.pause() }
                        } else {
                            RowButton(symbol: "bolt.horizontal.circle", title: "Connect") { remote.connect() }
                                .disabled(remote.busy)
                        }
                        RowButton(symbol: "list.bullet", title: "Choose another TV",
                                  action: { remote.showSettings = false; remote.showDevices = true; Task { await remote.scan() } }) {
                            Disclosure()
                        }
                        RowButton(symbol: "arrow.triangle.2.circlepath", title: "Pair again") {
                            remote.repair(); remote.showSettings = false
                        }
                        RowButton(symbol: "trash", title: "Forget this TV", tint: .red) { remote.forget() }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "General")
                ListCard {
                    RowButton(symbol: "square.grid.2x2", title: "Favorite apps",
                              action: { remote.showSettings = false; remote.showApps = true }) {
                        Disclosure(value: "\(remote.apps.count)")
                    }
                    RowDivider()
                    RowLabel(symbol: "power", title: "Open at login") {
                        Toggle("Open at login", isOn: $login).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    .onChange(of: login) { _, value in
                        do {
                            if value { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            remote.notice = "Login setting could not be changed: \(error.localizedDescription)"
                            login = SMAppService.mainApp.status == .enabled
                        }
                    }
                }
            }

            HStack {
                Text("Version \(version)").font(Design.Font.detail).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .glassControl()
                    .keyboardShortcut("q")
            }
            .padding(.leading, Design.Space.xs)
        }
    }
}
