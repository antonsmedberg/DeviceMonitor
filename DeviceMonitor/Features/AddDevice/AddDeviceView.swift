import SwiftUI

/// Add a device by IPv4, IPv6 or hostname with live validation: a grouped form on the page colour, the hint
/// in the warn ink and a save error in the bad ink.
struct AddDeviceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var portText = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, host, port
    }

    init() {}

    private var validation: Result<HostInput, DeviceMonitorError> {
        HostInputValidator.validate(host)
    }

    private var hostHint: String? {
        guard !host.isEmpty else { return nil }
        if case .failure(let error) = validation { return error.errorDescription }
        return nil
    }

    private var canSave: Bool {
        if case .success = validation, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return portText.isEmpty || HostInputValidator.validatePort(portText) != nil
        }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        TextField("Name", text: $name, prompt: Text("Office printer"))
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .host }
                            .accessibilityIdentifier("addDevice.name")
                        TextField("Address or hostname", text: $host, prompt: Text("192.168.1.24 or printer.local"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($focusedField, equals: .host)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .port }
                            .accessibilityIdentifier("addDevice.address")
                        TextField("Port (optional)", text: $portText, prompt: Text("80"))
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .port)
                            .accessibilityIdentifier("addDevice.port")
                    }
                    .dsListRow()
                } header: {
                    DSListHeader("Device")
                } footer: {
                    if let hostHint {
                        Label(hostHint, systemImage: "exclamationmark.triangle.fill")
                            .font(DSTypography.rowSubtitle)
                            .foregroundStyle(DSColor.degraded)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("addDevice.validation")
                    } else {
                        Text("IPv4, IPv6 and local hostnames are supported. The device is checked right away.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .font(DSTypography.rowSubtitle)
                            .foregroundStyle(DSColor.offline)
                            .dsListRow()
                    }
                }
            }
            .accessibilityIdentifier("screen.addDevice")
            .dsGroupedList()
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                        .accessibilityIdentifier("addDevice.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("addDevice.save")
                }
            }
            .task {
                focusedField = .name
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
    }

    private func save() {
        let port = portText.isEmpty ? nil : HostInputValidator.validatePort(portText)
        do {
            try environment.addManualDevice(name: name, host: host, preferredPort: port)
            dismiss()
        } catch {
            errorMessage = error.errorDescription
            environment.haptics.error()
        }
    }
}
