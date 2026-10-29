import Foundation
import Darwin

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main struct Checks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(description: message) }
    }

    @MainActor static func main() async {
        do {
            try metadata()
            try powerState()
            try await standbyConnection()
            try pairingURL()
            try command()
            try text()
            try volume()
            try discovery()
            try wake()
            if let host = ProcessInfo.processInfo.environment["SAMSUNG_TEST_HOST"] {
                try await hardware(host: host)
            } else { print("SKIP hardware checks: set SAMSUNG_TEST_HOST to the paired TV IP.") }
            print("ALL CHECKS PASSED")
        } catch { print("FAIL: \(error)"); exit(1) }
    }

    static func metadata() throws {
        let data = Data(#"{"device":{"id":"uuid:example","name":"75&quot; QLED","modelName":"QE75Q74DATXXN","wifiMac":"00:11:22:33:44:55","type":"Samsung SmartTV","OS":"Tizen"}}"#.utf8)
        let tv = try Television.decode(data, host: "192.168.1.20")
        try require(tv.name == "75\" QLED" && tv.model == "QE75Q74DATXXN" && tv.id == "uuid:example", "TV metadata should decode Samsung's response and HTML-encoded name")
        var rejected = false
        do { _ = try Television.decode(Data(#"{"device":{"type":"Roku","OS":"Roku"}}"#.utf8), host: "192.168.1.21") }
        catch { rejected = true }
        try require(rejected, "Other manufacturers must not be presented as Samsung TVs")
        print("PASS device metadata and manufacturer validation")
    }

    static func powerState() throws {
        for (state, standby) in [("on", false), ("standby", true), ("STANDBY", true), ("unknown", false)] {
            let data = Data("{\"device\":{\"type\":\"Samsung SmartTV\",\"OS\":\"Tizen\",\"PowerState\":\"\(state)\"}}".utf8)
            let tv = try Television.decode(data, host: "192.168.1.20")
            try require(tv.inStandby == standby, "Only an explicit standby response should mark the TV off: \(state)")
        }
        let legacy = try Television.decode(Data(#"{"device":{"type":"Samsung SmartTV","OS":"Tizen"}}"#.utf8), host: "192.168.1.20")
        try require(legacy.powerState == nil && !legacy.inStandby, "Missing power state must preserve older TV support")
        let saved = Data(#"{"id":"tv","name":"TV","model":"QLED","host":"192.168.1.20"}"#.utf8)
        let restored = try JSONDecoder().decode(Television.self, from: saved)
        try require(restored.powerState == nil, "Existing saved TVs must still load without a power state")
        print("PASS standby, on, unknown and legacy power states")
    }

    @MainActor static func standbyConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = RemoteStorage(directory: directory)
        let tv = Television(id: "standby-test", name: "TV", model: "QLED", host: "192.0.2.1", powerState: "standby")
        try storage.saveTV(tv)
        try storage.saveToken("test-token", for: tv)
        let remote = Remote(storage: storage, inspect: { _ in tv })
        defer { remote.pause() }
        for _ in 0..<2 {
            remote.connect()
            for _ in 0..<100 {
                if !remote.busy { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try require(remote.poweredOff && !remote.connected && !remote.busy, "Reconnect to a standby TV must leave the UI off, not connected")
            try require(remote.volume == nil, "A standby TV must not retain a stale volume")
        }
        remote.connect(waking: true)
        try await Task.sleep(nanoseconds: 20_000_000)
        try require(remote.state == .connecting, "Wake must allow time for a standby TV to boot")
        remote.pause()

        // A response from a cancelled connection must not reopen its socket.
        var reply: CheckedContinuation<Television?, Never>?
        let cancelled = Remote(storage: storage, inspect: { _ in
            await withCheckedContinuation { reply = $0 }
        })
        defer { cancelled.pause() }
        cancelled.connect()
        for _ in 0..<100 {
            if reply != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let reply else { throw CheckFailure(description: "Power check did not start") }
        cancelled.pause()
        var on = tv
        on.powerState = "on"
        reply.resume(returning: on)
        try await Task.sleep(nanoseconds: 20_000_000)
        try require(cancelled.state == .offline("Disconnected. Select Reconnect when you need the remote."), "A stale power check must not restart a disconnected session")
        print("PASS standby reconnect, wake grace period and cancelled power checks")
    }

    static func pairingURL() throws {
        let token = "test+&token=value"
        guard let url = SamsungProtocol.socketURL(host: "192.168.1.20", token: token),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw CheckFailure(description: "Invalid pairing URL") }
        try require(parts.scheme == "wss" && parts.port == 8002, "Pairing must use secure Samsung port")
        try require(parts.queryItems?.first(where: { $0.name == "token" })?.value == token, "Token must survive URL encoding")
        let name = parts.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        try require(Data(base64Encoded: name) == Data("Samsung Menu Remote".utf8), "Pairing prompt must identify our app")
        try require(SamsungProtocol.socketURL(host: "192.168.1.20", token: nil)?.absoluteString.contains("token=") == false, "First pairing must omit token")
        print("PASS pairing URL and credential escaping")
    }

    static func volume() throws {
        let request = RenderingControl.request(host: "192.168.1.20", action: "SetVolume", arguments: [("DesiredVolume", "13")])
        try require(request?.url?.absoluteString == "http://192.168.1.20:9197/upnp/control/RenderingControl1", "Wrong renderer control URL")
        try require(request?.value(forHTTPHeaderField: "SOAPACTION") == "\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"", "Wrong SOAP action header")
        let body = request?.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        try require(body.contains("<u:SetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>13</DesiredVolume></u:SetVolume>"), "Wrong SetVolume body")
        try require(RenderingControl.value("CurrentVolume", in: "<s:Body><u:GetVolumeResponse><CurrentVolume>13</CurrentVolume></u:GetVolumeResponse>") == "13", "Volume must parse from the response")
        try require(RenderingControl.value("CurrentMute", in: "<x/>") == nil, "Missing values must be nil")
        print("PASS renderer volume request and response")
    }

    static func command() throws {
        let data = Data(try SamsungProtocol.command(.volumeDown).utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try require(json?["method"] as? String == "ms.remote.control", "Wrong command method")
        let params = json?["params"] as? [String: String]
        try require(params == ["Cmd": "Click", "DataOfCmd": "KEY_VOLDOWN", "Option": "false", "TypeOfRemote": "SendRemoteKey"], "Volume command must match the wire format verified on the real TV")
        print("PASS verified volume command wire format")
    }

    static func text() throws {
        func decode(_ payload: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] ?? [:]
        }
        let input = try decode(SamsungProtocol.inputString("café 1"))
        try require(input["method"] as? String == "ms.remote.control", "Text must use the remote control method")
        try require(input["params"] as? [String: String] == ["Cmd": Data("café 1".utf8).base64EncodedString(), "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"], "Text must be UTF-8 base64 SendInputString")
        let end = try decode(SamsungProtocol.inputEnd())
        try require(end["params"] as? [String: String] == ["TypeOfRemote": "SendInputEnd"], "Wrong input end command")
        let announce = try decode(SamsungProtocol.textReceived())
        try require(announce["method"] as? String == "ms.channel.emit" && announce["params"] as? [String: String] == ["event": "custom.remote.textReceived", "to": "broadcast"], "Wrong text announcement")
        print("PASS text input wire format")
    }

    static func discovery() throws {
        try require(SamsungProtocol.discoveredHost(reply: "HTTP/1.1 200 OK\r\nlOcAtIoN: http://192.168.1.20:9197/dmr\r\n") == "192.168.1.20", "Discovery must support mixed-case headers and device service ports")
        try require(SamsungProtocol.discoveredHost(reply: "HTTP/1.1 200 OK\r\nSERVER: Samsung\r\n") == nil, "Replies without a device location must be ignored")
        print("PASS SSDP header parsing")
    }

    static func wake() throws {
        guard let packet = SamsungProtocol.wakePacket(mac: "00:11:22:33:44:55") else { throw CheckFailure(description: "No wake packet") }
        try require(packet.count == 102 && packet.prefix(6) == Data(repeating: 0xff, count: 6), "Wrong Wake-on-LAN header")
        for offset in stride(from: 6, to: 102, by: 6) {
            try require(packet.subdata(in: offset..<(offset + 6)) == Data([0, 0x11, 0x22, 0x33, 0x44, 0x55]), "Wrong MAC repetition in wake packet")
        }
        for mac in ["garbage", "0:11:22:33:44:55", "GG:11:22:33:44:55"] {
            try require(SamsungProtocol.wakePacket(mac: mac) == nil, "Malformed MAC should be rejected")
        }
        print("PASS Wake-on-LAN packet and malformed MAC rejection")
    }

    @MainActor static func hardware(host: String) async throws {
        let direct = try await TVDiscovery.inspect(host: host)
        let found = await TVDiscovery.scan()
        try require(found.contains { $0.id == direct.id }, "Production discovery must find the same TV as direct API access")
        print("PASS live production discovery and device API: \(direct.model)")
        let remote = Remote()
        guard let tv = remote.television, tv.host == host, RemoteStorage().token(for: tv) != nil else {
            throw CheckFailure(description: "No saved pairing for the requested TV; hardware check will not request new pairing")
        }
        defer { remote.pause() }
        for attempt in 1...2 {
            remote.connect()
            for _ in 0..<60 {
                if remote.connected { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(remote.connected, "Production Swift client did not authenticate: \(remote.state.title)")
            // Wait through a full heartbeat interval on the first connection.
            if attempt == 1 {
                try await Task.sleep(nanoseconds: 6_000_000_000)
                try require(remote.connected, "Connection did not survive the production heartbeat")
            }
            remote.pause()
            try require(!remote.connected, "Disconnect must reset the session state")
        }
        print("PASS live production pairing reuse, heartbeat and reconnection; no keys sent")
    }
}
