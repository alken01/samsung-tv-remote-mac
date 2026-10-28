import SwiftUI

struct AppsView: View {
    @ObservedObject var remote: Remote
    @NativeState private var appID = ""
    @NativeState private var adding = false

    private var others: [TVApp] { remote.available.filter { !remote.favoriteIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            if remote.available.isEmpty {
                GlassCard {
                    Text(remote.connected ? "Looking for apps on your TV…" : "Connect to your TV to see its apps.")
                        .font(Design.Font.body).foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Space.l) {
                        section("On the remote", empty: "Star an app below to add it.") {
                            ForEach(Array(remote.apps.enumerated()), id: \.element.id) { index, app in
                                row(app, favorite: true, first: index == 0, last: index == remote.apps.count - 1)
                            }
                        }
                        if !others.isEmpty {
                            section("More on this TV", empty: "") {
                                ForEach(others) { row($0, favorite: false, first: false, last: false) }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 430)
            }

            VStack(alignment: .leading, spacing: Design.Space.s) {
                SectionLabel(title: "Add app by ID")
                HStack(spacing: Design.Space.s) {
                    TextField("Tizen app ID", text: $appID)
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
                    .disabled(appID.trimmingCharacters(in: .whitespaces).isEmpty || adding || remote.television == nil)
                }
            }
        }
    }

    private func section<Rows: View>(_ title: String, empty: String, @ViewBuilder rows: @escaping () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            SectionLabel(title: title)
            ListCard {
                if title == "On the remote" && remote.apps.isEmpty {
                    Text(empty).font(Design.Font.detail).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Design.rowHeight, alignment: .leading)
                        .padding(.horizontal, Design.Space.s)
                }
                rows()
            }
        }
    }

    private func row(_ app: TVApp, favorite: Bool, first: Bool, last: Bool) -> some View {
        HStack(spacing: Design.Space.m) {
            AppIcon(app: app, size: 26)
            Text(app.name).font(Design.Font.body).lineLimit(1)
            Spacer(minLength: 0)
            if favorite {
                small("chevron.up", "Move up") { remote.moveFavorite(app, by: -1) }.disabled(first)
                small("chevron.down", "Move down") { remote.moveFavorite(app, by: 1) }.disabled(last)
            }
            if remote.customApps.contains(where: { $0.id == app.id }) {
                small("trash", "Remove app") { remote.removeCustomApp(app) }
            }
            small(favorite ? "star.fill" : "star", favorite ? "Remove from remote" : "Add to remote",
                  color: favorite ? .yellow : nil) { remote.toggleFavorite(app) }
        }
        .padding(.leading, Design.Space.s).padding(.trailing, Design.Space.xs)
        .frame(height: Design.rowHeight)
    }

    private func small(_ symbol: String, _ help: String, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: Design.Control.small, height: Design.Control.small)
        }
        .buttonStyle(PressStyle())
        .help(help)
        .accessibilityLabel("\(help): \(symbol)")
    }

    private func add() {
        guard !adding else { return }
        adding = true
        Task {
            await remote.addCustomApp(id: appID)
            adding = false
            appID = ""
        }
    }
}

extension TVApp {
    var brand: Color {
        switch name {
        case "YouTube", "YouTube Kids": return Color(red: 1.0, green: 0.0, blue: 0.2)
        case "Netflix": return Color(red: 0.9, green: 0.04, blue: 0.08)
        case "Prime Video": return Color(red: 0.0, green: 0.66, blue: 0.88)
        case "Disney+": return Color(red: 0.07, green: 0.24, blue: 0.81)
        case "Spotify": return Color(red: 0.11, green: 0.73, blue: 0.33)
        case "Apple Music": return Color(red: 0.98, green: 0.24, blue: 0.35)
        case "Plex": return Color(red: 0.9, green: 0.63, blue: 0.05)
        case "Twitch": return Color(red: 0.57, green: 0.27, blue: 1.0)
        case "Rakuten TV": return Color(red: 0.75, green: 0.0, blue: 0.1)
        case "Browser": return Color(red: 0.2, green: 0.5, blue: 0.95)
        case "Apple TV": return Color(white: 0.25)
        default: return .indigo
        }
    }
}
