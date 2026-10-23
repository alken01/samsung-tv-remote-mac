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
        return remote.showKeyboard ? .keyboard : .remote
    }

    var body: some View {
        VStack(spacing: 16) {
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
        .padding(18)
        .frame(width: 312)
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
        .onChange(of: remote.showKeyboard) { _, open in
            typing = open
            if open { KeyboardView.moveCaretToEnd() }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: screen)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: remote.notice)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: remote.state)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerSymbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .glassSurface(Circle())
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if screen == .remote || screen == .keyboard { status }
                else {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            switch screen {
            case .remote, .keyboard:
                GlassIconButton(symbol: "list.bullet", help: "Choose TV", size: 30) {
                    typing = false; remote.showDevices = true
                    Task { await remote.scan() }
                }
                GlassIconButton(symbol: "gearshape", help: "Settings", size: 30) {
                    typing = false; remote.showSettings = true
                }
            case .devices:
                if remote.scanning {
                    ProgressView().controlSize(.small).frame(width: 30, height: 30)
                } else {
                    GlassIconButton(symbol: "arrow.clockwise", help: "Scan again", size: 30) {
                        Task { await remote.scan() }
                    }
                }
                if remote.television != nil {
                    GlassIconButton(symbol: "xmark", help: "Back to remote", size: 30) { remote.showDevices = false }
                }
            case .settings:
                GlassIconButton(symbol: "xmark", help: "Close settings", size: 30) { remote.showSettings = false }
            case .apps:
                GlassIconButton(symbol: "xmark", help: "Back to remote", size: 30) { remote.showApps = false }
            }
        }
    }

    private var headerSymbol: String {
        switch screen {
        case .settings: return "gearshape"
        case .devices: return "dot.radiowaves.left.and.right"
        case .apps: return "square.grid.2x2"
        case .remote, .keyboard: return "tv"
        }
    }

    private var subtitle: String {
        switch screen {
        case .settings: return "Preferences and pairing"
        case .apps: return "Choose what the remote shows"
        default: return "On your local network"
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
                .font(.caption).foregroundStyle(.secondary)
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
            Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { remote.notice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonStyle(PressStyle()).foregroundStyle(.secondary).help("Dismiss")
        }
        .padding(12)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: notice) {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if remote.notice == notice { remote.notice = nil }
        }
    }

    // MARK: Keyboard

    private func openKeyboard(seed: String = "") {
        remote.text += seed
        if remote.showKeyboard { typing = true; KeyboardView.moveCaretToEnd() } else { remote.showKeyboard = true }
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
        case .escape, .delete: remote.send(.back)
        default:
            switch event.characters {
            case "+", "=": remote.send(.volumeUp)
            case "-": remote.send(.volumeDown)
            default:
                // Any printable character starts typing on the TV.
                guard event.phase == .down, let scalar = event.characters.unicodeScalars.first,
                      !CharacterSet.controlCharacters.contains(scalar),
                      !(0xF700...0xF8FF).contains(scalar.value) else { return .ignored }
                openKeyboard(seed: event.characters)
            }
        }
        return .handled
    }
}
