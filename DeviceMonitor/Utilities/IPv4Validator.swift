import Foundation

enum IPv4Validator {
    static func isValid(_ rawIP: String) -> Bool {
        let ip = rawIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { return false }

        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }

        return parts.allSatisfy { part in
            guard let value = Int(part), value >= 0, value <= 255 else {
                return false
            }
            return String(value) == part || part == "0"
        }
    }
}
