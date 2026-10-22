import XCTest

final class DeviceMonitorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesInDemoMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-uitest"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
