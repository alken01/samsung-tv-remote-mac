import SwiftUI
import AppKit

struct RemotePanel: View {
    @ObservedObject var remote: Remote
    @FocusState private var typing: Bool
    @FocusState private var panelFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Screen { case remote, keyboard, devices, settings, apps }

    private var screen: Screen {
        if remote.showSettings { return .settings }
        if remote.television == nil || remote.showDevices { return .devices }
        if remote.showApps { return .apps }
        return remote.imeActive && remote.showKeyboard ? .keyboard : .remote
    }

    var body: some View {
        VStack(spacing: Design.Space.l) {
            header
            Group {
                switch screen {
                case .remote: ControlsView(remote: remote) { openKeyboard() }
                case .keyboard: KeyboardView(remote: remote, focus: $typing) { closeKeyboard() }
                case .devices: DevicesView(remote: remote)
                case .settings: SettingsView(remote: remote)
                case .apps: AppsView(remote: remote)
                }
            }
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            if let notice = remote.notice { noticeView(notice) }
        }
        .padding(Design.Space.l)
        .frame(width: Design.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        // Pin content to the top while the panel animates to a new height.
        .frame(maxHeight: .infinity, alignment: .top)
        .focusable()
        .focused($panelFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .remotePanelDidOpen)) { _ in
            if screen == .keyboard { typing = true; KeyboardView.moveCaretToEnd() }
            else if screen == .remote { panelFocused = true }
        }
        .onChange(of: screen) { _, screen in
            typing = screen == .keyboard
            panelFocused = screen == .remote
            if typing { KeyboardView.moveCaretToEnd() }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: screen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: remote.notice)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: remote.state)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Design.Space.m) {
            if let back = backAction {
                GlassIconButton(symbol: "chevron.left", help: "Back", size: Design.Control.small, action: back)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(Design.Font.title)
                    .lineLimit(1)
                if screen == .remote || screen == .keyboard { status }
            }
            Spacer(minLength: Design.Space.xs)
            switch screen {
            case .remote, .keyboard:
                GlassIconButton(symbol: "gearshape", help: "Settings", size: Design.Control.small) {
                    typing = false; remote.showSettings = true
                }
            case .devices:
                if remote.scanning {
                    ProgressView().controlSize(.small).frame(width: Design.Control.small, height: Design.Control.small)
                } else {
                    GlassIconButton(symbol: "arrow.clockwise", help: "Scan again", size: Design.Control.small) {
                        Task { await remote.scan() }
                    }
                }
            case .settings, .apps:
                EmptyView()
            }
        }
        .frame(minHeight: Design.Control.large)
    }

    // Subscreens go back with a chevron on the left; the remote itself has nowhere to go back to.
    private var backAction: (() -> Void)? {
        switch screen {
        case .remote, .keyboard: return nil
        case .devices: return remote.television == nil ? nil : { remote.showDevices = false }
        case .settings: return { remote.showSettings = false }
        case .apps: return { remote.showApps = false }
        }
    }

    private var headerTitle: String {
        switch screen {
        case .settings: return "Settings"
        case .devices: return "Choose a TV"
        case .apps: return "Favorite apps"
        case .remote, .keyboard: return remote.television?.name ?? "Samsung TV"
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(remote.connected ? 0.8 : 0), radius: 3)
                .opacity(remote.busy ? 0.5 : 1)
                .animation(remote.busy && !reduceMotion ? .easeInOut(duration: 0.8).repeatForever() : .default, value: remote.busy)
            Text(remote.poweredOff && !remote.connected && !remote.busy ? "TV off" : remote.state.title)
                .font(Design.Font.detail).foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    private var statusColor: Color {
        switch remote.state {
        case .connected: return .green
        case .connecting, .pairing: return .orange
        default: return .secondary
        }
    }

    // MARK: Notice

    private func noticeView(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
            Text(notice).font(Design.Font.detail).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { remote.notice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonStyle(PressStyle()).foregroundStyle(.secondary).help("Dismiss")
        }
        .padding(Design.Space.m)
        .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: notice) {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if remote.notice == notice { remote.notice = nil }
        }
    }

    // MARK: Keyboard

    private func openKeyboard() {
        guard remote.imeActive else { return }
        remote.showKeyboard = true
    }

    private func closeKeyboard() {
        typing = false
        remote.showKeyboard = false
    }

    private func handle(_ event: KeyPress) -> KeyPress.Result {
        guard screen == .remote, remote.connected,
              event.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        switch event.key {
        case .upArrow: remote.send(.up)
        case .downArrow: remote.send(.down)
        case .leftArrow: remote.send(.left)
        case .rightArrow: remote.send(.right)
        case .return: remote.send(.select)
        case .space:
            if event.phase == .down { remote.togglePlayback() }
        case .delete, KeyEquivalent("\u{7f}"): remote.send(.back)
        default:
            switch event.characters.lowercased() {
            case "+", "=": remote.send(.volumeUp)
            case "-": remote.send(.volumeDown)
            case "h": if event.phase == .down { remote.send(.home) }
            case "m": if event.phase == .down { remote.send(.settings) }
            case "i": if event.phase == .down { remote.send(.source) }
            case "u": if event.phase == .down { remote.send(.mute) }
            default: return .ignored
            }
        }
        return .handled
    }
}
