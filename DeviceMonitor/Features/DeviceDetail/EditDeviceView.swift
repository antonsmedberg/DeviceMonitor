import SwiftUI

/// Nickname, kind, tags, notes, trust and Wake-on-LAN details: a form sheet that zooms from the detail's More
/// menu, or the same form in the inspector beside a wide detail column.
struct EditDeviceView: View {
    /// A sheet has its own navigation stack with Cancel and Done in its toolbar. The inspector declares no
    /// toolbar items or title, which would land in the detail's navigation bar: a header bar above the form
    /// carries the name, Cancel and Save, and it closes through `dismissEditInspector`.
    enum Presentation: Sendable {
        case sheet, inspector
    }

    let deviceID: UUID
    let presentation: Presentation

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissEditInspector) private var dismissInspector
    @Environment(\.displayScale) private var displayScale
    @State private var nickname = ""
    @State private var kind: DeviceKind = .unknown
    @State private var tagsText = ""
    @State private var notes = ""
    @State private var isFavorite = false
    @State private var isTrusted = false
    @State private var macAddress = ""
    @State private var preferredPortText = ""
    @State private var validationMessage: String?
    @State private var hasLoaded = false
    @State private var showDeleteConfirmation = false

    init(deviceID: UUID, presentation: EditDeviceView.Presentation = .sheet) {
        self.deviceID = deviceID
        self.presentation = presentation
    }

    private var device: DeviceSnapshot? { environment.directory.device(id: deviceID) }

    var body: some View {
        switch presentation {
        case .sheet:
            NavigationStack {
                form
                    .navigationTitle(device?.displayName ?? "Edit Device")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(role: .cancel) { close() }
                                .accessibilityIdentifier("edit.cancel")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(role: .confirm) { save() }
                                .disabled(device == nil)
                                .accessibilityIdentifier("edit.save")
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationSizing(.form)
        case .inspector:
            VStack(spacing: 0) {
                inspectorHeader
                form
            }
        }
    }

    /// Cancel, the device's name and Save on the page colour above a hairline, pinned while the form scrolls.
    /// Like a navigation bar, its text stops growing at the second accessibility size; the name truncates first.
    private var inspectorHeader: some View {
        HStack(spacing: DSLayout.space12) {
            Button {
                close()
            } label: {
                Text("Cancel")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize()
                    .frame(minWidth: DSLayout.minTapTarget, minHeight: DSLayout.minTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit.cancel")
            Text(device?.displayName ?? "Edit Device")
                .font(DSTypography.cardTitle)
                .foregroundStyle(DSColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button {
                save()
            } label: {
                Text("Save")
                    .font(DSTypography.segmentSelected)
                    .foregroundStyle(.tint)
                    .fixedSize()
                    .frame(minWidth: DSLayout.minTapTarget, minHeight: DSLayout.minTapTarget, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(device == nil)
            .accessibilityIdentifier("edit.save")
        }
        .padding(.horizontal, DSLayout.space16)
        .padding(.vertical, DSLayout.space4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DSColor.hairline)
                .frame(height: 1 / displayScale)
        }
        .background {
            DSColor.background
                .ignoresSafeArea()
        }
    }

    /// The grouped list on the page colour, each row on a card; the validation hint in the warn ink and Remove
    /// in the bad ink.
    private var form: some View {
        Form {
            Section {
                Group {
                    TextField(device?.name ?? "Nickname", text: $nickname)
                        .textInputAutocapitalization(.words)
                    if let device {
                        LabeledContent("Address", value: device.host)
                        if let hostname = device.hostname {
                            LabeledContent("Hostname", value: hostname)
                        }
                    }
                }
                .dsListRow()
            } header: {
                DSListHeader("Name")
            }

            Section {
                kindPicker
                    .dsListRow()
            } header: {
                DSListHeader("Kind")
            }

            Section {
                Group {
                    Toggle(isOn: $isFavorite) {
                        DSSettingsLabel("Favorite", systemImage: "star")
                    }
                    Toggle(isOn: $isTrusted) {
                        DSSettingsLabel("Trusted", systemImage: "checkmark.shield")
                    }
                }
                .dsListRow()
            } footer: {
                Text("Trusted devices do not count as strangers or newcomers in your security score.")
            }

            Section {
                Group {
                    TextField("Tags, separated by commas", text: $tagsText)
                        .textInputAutocapitalization(.never)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                .dsListRow()
            } header: {
                DSListHeader("Tags and notes")
            }

            Section {
                Group {
                    TextField("MAC address (for Wake-on-LAN)", text: $macAddress)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("Preferred port (optional)", text: $preferredPortText)
                        .keyboardType(.numberPad)
                }
                .dsListRow()
            } header: {
                DSListHeader("Advanced")
            } footer: {
                Text("The app cannot read MAC addresses itself. Enter one to enable Wake-on-LAN. A preferred port is checked first when monitoring.")
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(DSTypography.rowSubtitle)
                        .foregroundStyle(DSColor.degraded)
                        .dsListRow()
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Remove Device", systemImage: "trash")
                        .foregroundStyle(DSColor.offline)
                }
                .dsListRow()
            }
        }
        .accessibilityIdentifier("screen.editDevice")
        .dsGroupedList()
        .task {
            guard !hasLoaded, let device else { return }
            hasLoaded = true
            nickname = device.nickname ?? ""
            kind = device.kind
            tagsText = device.tags.joined(separator: ", ")
            notes = device.notes
            isFavorite = device.isFavorite
            isTrusted = device.isTrusted
            macAddress = device.macAddress ?? ""
            preferredPortText = device.preferredPort.map(String.init) ?? ""
        }
        .confirmationDialog("Remove this device?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                environment.remove(deviceIDs: [deviceID])
                close()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its history will be deleted. It will reappear if a scan finds it again.")
        }
    }

    /// A pushed list in the sheet; a menu in the inspector, which has no navigation stack to push onto.
    @ViewBuilder
    private var kindPicker: some View {
        let picker = Picker("Kind", selection: $kind) {
            ForEach(DeviceKind.allCases, id: \.self) { kind in
                Label(kind.title, systemImage: kind.systemImage).tag(kind)
            }
        }
        switch presentation {
        case .sheet:
            picker.pickerStyle(.navigationLink)
        case .inspector:
            picker.pickerStyle(.menu)
        }
    }

    private func close() {
        switch presentation {
        case .sheet: dismiss()
        case .inspector: dismissInspector()
        }
    }

    private func save() {
        guard let device else { return }
        var edit = DeviceEdit(snapshot: device)
        edit.nickname = nickname.isEmpty ? nil : nickname
        edit.kind = kind
        edit.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        edit.notes = notes
        edit.isFavorite = isFavorite
        edit.isTrusted = isTrusted
        edit.macAddress = macAddress.isEmpty ? nil : macAddress
        if preferredPortText.trimmingCharacters(in: .whitespaces).isEmpty {
            edit.preferredPort = nil
        } else if let port = HostInputValidator.validatePort(preferredPortText) {
            edit.preferredPort = port
        } else {
            validationMessage = "Enter a port between 1 and 65535."
            return
        }
        do {
            try environment.apply(edit)
            environment.haptics.success()
            close()
        } catch {
            validationMessage = error.errorDescription
            environment.haptics.error()
        }
    }
}

/// Closes the edit inspector. The inspector cannot use `dismiss`: in a split view's detail column it also
/// clears the selected device.
nonisolated struct EditInspectorDismissKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    nonisolated var dismissEditInspector: @MainActor @Sendable () -> Void {
        get { self[EditInspectorDismissKey.self] }
        set { self[EditInspectorDismissKey.self] = newValue }
    }
}
