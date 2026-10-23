import AppKit
import SwiftUI

/// Official app icons, taken from each service's App Store listing via Apple's public lookup API.
/// Downloaded once and cached in Application Support; nothing is bundled or sent besides the store ID.
@MainActor final class AppIcons: ObservableObject {
    static let shared = AppIcons()
    @Published private(set) var images: [String: NSImage] = [:]
    private var loading = Set<String>()
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SamsungMenuRemote/Icons", isDirectory: true)

    // Keyed by catalog name, because several services have two Tizen identifiers.
    private static let listings: [String: (id: String, country: String)] = [
        "YouTube": ("544007664", "us"),
        "YouTube Kids": ("936971630", "us"),
        "Netflix": ("363590051", "us"),
        "Prime Video": ("545519333", "us"),
        "Disney+": ("1446075923", "us"),
        "Apple TV": ("1174078549", "us"),
        "Spotify": ("324684580", "us"),
        "Apple Music": ("1108187390", "us"),
        "Plex": ("383457673", "us"),
        "Twitch": ("460177396", "us"),
        "Rakuten TV": ("532577301", "be")
    ]

    func load(_ app: TVApp) async {
        let key = app.name
        guard images[key] == nil, !loading.contains(key), let listing = Self.listings[key] else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        let file = directory.appendingPathComponent("\(listing.id).png")
        if let cached = NSImage(contentsOf: file) { images[key] = cached; return }
        guard let lookup = URL(string: "https://itunes.apple.com/lookup?id=\(listing.id)&country=\(listing.country)"),
              let (data, _) = try? await URLSession.shared.data(from: lookup),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artwork = (json["results"] as? [[String: Any]])?.first?["artworkUrl512"] as? String,
              // Ask Apple's image service for a lossless 256 px rendition instead of the 512 px JPEG.
              let url = URL(string: artwork.replacingOccurrences(of: "512x512bb.jpg", with: "256x256bb.png")),
              let (bytes, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: bytes) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? bytes.write(to: file, options: .atomic)
        images[key] = image
    }
}

/// The app's official icon on a rounded tile, or a brand-coloured symbol until it loads.
struct AppIcon: View {
    let app: TVApp
    var size: CGFloat = 30
    @ObservedObject private var icons = AppIcons.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let image = icons.images[app.name] {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: app.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(app.brand.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .task(id: app.name) { await icons.load(app) }
        .accessibilityHidden(true)
    }
}
