import Foundation
import SwiftUI

final class TVCertificateDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Samsung supplies a self-signed certificate. Limit this exception to the selected TV.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == host, challenge.protectionSpace.port == 8002,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}

enum ConnectionState: Equatable {
    case idle, connecting, pairing, connected, offline(String)
    var title: String {
        switch self {
        case .idle: return "Ready to pair"
        case .connecting: return "Connecting"
        case .pairing: return "Allow on your TV"
        case .connected: return "Connected"
        case .offline: return "Disconnected"
        }
    }
}

@MainActor final class Remote: ObservableObject {
    @Published private(set) var television: Television?
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discovered: [Television] = []
    @Published private(set) var scanning = false
    /// Catalog and custom apps whose metadata endpoint answered on this TV.
    @Published private(set) var available: [TVApp] = []
    @Published private(set) var favoriteIDs: [String] = UserDefaults.standard.stringArray(forKey: "favoriteApps") ?? TVApp.defaultFavorites
    @Published private(set) var customApps: [TVApp] = UserDefaults.standard.data(forKey: "customApps")
        .flatMap { try? JSONDecoder().decode([TVApp].self, from: $0) } ?? []
    @Published var notice: String?
    @Published var showDevices = false
    @Published var showSettings = false
    @Published var showKeyboard = false
    @Published var showApps = false
    /// Set after the power key, so the UI can offer power-on instead of an error.
    @Published private(set) var poweredOff = false
    /// True while the TV reports an open on-screen keyboard (for example YouTube search).
    @Published private(set) var imeActive = false
    /// TV volume 0–100 from its media renderer; nil until read, or when the TV does not offer it.
    @Published private(set) var volume: Int?
    @Published private(set) var muted = false
    /// Our best guess at whether playback is paused. Samsung has no play/pause toggle key that
    /// works in every app, so the single button alternates between the play and pause keys.
    private var playbackPaused = false
    /// Set while the slider is dragged, so a refresh does not pull the thumb back.
    var adjustingVolume = false
    /// Mirrored live to the TV's open text field.
    @Published var text = "" { didSet { if text != oldValue { queueText() } } }

    private let storage = RemoteStorage()
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var appProbe: Task<Void, Never>?
    private var textTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var sentText = ""
    private var textAnnounced = false
    private var generation = UUID()
    private var retryDelay: UInt64 = 2
    private var paused = false
    private var started = false

    var connected: Bool { state == .connected }
    /// Favourite apps in the user's order, limited to those present on this TV.
    var apps: [TVApp] { favoriteIDs.compactMap { id in available.first { $0.id == id } } }
    var busy: Bool { state == .connecting || state == .pairing }
    var detail: String? {
        if case .offline(let text) = state { return text }
        if state == .pairing { return "Choose Allow for Samsung Menu Remote using your TV remote." }
        return nil
    }

    init() {
        television = storage.loadTV()
    }

    func start() {
        guard !started else { return }
        started = true
        if let tv = television, storage.token(for: tv) != nil { connect() }
        Task { await scan() }
    }

    func scan() async {
        guard !scanning else { return }
        scanning = true
        discovered = await TVDiscovery.scan()
        scanning = false
        if let current = television, let updated = discovered.first(where: { $0.id == current.id }) {
            television = updated
            do { try storage.saveTV(updated) } catch { notice = "Could not save the TV address: \(error.localizedDescription)" }
            if !connected && !busy && !paused && storage.token(for: updated) != nil { connect() }
        }
    }

    func add(host: String) async {
        do { select(try await TVDiscovery.inspect(host: host.trimmingCharacters(in: .whitespacesAndNewlines))) }
        catch { notice = "Could not find that TV. \(error.localizedDescription)" }
    }

    func select(_ tv: Television) {
        television = tv
        available = []
        do { try storage.saveTV(tv) } catch { notice = "Could not save TV: \(error.localizedDescription)" }
        showDevices = false
        connect()
    }

