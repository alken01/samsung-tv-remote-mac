import SwiftUI

struct ControlsView: View {
    @ObservedObject var remote: Remote
    var openKeyboard: () -> Void

    var body: some View {
        VStack(spacing: Design.Space.l) {
            if let detail = remote.detail { banner(detail) }

            Group {
                VStack(spacing: Design.Space.m) {
                    ZStack {
                        DirectionPad(remote: remote)
                        VStack {
                            HStack {
                                // Power stays usable while disconnected: it wakes the TV instead.
                                GlassIconButton(symbol: "power", help: remote.connected ? "Turn TV off" : "Turn TV on",
                                                size: Design.Control.regular, color: remote.connected ? .red : .green) {
                                    if remote.connected { remote.send(.powerOff) } else { remote.wake() }
                                }
                                .disabled(remote.busy)
                                Spacer()
                                GlassIconButton(symbol: "rectangle.on.rectangle", help: "Inputs", size: Design.Control.regular) { remote.send(.source) }
                                    .disabled(!remote.connected)
                            }
                            Spacer()
                            HStack {
                                GlassIconButton(symbol: "arrow.uturn.backward", help: "Back · Esc", size: Design.Control.regular) { remote.send(.back) }
                                Spacer()
                                GlassIconButton(symbol: "house", help: "Home", size: Design.Control.regular) { remote.send(.home) }
                            }
                            .disabled(!remote.connected)
                        }
                    }
                    .frame(height: DirectionPad.size)

                    VStack(spacing: Design.Space.m) {
                        if let volume = remote.volume { VolumeSlider(remote: remote, level: volume) }

                        HStack(spacing: Design.Space.s) {
                            if remote.volume == nil {
                                // Without the renderer's absolute volume, fall back to the volume keys.
                                SegmentedGlass {
                                    segment(.volumeDown, "minus", "Volume down · −")
                                    segment(.mute, "speaker.slash.fill", "Mute")
                                    segment(.volumeUp, "plus", "Volume up · +")
                                }
                            }
                            SegmentedGlass { playback }
                            GlassIconButton(symbol: "slider.horizontal.3", help: "TV menu", size: Design.Control.large) {
                                remote.send(.settings)
                            }
                        }

                        // Only offered while the TV has a text field open; typing any letter still opens the keyboard.
                        if remote.imeActive {
                            Button(action: openKeyboard) {
                                HStack(spacing: Design.Space.s) {
                                    Image(systemName: "keyboard").font(.system(size: 14, weight: .semibold))
                                    Text("Type on TV").font(Design.Font.button)
                                }
                                .modifier(EnabledFade())
                                .frame(maxWidth: .infinity)
                                .frame(height: Design.Control.large)
                                .glassSurface(Capsule(), interactive: true)
                            }
                            .buttonStyle(PressStyle(highlight: false))
                            .help("The TV has a text field open")
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .animation(.smooth(duration: 0.25), value: remote.imeActive)
                    .disabled(!remote.connected)
                }
            }

            if !remote.available.isEmpty { apps }
        }
        .onReceive(NotificationCenter.default.publisher(for: .remotePanelDidOpen)) { _ in
            Task { await remote.refreshVolume() }
        }
    }

    @ViewBuilder private var playback: some View {
        segment(.rewind, "backward.fill", "Rewind")
        Button { remote.togglePlayback() } label: {
            Image(systemName: "playpause.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: Design.Control.small)
        }
        .buttonStyle(PressStyle(shape: AnyShape(Capsule())))
        .help("Play or pause")
        .accessibilityLabel("Play or pause")
        segment(.forward, "forward.fill", "Fast forward")
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
                .frame(height: Design.Control.small)
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
                .font(Design.Font.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if remote.busy {
                ProgressView().controlSize(.small).frame(width: Design.Control.small, height: Design.Control.small)
            } else {
                GlassIconButton(symbol: "arrow.clockwise", help: "Reconnect", size: Design.Control.small) { remote.connect() }
            }
        }
        .padding(.leading, Design.Space.l).padding(.trailing, Design.Space.xs + 2).padding(.vertical, Design.Space.xs + 2)
        .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            HStack {
                SectionLabel(title: "Apps")
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
            if !remote.apps.isEmpty {
                Group {
                    // Icons only, on one glass shelf; the name shows on hover.
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 14), count: appColumns), spacing: 14) {
                        ForEach(remote.apps) { app in
                            Button { remote.launch(app) } label: {
                                AppIcon(app: app, size: 36)
                                    .modifier(EnabledFade())
                            }
                            .buttonStyle(PressStyle(highlight: false))
                            .disabled(!remote.connected)
                            .help(app.name)
                            .accessibilityLabel("Open \(app.name)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Space.l)
                    .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
                }
            }
        }
    }
}

/// The TV's absolute volume on one glass capsule: mute on the left, the level on the right.
private struct VolumeSlider: View {
    @ObservedObject var remote: Remote
    let level: Int

    private var symbol: String {
        if remote.muted || level == 0 { return "speaker.slash.fill" }
        return level < 34 ? "speaker.wave.1.fill" : level < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: Design.Space.s) {
            Button { remote.send(.mute) } label: {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(remote.muted ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Design.Control.small, height: Design.Control.small)
            }
            .buttonStyle(PressStyle())
            .help(remote.muted ? "Unmute" : "Mute")
            .accessibilityLabel(remote.muted ? "Unmute" : "Mute")

            Slider(value: Binding(get: { Double(level) }, set: { remote.setVolume(Int($0.rounded())) }),
                   in: 0...100) { editing in
                remote.adjustingVolume = editing
            }
            .controlSize(.small)
            .opacity(remote.muted ? 0.5 : 1)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(level)")

            Text("\(level)")
                .font(Design.Font.detail.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
                .contentTransition(.numericText(value: Double(level)))
        }
        .padding(.leading, Design.Space.xs).padding(.trailing, Design.Space.m)
        .frame(height: Design.Control.large)
        .modifier(EnabledFade())
        .glassSurface(Capsule())
        .animation(.snappy(duration: 0.2), value: level)
    }
}

/// Several plain buttons sharing one glass capsule.
private struct SegmentedGlass<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        // Segments are `Control.small` tall; the inset brings the capsule to `Control.large` like its neighbours.
        HStack(spacing: 0, content: content)
            .padding((Design.Control.large - Design.Control.small) / 2)
            .glassSurface(Capsule())
    }
}

struct DirectionPad: View {
    @ObservedObject var remote: Remote
    static let size: CGFloat = 160

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                .padding(34)
            arrow(.up, "chevron.up", "Up · ↑").offset(y: -Self.size * 0.33)
            arrow(.down, "chevron.down", "Down · ↓").offset(y: Self.size * 0.33)
            arrow(.left, "chevron.left", "Left · ←").offset(x: -Self.size * 0.33)
            arrow(.right, "chevron.right", "Right · →").offset(x: Self.size * 0.33)
            Button { remote.send(.select) } label: {
                Text("OK")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
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
                .frame(width: 42, height: 42)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected)
        .help(label)
        .accessibilityLabel(label)
    }
}
