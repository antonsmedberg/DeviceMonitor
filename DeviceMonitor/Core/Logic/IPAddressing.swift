import Foundation
import Darwin

/// A strict IPv4 address value. Named to avoid clashing with `Network.IPv4Address`.
nonisolated struct IPv4Host: Sendable, Codable, Hashable, Comparable, CustomStringConvertible {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Accepts only canonical dotted quads: four octets, no empty parts, no leading zeros, each 0…255.
    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            if part.count > 1 && part.first == "0" { return nil }
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        rawValue = value
    }

    var octets: (UInt8, UInt8, UInt8, UInt8) {
        (
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        )
    }

    var description: String {
        let o = octets
        return "\(o.0).\(o.1).\(o.2).\(o.3)"
    }

    var isPrivate: Bool {
        let o = octets
        return o.0 == 10
            || (o.0 == 172 && (16...31).contains(o.1))
            || (o.0 == 192 && o.1 == 168)
    }

    var isLinkLocal: Bool {
        let o = octets
        return o.0 == 169 && o.1 == 254
    }

    var isLoopback: Bool { octets.0 == 127 }

    var isMulticast: Bool { (224...239).contains(octets.0) }

    static func < (lhs: IPv4Host, rhs: IPv4Host) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct IPv4Subnet: Sendable, Codable, Hashable, CustomStringConvertible {
    let network: IPv4Host
    let prefixLength: UInt8

    /// Networks shorter than /22 (more than 1,022 hosts) are refused for phone scans.
    static let maxScanPrefixLength: UInt8 = 22

    init(address: IPv4Host, prefixLength: UInt8) {
        let prefix = min(prefixLength, 32)
        network = IPv4Host(rawValue: address.rawValue & Self.mask(prefixLength: prefix))
        self.prefixLength = prefix
    }

    init?(address: IPv4Host, netmask: IPv4Host) {
        guard let prefix = Self.prefixLength(netmask: netmask.rawValue) else { return nil }
        self.init(address: address, prefixLength: prefix)
    }

    init?(cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let address = IPv4Host(String(parts[0])),
              let prefix = UInt8(parts[1]),
              prefix <= 32 else { return nil }
        self.init(address: address, prefixLength: prefix)
    }

    var netmask: IPv4Host { IPv4Host(rawValue: Self.mask(prefixLength: prefixLength)) }

    var broadcast: IPv4Host { IPv4Host(rawValue: network.rawValue | ~Self.mask(prefixLength: prefixLength)) }

    /// Usable host count (network and broadcast excluded); 0 for /31 and /32.
    var hostCount: Int {
        guard prefixLength <= 30 else { return 0 }
        return Int(1 << (32 - Int(prefixLength))) - 2
    }

    var isScannable: Bool { prefixLength >= Self.maxScanPrefixLength && prefixLength <= 30 }

    var description: String { "\(network)/\(prefixLength)" }

    func contains(_ address: IPv4Host) -> Bool {
        address.rawValue & Self.mask(prefixLength: prefixLength) == network.rawValue
    }

    /// Usable hosts in ascending order; empty when the prefix is longer than /30.
    func hosts() -> [IPv4Host] {
        guard prefixLength <= 30 else { return [] }
        let first = network.rawValue + 1
        let last = broadcast.rawValue - 1
        return (first...last).map { IPv4Host(rawValue: $0) }
    }

    static func mask(prefixLength: UInt8) -> UInt32 {
        if prefixLength == 0 { return 0 }
        if prefixLength >= 32 { return UInt32.max }
        return UInt32.max << (32 - UInt32(prefixLength))
    }

    /// Returns the prefix length for a contiguous netmask, or nil for a non-contiguous one.
    static func prefixLength(netmask: UInt32) -> UInt8? {
        let inverted = ~netmask
        guard (inverted &+ 1) & inverted == 0 else { return nil }
        return UInt8(netmask.nonzeroBitCount)
    }
}

/// A validated, normalized host entered by the user.
nonisolated struct HostInput: Sendable, Hashable {
    nonisolated enum Kind: String, Sendable, Hashable {
        case ipv4, ipv6, hostname
    }

    let normalized: String
    let kind: Kind

    init(normalized: String, kind: Kind) {
        self.normalized = normalized
        self.kind = kind
    }
}

nonisolated enum HostInputValidator {
    static let maxHostnameLength = 253

    static func validate(_ raw: String) -> Result<HostInput, DeviceMonitorError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidInput(field: "address", reason: "Enter an IP address or hostname."))
        }
        if let v4 = IPv4Host(trimmed) {
            return .success(HostInput(normalized: v4.description, kind: .ipv4))
        }
        if isValidIPv6(trimmed) {
            return .success(HostInput(normalized: normalizeIPv6(trimmed), kind: .ipv6))
        }
        if isValidHostname(trimmed) {
            return .success(HostInput(normalized: trimmed.lowercased(), kind: .hostname))
        }
        if trimmed.allSatisfy({ $0.isNumber || $0 == "." }) {
            return .failure(.invalidInput(field: "address", reason: "Enter a valid IPv4 address such as 192.168.1.10."))
        }
        if trimmed.contains(":") {
            return .failure(.invalidInput(field: "address", reason: "Enter a valid IPv6 address such as fe80::1."))
        }
        return .failure(.invalidInput(field: "address", reason: "Enter a valid IP address or hostname."))
    }

    static func isValidIPv6(_ raw: String) -> Bool {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("[") && candidate.hasSuffix("]") {
            candidate = String(candidate.dropFirst().dropLast())
        }
        if let percent = candidate.firstIndex(of: "%") {
            candidate = String(candidate[..<percent])
        }
        guard candidate.contains(":"), candidate.count <= 45 else { return false }
        var buffer = in6_addr()
        let result = candidate.withCString { pointer in
            inet_pton(AF_INET6, pointer, &buffer)
        }
        return result == 1
    }

    static func isValidHostname(_ raw: String) -> Bool {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.count <= maxHostnameLength else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy(isValidLabel) else { return false }
        if let last = labels.last, last.allSatisfy({ $0.isNumber }) { return false }
        return true
    }

    static func validatePort(_ raw: String) -> UInt16? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let port = UInt16(trimmed), port > 0 else { return nil }
        return port
    }

    static func normalizeIPv6(_ raw: String) -> String {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("[") && candidate.hasSuffix("]") {
            candidate = String(candidate.dropFirst().dropLast())
        }
        return candidate.lowercased()
    }

    private static func isValidLabel(_ label: Substring) -> Bool {
        guard (1...63).contains(label.count) else { return false }
        guard label.first != "-", label.last != "-" else { return false }
        return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
