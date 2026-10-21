import Foundation

/// Every user-facing failure in the app. Each case carries a plain-language description and a recovery suggestion.
nonisolated enum DeviceMonitorError: Error, LocalizedError, Sendable, Hashable {
    case storeUnavailable(underlying: String)
    case migrationFailed(recovered: Bool)
    case localNetworkDenied
    case noWiFi
    case noIPv4Address
    case subnetTooLarge(prefixLength: UInt8)
    case invalidInput(field: String, reason: String)
    case deviceNotFound(UUID)
    case duplicateDevice(host: String)
    case scanCancelled
    case scanTimedOut
    case exportFailed(String)
    case wakeFailed(String)
    case deviceLimitReached(limit: Int)
    case deviceDidNotAnswer

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "Local storage could not be opened."
        case .migrationFailed(let recovered):
            return recovered
                ? "Your earlier device history could not be upgraded, so a fresh store was created."
                : "Your device history could not be upgraded."
        case .localNetworkDenied:
            return "DeviceMonitor does not have permission to access your local network."
        case .noWiFi:
            return "You are not connected to a Wi‑Fi network."
        case .noIPv4Address:
            return "This Wi‑Fi network has not given your phone an IPv4 address, so it cannot be scanned."
        case .subnetTooLarge(let prefixLength):
            return "This network (/\(prefixLength)) is too large to scan from a phone."
        case .invalidInput(_, let reason):
            return reason
        case .deviceNotFound:
            return "That device no longer exists."
        case .duplicateDevice(let host):
            return "A device with the address \(host) is already in your list."
        case .scanCancelled:
            return "The scan was cancelled."
        case .scanTimedOut:
            return "The scan took too long and was stopped."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .wakeFailed(let reason):
            return "The wake-up packet could not be sent: \(reason)"
        case .deviceLimitReached(let limit):
            return "You can monitor up to \(limit) devices."
        case .deviceDidNotAnswer:
            return "The device did not answer, so its ports could not be checked."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storeUnavailable:
            return "Restart the app. If the problem persists, free up storage space or reinstall."
        case .migrationFailed(let recovered):
            return recovered
                ? "A backup of the previous data was kept in the app's Application Support folder."
                : "Delete and reinstall the app to start fresh."
        case .localNetworkDenied:
            return "Open Settings › Privacy & Security › Local Network and enable DeviceMonitor."
        case .noWiFi:
            return "Join the Wi‑Fi network your devices are on, then try again."
        case .noIPv4Address:
            return "Reconnect to the network or restart the router. You can still add devices by address."
        case .subnetTooLarge:
            return "Add important devices manually by address instead of scanning."
        case .invalidInput(let field, _):
            return "Check the \(field) and try again."
        case .deviceNotFound:
            return "Pull to refresh the list."
        case .duplicateDevice:
            return "Open the existing device instead, or rename it."
        case .scanCancelled:
            return nil
        case .scanTimedOut:
            return "Try again on a quieter network or add devices manually."
        case .exportFailed:
            return "Try again, or export fewer devices."
        case .wakeFailed:
            return "Make sure the device's MAC address is correct and it was recently on this network."
        case .deviceLimitReached:
            return "Remove devices you no longer need."
        case .deviceDidNotAnswer:
            return "Make sure it is switched on and on this Wi‑Fi network, then try again. The ports found earlier are kept."
        }
    }
}
