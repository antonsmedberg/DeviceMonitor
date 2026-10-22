import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// CSV and JSON exports of the device list. Nothing leaves the phone unless the user shares it.
nonisolated enum DeviceExport {
    static func csv(_ devices: [DeviceSnapshot]) -> String {
        var lines = ["name,host,hostname,kind,state,confidence,latency_ms,vendor,mac,favorite,trusted,first_seen,last_seen,open_ports,tags"]
        let formatter = ISO8601DateFormatter()
        for device in devices {
            let fields: [String] = [
                device.displayName,
                device.host,
                device.hostname ?? "",
                device.kind.rawValue,
                device.state.rawValue,
                String(format: "%.2f", device.confidence),
                device.latencyMilliseconds.map { String(format: "%.1f", $0) } ?? "",
                device.vendor ?? "",
                device.macAddress ?? "",
                device.isFavorite ? "yes" : "no",
                device.isTrusted ? "yes" : "no",
                formatter.string(from: device.firstSeen),
                device.lastSeen.map { formatter.string(from: $0) } ?? "",
                device.openPorts.map(String.init).joined(separator: " "),
                device.tags.joined(separator: " "),
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ devices: [DeviceSnapshot], events: [StatusEventSnapshot]) throws(DeviceMonitorError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(ExportDocument(exportedAt: Date(), devices: devices, events: events))
        } catch {
            throw DeviceMonitorError.exportFailed(error.localizedDescription)
        }
    }

    /// RFC 4180 quoting, plus a leading apostrophe on anything a spreadsheet would run as a
    /// formula. Names and vendors come from devices on the network, so they are untrusted.
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        let needsQuotes = value != field || value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    nonisolated struct ExportDocument: Codable, Sendable {
        let exportedAt: Date
        let devices: [DeviceSnapshot]
        let events: [StatusEventSnapshot]
    }
}

/// A file the share sheet can hand to other apps.
nonisolated struct ExportFile: Transferable, Sendable {
    let data: Data
    let contentType: UTType
    let filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { file in
            file.data
        }
        .suggestedFileName { file in
            file.filename
        }
    }
}
