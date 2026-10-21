import Foundation

nonisolated struct MACAddress: Sendable, Codable, Hashable, CustomStringConvertible {
    let bytes: [UInt8]

    /// Accepts `AA:BB:CC:DD:EE:FF`, `aa-bb-cc-dd-ee-ff`, `aabb.ccdd.eeff` and `aabbccddeeff`.
    init?(_ string: String) {
        let cleaned = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard cleaned.count == 12, cleaned.allSatisfy(\.isHexDigit) else { return nil }
        var parsed: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let value = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            parsed.append(value)
            index = next
        }
        bytes = parsed
    }

    init?(bytes: [UInt8]) {
        guard bytes.count == 6 else { return nil }
        self.bytes = bytes
    }

    var description: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Randomised (private) addresses carry no vendor information.
    var isLocallyAdministered: Bool {
        (bytes[0] & 0x02) != 0
    }

    var ouiPrefix: String {
        bytes.prefix(3).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

nonisolated enum WakeOnLAN {
    /// 6 × 0xFF followed by the MAC repeated 16 times (102 bytes).
    static func magicPacket(for mac: MACAddress) -> Data {
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: mac.bytes)
        }
        return packet
    }
}
