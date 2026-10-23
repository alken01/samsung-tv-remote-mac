import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var remote: Remote
    @NativeState private var login = SMAppService.mainApp.status == .enabled
    @AppStorage(MediaKeys.defaultsKey) private var volumeKeys = true
    @NativeState private var trusted = MediaKeys.trusted

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let tv = remote.television {
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "tv")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 34, height: 34)
                            .background(.primary.opacity(0.07), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tv.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text("\(tv.model) · \(tv.host)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .lineLimit(1).textSelection(.enabled)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Pair again") { remote.repair(); remote.showSettings = false }.glassControl()
                        Button("Forget", role: .destructive) { remote.forget() }.glassControl()
                        Spacer(minLength: 0)
                        if remote.connected {
                            Button("Disconnect") { remote.pause() }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button { remote.showSettings = false; remote.showApps = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(.primary.opacity(0.07), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Favorite apps").font(.system(size: 13, weight: .medium))
                        Text("\(remote.apps.count) on the remote").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
            }
            .buttonStyle(PressStyle(highlight: false))

            GlassCard {
                Toggle(isOn: $volumeKeys) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac volume keys control TV").font(.system(size: 13, weight: .medium))
                        Text("While the remote is open, volume and mute keys change the TV instead of the Mac.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                if volumeKeys && !trusted {
                    HStack(spacing: 8) {
                        Text("Needs Accessibility access.").font(.caption).foregroundStyle(.orange)
                        Spacer(minLength: 0)
                        Button("Allow…") {
                            MediaKeys.requestAccess()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .glassControl()
                    }
                }
            }
            .task {
                // Reflect permission granted in System Settings while this screen is open.
                while !Task.isCancelled {
                    trusted = MediaKeys.trusted
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            GlassCard {
                Toggle(isOn: $login) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open at login").font(.system(size: 13, weight: .medium))
                        Text("Keep the remote in your menu bar.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
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

            HStack {
                Text("Version \(version)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .glassControl()
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 4)
        }
    }
}
