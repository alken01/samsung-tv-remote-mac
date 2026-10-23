import SwiftUI

struct DevicesView: View {
    @ObservedObject var remote: Remote
    @FocusState private var editing: Bool
    @NativeState private var address = ""
    @NativeState private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if remote.discovered.isEmpty { empty }
            else {
                GlassGroup {
                    VStack(spacing: 8) { ForEach(remote.discovered) { row($0) } }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add by IP address")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4)
                HStack(spacing: 8) {
                    TextField("192.168.1.10", text: $address)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13).monospacedDigit())
                        .focused($editing)
                        .onSubmit(add)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassSurface(Capsule())
                    Button(action: add) {
                        if adding { ProgressView().controlSize(.small) } else { Text("Add") }
                    }
                    .glassControl(prominent: true)
                    .controlSize(.large)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || adding)
                }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, isActive: remote.scanning)
            Text(remote.scanning ? "Looking for your TV…" : "No TVs found")
                .font(.headline)
            Text("Make sure your Mac and Samsung TV are on the same network, or enter the TV’s IP address below.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func row(_ tv: Television) -> some View {
        let current = tv.id == remote.television?.id
        return Button { remote.select(tv) } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.07), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(tv.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(tv.model).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(tv.host).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: current ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: current ? 16 : 11, weight: .semibold))
                    .foregroundStyle(current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(10)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(PressStyle(highlight: false))
        .help(current ? "Reconnect to \(tv.name)" : "Use \(tv.name)")
    }

    private func add() {
        guard !adding, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        adding = true
        Task { await remote.add(host: address); adding = false }
    }
}
