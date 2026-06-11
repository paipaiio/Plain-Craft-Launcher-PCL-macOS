import Foundation

#if canImport(Darwin)
import Darwin
#endif

struct MinecraftLANWorld: Identifiable, Hashable, Sendable {
    let host: String
    let port: Int
    let motd: String
    let discoveredAt: Date

    var id: String {
        "\(host):\(port):\(motd)"
    }

    var address: String {
        "\(host):\(port)"
    }
}

enum MinecraftLANDiscoveryService {
    private static let multicastAddress = "224.0.2.60"
    private static let multicastPort: UInt16 = 4445

    static func parseAnnouncement(_ message: String, host: String, discoveredAt: Date = Date()) -> MinecraftLANWorld? {
        guard let motd = message.minecraftLANValue(named: "MOTD")?.trimmed,
              let portText = message.minecraftLANValue(named: "AD")?.trimmed,
              let port = Int(portText),
              (1...65_535).contains(port) else {
            return nil
        }
        return MinecraftLANWorld(
            host: host,
            port: port,
            motd: motd.nonEmpty ?? "Minecraft LAN World",
            discoveredAt: discoveredAt
        )
    }

    static func scan(timeout: TimeInterval = 3.0) -> [MinecraftLANWorld] {
        #if canImport(Darwin)
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return [] }
        defer { close(socketFD) }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var bindAddress = sockaddr_in()
        bindAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddress.sin_family = sa_family_t(AF_INET)
        bindAddress.sin_port = multicastPort.bigEndian
        bindAddress.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &bindAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return [] }

        var membership = ip_mreq()
        guard inet_pton(AF_INET, multicastAddress, &membership.imr_multiaddr) == 1 else { return [] }
        membership.imr_interface = in_addr(s_addr: INADDR_ANY)
        setsockopt(socketFD, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size))

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))

        let deadline = Date().addingTimeInterval(max(timeout, 0.25))
        var worldsByAddress: [String: MinecraftLANWorld] = [:]

        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 2048)
            var sender = sockaddr_in()
            var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return withUnsafeMutablePointer(to: &sender) { senderPointer in
                    senderPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        recvfrom(socketFD, baseAddress, rawBuffer.count, 0, sockaddrPointer, &senderLength)
                    }
                }
            }
            guard count > 0 else { continue }
            let data = Data(buffer.prefix(count))
            guard let message = String(data: data, encoding: .utf8),
                  let host = ipv4String(from: sender),
                  let world = parseAnnouncement(message, host: host) else {
                continue
            }
            worldsByAddress[world.address] = world
        }

        return worldsByAddress.values.sorted { left, right in
            let motdCompare = left.motd.localizedStandardCompare(right.motd)
            if motdCompare != .orderedSame {
                return motdCompare == .orderedAscending
            }
            return left.address.localizedStandardCompare(right.address) == .orderedAscending
        }
        #else
        return []
        #endif
    }

    #if canImport(Darwin)
    private static func ipv4String(from address: sockaddr_in) -> String? {
        var address = address.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self)
        return value == "0.0.0.0" ? nil : value
    }
    #endif
}

private extension String {
    func minecraftLANValue(named name: String) -> String? {
        guard let start = range(of: "[\(name)]"),
              let end = range(of: "[/\(name)]", range: start.upperBound..<endIndex) else {
            return nil
        }
        return String(self[start.upperBound..<end.lowerBound])
    }
}
