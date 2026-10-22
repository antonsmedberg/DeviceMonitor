import Foundation

/// Launch flags used by previews, UI tests and screenshot runs.
nonisolated struct LaunchArguments: Sendable, Hashable {
    let isDemo: Bool
    let isUITest: Bool
    let isScreenshots: Bool
    let isPreview: Bool
    /// The process hosts the unit tests: build no environment, so no probes or Bonjour run behind them.
    let isUnitTestHost: Bool
    /// `-appearance light|dark` pins the color scheme for screenshot runs.
    let appearance: String?

    static var current: LaunchArguments {
        LaunchArguments(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
    }

    init(arguments: [String], environment: [String: String]) {
        isDemo = arguments.contains("-demo")
        isUITest = arguments.contains("-uitest")
        isScreenshots = arguments.contains("-screenshots")
        isPreview = environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        isUnitTestHost = environment["XCTestConfigurationFilePath"] != nil && !isUITest
        if let flag = arguments.firstIndex(of: "-appearance"), arguments.indices.contains(flag + 1) {
            appearance = arguments[flag + 1]
        } else {
            appearance = nil
        }
    }

    init(isDemo: Bool, isUITest: Bool = false, isScreenshots: Bool = false, isPreview: Bool = false) {
        self.isDemo = isDemo
        self.isUITest = isUITest
        self.isScreenshots = isScreenshots
        self.isPreview = isPreview
        self.isUnitTestHost = false
        self.appearance = nil
    }

    /// Demo data is used whenever the app cannot or should not touch a real network.
    var usesDemoData: Bool { isDemo || isPreview || isScreenshots }
}
