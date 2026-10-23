import Foundation
import Darwin

final class TVTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == host, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}

@main struct Probe {
    static func main() async {
        guard CommandLine.arguments.count >= 3 else {
            print("Usage: probe TV_IP TOKEN_FILE [KEY_CODE]"); return
        }
        let host = CommandLine.arguments[1]
        let tokenURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let existing = try? String(contentsOf: tokenURL, encoding: .utf8)
        var url = URLComponents()
        url.scheme = "wss"; url.host = host; url.port = 8002
        url.path = "/api/v2/channels/samsung.remote.control"
        url.queryItems = [URLQueryItem(name: "name", value: Data("Samsung Menu Remote".utf8).base64EncodedString())]
        if let existing { url.queryItems?.append(URLQueryItem(name: "token", value: existing)) }
        let trust = TVTrust(host: host)
        let session = URLSession(configuration: .ephemeral, delegate: trust, delegateQueue: nil)
        let socket = session.webSocketTask(with: url.url!)
        socket.resume()
        print(existing == nil ? "PAIRING REQUEST SENT. Accept Allow on your TV." : "RECONNECTING WITH SAVED TOKEN.")
        fflush(stdout)
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            print("TIMEOUT: no confirmed pairing within 90 seconds.")
            socket.cancel(with: .goingAway, reason: nil)
            exit(2)
        }
        do {
            while true {
                let message = try await socket.receive()
                let bytes: Data
                switch message { case .string(let text): bytes = Data(text.utf8)
                    case .data(let data): bytes = data
                    @unknown default: continue }
                guard let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { continue }
                let name = event["event"] as? String ?? "unknown"
                print("EVENT: \(name)"); fflush(stdout)
                if name == "ms.channel.unauthorized" { throw NSError(domain: "Pairing", code: 1, userInfo: [NSLocalizedDescriptionKey: "TV denied pairing"]) }
                guard name == "ms.channel.connect" else { continue }
                if let data = event["data"] as? [String: Any], let raw = data["token"] {
                    let token = String(describing: raw)
                    try token.write(to: tokenURL, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
                    print("TOKEN SAVED privately; value omitted.")
                }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    socket.sendPing { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                print("PASS: authenticated Swift WebSocket connection and ping.")
                if CommandLine.arguments.count > 3 {
                    let key = CommandLine.arguments[3]
                    guard ["KEY_INFO", "KEY_RETURN", "KEY_VOLDOWN", "KEY_VOLUP"].contains(key) else { throw NSError(domain: "Probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Only INFO, RETURN and volume steps permitted in this probe"]) }
                    let body: [String: Any] = ["method": "ms.remote.control", "params": ["Cmd": "Click", "DataOfCmd": key, "Option": "false", "TypeOfRemote": "SendRemoteKey"]]
                    let payload = try JSONSerialization.data(withJSONObject: body)
                    try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
                    print("SENT: \(key). Visual confirmation is needed; send success alone does not prove TV behavior.")
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                timeout.cancel()
                socket.cancel(with: .normalClosure, reason: nil)
                session.invalidateAndCancel()
                return
            }
        } catch {
            timeout.cancel()
            print("FAIL: \(error.localizedDescription)")
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            exit(1)
        }
    }
}
