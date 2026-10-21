import Foundation
import CryptoKit

/// Stable device identity so nicknames, notes and tags survive IP changes.
///
/// Priority: globally administered MAC → hostname → Bonjour name → address.
nonisolated enum DeviceIdentity {
    static func key(macAddress: String?, hostname: String?, bonjourName: String?, host: String) -> String {
        if let macAddress, let mac = MACAddress(macAddress), !mac.isLocallyAdministered {
            return "mac:\(mac.description)"
        }
        if let hostname = normalizedHostname(hostname) {
            return "host:\(hostname)"
        }
        if let bonjour = bonjourIdentity(bonjourName) {
            if let mac = bonjour.mac {
                return "mac:\(mac.description)"
            }
            return "bonjour:\(bonjour.name)"
        }
        return "ip:\(host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    /// How strongly a key identifies a device, in the same order as `key(...)`: MAC, hostname,
    /// Bonjour name, then address. Empty keys (rows migrated from 1.0) are weakest.
    static func strength(of key: String) -> Int {
        if key.hasPrefix("mac:") { return 3 }
        if key.hasPrefix("host:") { return 2 }
        if key.hasPrefix("bonjour:") { return 1 }
        return 0
    }

    /// AirPlay audio (RAOP) and some speakers name their service `<MAC>@<name>`, while the same
    /// device's other services use just `<name>`. The MAC is the stronger identity, and the part
    /// after `@` matches the sibling services, so both collapse to one device.
    static func bonjourIdentity(_ serviceName: String?) -> (mac: MACAddress?, name: String)? {
        guard let trimmed = serviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if let separator = trimmed.firstIndex(of: "@"), let mac = MACAddress(String(trimmed[..<separator])) {
            let rest = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            return (mac.isLocallyAdministered ? nil : mac, rest.isEmpty ? trimmed.lowercased() : rest.lowercased())
        }
        return (nil, trimmed.lowercased())
    }

    /// Lowercased, without trailing dot or `.local` suffix; nil when empty.
    static func normalizedHostname(_ hostname: String?) -> String? {
        guard var value = hostname?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        while value.hasSuffix(".") { value.removeLast() }
        if value.hasSuffix(".local") { value.removeLast(".local".count) }
        return value.isEmpty ? nil : value
    }

    /// Deterministic UUID (SHA-256 based, RFC 4122 version 5 bits) for an identity key.
    static func uuid(forKey key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Deterministic value in 0..<1 derived from the UUID, used for scheduling jitter.
    static func jitterFraction(for id: UUID) -> Double {
        let u = id.uuid
        let value = (UInt32(u.0) << 24) | (UInt32(u.1) << 16) | (UInt32(u.2) << 8) | UInt32(u.3)
        return Double(value) / 4_294_967_296
    }
}
