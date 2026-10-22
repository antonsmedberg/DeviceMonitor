import Foundation

/// One step of a scan as the sheet lists it while scanning.
nonisolated struct ScanStage: Sendable, Hashable, Identifiable {
    nonisolated enum Step: Int, Sendable, Hashable, CaseIterable {
        case sweep, measure, identify, compare
    }

    nonisolated enum Phase: String, Sendable, Hashable {
        case waiting, running, done
    }

    let step: Step
    let phase: Phase
    /// Addresses swept, hosts measured or hosts identified; nil when the step has nothing to count.
    let count: Int?

    var id: Int { step.rawValue }

    var title: String {
        switch step {
        case .sweep: return "Sweep addresses"
        case .measure: return "Measure response"
        case .identify: return "Identify devices"
        case .compare: return "Compare with last scan"
        }
    }

    init(step: Step, phase: Phase, count: Int?) {
        self.step = step
        self.phase = phase
        self.count = count
    }

    /// The sweep runs until every address is checked. Measuring and identifying run once something is found.
    /// The comparison runs once the sweep is done. Everything is done when the scan finishes.
    /// - Parameters:
    ///   - measured: found hosts with a latency.
    ///   - identified: found hosts with a known kind or name.
    static func stages(progress: ScanProgress?, isScanning: Bool, isFinished: Bool, measured: Int, identified: Int) -> [ScanStage] {
        let isSwept = isFinished || (progress.map { $0.total > 0 && $0.scanned >= $0.total } ?? false)
        let hasFound = (progress?.found ?? 0) > 0

        let sweep: Phase
        if isSwept {
            sweep = .done
        } else if isScanning && progress != nil {
            sweep = .running
        } else {
            sweep = .waiting
        }

        let found: Phase
        if isFinished {
            found = .done
        } else if hasFound && isScanning {
            found = .running
        } else {
            found = .waiting
        }

        let compare: Phase
        if isFinished {
            compare = .done
        } else if isSwept && isScanning {
            compare = .running
        } else {
            compare = .waiting
        }

        return [
            ScanStage(step: .sweep, phase: sweep, count: progress?.scanned),
            ScanStage(step: .measure, phase: found, count: measured),
            ScanStage(step: .identify, phase: found, count: identified),
            ScanStage(step: .compare, phase: compare, count: nil),
        ]
    }
}

/// The finished scan in one line, and the order of its Found list.
nonisolated enum ScanSummary {
    /// "12 found · 1 new · 2 not answering · fastest 1.1 ms". The count always leads; "new" and "not
    /// answering" appear only when non-zero. Not answering: known devices of this network, not added by hand,
    /// that the scan did not find.
    static func text(found: [DiscoveredHost], known: [DeviceSnapshot], networkKey: String?, now: Date) -> String {
        let knownByHost = Dictionary(known.map { ($0.host, $0) }, uniquingKeysWith: { first, _ in first })
        let foundHosts = Set(found.map(\.host))
        var parts = ["\(found.count) found"]

        let newCount = found.filter { isNew(knownByHost[$0.host], now: now) }.count
        if newCount > 0 {
            parts.append("\(newCount) new")
        }
        let missing = known.filter { device in
            !device.isUserAdded
                && (device.networkKey == nil || device.networkKey == networkKey)
                && !foundHosts.contains(device.host)
        }.count
        if missing > 0 {
            parts.append("\(missing) not answering")
        }
        if let fastest = found.compactMap({ $0.probe?.outcome.latencyMilliseconds }).min() {
            parts.append("fastest \(Formatters.latency(fastest))")
        }
        return parts.joined(separator: " · ")
    }

    /// New on the network and not added by hand, as on the Devices list.
    static func isNew(_ device: DeviceSnapshot?, now: Date) -> Bool {
        guard let device else { return false }
        return device.isNew(now: now) && !device.isUserAdded
    }

    /// New hosts first, then by IPv4 address (".9" before ".10"); otherwise in the order they were found.
    static func ordered(found: [DiscoveredHost], known: [String: DeviceSnapshot], now: Date) -> [DiscoveredHost] {
        found.enumerated()
            .sorted { lhs, rhs in
                let lhsNew = isNew(known[lhs.element.host], now: now)
                let rhsNew = isNew(known[rhs.element.host], now: now)
                if lhsNew != rhsNew {
                    return lhsNew
                }
                switch (IPv4Host(lhs.element.host)?.rawValue, IPv4Host(rhs.element.host)?.rawValue) {
                case let (lhsAddress?, rhsAddress?) where lhsAddress != rhsAddress:
                    return lhsAddress < rhsAddress
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.offset < rhs.offset
                }
            }
            .map { $0.element }
    }
}
