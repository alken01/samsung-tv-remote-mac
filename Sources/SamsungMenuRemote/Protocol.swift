import Foundation

struct Television: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var model: String
    var host: String
    var mac: String?

    static func decode(_ data: Data, host: String) throws -> Television {
        struct Response: Decodable {
            struct Device: Decodable {
                var id: String?
                var name: String?
                var modelName: String?
                var wifiMac: String?
                var type: String?
                var OS: String?
            }
            var device: Device
        }
        let device = try JSONDecoder().decode(Response.self, from: data).device
        guard device.OS == "Tizen", device.type?.contains("Samsung") == true else {
            throw RemoteError.message("This device is not a Samsung Tizen TV.")
        }
        return Television(id: device.id ?? device.wifiMac ?? host,
                          name: (device.name ?? "Samsung TV").replacingOccurrences(of: "&quot;", with: "\""),
                          model: device.modelName ?? "Samsung Tizen", host: host, mac: device.wifiMac)
    }
}

enum RemoteError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum TVKey: String, CaseIterable {
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT", select = "KEY_ENTER"
    case back = "KEY_RETURN", home = "KEY_HOME", settings = "KEY_MENU", source = "KEY_SOURCE"
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case play = "KEY_PLAY", pause = "KEY_PAUSE", rewind = "KEY_REWIND", forward = "KEY_FF"
    case channelUp = "KEY_CHUP", channelDown = "KEY_CHDOWN"
    // Recent models ignore KEY_POWEROFF over the network; KEY_POWER turns them off.
    case powerOff = "KEY_POWER"
}

struct TVApp: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var symbol: String
    // Probed against the TV; only identifiers whose metadata endpoint answers are shown.
    // Several services changed identifiers over the years, so both generations are listed.
    static let catalog = [
        TVApp(id: "111299001912", name: "YouTube", symbol: "play.rectangle.fill"),
        TVApp(id: "3201907018807", name: "Netflix", symbol: "film"),
        TVApp(id: "11101200001", name: "Netflix", symbol: "film"),
        TVApp(id: "3201910019365", name: "Prime Video", symbol: "play.tv"),
        TVApp(id: "3201512006785", name: "Prime Video", symbol: "play.tv"),
        TVApp(id: "3201901017640", name: "Disney+", symbol: "sparkles.tv"),
        TVApp(id: "3201807016597", name: "Apple TV", symbol: "appletv"),
        TVApp(id: "3201606009684", name: "Spotify", symbol: "music.note"),
        TVApp(id: "3201908019041", name: "Apple Music", symbol: "music.quarternote.3"),
        TVApp(id: "3201512006963", name: "Plex", symbol: "play.circle.fill"),
        TVApp(id: "3202203026841", name: "Twitch", symbol: "gamecontroller.fill"),
        TVApp(id: "3201511006428", name: "Rakuten TV", symbol: "film.stack"),
        TVApp(id: "3201611010983", name: "YouTube Kids", symbol: "play.rectangle.fill"),
        TVApp(id: "3202010022079", name: "Browser", symbol: "globe")
    ]
    static let defaultFavorites = ["111299001912", "3201907018807", "11101200001", "3201910019365",
                                   "3201512006785", "3201901017640", "3201606009684", "3201807016597"]
}

enum SamsungProtocol {
    static func socketURL(host: String, token: String?) -> URL? {
        var parts = URLComponents()
        parts.scheme = "wss"; parts.host = host; parts.port = 8002
        parts.path = "/api/v2/channels/samsung.remote.control"
        parts.queryItems = [URLQueryItem(name: "name", value: Data("Samsung Menu Remote".utf8).base64EncodedString())]
        if let token { parts.queryItems?.append(URLQueryItem(name: "token", value: token)) }
        return parts.url
    }

    static func command(_ key: TVKey) throws -> String {
        try json(["method": "ms.remote.control", "params": ["Cmd": "Click", "DataOfCmd": key.rawValue,
                  "Option": "false", "TypeOfRemote": "SendRemoteKey"]])
    }

    // Replaces the contents of the TV's open IME field with `text`.
    static func inputString(_ text: String) throws -> String {
        try json(["method": "ms.remote.control", "params": ["Cmd": Data(text.utf8).base64EncodedString(),
                  "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"]])
    }

    static func inputEnd() throws -> String {
        try json(["method": "ms.remote.control", "params": ["TypeOfRemote": "SendInputEnd"]])
    }

    // Some TVs ignore text until this broadcast precedes the first string of an IME session.
    static func textReceived() throws -> String {
        try json(["method": "ms.channel.emit", "params": ["event": "custom.remote.textReceived", "to": "broadcast"]])
    }

    static func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    static func wakePacket(mac: String) -> Data? {
        let parts = mac.split(separator: ":")
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6, parts.allSatisfy({ $0.count == 2 }) else { return nil }
        return Data([UInt8](repeating: 0xff, count: 6) + Array(repeating: bytes, count: 16).flatMap { $0 })
    }

    static func discoveredHost(reply: String) -> String? {
        let location = reply.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("location:") }
        guard let location, let colon = location.firstIndex(of: ":") else { return nil }
        let value = location[location.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return URL(string: value)?.host
    }
}
