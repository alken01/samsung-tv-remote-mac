import SwiftUI

struct ControlsView: View {
    @ObservedObject var remote: Remote
    var openKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let detail = remote.detail { banner(detail) }

            Group {
                VStack(spacing: 14) {
                    ZStack {
                        DirectionPad(remote: remote)
                        VStack {
                            HStack {
                                // Power stays usable while disconnected: it wakes the TV instead.
                                GlassIconButton(symbol: "power", help: remote.connected ? "Turn TV off" : "Turn TV on",
                                                size: 36, color: remote.connected ? .red : .green) {
                                    if remote.connected { remote.send(.powerOff) } else { remote.wake() }
                                }
                                .disabled(remote.busy)
                                Spacer()
                                GlassIconButton(symbol: "rectangle.on.rectangle", help: "Inputs", size: 36) { remote.send(.source) }
                                    .disabled(!remote.connected)
                            }
                            Spacer()
                            HStack {
                                GlassIconButton(symbol: "arrow.uturn.backward", help: "Back · Esc", size: 36) { remote.send(.back) }
                                Spacer()
                                GlassIconButton(symbol: "house", help: "Home", size: 36) { remote.send(.home) }
                            }
                            .disabled(!remote.connected)
                        }
                    }
                    .frame(height: DirectionPad.size)

                    VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        SegmentedGlass {
                            segment(.volumeDown, "minus", "Volume down · −")
                            segment(.mute, "speaker.slash.fill", "Mute")
                            segment(.volumeUp, "plus", "Volume up · +")
                        }
                        SegmentedGlass {
                            segment(.rewind, "backward.fill", "Rewind")
                            segment(.play, "play.fill", "Play")
                            segment(.pause, "pause.fill", "Pause")
                            segment(.forward, "forward.fill", "Fast forward")
                        }
                    }

                    HStack(spacing: 10) {
                        Button(action: openKeyboard) {
                            HStack(spacing: 8) {
                                Image(systemName: "keyboard").font(.system(size: 14, weight: .semibold))
                                Text("Type on TV").font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 0)
                                Text("or just type").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            .modifier(EnabledFade())
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .glassSurface(Capsule(), interactive: true)
                        }
                        .buttonStyle(PressStyle(highlight: false))
                        .help("Type into any text field on the TV")
                        GlassIconButton(symbol: "slider.horizontal.3", help: "TV menu", size: 40) { remote.send(.settings) }
                    }
                    }
                    .disabled(!remote.connected)
                }
            }

            if !remote.available.isEmpty { apps }
        }
    }

    // Up to five per row, centred; six split into two even rows of three.
    private var appColumns: Int {
        let count = remote.apps.count
        return count == 6 ? 3 : max(1, min(count, 5))
    }

    private func segment(_ key: TVKey, _ symbol: String, _ label: String) -> some View {
        Button { remote.send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(PressStyle(shape: AnyShape(Capsule())))
        .help(label)
        .accessibilityLabel(label)
    }

    // Same capsule language as the controls below it, with power on the left doing the waking.
    private func banner(_ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: remote.state == .pairing ? "hand.tap.fill" : remote.poweredOff ? "moon.fill" : "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(remote.state == .pairing ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .symbolEffect(.pulse, isActive: remote.busy)
                .frame(width: 18)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if remote.busy {
                ProgressView().controlSize(.small).frame(width: 30, height: 30)
            } else {
                GlassIconButton(symbol: "arrow.clockwise", help: "Reconnect", size: 30) { remote.connect() }
            }
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
        .frame(minHeight: 42)
        .glassSurface(RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { remote.showApps = true } label: {
                    Text(remote.apps.isEmpty ? "Choose apps" : "Edit")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).frame(height: 22)
                }
                .buttonStyle(PressStyle(shape: AnyShape(Capsule())))
                .foregroundStyle(Color.accentColor)
                .help("Choose favourite apps")
            }
            .padding(.horizontal, 4)
            if !remote.apps.isEmpty {
                Group {
                    // Icons only, on one glass shelf; the name shows on hover.
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 18), count: appColumns), spacing: 14) {
                        ForEach(remote.apps) { app in
                            Button { remote.launch(app) } label: {
                                AppIcon(app: app, size: 40)
                                    .modifier(EnabledFade())
                            }
                            .buttonStyle(PressStyle(highlight: false))
                            .disabled(!remote.connected)
                            .help(app.name)
                            .accessibilityLabel("Open \(app.name)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }
}

/// Several plain buttons sharing one glass capsule.
private struct SegmentedGlass<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 0, content: content)
            .padding(3)
            .glassSurface(Capsule())
    }
}

struct DirectionPad: View {
    @ObservedObject var remote: Remote
    static let size: CGFloat = 184

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                .padding(40)
            arrow(.up, "chevron.up", "Up · ↑").offset(y: -Self.size * 0.33)
            arrow(.down, "chevron.down", "Down · ↓").offset(y: Self.size * 0.33)
            arrow(.left, "chevron.left", "Left · ←").offset(x: -Self.size * 0.33)
            arrow(.right, "chevron.right", "Right · →").offset(x: Self.size * 0.33)
            Button { remote.send(.select) } label: {
                Text("OK")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background { AccentFill(shape: Circle()) }
                    .shadow(color: .accentColor.opacity(0.35), radius: 10, y: 3)
            }
            .buttonStyle(PressStyle(highlight: false))
            .disabled(!remote.connected)
            .help("Select · Return")
            .accessibilityLabel("Select")
        }
        .frame(width: Self.size, height: Self.size)
        // Glass applied to the stack sits behind its buttons; a glass sibling would cover them.
        .glassSurface(Circle())
    }

    private func arrow(_ key: TVKey, _ symbol: String, _ label: String) -> some View {
        Button { remote.send(key) } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected)
        .help(label)
        .accessibilityLabel(label)
    }
}
