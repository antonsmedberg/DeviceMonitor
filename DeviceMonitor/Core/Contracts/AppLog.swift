import Foundation
import os

/// Structured logging categories. Hostnames and addresses are always interpolated with `privacy: .private`.
nonisolated enum AppLog {
    static let subsystem = "eu.smedberg.DeviceMonitor"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let probe = Logger(subsystem: subsystem, category: "probe")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
}
