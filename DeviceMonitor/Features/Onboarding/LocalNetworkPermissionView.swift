import SwiftUI

/// Shown when Local Network access is off: what it is for, and a deep link to Settings.
struct LocalNetworkDeniedBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        InfoBanner(
            title: "Local network access is off",
            message: "DeviceMonitor needs it to see the devices on your Wi‑Fi. Turn it on under Settings › Privacy & Security › Local Network.",
            systemImage: "lock.shield.fill",
            tint: DSColor.offline,
            actionTitle: "Open Settings"
        ) {
            if let url = LocalNetworkPermission.settingsURL() {
                openURL(url)
            }
        }
    }
}
