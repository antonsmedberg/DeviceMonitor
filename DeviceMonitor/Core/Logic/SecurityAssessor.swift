import Foundation

nonisolated struct SecurityFinding: Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let advice: String
    let severity: PortRisk
    let deviceID: UUID?

    init(id: String, title: String, detail: String, advice: String, severity: PortRisk, deviceID: UUID?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.advice = advice
        self.severity = severity
        self.deviceID = deviceID
    }
}

/// One capped deduction behind the score: the points a category lost, out of its maximum.
nonisolated struct SecurityFactor: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: String, Sendable, Hashable {
        case services, newcomers, router
    }

    let kind: Kind
    let pointsLost: Int
    let maximum: Int

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .services: return "Open services"
        case .newcomers: return "Unknown devices"
        case .router: return "Router stability"
        }
    }

    init(kind: Kind, pointsLost: Int, maximum: Int) {
        self.kind = kind
        self.pointsLost = pointsLost
        self.maximum = maximum
    }
}

nonisolated struct SecurityScore: Sendable, Hashable {
    let value: Int
    let findings: [SecurityFinding]
    /// The deductions that explain `value`, in display order.
    let factors: [SecurityFactor]

    init(value: Int, findings: [SecurityFinding], factors: [SecurityFactor] = []) {
        self.value = min(max(value, 0), 100)
        self.findings = findings
        self.factors = factors
    }

    var grade: String {
        switch value {
        case 90...: return "Excellent"
        case 75..<90: return "Good"
        case 50..<75: return "Needs attention"
        default: return "At risk"
        }
    }
}

