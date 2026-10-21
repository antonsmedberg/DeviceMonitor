import Foundation

nonisolated struct TimelineEntry: Sendable, Hashable, Identifiable {
    nonisolated enum Kind: String, Sendable, Hashable, CaseIterable {
        case newDevice, left, returned, outageStarted, outageEnded

        var title: String {
            switch self {
            case .newDevice: return "New device"
            case .left: return "Went offline"
            case .returned: return "Back online"
            case .outageStarted: return "Network outage"
            case .outageEnded: return "Network restored"
            }
        }

        var systemImage: String {
            switch self {
            case .newDevice: return "sparkles"
            case .left: return "xmark.circle"
            case .returned: return "checkmark.circle"
            case .outageStarted: return "wifi.exclamationmark"
            case .outageEnded: return "wifi"
            }
        }
    }

    let id: String
    let date: Date
    let kind: Kind
    let deviceID: UUID?
    let title: String
    let subtitle: String?

    init(id: String, date: Date, kind: Kind, deviceID: UUID?, title: String, subtitle: String?) {
        self.id = id
        self.date = date
        self.kind = kind
        self.deviceID = deviceID
        self.title = title
        self.subtitle = subtitle
    }
}

/// Turns raw status events into a human timeline and collapses mass drop-outs into outages.
nonisolated enum NetworkTimelineBuilder {
    /// - Parameters:
    ///   - outageWindowSeconds: drop-outs this close together count as one event.
    ///   - outageFraction: share of the known devices that must drop together to call it an outage.
    ///   - newDeviceWindowSeconds: an online event this soon after `firstSeen` is the device's arrival.
    static func entries(
        events: [StatusEventSnapshot],
        devices: [UUID: DeviceSnapshot],
        gatewayID: UUID?,
        outageWindowSeconds: Double,
        outageFraction: Double,
        newDeviceWindowSeconds: Double = 600,
        now: Date
    ) -> [TimelineEntry] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var hasBeenOnline: Set<UUID> = []
        var consumed: Set<UUID> = []
        var entries: [TimelineEntry] = []
        var outage: (members: Set<UUID>, returned: Set<UUID>)?
        var lastState: [UUID: ReachabilityState] = [:]

        for (index, event) in sorted.enumerated() {
            // Tracked for every event, including drop-outs folded into an outage.
            let previous = lastState.updateValue(event.state, forKey: event.deviceID)
            guard !consumed.contains(event.id) else { continue }
            let device = devices[event.deviceID]
            let name = device?.displayName ?? "Unknown device"

            switch event.state {
            case .online:
                let wasOnline = hasBeenOnline.contains(event.deviceID)
                hasBeenOnline.insert(event.deviceID)

                if var open = outage, open.members.contains(event.deviceID) {
                    open.returned.insert(event.deviceID)
                    let gatewayBack = event.deviceID == gatewayID
                    if gatewayBack || open.returned.count * 2 >= open.members.count {
                        outage = nil
                        entries.append(TimelineEntry(
                            id: "outage-end-\(event.id.uuidString)",
                            date: event.timestamp,
                            kind: .outageEnded,
                            deviceID: nil,
                            title: TimelineEntry.Kind.outageEnded.title,
                            subtitle: gatewayBack ? "Router is answering again" : "Devices are back"
                        ))
                    } else {
                        outage = open
                    }
                    continue
                }
                // Recovering from Unstable is not a return: the device never left.
                if previous == .online || previous == .degraded {
                    continue
                }

                let isNew = device.map { event.timestamp.timeIntervalSince($0.firstSeen) <= newDeviceWindowSeconds } ?? !wasOnline
                let kind: TimelineEntry.Kind = isNew && !wasOnline ? .newDevice : .returned
                entries.append(TimelineEntry(
                    id: event.id.uuidString,
                    date: event.timestamp,
                    kind: kind,
                    deviceID: event.deviceID,
                    title: name,
                    subtitle: kind.title
                ))

            case .offline:
                if var open = outage {
                    // A member that came back and dropped again stays part of the open outage;
                    // anyone else leaving during it gets an ordinary row.
                    if open.members.contains(event.deviceID) {
                        open.returned.remove(event.deviceID)
                        outage = open
                        continue
                    }
                } else if let started = outageStart(at: index, in: sorted, consumed: consumed, devices: devices, gatewayID: gatewayID, windowSeconds: outageWindowSeconds, fraction: outageFraction) {
                    outage = (members: started.members, returned: [])
                    consumed.formUnion(started.eventIDs)
                    entries.append(TimelineEntry(
                        id: "outage-start-\(event.id.uuidString)",
                        date: event.timestamp,
                        kind: .outageStarted,
                        deviceID: nil,
                        title: TimelineEntry.Kind.outageStarted.title,
                        subtitle: started.gatewayDown ? "Router stopped answering" : "\(started.members.count) devices went offline together"
                    ))
                    continue
                }
                entries.append(TimelineEntry(
                    id: event.id.uuidString,
                    date: event.timestamp,
                    kind: .left,
                    deviceID: event.deviceID,
                    title: name,
                    subtitle: TimelineEntry.Kind.left.title
                ))

            case .degraded, .unknown:
                continue
            }
        }

        return entries.sorted { $0.date > $1.date }
    }

    /// Looks ahead from an offline event for a mass drop-out: the router leaving, or enough of the
    /// known devices leaving within `windowSeconds`. Returns the members and the events it consumes.
    private static func outageStart(
        at index: Int,
        in sorted: [StatusEventSnapshot],
        consumed: Set<UUID>,
        devices: [UUID: DeviceSnapshot],
        gatewayID: UUID?,
        windowSeconds: Double,
        fraction: Double
    ) -> (members: Set<UUID>, eventIDs: [UUID], gatewayDown: Bool)? {
        let first = sorted[index]
        var lefts: [StatusEventSnapshot] = [first]
        var cursor = index + 1
        while cursor < sorted.count, sorted[cursor].timestamp.timeIntervalSince(first.timestamp) <= windowSeconds {
            let candidate = sorted[cursor]
            if candidate.state == .offline, !consumed.contains(candidate.id) {
                lefts.append(candidate)
            }
            cursor += 1
        }
        let members = Set(lefts.map(\.deviceID))
        let population = devices.values.filter { $0.firstSeen <= first.timestamp }.count
        let threshold = max(3, Int((fraction * Double(max(population, 1))).rounded(.up)))
        let gatewayDown = gatewayID.map { members.contains($0) } ?? false
        guard gatewayDown || members.count >= threshold else { return nil }
        return (members, lefts.map(\.id), gatewayDown)
    }

    static func sectionedByDay(_ entries: [TimelineEntry], calendar: Calendar) -> [(day: Date, entries: [TimelineEntry])] {
        var buckets: [Date: [TimelineEntry]] = [:]
        for entry in entries {
            buckets[calendar.startOfDay(for: entry.date), default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).map { day in
            (day: day, entries: buckets[day, default: []].sorted { $0.date > $1.date })
        }
    }
}
