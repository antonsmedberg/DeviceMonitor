import SwiftUI

enum AddDeviceField: Hashable {
    case name
    case ip
}

struct DeviceModalScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    private let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "square.stack.3d.up.fill",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Layout.contentSpacing) {
                    DeviceModalHeader(
                        title: title,
                        subtitle: subtitle,
                        systemImage: systemImage,
                        onClose: {
                            dismiss()
                        }
                    )

                    content
                }
                .padding(.horizontal, AppTheme.Layout.screenInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .scrollDismissesKeyboard(.interactively)
        .fontDesign(.rounded)
    }
}

struct DeviceModalHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.selectedControlFill)

                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    ViewThatFits(in: .horizontal) {
                        Text(title)
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(title)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, AppTheme.Layout.compactIconButtonSize + 12)

            ModalCloseButton(action: onClose)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

private struct ModalCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .frame(
                    width: AppTheme.Layout.compactIconButtonSize,
                    height: AppTheme.Layout.compactIconButtonSize
                )
        }
        .appCompactCircularGlassButton()
        .accessibilityLabel("Close")
    }
}

struct DeviceModalCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: AppTheme.Layout.cardCornerRadius,
            style: .continuous
        )

        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Layout.modalCardPadding)
            .background(
                ZStack {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.sheetCardFill,
                                    AppTheme.cardFill
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(shape)
                .overlay(
                    shape.stroke(AppTheme.strongStroke, lineWidth: 1)
                )
            )
            .shadow(color: AppTheme.shadow.opacity(0.62), radius: 6, y: 4)
    }
}

struct DeviceModalActionButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if isProminent {
            Button(action: action) {
                label
            }
            .appProminentGlassButton()
        } else {
            Button(action: action) {
                label
            }
            .appGlassButton()
        }
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }
}

struct DeviceModalInputField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let keyboardType: UIKeyboardType
    let textInputAutocapitalization: TextInputAutocapitalization
    let submitLabel: SubmitLabel
    let focusedField: FocusState<AddDeviceField?>.Binding
    let equals: AddDeviceField
    let onSubmit: () -> Void
    let iconSystemName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 10) {
                if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                TextField(prompt, text: $text)
                    .focused(focusedField, equals: equals)
                    .textInputAutocapitalization(textInputAutocapitalization)
                    .autocorrectionDisabled()
                    .keyboardType(keyboardType)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .tint(AppTheme.accent)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.inputFieldFill,
                                AppTheme.controlFill
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
                            .stroke(AppTheme.fieldStroke, lineWidth: 1)
                    )
            )
        }
    }
}

struct DeviceDetailRow: View {
    let label: String
    let value: String
    let isCopyable: Bool

    init(label: String, value: String, isCopyable: Bool = false) {
        self.label = label
        self.value = value
        self.isCopyable = isCopyable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            HStack(alignment: .center, spacing: 10) {
                Text(value)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.84)

                Spacer(minLength: 0)

                if isCopyable {
                    Button {
                        UIPasteboard.general.string = value
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .frame(
                                width: AppTheme.Layout.smallIconButtonSize,
                                height: AppTheme.Layout.smallIconButtonSize
                            )
                    }
                    .appCircularGlassButton()
                    .accessibilityLabel("Copy \(label)")
                }
            }
        }
    }
}

struct StatusEventRow: View {
    let status: StatusEvent

    private var tint: Color {
        status.isOnline ? AppTheme.online : AppTheme.offline
    }

    private var title: String {
        status.isOnline ? "Device became online" : "Device became offline"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: status.isOnline ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)

                Text(status.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .appCardStyle(
            cornerRadius: 18,
            fill: AppTheme.controlFill,
            stroke: AppTheme.cardStroke,
            shadowRadius: 0,
            shadowY: 0
        )
    }
}
