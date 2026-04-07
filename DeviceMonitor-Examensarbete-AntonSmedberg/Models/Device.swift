import Foundation
import SwiftData

@Model
final class Device: Identifiable {
    @Attribute(.unique) var id: UUID
    var namn: String
    @Attribute(.unique) var ipAddress: String
    var isOnline: Bool
    var senastSedd: Date?
    var isUserAdded: Bool

    @Relationship(deleteRule: .cascade, inverse: \StatusEvent.device)
    var statusHistorik: [StatusEvent]

    init(
        id: UUID = UUID(),
        namn: String,
        ipAddress: String,
        isOnline: Bool = false,
        senastSedd: Date? = nil,
        statusHistorik: [StatusEvent] = [],
        isUserAdded: Bool = false
    ) {
        self.id = id
        self.namn = namn
        self.ipAddress = ipAddress
        self.isOnline = isOnline
        self.senastSedd = senastSedd
        self.isUserAdded = isUserAdded
        self.statusHistorik = statusHistorik
    }
}

@Model
final class StatusEvent: Identifiable {
    @Attribute(.unique) var id: UUID
    var tidpunkt: Date
    var isOnline: Bool
    var device: Device?

    init(
        id: UUID = UUID(),
        tidpunkt: Date = .now,
        isOnline: Bool,
        device: Device? = nil
    ) {
        self.id = id
        self.tidpunkt = tidpunkt
        self.isOnline = isOnline
        self.device = device
    }
}

extension Device {
    var name: String {
        get { namn }
        set { namn = newValue }
    }

    var lastSeen: Date? {
        get { senastSedd }
        set { senastSedd = newValue }
    }

    var statusHistory: [StatusEvent] {
        get { statusHistorik }
        set { statusHistorik = newValue }
    }

    var hasCompletedInitialCheck: Bool {
        lastStatusCheck != nil || lastSeen != nil
    }

    var lastStatusCheck: Date? {
        statusHistorik.map(\.timestamp).max()
    }
}

extension StatusEvent {
    var timestamp: Date {
        get { tidpunkt }
        set { tidpunkt = newValue }
    }
}
