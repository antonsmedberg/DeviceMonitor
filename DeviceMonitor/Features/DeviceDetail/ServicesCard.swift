import SwiftUI

/// Open services from the last port scan, riskiest first, each with its risk word and, when risky, the advice
/// under it; then the services the device advertises over Bonjour.
struct ServicesCard: View {
    private let ports: [PortScanResult]
    private let services: [DiscoveredService]
    private let isScanning: Bool
    private let onRescan: () -> Void

    @Environment(\.displayScale) private var displayScale

    /// The text column: a 42 pt thumbnail and 12 pt.
    private static let textLeading = DSLayout.thumbnailService + DSLayout.space12

    init(ports: [PortScanResult], services: [DiscoveredService], isScanning: Bool, onRescan: @escaping () -> Void) {
        self.ports = ports
        self.services = services
        self.isScanning = isScanning
        self.onRescan = onRescan
    }

    /// High risk first, then medium, then low, each by port.
    private var open: [PortScanResult] {
        ports.filter(\.isOpen).sorted { lhs, rhs in
            let lhsRank = Self.rank(lhs.risk)
            let rhsRank = Self.rank(rhs.risk)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            return lhs.port < rhs.port
        }
    }

    var body: some View {
        let open = self.open

        VStack(alignment: .leading, spacing: 0) {
            DSTitleRow("Open services", qualifier: ports.isEmpty ? nil : "(\(open.count))") {
                if !ports.isEmpty {
                    DSLink("Rescan", accessibilityLabel: "Rescan ports", action: onRescan)
                        .disabled(isScanning)
                        .accessibilityIdentifier("detail.rescanPorts")
                }
            }
            if ports.isEmpty {
                message("Use Scan Ports above to check which services this device exposes. It takes a few seconds and only touches common ports.")
            } else if open.isEmpty {
                message("No common services are open. Checked \(ports.count) ports.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(open.enumerated()), id: \.element.id) { index, result in
                        portRow(result, isLast: index == open.count - 1)
                    }
                }
            }
            if !services.isEmpty {
                DSListHeader("Advertised on the network")
                    .padding(.top, DSLayout.space16)
                VStack(spacing: 0) {
                    ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                        serviceRow(service, isLast: index == services.count - 1)
                    }
                }
                .padding(.top, DSLayout.space4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.servicesCard")
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(DSTypography.body)
            .foregroundStyle(DSColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DSLayout.space12)
    }

    /// A 66 pt row: the service's glyph on a 42 pt render with a risk badge for medium and high risk, the
    /// service over "445 │ TCP │ File sharing", and the risk word. Advice follows under a risky row.
    private func portRow(_ result: PortScanResult, isLast: Bool) -> some View {
        let service = Self.service(port: result.port)
        let tone = DSTone.forRisk(result.risk)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DSLayout.space12) {
                DSThumbnail(
                    systemImage: service.glyph,
                    size: DSLayout.thumbnailService,
                    badge: result.risk == .low ? nil : .risk(result.risk)
                )
                VStack(alignment: .leading, spacing: DSLayout.space2) {
                    Text(result.serviceName)
                        .font(DSTypography.rowTitle)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    DetailSegments(["\(result.port)", "TCP"] + (service.role.map { [$0] } ?? []))
                }
                Spacer(minLength: DSLayout.space8)
                Text(Self.riskWord(result.risk))
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.ink(tone))
                    .lineLimit(1)
                    .fixedSize()
            }
            if result.risk != .low {
                Text(SecurityAssessor.advice(port: result.port))
                    .font(DSTypography.rowSubtitle)
                    .foregroundStyle(DSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.textLeading)
            }
        }
        .padding(.vertical, DSLayout.space12)
        .overlay(alignment: .bottom) {
            if !isLast {
                separator
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A 44 pt row: the Bonjour glyph in the thumbnail column, the name over "_smb._tcp │ port 445".
    private func serviceRow(_ service: DiscoveredService, isLast: Bool) -> some View {
        HStack(spacing: DSLayout.space12) {
            Image(systemName: "bonjour")
                .font(DSTypography.body)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: DSLayout.thumbnailService)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSLayout.space2) {
                Text(service.name)
                    .font(DSTypography.rowTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .lineLimit(1)
                DetailSegments([service.type] + (service.port.map { ["port \($0)"] } ?? []))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DSLayout.space4)
        .frame(minHeight: DSLayout.settingsRowHeight)
        .overlay(alignment: .bottom) {
            if !isLast {
                separator
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A hairline from the text column to the card's trailing edge.
    private var separator: some View {
        Rectangle()
            .fill(DSColor.hairline)
            .frame(height: 1 / displayScale)
            .padding(.leading, Self.textLeading)
    }

    private static func rank(_ risk: PortRisk) -> Int {
        switch risk {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    /// "High risk" in the bad ink, "Review" in the warn ink, "OK" in grey.
    private static func riskWord(_ risk: PortRisk) -> String {
        switch risk {
        case .low: return "OK"
        case .medium: return "Review"
        case .high: return "High risk"
        }
    }

    /// The service's line glyph and what it is for; other ports get a number glyph and no role.
    private static func service(port: UInt16) -> (glyph: String, role: String?) {
        switch port {
        case 139, 445, 548: return ("externaldrive", "File sharing")
        case 80, 443, 8000, 8080, 8443: return ("globe", "Web interface")
        case 22, 23: return ("terminal", "Remote shell")
        case 53: return ("text.book.closed", "Name lookup")
        case 631, 9100: return ("printer", "Printing")
        case 554: return ("video", "Video stream")
        case 1883: return ("antenna.radiowaves.left.and.right", "Smart home messages")
        default: return ("number", nil)
        }
    }
}

#Preview("Open services") {
    ScrollView {
        ServicesCard(
            ports: ([22, 443, 445, 5001] as [UInt16]).map { port in
                PortScanResult(port: port, isOpen: true, serviceName: SecurityAssessor.serviceName(port: port), risk: SecurityAssessor.risk(port: port))
            },
            services: [DiscoveredService(type: "_smb._tcp", name: "DiskStation", port: 445, txt: [:])],
            isScanning: false,
            onRescan: {}
        )
        .padding(DSLayout.space16)
    }
    .background {
        DSColor.background.ignoresSafeArea()
    }
}
