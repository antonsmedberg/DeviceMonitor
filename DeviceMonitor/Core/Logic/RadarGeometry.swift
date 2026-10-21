import Foundation

/// Where a scanned host sits on the scan radar: faster hosts sit closer, and none sits on the ring labels' spoke.
nonisolated enum RadarGeometry {
    /// The spoke the ring labels sit on: 12 o'clock, in radians clockwise from 3 o'clock.
    static let labelBearing = -Double.pi / 2
    /// The wedge centred on `labelBearing` that no blip enters: room for "2", "10" and "50 ms" at up to
    /// xxxLarge text on a 240 pt radar, with a lit blip beside them.
    static let labelWedge = 48 * Double.pi / 180

    /// Fraction of the radius in inner...outer; log scale, 1 ms → inner + 0.13·(outer−inner), ≥ 200 ms → outer;
    /// nil, non-finite or ≤ 0 → outer.
    static func distance(latency milliseconds: Double?, inner: Double, outer: Double) -> Double {
        guard let milliseconds, milliseconds.isFinite, milliseconds > 0 else { return outer }
        return inner + (outer - inner) * min(1, log(1 + milliseconds) / log(201))
    }

    /// `angle` (radians clockwise from 3 o'clock, any turn) moved into the circle less the label wedge in
    /// proportion, so the kind sectors keep their order and share: `labelBearing` lands on the wedge's
    /// clockwise edge, and angles just short of a full turn later next to its other edge.
    static func bearing(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        var offset = (angle - labelBearing).truncatingRemainder(dividingBy: turn)
        if offset < 0 {
            offset += turn
        }
        return labelBearing + labelWedge / 2 + offset * (turn - labelWedge) / turn
    }
}