/// Port knowledge and a transparent 0–100 network score.
nonisolated enum SecurityAssessor {
    static let commonPorts: [UInt16] = [
        21, 22, 23, 25, 53, 80, 110, 139, 143, 443, 445, 548, 554, 631, 1883, 3389, 5000, 5900, 8000, 8080, 8443, 9100, 49152, 62078,
    ]

    static func risk(port: UInt16) -> PortRisk {
        switch port {
        case 21, 23, 139, 445, 3389, 5900, 110, 143:
            return .high
        case 25, 53, 80, 548, 554, 1883, 5000, 8000, 8080, 49152, 161, 1900:
            return .medium
        default:
            return .low
        }
    }

    static func serviceName(port: UInt16) -> String {
        switch port {
        case 21: return "FTP"
        case 22: return "SSH"
        case 23: return "Telnet"
        case 25: return "SMTP"
        case 53: return "DNS"
        case 80: return "HTTP"
        case 110: return "POP3"
        case 139: return "NetBIOS"
        case 143: return "IMAP"
        case 161: return "SNMP"
        case 443: return "HTTPS"
        case 445: return "SMB"
        case 548: return "AFP"
        case 554: return "RTSP"
        case 631: return "IPP printing"
        case 1883: return "MQTT"
        case 1900: return "UPnP"
        case 3389: return "Remote Desktop"
        case 5000: return "UPnP / NAS web"
        case 5900: return "VNC"
        case 7000: return "AirPlay"
        case 8000: return "HTTP alt"
        case 8080: return "HTTP proxy"
        case 8443: return "HTTPS alt"
        case 9100: return "Raw printing"
        case 49152: return "UPnP control"
        case 62078: return "iOS sync"
        default: return "Port \(port)"
        }
    }

    static func advice(port: UInt16) -> String {
        switch port {
        case 21: return "FTP sends passwords in plain text. Prefer SFTP and disable FTP if you do not use it."
        case 23: return "Telnet is unencrypted and often ships with default passwords. Disable it or replace it with SSH."
        case 139, 445: return "File sharing is exposed. Make sure it needs a strong password and is not reachable from the internet."
        case 3389: return "Remote Desktop is a common attack target. Use a VPN or disable it when not needed."
        case 5900: return "VNC is often unencrypted. Use a strong password and keep it off the internet."
        case 110, 143: return "Plain-text mail protocols can leak credentials. Prefer their TLS variants."
        case 80, 8000, 8080: return "A web interface without HTTPS. Change default credentials and prefer the HTTPS port if available."
        case 1883: return "MQTT without TLS. Require authentication and keep the broker on the local network."
        case 53: return "A DNS server is running. Fine for routers; unexpected on other devices."
        case 554: return "Camera stream exposed. Check that it requires a password."
        case 1900, 49152, 5000: return "UPnP can open router ports automatically. Disable it on the router if you do not need it."
        case 22: return "SSH is encrypted. Use keys instead of passwords where possible."
        case 443, 8443: return "Encrypted web interface. Keep its firmware updated."
        default: return "Review whether this service needs to be reachable."
        }
    }

    /// DNS and the admin web interface are what a router is for, so on the gateway they are not findings.
    private static let expectedGatewayPorts: Set<UInt16> = [53, 80, 443, 8443]

    /// `risk(port:)`, except that the router's own DNS and admin web ports are low risk.
    static func risk(port: UInt16, isGateway: Bool) -> PortRisk {
        isGateway && expectedGatewayPorts.contains(port) ? .low : risk(port: port)
    }

    /// Transparent score: 100 minus capped deductions for risky services, untrusted newcomers and an unstable gateway.
    static func score(devices: [DeviceSnapshot], now: Date) -> SecurityScore {
        var findings: [SecurityFinding] = []
        var highPenalty = 0
        var mediumPenalty = 0

        for device in devices {
            for port in device.openPorts.sorted() {
                switch risk(port: port, isGateway: device.isGateway) {
                case .high:
                    highPenalty += 15
                    findings.append(SecurityFinding(
                        id: "port-\(device.id.uuidString)-\(port)",
                        title: "\(serviceName(port: port)) open on \(device.displayName)",
                        detail: "Port \(port) answered a connection attempt.",
                        advice: advice(port: port),
                        severity: .high,
                        deviceID: device.id
                    ))
                case .medium:
                    mediumPenalty += 5
                    findings.append(SecurityFinding(
                        id: "port-\(device.id.uuidString)-\(port)",
                        title: "\(serviceName(port: port)) open on \(device.displayName)",
                        detail: "Port \(port) answered a connection attempt.",
                        advice: advice(port: port),
                        severity: .medium,
                        deviceID: device.id
                    ))
                case .low:
                    break
                }
            }
        }

        let untrustedNew = devices.filter { !$0.isTrusted && !$0.isUserAdded && $0.isNew(now: now) }
        var newcomerPenalty = 0
        if !untrustedNew.isEmpty {
            newcomerPenalty = 10
            findings.append(SecurityFinding(
                id: "untrusted-new",
                title: untrustedNew.count == 1 ? "1 new device you have not trusted" : "\(untrustedNew.count) new devices you have not trusted",
                detail: untrustedNew.prefix(3).map(\.displayName).joined(separator: ", "),
                advice: "Open each device and mark it trusted if you recognise it. Unknown devices may mean your Wi‑Fi password is shared.",
                severity: .medium,
                deviceID: untrustedNew.count == 1 ? untrustedNew[0].id : nil
            ))
        }

        var gatewayPenalty = 0
        if let gateway = devices.first(where: { $0.isGateway }), gateway.state == .degraded || gateway.state == .offline {
            gatewayPenalty = 10
            findings.append(SecurityFinding(
                id: "gateway-unstable",
                title: "Your router is not answering reliably",
                detail: "\(gateway.displayName) is \(gateway.state.title.lowercased()).",
                advice: "Restart the router if this persists; all other device statuses are unreliable while it is down.",
                severity: .medium,
                deviceID: gateway.id
            ))
        }

        let servicesPenalty = min(highPenalty, 45) + min(mediumPenalty, 20)
        let total = 100 - servicesPenalty - newcomerPenalty - gatewayPenalty
        let ordered = findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return rank(lhs.severity) < rank(rhs.severity) }
            return lhs.title < rhs.title
        }
        let factors = [
            SecurityFactor(kind: .services, pointsLost: servicesPenalty, maximum: 45 + 20),
            SecurityFactor(kind: .newcomers, pointsLost: newcomerPenalty, maximum: 10),
            SecurityFactor(kind: .router, pointsLost: gatewayPenalty, maximum: 10),
        ]
        return SecurityScore(value: total, findings: ordered, factors: factors)
    }

    private static func rank(_ risk: PortRisk) -> Int {
        switch risk {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
