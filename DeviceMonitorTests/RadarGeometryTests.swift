import Foundation
import Testing
@testable import DeviceMonitor

@Suite("Radar geometry")
struct RadarGeometryTests {
    private let inner = 0.42
    private let outer = 0.92

    @Test func fasterHostsSitCloser() {
        let latencies: [Double] = [0.2, 1, 2, 10, 50, 100, 199]
        let distances = latencies.map { RadarGeometry.distance(latency: $0, inner: inner, outer: outer) }
        for (faster, slower) in zip(distances, distances.dropFirst()) {
            #expect(faster < slower)
        }
        for distance in distances {
            #expect(distance > inner && distance < outer)
        }
        let oneMillisecond = RadarGeometry.distance(latency: 1, inner: inner, outer: outer)
        #expect(abs(oneMillisecond - (inner + 0.13 * (outer - inner))) < 0.001)
    }

    @Test func slowAndMissingLatencySitOnTheOuterEdge() {
        let atLimit = RadarGeometry.distance(latency: 200, inner: inner, outer: outer)
        #expect(abs(atLimit - outer) < 1e-9)
        let beyond = RadarGeometry.distance(latency: 5_000, inner: inner, outer: outer)
        #expect(abs(beyond - outer) < 1e-9)
        let unusable: [Double?] = [nil, 0, -3, Double.nan, Double.infinity]
        for latency in unusable {
            let distance = RadarGeometry.distance(latency: latency, inner: inner, outer: outer)
            #expect(distance == outer)
        }
    }

    @Test func blipsStayOutOfTheLabelWedgeInOrder() {
        let turn = 2 * Double.pi
        let halfWedge = RadarGeometry.labelWedge / 2
        let angles = Array(stride(from: -Double.pi / 2, to: 3 * Double.pi / 2, by: 0.01))
        let bearings = angles.map { RadarGeometry.bearing($0) }
        for bearing in bearings {
            let offset = bearing - RadarGeometry.labelBearing
            #expect(offset >= halfWedge - 1e-9 && offset < turn - halfWedge)
        }
        for (earlier, later) in zip(bearings, bearings.dropFirst()) {
            #expect(earlier < later)
        }
        #expect(abs(RadarGeometry.bearing(RadarGeometry.labelBearing) - (RadarGeometry.labelBearing + halfWedge)) < 1e-9)
        #expect(abs(RadarGeometry.bearing(0.4 + turn) - RadarGeometry.bearing(0.4)) < 1e-9)
        #expect(abs(RadarGeometry.bearing(0.4 - turn) - RadarGeometry.bearing(0.4)) < 1e-9)
    }
}
