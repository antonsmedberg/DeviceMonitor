import SwiftUI

/// The iPad menu bar for a hardware keyboard: the network actions and the tabs. Every keyboard shortcut in the
/// app lives here, so each exists once.
struct DeviceMonitorCommands: Commands {
    /// Nil only in the unit-test host, which builds no environment.
    let environment: AppEnvironment?

    init(environment: AppEnvironment?) {
        self.environment = environment
    }

    private var pauseTitle: String {
        environment?.isPausedByUser == true ? "Resume Monitoring" : "Pause Monitoring"
    }

    var body: some Commands {
        CommandMenu("Network") {
            Button("Scan Network") {
                present(.scan)
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("Check All Now") {
                environment?.checkAllNow()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(pauseTitle) {
                environment?.togglePause()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Add Device…") {
                present(.addDevice)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Go") {
            Button("Overview") {
                show(.overview)
            }
            .keyboardShortcut("1", modifiers: .command)
            Button("Devices") {
                show(.devices)
            }
            .keyboardShortcut("2", modifiers: .command)
            Button("Activity") {
                show(.activity)
            }
            .keyboardShortcut("3", modifiers: .command)
            Button("Insights") {
                show(.insights)
            }
            .keyboardShortcut("4", modifiers: .command)
            Button("Settings") {
                show(.settings)
            }
            .keyboardShortcut("5", modifiers: .command)
            Button("Find Device") {
                show(.devices)
                environment?.router.isSearchPresented = true
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    private func show(_ tab: AppTab) {
        environment?.router.selectedTab = tab
    }

    /// Sheets open over the selected tab, and zoom out of its Scan or Add control when it has one.
    private func present(_ sheet: AppSheet) {
        environment?.router.present(sheet)
    }
}
