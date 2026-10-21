import Foundation
import Network

/// The Bonjour service types the app browses. Must stay identical to `NSBonjourServices` in Info.plist.
nonisolated enum BonjourServiceCatalog {
    static let declaredTypes: [String] = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_airplay._tcp", "_raop._tcp",
        "_hap._tcp", "_homekit._tcp", "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_googlecast._tcp", "_spotify-connect._tcp", "_companion-link._tcp",
        "_device-info._tcp", "_workstation._tcp", "_rfb._tcp", "_sonos._tcp", "_hue._tcp", "_matter._tcp",
        "_apple-mobdev2._tcp", "_rdlink._tcp", "_daap._tcp", "_mqtt._tcp", "_nvstream._tcp",
    ]

    static func port(for type: String) -> UInt16? {
        switch type {
        case "_http._tcp": return 80
        case "_https._tcp": return 443
        case "_ssh._tcp", "_sftp-ssh._tcp": return 22
        case "_airplay._tcp": return 7000
        case "_raop._tcp": return 5000
        case "_ipp._tcp": return 631
        case "_ipps._tcp": return 631
        case "_printer._tcp", "_pdl-datastream._tcp": return 9100
        case "_smb._tcp": return 445
        case "_afpovertcp._tcp": return 548
        case "_googlecast._tcp": return 8009
        case "_rfb._tcp": return 5900
        case "_mqtt._tcp": return 1883
        case "_daap._tcp": return 3689
        case "_apple-mobdev2._tcp": return 62078
        default: return nil
        }
    }

    static func parseTXT(_ record: NWTXTRecord) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in record.dictionary {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty, trimmedKey.count <= 64 else { continue }
            result[trimmedKey] = String(value.prefix(255))
        }
        return result
    }
}
