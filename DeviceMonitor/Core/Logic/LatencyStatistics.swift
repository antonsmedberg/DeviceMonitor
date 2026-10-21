import Foundation

/// Summary statistics over a set of latency samples in milliseconds.
nonisolated struct LatencySummary: Sendable, Hashable {
    let count: Int
    let minimum: Double
    let maximum: Double
    let mean: Double
    let median: Double
    let p95: Double
    let jitter: Double

    init(count: Int, minimum: Double, maximum: Double, mean: Double, median: Double, p95: Double, jitter: Double) {
        self.count = count
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
        self.median = median
        self.p95 = p95
        self.jitter = jitter
    }

    /// Returns nil for an empty input.
    init?(samples: [Double]) {
        let valid = samples.filter { $0.isFinite && $0 >= 0 }
        guard !valid.isEmpty else { return nil }
        let sorted = valid.sorted()
        let total = valid.reduce(0, +)
        var jitterTotal = 0.0
        if valid.count >= 2 {
            for index in 1..<valid.count {
                jitterTotal += abs(valid[index] - valid[index - 1])
            }
        }
        self.init(
            count: valid.count,
            minimum: sorted[0],
            maximum: sorted[sorted.count - 1],
            mean: total / Double(valid.count),
            median: Self.nearestRank(sorted, percentile: 0.5),
            p95: Self.nearestRank(sorted, percentile: 0.95),
            jitter: valid.count >= 2 ? jitterTotal / Double(valid.count - 1) : 0
        )
    }

    static func nearestRank(_ sorted: [Double], percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(percentile, 0), 1)
        let rank = Int((clamped * Double(sorted.count)).rounded(.up))
        let index = max(0, min(sorted.count - 1, rank - 1))
        return sorted[index]
    }
}

/// Reads a latency series in words: its typical band, what counts as a spike, and a one-line headline.
nonisolated enum LatencyNarrative {
    /// p10...p90 (nearest rank) of the finite, non-negative samples; nil below 4 samples.
    static func typicalBand(_ samples: [Double]) -> ClosedRange<Double>? {
        let sorted = samples.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard sorted.count >= 4 else { return nil }
        let low = LatencySummary.nearestRank(sorted, percentile: 0.1)
        let high = LatencySummary.nearestRank(sorted, percentile: 0.9)
        return low...high
    }

    /// max(band.upperBound * 1.5, band.upperBound + 1).
    static func spikeThreshold(for band: ClosedRange<Double>) -> Double {
        max(band.upperBound * 1.5, band.upperBound + 1)
    }

    /// "Steady around 2.0 ms" | "3 spikes above 4.9 ms" | "Slower than usual: 18 ms vs 2.0 ms typical"
    /// (the last when the median of the last 10 samples > 1.5 × band.upperBound); nil below 4 samples.
    /// `samples` are in time order, oldest first.
    static func headline(samples: [Double]) -> String? {
        let valid = samples.filter { $0.isFinite && $0 >= 0 }
        guard let band = typicalBand(valid) else { return nil }
        let typical = LatencySummary.nearestRank(valid.sorted(), percentile: 0.5)
        let recent = LatencySummary.nearestRank(valid.suffix(10).sorted(), percentile: 0.5)
        if recent > band.upperBound * 1.5 {
            return "Slower than usual: \(Formatters.latency(recent)) vs \(Formatters.latency(typical)) typical"
        }
        let threshold = spikeThreshold(for: band)
        let spikeCount = valid.filter { $0 > threshold }.count
        if spikeCount > 0 {
            let spikes = Formatters.count(spikeCount, singular: "spike", plural: "spikes")
            return "\(spikes) above \(Formatters.latency(threshold))"
        }
        return "Steady around \(Formatters.latency(typical))"
    }
}
