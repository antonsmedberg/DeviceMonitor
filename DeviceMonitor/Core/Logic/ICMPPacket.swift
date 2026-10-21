import Foundation

/// Pure ICMPv4 echo helpers (RFC 792) with the RFC 1071 checksum.
nonisolated enum ICMPPacket {
    static let echoRequestType: UInt8 = 8
    static let echoReplyType: UInt8 = 0
    static let headerLength = 8

    static func checksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let bytes = [UInt8](data)
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }

    static func echoRequest(identifier: UInt16, sequence: UInt16, payload: Data) -> Data {
        var packet = Data(capacity: headerLength + payload.count)
        packet.append(echoRequestType)
        packet.append(0)
        packet.append(contentsOf: [0, 0])
        packet.append(UInt8(identifier >> 8))
        packet.append(UInt8(identifier & 0xFF))
        packet.append(UInt8(sequence >> 8))
        packet.append(UInt8(sequence & 0xFF))
        packet.append(payload)
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Accepts a datagram as returned by `SOCK_DGRAM`/`IPPROTO_ICMP` on Darwin, where the IPv4 header is included.
    static func isEchoReply(_ datagram: Data, identifier: UInt16, sequence: UInt16) -> Bool {
        let bytes = [UInt8](datagram)
        guard bytes.count >= headerLength else { return false }

        var offset = 0
        let version = bytes[0] >> 4
        if version == 4 {
            let headerLength = Int(bytes[0] & 0x0F) * 4
            guard headerLength >= 20, bytes.count >= headerLength + Self.headerLength else { return false }
            offset = headerLength
        }

        guard bytes[offset] == echoReplyType, bytes[offset + 1] == 0 else { return false }
        let replyIdentifier = UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5])
        let replySequence = UInt16(bytes[offset + 6]) << 8 | UInt16(bytes[offset + 7])
        return replyIdentifier == identifier && replySequence == sequence
    }
}
