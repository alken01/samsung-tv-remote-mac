import SwiftUI

struct DevicesView: View {
    @ObservedObject var remote: Remote
    @NativeState private var address = ""
    @NativeState private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            if remote.discovered.isEmpty { empty }
            else {
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    SectionLabel(title: "On this network")
                    ListCard {
                        ForEach(Array(remote.discovered.enumerated()), id: \.element.id) { index, tv in
                            if index > 0 { RowDivider() }
                            row(tv)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "Add by IP address")
                HStack(spacing: Design.Space.s) {
                    TextField("192.168.1.10", text: $address)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13).monospacedDigit())
                        .onSubmit(add)
                        .padding(.horizontal, Design.Space.l)
                        .frame(height: Design.Control.regular)
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
        VStack(spacing: Design.Space.s) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, isActive: remote.scanning)
            Text(remote.scanning ? "Looking for your TV…" : "No TVs found")
                .font(Design.Font.title)
            Text("Make sure your Mac and Samsung TV are on the same network, or enter the TV’s IP address below.")
                .font(Design.Font.detail).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Design.Space.l + Design.Space.s)
        .padding(.horizontal, Design.Space.l)
        .frame(maxWidth: .infinity)
        .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
    }

    private func row(_ tv: Television) -> some View {
        let current = tv.id == remote.television?.id
        return RowButton(symbol: "tv", title: tv.name, detail: "\(tv.model) · \(tv.host)",
                         action: { remote.select(tv) }) {
            if current {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accentColor)
            } else {
                Disclosure()
            }
        }
        .help(current ? "Reconnect to \(tv.name)" : "Use \(tv.name)")
    }

    private func add() {
        guard !adding, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        adding = true
        Task { await remote.add(host: address); adding = false }
    }
}
