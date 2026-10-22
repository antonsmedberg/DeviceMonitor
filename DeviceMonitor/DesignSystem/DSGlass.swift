import SwiftUI

/// Transient message that floats above every tab, for errors raised outside the current screen. A card
/// tint keeps it legible over busy lists, and its corners stay concentric with the display's near the top
/// edge.
struct DSGlassToast: View {
    let error: DeviceMonitorError
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(alignment: .top, spacing: DSLayout.space12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DSColor.degraded)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.errorDescription ?? "Something went wrong.")
                        .font(DSTypography.body.weight(.semibold))
                        .foregroundStyle(DSColor.textPrimary)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(DSTypography.rowSubtitle)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSLayout.space16)
            .padding(.vertical, DSLayout.space12)
            .frame(maxWidth: 560)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(DSColor.card.opacity(0.6)).interactive(), in: ConcentricRectangle(corners: .concentric(minimum: 22), isUniform: true))
        .padding(.horizontal, DSLayout.space16)
        .accessibilityHint("Double-tap to dismiss")
    }
}

/// The label of Overview's network menu; the toolbar draws the glass capsule around it. A 20 pt status disc
/// (its fill and glyph say what monitoring is doing), the network name (at most 180 pt, truncated) and a
/// chevron.
struct DSNetworkCapsuleLabel: View {
    private let title: String
    private let status: MonitorStatus

    init(title: String, status: MonitorStatus) {
        self.title = title
        self.status = status
    }

    var body: some View {
        HStack(spacing: DSLayout.space8) {
            disc
            HStack(spacing: 6) {
                WidthLimit(maxWidth: 180) {
                    Text(title)
                        .font(DSTypography.headerName)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network, \(title), \(status.shortHeadline(now: Date()))")
        .accessibilityHint("Shows network actions")
    }

    @ViewBuilder
    private var disc: some View {
        switch status.kind {
        case .live:
            statusDisc(DSColor.onlineFill, glyph: "waveform.path.ecg", ink: .black)
                .dsBreathing(isActive: true, mode: .opacity)
        case .scanning:
            statusDisc(.tint, glyph: "dot.radiowaves.left.and.right", ink: .white)
        case .paused:
            statusDisc(DSColor.degradedFill, glyph: "pause.fill", ink: .black)
        case .offWiFi:
            statusDisc(DSColor.degradedFill, glyph: "wifi.slash", ink: .black)
        case .stale:
            statusDisc(DSColor.degradedFill, glyph: "hourglass", ink: .black)
        case .empty:
            statusDisc(DSColor.neutralMark, glyph: "circle.dashed", ink: .black)
        }
    }

    private func statusDisc<S: ShapeStyle>(_ fill: S, glyph: String, ink: Color) -> some View {
        Circle()
            .fill(fill)
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ink)
            }
    }
}

/// Proposes at most `maxWidth` to its content, so a one-line label hugs a short text and truncates a long one
/// there, also when the parent asks for the ideal size, as a toolbar does. A flexible frame under `fixedSize`
/// would pass the unlimited ideal width through.
private struct WidthLimit: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(limited(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: limited(proposal))
    }

    private func limited(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: proposal.height)
    }
}