    func connect() {
        guard let tv = television else { showDevices = true; return }
        stopConnection()
        paused = false
        notice = nil
        let token = storage.token(for: tv)
        guard let url = SamsungProtocol.socketURL(host: tv.host, token: token) else {
            state = .offline("The TV address is invalid."); return
        }
        state = token == nil ? .pairing : .connecting
        let id = generation
        let session = URLSession(configuration: .ephemeral, delegate: TVCertificateDelegate(host: tv.host), delegateQueue: nil)
        self.session = session
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 35_000_000_000) } catch { return }
            guard let self, self.generation == id, !self.connected else { return }
            self.failed(token == nil ? "Pairing timed out. Turn on the TV, reconnect and select Allow." : "The TV is unreachable. Check power and Wi-Fi.", id: id)
        }
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == id else { return }
                    let bytes: Data
                    switch message {
                    case .string(let text): bytes = Data(text.utf8)
                    case .data(let data): bytes = data
                    @unknown default: continue
                    }
                    guard let event = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { continue }
                    switch event["event"] as? String {
                    case "ms.channel.connect":
                        if let payload = event["data"] as? [String: Any], let raw = payload["token"],
                           let token = raw as? String ?? (raw as? Int).map(String.init) {
                            do { try self.storage.saveToken(token, for: tv) }
                            catch { self.notice = "Paired, but the credential could not be saved: \(error.localizedDescription)" }
                        }
                        self.deadline?.cancel()
                        self.poweredOff = false
                        self.state = .connected
                        self.retryDelay = 2
                        self.startHeartbeat(socket: socket, id: id)
                        self.findApps(tv: tv, id: id)
                        Task { await self.refreshVolume() }
                    case "ms.channel.unauthorized", "ms.channel.timeOut":
                        self.failed("The TV did not allow this connection. Use Pair again in Settings.", id: id, reconnect: false)
                        return
                    case "ms.remote.imeStart":
                        self.resetTextSession()
                        self.imeActive = true
                        if !self.showSettings && !self.showDevices { self.showKeyboard = true }
                    case "ms.remote.imeEnd":
                        self.resetTextSession()
                        self.imeActive = false
                        self.showKeyboard = false
                    case "ms.error":
                        self.notice = "The TV could not perform that command. Support varies between TV apps."
                    default: break
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.failed("Connection lost. Check that the TV is on and on the same network.", id: id)
            }
        }
    }

    private func startHeartbeat(socket: URLSessionWebSocketTask, id: UUID) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        socket.sendPing { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.failed("The TV connection stopped responding.", id: id)
                    return
                }
            }
        }
    }

    private func failed(_ message: String, id: UUID, reconnect: Bool = true) {
        guard generation == id else { return }
        stopConnection()
        state = .offline(message)
        guard reconnect, !paused, let tv = television, storage.token(for: tv) != nil else { return }
        let delay = retryDelay
        retryDelay = min(30, retryDelay * 2)
        retry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
            guard let self, !self.paused else { return }
            self.connect()
        }
    }

    private func stopConnection() {
        generation = UUID()
        receiver?.cancel(); receiver = nil
        heartbeat?.cancel(); heartbeat = nil
        deadline?.cancel(); deadline = nil
        retry?.cancel(); retry = nil
        appProbe?.cancel(); appProbe = nil
        textTask?.cancel(); textTask = nil
        volumeTask?.cancel(); volumeTask = nil
        imeActive = false
        sentText = ""; textAnnounced = false
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
    }

    func send(_ key: TVKey) {
        guard connected, let socket else { return }
        let id = generation
        Task {
            do {
                try await socket.send(.string(SamsungProtocol.command(key)))
                if [.volumeUp, .volumeDown, .mute].contains(key) {
                    // The TV applies the key a moment later; read back what it settled on.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    await refreshVolume()
                }
                if key == .powerOff, generation == id {
                    paused = true
                    stopConnection()
                    poweredOff = true
                    state = .offline("The TV is off. Press power to turn it back on.")
                }
            } catch { failed("The command could not reach the TV.", id: id) }
        }
    }

    // Coalesces fast typing into one update; each update carries the whole field contents.
    private func queueText() {
        textTask?.cancel()
        guard connected, socket != nil, text != sentText else { return }
        let id = generation
        textTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 70_000_000) } catch { return }
            guard let self, self.generation == id else { return }
            await self.pushText(id: id)
        }
    }

    private func pushText(id: UUID) async {
        guard let socket, text != sentText else { return }
        let value = text
        do {
            if !textAnnounced {
                textAnnounced = true
                try await socket.send(.string(SamsungProtocol.textReceived()))
            }
            try await socket.send(.string(SamsungProtocol.inputString(value)))
            if generation == id { sentText = value }
        } catch { failed("Text could not reach the TV.", id: id) }
    }

    /// Sends any pending text, then confirms it on the TV (Done / Search).
    func submitText() {
        guard connected, let socket else { return }
        textTask?.cancel()
        let id = generation
        Task {
            await pushText(id: id)
            guard generation == id else { return }
            do { try await socket.send(.string(SamsungProtocol.inputEnd())) }
            catch { failed("Text could not reach the TV.", id: id); return }
            resetTextSession()
        }
    }

    private func resetTextSession() {
        textTask?.cancel()
        sentText = ""
        textAnnounced = false
        text = ""
    }

    func launch(_ app: TVApp) {
        guard connected, let tv = television,
              let url = URL(string: "http://\(tv.host):8001/api/v2/applications/\(app.id)") else { return }
        let id = generation
        Task {
            do {
                var request = URLRequest(url: url, timeoutInterval: 5)
                request.httpMethod = "POST"
                let (_, response) = try await URLSession.shared.data(for: request)
                guard generation == id else { return }
                guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                    notice = "\(app.name) could not be opened on this TV."; return
                }
            } catch { if generation == id { notice = "Could not open \(app.name): \(error.localizedDescription)" } }
        }
    }

    func togglePlayback() {
        send(playbackPaused ? .play : .pause)
        playbackPaused.toggle()
    }

    func refreshVolume() async {
        guard connected, let host = television?.host, !adjustingVolume, volumeTask == nil else { return }
        let id = generation
        async let level = Self.renderer(host: host, action: "GetVolume", reading: "CurrentVolume")
        async let mute = Self.renderer(host: host, action: "GetMute", reading: "CurrentMute")
        let (newLevel, newMute) = await (level, mute)
        guard generation == id, !adjustingVolume, volumeTask == nil else { return }
        volume = newLevel.flatMap { Int($0) }.map { min(100, max(0, $0)) }
        muted = newMute == "1"
    }

    /// Shows the new level at once and sends only the latest one while the slider moves.
    func setVolume(_ level: Int) {
        guard connected, let host = television?.host else { return }
        let level = min(100, max(0, level))
        guard level != volume else { return }
        volume = level
        muted = false
        volumeTask?.cancel()
        let id = generation
        volumeTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 60_000_000) } catch { return }
            let sent = await Self.renderer(host: host, action: "SetVolume", arguments: [("DesiredVolume", String(level))])
            guard let self, self.generation == id, !Task.isCancelled else { return }
            self.volumeTask = nil
            if sent == nil { self.notice = "The TV did not accept the volume change." }
        }
    }

    /// Runs a RenderingControl action; returns the `reading` value, or "" when there is none to read.
    nonisolated private static func renderer(host: String, action: String, arguments: [(String, String)] = [],
                                             reading: String? = nil) async -> String? {
        guard let request = RenderingControl.request(host: host, action: action, arguments: arguments),
              let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let reading else { return "" }
        return RenderingControl.value(reading, in: String(decoding: data, as: UTF8.self))
    }

    private func findApps(tv: Television, id: UUID) {
        appProbe?.cancel()
        let candidates = TVApp.catalog + customApps.filter { custom in !TVApp.catalog.contains { $0.id == custom.id } }
        appProbe = Task { [weak self] in
            let installed = await withTaskGroup(of: String?.self) { group in
                for app in candidates {
                    group.addTask { await Self.appName(host: tv.host, id: app.id) == nil ? nil : app.id }
                }
                var result = Set<String>()
                for await value in group { if let value { result.insert(value) } }
                return result
            }
            guard !Task.isCancelled, let self, self.generation == id else { return }
            var seen = Set<String>()
            // Keep one entry per service when both identifier generations answer.
            self.available = candidates.filter { installed.contains($0.id) && seen.insert($0.name).inserted }
        }
    }

    /// The TV's name for an installed app, or nil when the identifier is unknown to it.
    nonisolated static func appName(host: String, id: String) async -> String? {
        guard let url = URL(string: "http://\(host):8001/api/v2/applications/\(id)"),
              let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 3)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["name"] as? String ?? id
    }

    func toggleFavorite(_ app: TVApp) {
        if let index = favoriteIDs.firstIndex(of: app.id) { favoriteIDs.remove(at: index) }
        else { favoriteIDs.append(app.id) }
        UserDefaults.standard.set(favoriteIDs, forKey: "favoriteApps")
    }

    func moveFavorite(_ app: TVApp, by offset: Int) {
        let order = apps.map(\.id)
        guard let from = order.firstIndex(of: app.id), order.indices.contains(from + offset) else { return }
        let other = order[from + offset]
        guard let a = favoriteIDs.firstIndex(of: app.id), let b = favoriteIDs.firstIndex(of: other) else { return }
        favoriteIDs.swapAt(a, b)
        UserDefaults.standard.set(favoriteIDs, forKey: "favoriteApps")
    }

    func addCustomApp(id raw: String) async {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tv = television, !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) else {
            notice = "Enter a Tizen app ID, for example 111299001912."; return
        }
        guard let name = await Self.appName(host: tv.host, id: id) else {
            notice = "The TV does not know an app with ID \(id)."; return
        }
        let app = TVApp.catalog.first { $0.id == id } ?? TVApp(id: id, name: name, symbol: "app.fill")
        if !TVApp.catalog.contains(where: { $0.id == id }) && !customApps.contains(where: { $0.id == id }) {
            customApps.append(app)
            if let data = try? JSONEncoder().encode(customApps) { UserDefaults.standard.set(data, forKey: "customApps") }
        }
        if !available.contains(where: { $0.id == id }) { available.append(app) }
        if !favoriteIDs.contains(id) { toggleFavorite(app) }
    }

    func removeCustomApp(_ app: TVApp) {
        customApps.removeAll { $0.id == app.id }
        available.removeAll { $0.id == app.id && !TVApp.catalog.contains($0) }
        favoriteIDs.removeAll { $0 == app.id }
        UserDefaults.standard.set(favoriteIDs, forKey: "favoriteApps")
        if let data = try? JSONEncoder().encode(customApps) { UserDefaults.standard.set(data, forKey: "customApps") }
    }

    func wake() {
        guard let mac = television?.mac else { notice = "Connect to the TV once to learn its MAC address."; return }
        do {
            try TVDiscovery.wake(mac: mac)
            connect()
            notice = "Wake request sent. The TV may take a few seconds to respond."
        } catch { notice = error.localizedDescription }
    }

    func repair() {
        guard let tv = television else { return }
        stopConnection()
        do { try storage.forget(tv); try storage.saveTV(tv); connect() }
        catch { notice = "Could not reset pairing: \(error.localizedDescription)" }
    }

    func forget() {
        guard let tv = television else { return }
        stopConnection()
        do {
            try storage.forget(tv)
            television = nil; available = []; state = .idle; showSettings = false; showKeyboard = false
        } catch { notice = "Could not forget TV: \(error.localizedDescription)" }
    }

    func pause() {
        paused = true
        stopConnection()
        state = .offline("Disconnected. Select Reconnect when you need the remote.")
    }
}
