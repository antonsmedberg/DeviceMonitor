import Foundation

/// Infers a device kind, vendor and name from Bonjour services, open ports and hostnames.
nonisolated enum DeviceClassifier {
    static func kind(services: [DiscoveredService], openPorts: [UInt16], hostname: String?, vendor: String?, isGateway: Bool) -> DeviceKind {
        if isGateway { return .router }

        if let modelKind = kind(fromModelHints: services) { return modelKind }

        let types = Set(services.map(\.type))
        if let serviceKind = kind(fromServiceTypes: types) { return serviceKind }

        if let hostname = DeviceIdentity.normalizedHostname(hostname), let hostKind = kind(fromHostname: hostname) {
            return hostKind
        }

        if let vendor, let vendorKind = kind(fromVendor: vendor.lowercased()) { return vendorKind }

        // Every modern Apple device advertises these, so they only decide when nothing else did.
        if types.contains("_companion-link._tcp") || types.contains("_rdlink._tcp") { return .phone }

        return kind(fromPorts: Set(openPorts))
    }

    static func vendor(from services: [DiscoveredService], hostname: String?) -> String? {
        for service in services {
            for key in ["manufacturer", "vendor", "ty", "md", "model", "am", "usb_MFG"] {
                if let value = service.txt[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    return cleanedVendor(value)
                }
            }
        }
        guard let hostname = DeviceIdentity.normalizedHostname(hostname) else { return nil }
        for (needle, name) in vendorHostnameHints where hostnameMatches(hostname, needle: needle) {
            return name
        }
        return nil
    }

    /// Hostname needles are matched by whole label when they are short, so "annas-iphone" is not a NAS
    /// and "shuey-pc" is not a Hue bridge: three-letter needles must equal a label or be followed only by
    /// digits ("nas01"), four-letter needles must start a label ("ipadpro"), longer or hyphenated needles
    /// may appear anywhere ("living-room-tv", "synologynas").
    static func hostnameMatches(_ hostname: String, needle: String) -> Bool {
        if needle.count >= 5 || needle.contains("-") {
            return hostname.contains(needle)
        }
        let labels = hostname.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return labels.contains { label in
            guard label.hasPrefix(needle) else { return false }
            let rest = label.dropFirst(needle.count)
            return rest.isEmpty || needle.count >= 4 || rest.allSatisfy(\.isNumber)
        }
    }

    /// A friendly Bonjour name first, then the prettified hostname, then "Device N" from the last
    /// IPv4 octet, then the address itself.
    static func suggestedName(from services: [DiscoveredService], hostname: String?, host: String) -> String {
        for service in services {
            if let name = friendlyName(service) { return name }
        }
        if let hostname = DeviceIdentity.normalizedHostname(hostname) {
            return prettified(hostname)
        }
        if let v4 = IPv4Host(host) {
            return "Device \(v4.octets.3)"
        }
        return host
    }

    // MARK: - Rules

    private static func kind(fromModelHints services: [DiscoveredService]) -> DeviceKind? {
        for service in services {
            for key in ["model", "md", "ty", "am"] {
                guard let value = service.txt[key]?.lowercased() else { continue }
                if value.contains("appletv") || value.contains("apple tv") || value.contains("chromecast") || value.contains("shield") { return .tv }
                if value.contains("homepod") || value.contains("audioaccessory") { return .hub }
                if value.contains("iphone") { return .phone }
                if value.contains("ipad") { return .tablet }
                if value.contains("watch") { return .watch }
                if value.contains("macbook") || value.contains("imac") || value.contains("macmini") || value.contains("mac mini") || value.contains("macpro") || value.contains("macstudio") { return .computer }
                // Macs since 2022 report generic model identifiers such as "Mac14,2".
                if value.hasPrefix("mac") { return .computer }
                if value.contains("printer") || value.contains("laserjet") || value.contains("officejet") || value.contains("deskjet") { return .printer }
                if value.contains("sonos") || value.contains("speaker") { return .speaker }
                if value.contains("camera") || value.contains("doorbell") { return .camera }
                if value.contains("synology") || value.contains("diskstation") || value.contains("qnap") { return .nas }
                if value.contains("playstation") || value.contains("xbox") || value.contains("nintendo") { return .console }
                if value.contains("bridge") || value.contains("hub") { return .hub }
            }
        }
        return nil
    }

    private static func kind(fromServiceTypes types: Set<String>) -> DeviceKind? {
        if types.contains("_ipp._tcp") || types.contains("_ipps._tcp") || types.contains("_printer._tcp") || types.contains("_pdl-datastream._tcp") { return .printer }
        if types.contains("_googlecast._tcp") || types.contains("_nvstream._tcp") { return .tv }
        if types.contains("_sonos._tcp") || types.contains("_spotify-connect._tcp") { return .speaker }
        if types.contains("_raop._tcp") && !types.contains("_companion-link._tcp") { return .speaker }
        if types.contains("_airplay._tcp") { return .tv }
        if types.contains("_hue._tcp") || types.contains("_mqtt._tcp") { return .hub }
        if types.contains("_hap._tcp") || types.contains("_homekit._tcp") || types.contains("_matter._tcp") { return .iot }
        if types.contains("_apple-mobdev2._tcp") { return .phone }
        if types.contains("_smb._tcp") && (types.contains("_afpovertcp._tcp") || types.contains("_http._tcp")) && !types.contains("_rfb._tcp") && !types.contains("_ssh._tcp") { return .nas }
        if types.contains("_rfb._tcp") || types.contains("_workstation._tcp") || types.contains("_ssh._tcp") || types.contains("_sftp-ssh._tcp") || types.contains("_daap._tcp") { return .computer }
        return nil
    }

    private static func kind(fromHostname hostname: String) -> DeviceKind? {
        for (needles, kind) in hostnameRules {
            for needle in needles where hostnameMatches(hostname, needle: needle) {
                return kind
            }
        }
        return nil
    }

    private static func kind(fromVendor vendor: String) -> DeviceKind? {
        if vendor.contains("synology") || vendor.contains("qnap") || vendor.contains("western digital") { return .nas }
        if vendor.contains("brother") || vendor.contains("epson") || vendor.contains("canon") || vendor.contains("hewlett") || vendor.contains("hp inc") { return .printer }
        if vendor.contains("sonos") || vendor.contains("bose") { return .speaker }
        if vendor.contains("ubiquiti") || vendor.contains("netgear") || vendor.contains("tp-link") || vendor.contains("asus") || vendor.contains("avm") || vendor.contains("mikrotik") { return .router }
        if vendor.contains("philips") || vendor.contains("signify") { return .hub }
        if vendor.contains("espressif") || vendor.contains("shelly") || vendor.contains("tuya") { return .iot }
        if vendor.contains("samsung") || vendor.contains("lg electronics") || vendor.contains("roku") { return .tv }
        if vendor.contains("sony interactive") || vendor.contains("microsoft") || vendor.contains("nintendo") { return .console }
        return nil
    }

    private static func kind(fromPorts ports: Set<UInt16>) -> DeviceKind {
        if ports.contains(9100) || ports.contains(631) || ports.contains(515) { return .printer }
        if ports.contains(554) || ports.contains(8554) { return .camera }
        if ports.contains(62078) { return .phone }
        if ports.contains(3389) { return .computer }
        if (ports.contains(5000) || ports.contains(5001)) && ports.contains(445) { return .nas }
        if ports.contains(8009) || ports.contains(7000) { return .tv }
        if ports.contains(1883) { return .hub }
        if ports.contains(22) && ports.contains(445) { return .computer }
        if ports.contains(23) && !ports.contains(22) { return .iot }
        if ports.contains(22) { return .computer }
        return .unknown
    }

    private static let hostnameRules: [([String], DeviceKind)] = [
        (["router", "gateway", "fritz", "unifi", "udm", "asus", "netgear", "tp-link", "tplink", "openwrt", "pfsense", "edgerouter", "mikrotik", "orbi", "eero", "velop"], .router),
        (["printer", "brother", "epson", "canon", "laserjet", "officejet", "deskjet", "hp-", "hpprint"], .printer),
        (["nas", "synology", "diskstation", "qnap", "truenas", "unraid", "freenas"], .nas),
        (["iphone"], .phone),
        (["ipad"], .tablet),
        (["watch"], .watch),
        (["macbook", "imac", "mac-mini", "macmini", "mac-studio", "macpro", "desktop", "laptop", "thinkpad", "workstation", "-pc", "pc-"], .computer),
        (["appletv", "apple-tv", "roku", "firetv", "fire-tv", "chromecast", "shield", "bravia", "smarttv", "smart-tv", "-tv", "tv-"], .tv),
        (["cam", "camera", "ring-", "doorbell", "nest-cam", "reolink", "hikvision", "dahua", "wyze"], .camera),
        (["sonos", "homepod", "echo-", "alexa", "speaker", "bose"], .speaker),
        (["hue", "bridge", "homebridge", "home-assistant", "homeassistant", "hubitat", "smartthings", "hub"], .hub),
        (["esp", "tasmota", "shelly", "plug", "bulb", "thermostat", "sensor", "sonoff", "tuya", "nest", "wemo", "roomba", "robot"], .iot),
        (["xbox", "playstation", "ps5", "ps4", "nintendo", "switch"], .console),
    ]

    private static let vendorHostnameHints: [(String, String)] = [
        ("synology", "Synology"), ("diskstation", "Synology"), ("qnap", "QNAP"), ("fritz", "AVM"),
        ("unifi", "Ubiquiti"), ("udm", "Ubiquiti"), ("netgear", "Netgear"), ("tp-link", "TP-Link"),
        ("asus", "ASUS"), ("brother", "Brother"), ("epson", "Epson"), ("canon", "Canon"), ("hp-", "HP"),
        ("sonos", "Sonos"), ("roku", "Roku"), ("shelly", "Shelly"), ("tasmota", "Tasmota"), ("philips", "Philips"),
        ("hue", "Philips Hue"), ("samsung", "Samsung"), ("xbox", "Microsoft"), ("playstation", "Sony"),
    ]

    private static func cleanedVendor(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 40 { return String(trimmed.prefix(40)) }
        return trimmed
    }

    /// Service types whose instance names are identifiers, never a name someone chose: Wi‑Fi sync
    /// uses `<MAC>@<IPv6 address>` and Matter uses fabric and node IDs.
    private static let identifierServiceTypes: Set<String> = ["_apple-mobdev2._tcp", "_matter._tcp"]

    /// AirPlay, RAOP and Sonos name services `<id>@<Room>`, so only the part after the last `@`
    /// counts, and `_workstation._tcp` appends ` [<MAC>]`, which is dropped. Cast devices put their
    /// friendly name in the `fn` TXT key and a hex id after a dash in the instance name.
    /// Identifier services, empty names and generic `device-…` names are not friendly.
    private static func friendlyName(_ service: DiscoveredService) -> String? {
        guard !identifierServiceTypes.contains(service.type) else { return nil }
        if let castName = service.txt["fn"]?.trimmingCharacters(in: .whitespacesAndNewlines), !castName.isEmpty {
            return castName
        }
        var serviceName = service.name
        if let dash = serviceName.lastIndex(of: "-"), serviceName.distance(from: dash, to: serviceName.endIndex) > 16,
           serviceName[serviceName.index(after: dash)...].allSatisfy(\.isHexDigit) {
            serviceName = String(serviceName[..<dash])
        }
        var room = Substring(serviceName)
        if let separator = serviceName.lastIndex(of: "@") {
            room = serviceName[serviceName.index(after: separator)...]
        }
        if room.hasSuffix("]"), let bracket = room.range(of: " [", options: .backwards) {
            room = room[..<bracket.lowerBound]
        }
        let name = room.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.lowercased().hasPrefix("device-") else { return nil }
        return name
    }

    private static func prettified(_ hostname: String) -> String {
        let base = hostname.split(separator: ".").first.map(String.init) ?? hostname
        return base
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
