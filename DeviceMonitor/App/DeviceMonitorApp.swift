import SwiftUI

@main
struct DeviceMonitorApp: App {
    @State private var environment: AppEnvironment? = LaunchArguments.current.isUnitTestHost
        ? nil
        : AppEnvironment.make(arguments: LaunchArguments.current)
    @Environment(\.scenePhase) private var scenePhase

    private static var pinnedColorScheme: ColorScheme? {
        switch LaunchArguments.current.appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootView()
                    .environment(environment)
                    .tint(environment.settings.accent.color)
                    .preferredColorScheme(Self.pinnedColorScheme)
                    .task {
                        environment.start()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        environment.handleScenePhase(phase)
                    }
            }
        }
        .commands {
            DeviceMonitorCommands(environment: environment)
        }
    }
}
