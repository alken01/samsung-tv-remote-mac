import Foundation
import Darwin

struct TVDiscovery {
    static func inspect(host: String) async throws -> Television {
        guard !host.isEmpty, !host.contains("/"), !host.contains(":"), !host.contains(" "),
              let url = URL(string: "http://\(host):8001/api/v2/") else {
            throw RemoteError.message("Enter a TV IP address or local hostname.")
        }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 3))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RemoteError.message("The Samsung TV API did not respond.")
        }
        return try Television.decode(data, host: host)
    }

    static func scan() async -> [Television] {
        let hosts = await Task.detached(priority: .utility) { ssdpHosts() }.value
        return await withTaskGroup(of: Television?.self) { group in
            for host in hosts { group.addTask { try? await inspect(host: host) } }
            var found: [Television] = []
            for await tv in group {
                if let tv, !found.contains(where: { $0.id == tv.id }) { found.append(tv) }
            }
            return found.sorted { $0.name < $1.name }
        }
    }

    private static func localAddresses() -> [in_addr] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [in_addr] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let item = entry.pointee
            guard let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  item.ifa_flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0 else { continue }
            let name = String(cString: item.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            let value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            result.append(value)
        }
        return result
    }

    private static func ssdpHosts() -> Set<String> {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(1900).bigEndian
        destination.sin_addr.s_addr = inet_addr("239.255.255.250")
        // This TV advertises DIAL and MediaRenderer, but not RemoteControlReceiver.
        // Discover broadly, then validate every responder against Samsung's device API.
        let payload = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n"
        for var address in localAddresses() {
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &address, socklen_t(MemoryLayout<in_addr>.size))
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddress in
                    payload.withCString { bytes in
                        _ = sendto(fd, bytes, strlen(bytes), 0, sockAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
        var hosts = Set<String>()
        var bytes = [UInt8](repeating: 0, count: 8192)
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            let count = recv(fd, &bytes, bytes.count, 0)
            guard count > 0 else { continue }
            let reply = String(decoding: bytes.prefix(count), as: UTF8.self)
            if let host = SamsungProtocol.discoveredHost(reply: reply) { hosts.insert(host) }
            if hosts.count >= 64 { break }
        }
        return hosts
    }

    static func wake(mac: String) throws {
        guard let packet = SamsungProtocol.wakePacket(mac: mac) else {
            throw RemoteError.message("The TV has not supplied a valid network MAC address.")
        }
        var enabled: Int32 = 1
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(9).bigEndian
        destination.sin_addr.s_addr = INADDR_BROADCAST
        // Bind to the physical LAN so an active VPN cannot capture broadcasts.
        var countSent = 0
        for address in localAddresses() {
            var local = sockaddr_in()
            local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            local.sin_family = sa_family_t(AF_INET)
            local.sin_addr = address
            let wakeFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard wakeFD >= 0 else { continue }
            setsockopt(wakeFD, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size))
            let bound = withUnsafePointer(to: &local) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(wakeFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound == 0 {
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { target in
                        packet.withUnsafeBytes { buffer in
                            if sendto(wakeFD, buffer.baseAddress, buffer.count, 0, target, socklen_t(MemoryLayout<sockaddr_in>.size)) == buffer.count { countSent += 1 }
                        }
                    }
                }
            }
            close(wakeFD)
        }
        guard countSent > 0 else { throw RemoteError.message("Wake request could not reach your local network.") }
    }
}
