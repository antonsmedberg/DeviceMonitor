import SwiftUI

struct AddDeviceView: View {
    @Binding var newName: String
    @Binding var newIP: String
    let onSave: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: AddDeviceField?

    private var isIPLikelyValid: Bool {
        IPv4Validator.isValid(newIP)
    }

    private var isFormValid: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isIPLikelyValid
    }

    var body: some View {
        DeviceModalScaffold(
            title: "Add Device",
            subtitle: "Create a clear label and confirm the IPv4 address.",
            systemImage: "plus.circle.fill"
        ) {
            DeviceModalCard {
                VStack(alignment: .leading, spacing: 16) {
                    DeviceModalInputField(
                        title: "Device name",
                        text: $newName,
                        prompt: "Office Camera",
                        keyboardType: .default,
                        textInputAutocapitalization: .words,
                        submitLabel: .next,
                        focusedField: $focusedField,
                        equals: .name,
                        onSubmit: {
                            focusedField = .ip
                        },
                        iconSystemName: "rectangle.and.pencil.and.ellipsis"
                    )

                    DeviceModalInputField(
                        title: "IPv4 address",
                        text: $newIP,
                        prompt: "192.168.0.24",
                        keyboardType: .numbersAndPunctuation,
                        textInputAutocapitalization: .never,
                        submitLabel: .done,
                        focusedField: $focusedField,
                        equals: .ip,
                        onSubmit: handleSave,
                        iconSystemName: "network"
                    )

                    if !newIP.isEmpty && !isIPLikelyValid {
                        Text("Enter a valid IPv4 address, for example 192.168.0.24.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.warning)
                    }

                    Label(
                        "The device appears immediately in the dashboard after you save it.",
                        systemImage: "bolt.badge.checkmark"
                    )
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    DeviceModalActionButton(
                        title: "Save Device",
                        systemImage: "checkmark.circle.fill",
                        isProminent: true,
                        action: handleSave
                    )
                    .disabled(!isFormValid)
                }
            }
        }
        .task {
            focusedField = .name
        }
    }

    private func handleSave() {
        guard isFormValid, onSave() else { return }
        dismiss()
    }
}

struct DeviceSearchView: View {
    let devices: [Device]
    let onDeleteID: (UUID) -> Void
    let onAddDevice: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText = ""
    @State private var selectedDevice: Device?

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDevices: [Device] {
        guard !trimmedSearchText.isEmpty else { return devices }

        let query = trimmedSearchText.localizedLowercase
        return devices.filter { device in
            device.name.localizedLowercase.contains(query) ||
            device.ipAddress.localizedLowercase.contains(query)
        }
    }

    private var resultsText: String {
        if trimmedSearchText.isEmpty {
            return devices.count == 1 ? "1 device available" : "\(devices.count) devices available"
        }

        return filteredDevices.count == 1 ? "1 match" : "\(filteredDevices.count) matches"
    }

    var body: some View {
        ZStack {
            AppScreenBackground()

            VStack(alignment: .leading, spacing: AppTheme.Layout.contentSpacing) {
                DeviceModalHeader(
                    title: "Search Devices",
                    subtitle: nil,
                    systemImage: "magnifyingglass.circle.fill",
                    onClose: {
                        dismiss()
                    }
                )
                .padding(.horizontal, AppTheme.Layout.screenInset)
                .padding(.top, 12)

                searchCard
                    .padding(.horizontal, AppTheme.Layout.screenInset)

                if filteredDevices.isEmpty {
                    Spacer(minLength: 0)

                    searchEmptyState
                        .padding(.horizontal, AppTheme.Layout.screenInset)

                    Spacer(minLength: 0)
                } else {
                    DeviceSearchResultsList(
                        devices: filteredDevices,
                        onSelectDevice: { device in
                            selectedDevice = device
                        },
                        onDeleteID: onDeleteID
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .fullScreenCover(item: $selectedDevice) { device in
            DeviceDetailView(device: device)
        }
        .task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            isSearchFieldFocused = true
        }
    }

    private var searchCard: some View {
        DeviceModalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            trimmedSearchText.isEmpty
                            ? AppTheme.secondaryText
                            : AppTheme.accent
                        )
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    trimmedSearchText.isEmpty
                                    ? AppTheme.highlightFill
                                    : AppTheme.accentFill
                                )
                        )

                    TextField("Search by name or IP address", text: $searchText)
                        .focused($isSearchFieldFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.primaryText)
                        .tint(AppTheme.accent)

                    if !trimmedSearchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFieldFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .frame(
                                    width: AppTheme.Layout.smallIconButtonSize,
                                    height: AppTheme.Layout.smallIconButtonSize
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
                        .fill(AppTheme.inputFieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
                                .stroke(AppTheme.fieldStroke, lineWidth: 1)
                        )
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: AppTheme.Layout.fieldCornerRadius, style: .continuous)
                )
                .onTapGesture {
                    isSearchFieldFocused = true
                }

                Text(resultsText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .monospacedDigit()
            }
        }
    }

    private var searchEmptyState: some View {
        DeviceModalCard {
            VStack(spacing: 14) {
                Image(systemName: trimmedSearchText.isEmpty ? "desktopcomputer" : "magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(AppTheme.emptyStateIconFill)
                    )

                Text(trimmedSearchText.isEmpty ? "No devices yet" : "No matching devices")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)

                Text(
                    trimmedSearchText.isEmpty
                    ? "Add a device to start monitoring."
                    : "Try another name or IP."
                )
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)

                if trimmedSearchText.isEmpty {
                    DeviceModalActionButton(
                        title: "Add Device",
                        systemImage: "plus",
                        isProminent: true,
                        action: {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 180_000_000)
                                guard !Task.isCancelled else { return }
                                onAddDevice()
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}
