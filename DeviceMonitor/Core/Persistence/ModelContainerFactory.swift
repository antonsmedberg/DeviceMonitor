import Foundation
import SwiftData
import Darwin
import os

/// The only place a `ModelContainer` is created. Handles migration failure by moving the
/// old store aside and starting fresh, and falls back to memory when the disk is unusable.
@MainActor
enum ModelContainerFactory {
    nonisolated enum Outcome: String, Sendable, Hashable {
        case persistent
        case recoveredFromBackup
        case inMemoryFallback
    }

    nonisolated struct Startup: Sendable {
        let container: ModelContainer?
        let outcome: Outcome
        let error: DeviceMonitorError?

        init(container: ModelContainer?, outcome: Outcome, error: DeviceMonitorError?) {
            self.container = container
            self.outcome = outcome
            self.error = error
        }
    }

    static var currentSchema: Schema {
        Schema(versionedSchema: SchemaV2.self)
    }

    static func makePersistent() -> Startup {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false, cloudKitDatabase: .none)

        do {
            let container = try ModelContainer(
                for: currentSchema,
                migrationPlan: DeviceMonitorMigrationPlan.self,
                configurations: [configuration]
            )
            return Startup(container: container, outcome: .persistent, error: nil)
        } catch {
            AppLog.store.error("Opening the persistent store failed: \(error.localizedDescription, privacy: .public)")
            // A full disk, a locked file or data protection before first unlock are temporary:
            // keep the store untouched, run in memory and try again on the next launch.
            // SwiftData usually wraps the cause in an opaque error, so look at the conditions too.
            if isTransient(error as NSError) || environmentLooksTransient(storeURL: configuration.url) {
                return inMemoryStartup(reason: "your saved devices are temporarily unavailable; restart the app to load them")
            }
        }

        let backedUp = moveStoreAside(at: configuration.url)

        do {
            let fresh = ModelConfiguration(isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            let container = try ModelContainer(
                for: currentSchema,
                migrationPlan: DeviceMonitorMigrationPlan.self,
                configurations: [fresh]
            )
            AppLog.store.warning("Recovered with a fresh store (backup kept: \(backedUp, privacy: .public))")
            return Startup(container: container, outcome: .recoveredFromBackup, error: .migrationFailed(recovered: backedUp))
        } catch {
            AppLog.store.error("Creating a fresh store failed: \(error.localizedDescription, privacy: .public)")
        }

        return inMemoryStartup(reason: "running in memory only")
    }

    private static func inMemoryStartup(reason: String) -> Startup {
        do {
            let container = try makeInMemory()
            return Startup(container: container, outcome: .inMemoryFallback, error: .storeUnavailable(underlying: reason))
        } catch {
            return Startup(container: nil, outcome: .inMemoryFallback, error: .storeUnavailable(underlying: error.localizedDescription))
        }
    }

    /// Errors that say nothing is wrong with the store itself, searched through underlying errors.
    nonisolated static func isTransient(_ error: NSError) -> Bool {
        let cocoa: Set<Int> = [NSFileWriteOutOfSpaceError, NSFileReadNoPermissionError, NSFileWriteNoPermissionError, NSFileLockingError]
        let posix: Set<Int> = [Int(ENOSPC), Int(EACCES), Int(EPERM), Int(EBUSY), Int(EAGAIN)]
        // SQLITE_BUSY, SQLITE_LOCKED, SQLITE_IOERR, SQLITE_FULL, SQLITE_CANTOPEN, SQLITE_AUTH.
        let sqlite: Set<Int> = [5, 6, 10, 13, 14, 23]
        var current: NSError? = error
        var depth = 0
        while let candidate = current, depth < 8 {
            switch candidate.domain {
            case NSCocoaErrorDomain where cocoa.contains(candidate.code): return true
            case NSPOSIXErrorDomain where posix.contains(candidate.code): return true
            case "NSSQLiteErrorDomain" where sqlite.contains(candidate.code): return true
            default: break
            }
            if let sqliteCode = candidate.userInfo["NSSQLiteErrorDomain"] as? Int, sqlite.contains(sqliteCode) {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    /// Conditions that make opening (or migrating) an intact store fail for now: the file cannot be
    /// read yet (data protection before first unlock) or the disk is too full to migrate it.
    nonisolated static func environmentLooksTransient(storeURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: storeURL) else { return true }
        try? handle.close()
        let storeSize = (try? storeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let directory = storeURL.deletingLastPathComponent()
        if let available = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
            // A migration copies the tables, so it needs a few times the store's size plus headroom.
            return available < Int64(storeSize) * 3 + 50_000_000
        }
        return false
    }

    static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(
            for: currentSchema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    /// Moves `default.store` (+ `-wal`, `-shm`) into a timestamped backup folder. Returns true when something was moved.
    private static func moveStoreAside(at storeURL: URL) -> Bool {
        let fileManager = FileManager.default
        let candidates = [storeURL, storeURL.appendingPathExtension("wal"), storeURL.appendingPathExtension("shm")]
            + ["-wal", "-shm"].map { suffix in
                URL(fileURLWithPath: storeURL.path + suffix)
            }
        let existing = candidates.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return false }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDirectory = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            for url in existing {
                try fileManager.moveItem(at: url, to: backupDirectory.appendingPathComponent(url.lastPathComponent))
            }
            return true
        } catch {
            AppLog.store.error("Backing up the old store failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
