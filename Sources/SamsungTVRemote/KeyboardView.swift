import SwiftUI
import AppKit

struct KeyboardView: View {
    @ObservedObject var remote: Remote
    var focus: FocusState<Bool>.Binding
    var close: () -> Void

    var body: some View {
        VStack(spacing: Design.Space.m) {
            HStack {
                Button(action: close) {
                    Label("Remote", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                }
                .buttonStyle(PressStyle(shape: AnyShape(Capsule())))
                .help("Back to remote · Esc")
                Spacer()
                liveBadge
            }

            HStack(spacing: Design.Space.s) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Type on your TV", text: $remote.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused(focus)
                    .onSubmit(submit)
                    .onKeyPress(.escape) { close(); return .handled }
                    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { navigate($0.key) }
                if !remote.text.isEmpty {
                    Button { remote.text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Design.Space.l)
            .frame(height: 44)
            .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(focus.wrappedValue ? 0.55 : 0), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.15), value: focus.wrappedValue)
            .animation(.easeOut(duration: 0.15), value: remote.text.isEmpty)

            Button(action: submit) {
                Label("Enter", systemImage: "return").frame(maxWidth: .infinity)
            }
            .glassControl(prominent: true)
            .controlSize(.large)
            .disabled(!remote.connected)
            .help("Confirm on the TV · Return")

            Text(remote.imeActive
                 ? "Return confirms · Esc goes back"
                 : "Select a text field on the TV to start")
                .font(Design.Font.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            DispatchQueue.main.async { focus.wrappedValue = true; Self.moveCaretToEnd() }
        }
    }

    // Focusing a field selects its contents; put the caret after any seeded character instead.
    static func moveCaretToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(remote.imeActive ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(remote.imeActive ? 0.8 : 0), radius: 3)
            Text(remote.imeActive ? "TV keyboard open" : "No text field on TV")
                .font(Design.Font.detail.weight(.medium))
                .foregroundStyle(remote.imeActive ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .glassSurface(Capsule())
        .animation(.smooth(duration: 0.25), value: remote.imeActive)
    }

    // With nothing typed, Return behaves like OK so the keyboard doubles as a remote.
    private func submit() {
        guard remote.connected else { return }
        if remote.text.isEmpty && !remote.imeActive { remote.send(.select) } else { remote.submitText() }
        DispatchQueue.main.async { focus.wrappedValue = true }
    }

    // Up and down always drive the TV; left and right only once there is no text to edit locally.
    private func navigate(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .upArrow: remote.send(.up)
        case .downArrow: remote.send(.down)
        case .leftArrow where remote.text.isEmpty: remote.send(.left)
        case .rightArrow where remote.text.isEmpty: remote.send(.right)
        default: return .ignored
        }
        return .handled
    }
}
