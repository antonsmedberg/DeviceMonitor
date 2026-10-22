import Foundation

/// An absolute range drawn as a gradient bar: where a value sits, the ticks under the bar and the colour
/// stops, so the bar and its marker always agree.
nonisolated struct QualityScale: Sendable, Hashable {
    nonisolated struct Stop: Sendable, Hashable {
        /// 0...1 along the bar.
        let location: Double
        let tone: DSTone

        init(location: Double, tone: DSTone) {
            self.location = location
            self.tone = tone
        }
    }

    let lowerBound: Double
    let upperBound: Double
    let isLogarithmic: Bool
    let ticks: [Double]
    let tickLabels: [String]
    /// Ascending by location, from 0 to 1.
    let stops: [Stop]

    init(lowerBound: Double, upperBound: Double, isLogarithmic: Bool, ticks: [Double], tickLabels: [String], stops: [Stop]) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.isLogarithmic = isLogarithmic
        self.ticks = ticks
        self.tickLabels = tickLabels
        self.stops = stops
    }

    /// 0...1, clamped; log10 for logarithmic scales.
    func position(of value: Double) -> Double {
        let fraction: Double
        if isLogarithmic {
            guard value > 0, lowerBound > 0, upperBound > lowerBound else { return 0 }
            fraction = (log10(value) - log10(lowerBound)) / (log10(upperBound) - log10(lowerBound))
        } else {
            guard upperBound > lowerBound else { return 0 }
            fraction = (value - lowerBound) / (upperBound - lowerBound)
        }
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// The two stops around `position` (clamped to 0...1) and how far it lies between them (0...1);
    /// both stops are the same at or beyond the ends. GradientScaleView mixes their colours for the marker.
    func segment(at position: Double) -> (lower: Stop, upper: Stop, fraction: Double) {
        let clamped = position.isFinite ? min(max(position, 0), 1) : 0
        guard let first = stops.first, let last = stops.last else {
            let neutral = Stop(location: 0, tone: .neutral)
            return (neutral, neutral, 0)
        }
        if clamped <= first.location { return (first, first, 0) }
        if clamped >= last.location { return (last, last, 0) }
        for (lower, upper) in zip(stops, stops.dropFirst()) where clamped >= lower.location && clamped < upper.location {
            let span = upper.location - lower.location
            return (lower, upper, span > 0 ? (clamped - lower.location) / span : 0)
        }
        return (last, last, 0)
    }

    /// 1...300 ms, logarithmic; ticks 1, 3, 10, 30, 100, 300 labelled "1", "3", "10", "30", "100", "300 ms";
    /// stops centred on the LatencyGrade boundaries (30 ms = 0.596, 100 ms = 0.807):
    /// good 0 and 0.56 (≈ 24 ms), warn 0.64 (≈ 39 ms) and 0.77 (≈ 81 ms), bad 0.85 (≈ 128 ms) and 1,
    /// so the colour under the marker always agrees with the grade the ⓘ explains.
    static let latency = QualityScale(
        lowerBound: 1,
        upperBound: 300,
        isLogarithmic: true,
        ticks: [1, 3, 10, 30, 100, 300],
        tickLabels: ["1", "3", "10", "30", "100", "300 ms"],
        stops: [
            Stop(location: 0, tone: .good),
            Stop(location: 0.56, tone: .good),
            Stop(location: 0.64, tone: .warn),
            Stop(location: 0.77, tone: .warn),
            Stop(location: 0.85, tone: .bad),
            Stop(location: 1, tone: .bad),
        ]
    )

    /// 0...100, linear; ticks every 20; stops bad 0 and 0.40, warn 0.55 and 0.68, good 0.80 and 1.
    static let securityScore = QualityScale(
        lowerBound: 0,
        upperBound: 100,
        isLogarithmic: false,
        ticks: [0, 20, 40, 60, 80, 100],
        tickLabels: ["0", "20", "40", "60", "80", "100"],
        stops: [
            Stop(location: 0, tone: .bad),
            Stop(location: 0.40, tone: .bad),
            Stop(location: 0.55, tone: .warn),
            Stop(location: 0.68, tone: .warn),
            Stop(location: 0.80, tone: .good),
            Stop(location: 1, tone: .good),
        ]
    )
}

/// The absolute grade, shown only inside the latency-range ⓘ popover (one vocabulary on screen).
nonisolated enum LatencyGrade: String, Sendable, Hashable, CaseIterable {
    case good, fair, poor

    var title: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    /// The popover's word colour.
    var tone: DSTone {
        switch self {
        case .good: return .good
        case .fair: return .warn
        case .poor: return .bad
        }
    }

    var explanation: String {
        switch self {
        case .good: return "Under 30 ms: calls and games feel instant."
        case .fair: return "30 to 100 ms: browsing feels normal, calls and games may lag a little."
        case .poor: return "100 ms or more: video calls and games will notice."
        }
    }

    /// Under 30 ms good, under 100 ms fair, else poor.
    static func grade(milliseconds: Double) -> LatencyGrade {
        if milliseconds < 30 { return .good }
        if milliseconds < 100 { return .fair }
        return .poor
    }
}

extension LatencyQuality {
    /// Fast and normal are good; slower than usual warns; slow is bad.
    nonisolated var tone: DSTone {
        switch self {
        case .fast, .normal: return .good
        case .slower: return .warn
        case .slow: return .bad
        }
    }
}
