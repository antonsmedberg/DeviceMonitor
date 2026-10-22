import SwiftUI

/// iPhone Duo adaptivity. Everything 27.1-only lives here and compiles to a no-op elsewhere.
extension View {
    /// Reports where an active vertical division (the fold) crosses this view, as a span of x in
    /// the view's own coordinates, or nil when none does, so custom graphics can keep controls off it.
    func duoVerticalDivision(_ span: Binding<ClosedRange<CGFloat>?>) -> some View {
        modifier(DuoVerticalDivisionModifier(span: span))
    }
}

private struct DuoVerticalDivisionModifier: ViewModifier {
    @Binding var span: ClosedRange<CGFloat>?

    func body(content: Content) -> some View {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            content.background {
                GeometryReader { proxy in
                    // Recomputed on every geometry pass, so the fold becoming active without a
                    // resize (flat → partially folded) is picked up too. Frames are in this view's
                    // coordinates, so the span is where the fold really crosses it.
                    let current = proxy.reservedRegions(kind: .division)
                        .filter { $0.isActive && $0.frame.height > $0.frame.width }
                        .max { $0.frame.width < $1.frame.width }
                        .map { $0.frame.minX...$0.frame.maxX }
                    Color.clear
                        .onChange(of: current, initial: true) { _, value in
                            span = value
                        }
                }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
