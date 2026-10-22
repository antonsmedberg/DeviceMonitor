import SwiftUI

/// Where a value sits on an absolute range: a perceptual green-to-red bar with a marker in the bar's own
/// colour at the value, optional rug ticks for every other value, and labelled ticks underneath. The first
/// label starts at the leading edge and the last ends at the trailing edge, so nothing hangs outside.
/// Without a value the marker is hidden and the bar dims.
struct DSGradientScale: View {
    let scale: QualityScale
    let value: Double?
    let marks: [Double]
    let markerSymbol: String
    let accessibilityLabel: String
    let accessibilityValue: String

    /// Stem between the marker and the bar.
    private static let stemHeight: CGFloat = 4

    init(
        scale: QualityScale,
        value: Double?,
        marks: [Double] = [],
        markerSymbol: String,
        accessibilityLabel: String,
        accessibilityValue: String
    ) {
        self.scale = scale
        self.value = value
        self.marks = marks
        self.markerSymbol = markerSymbol
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }

    var body: some View {
        let tickPositions = scale.ticks.map { scale.position(of: $0) }
        let markPositions = marks.map { scale.position(of: $0) }

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                AxisLabelsLayout(positions: markPositions, pinsEnds: false) {
                    ForEach(markPositions.indices, id: \.self) { _ in
                        Rectangle()
                            .fill(DSColor.neutralMark)
                            .frame(width: 1, height: 6)
                    }
                }
                .padding(.bottom, DSLayout.space2)
                if let value {
                    let position = scale.position(of: value)
                    AxisLabelsLayout(positions: [position], pinsEnds: false) {
                        marker(color: markerColor(at: position))
                    }
                }
            }
            .frame(height: DSLayout.markerSize + Self.stemHeight, alignment: .bottom)
            Capsule()
                .fill(.linearGradient(barGradient.colorSpace(.perceptual), startPoint: .leading, endPoint: .trailing))
                .frame(height: DSLayout.scaleHeight)
                .opacity(value == nil ? 0.4 : 1)
            AxisLabelsLayout(positions: tickPositions, pinsEnds: false) {
                ForEach(tickPositions.indices, id: \.self) { _ in
                    Rectangle()
                        .fill(DSColor.hairline)
                        .frame(width: 1, height: 4)
                }
            }
            .padding(.top, DSLayout.space2)
            AxisLabelsLayout(positions: tickPositions, pinsEnds: true) {
                ForEach(scale.tickLabels.indices, id: \.self) { index in
                    Text(scale.tickLabels[index])
                        .font(DSTypography.tileLabel)
                        .foregroundStyle(DSColor.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.top, DSLayout.space2)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    /// The scale's stops in their fills; the bar interpolates them in the perceptual colour space.
    private var barGradient: Gradient {
        Gradient(stops: scale.stops.map { stop in
            Gradient.Stop(color: DSColor.fill(stop.tone), location: stop.location)
        })
    }

    /// The bar's own colour at `position`, mixed from the two stops around it, so marker and bar agree.
    private func markerColor(at position: Double) -> Color {
        let segment = scale.segment(at: position)
        return DSColor.fill(segment.lower.tone).mix(with: DSColor.fill(segment.upper.tone), by: segment.fraction, in: .perceptual)
    }

    /// A ringed disc with the symbol, over a stem down to the bar.
    private func marker(color: Color) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(DSColor.card.mix(with: color, by: 0.25, in: .perceptual))
                Circle()
                    .strokeBorder(color, lineWidth: 1.5)
                Image(systemName: markerSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.textPrimary)
            }
            .frame(width: DSLayout.markerSize, height: DSLayout.markerSize)
            Rectangle()
                .fill(color)
                .frame(width: 1, height: Self.stemHeight)
        }
    }
}
