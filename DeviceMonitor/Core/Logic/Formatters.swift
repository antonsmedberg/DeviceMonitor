import Foundation

/// Small, allocation-free formatting helpers used across the UI.
nonisolated enum Formatters {
    static func latency(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return "—" }
        if milliseconds >= 1000 {
            return String(format: "%.1f s", milliseconds / 1000)
        }
        if milliseconds < 10 {
            return String(format: "%.1f ms", milliseconds)
        }
        return "\(Int(milliseconds.rounded())) ms"
    }

    /// Whole percent, except that 99–100 % gets one decimal rounded down, so only exactly 1 reads "100%".
    static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        if clamped >= 0.99, clamped < 1 {
            return String(format: "%.1f%%", (clamped * 1000).rounded(.down) / 10)
        }
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// "Just now", "5 min ago", "Yesterday, 14:05" or, further back, a short date without the time.
    static func relative(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 6 * 3600 {
            let hours = Int(seconds / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today, \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded())) s" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) min" }
        let hours = seconds / 3600
        if hours < 48 { return String(format: "%.1f h", hours) }
        return "\(Int((hours / 24).rounded())) d"
    }

    static func count(_ value: Int, singular: String, plural: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(plural)"
    }
}
