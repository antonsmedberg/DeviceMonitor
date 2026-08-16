import SwiftUI

struct DevicesFilterBar: View, Equatable {
    let selectedFilter: DevicesViewModel.FilterType
    let onSelect: (DevicesViewModel.FilterType) -> Void

    static func == (lhs: DevicesFilterBar, rhs: DevicesFilterBar) -> Bool {
        lhs.selectedFilter == rhs.selectedFilter
    }

    var body: some View {
        Picker(
            "Device Filter",
            selection: Binding(
                get: { selectedFilter },
                set: { onSelect($0) }
            )
        ) {
            ForEach(DevicesViewModel.FilterType.allCases, id: \.self) { filter in
                Text(filter.title)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .tint(selectionTint)
        .frame(maxWidth: 268)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(filterBackdrop)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Device Filter")
        .accessibilityValue(selectedFilter.title)
        .accessibilityHint("Filters the list by all, online, or offline devices")
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }

    private var filterBackdrop: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.03, green: 0.05, blue: 0.10).opacity(0.98),
                            Color(red: 0.07, green: 0.11, blue: 0.20).opacity(0.98),
                            Color(red: 0.10, green: 0.16, blue: 0.28).opacity(0.94)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            AppTheme.backgroundGradient
                .opacity(0.22)
                .clipShape(shape)

            RadialGradient(
                colors: [
                    selectionTint.opacity(0.12),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 160
            )
            .clipShape(shape)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.02),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .clipShape(shape)
        }
        .overlay(
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        selectionTint.opacity(0.08),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        )
        .shadow(color: selectionTint.opacity(0.08), radius: 8, y: 3)
        .shadow(color: AppTheme.shadow.opacity(0.20), radius: 10, y: 4)
    }

    private var selectionTint: Color {
        switch selectedFilter {
            case .all:
                return Color(red: 0.33, green: 0.56, blue: 0.88)
            case .online:
                return Color(red: 0.24, green: 0.70, blue: 0.53)
            case .offline:
                return Color(red: 0.79, green: 0.40, blue: 0.39)
        }
    }
}

private extension DevicesViewModel.FilterType {
    var title: String {
        switch self {
            case .all:
                return "All"
            case .online:
                return "Online"
            case .offline:
                return "Offline"
        }
    }
}
