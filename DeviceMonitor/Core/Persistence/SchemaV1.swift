import Foundation
import SwiftData

/// Exact replica of the schema that shipped in version 1.0 (Swedish attribute names).
/// It exists only so SwiftData can recognise existing stores and migrate them to `SchemaV2`.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Device.self, StatusEvent.self]
    }

    @Model
    final class Device {
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
    final class StatusEvent {
        @Attribute(.unique) var id: UUID
        var tidpunkt: Date
        var isOnline: Bool
        var device: Device?

        init(id: UUID = UUID(), tidpunkt: Date = .now, isOnline: Bool, device: Device? = nil) {
            self.id = id
            self.tidpunkt = tidpunkt
            self.isOnline = isOnline
            self.device = device
        }
    }
}
