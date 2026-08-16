import XCTest

final class DeviceMonitorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsDeviceMonitorTitle() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Device Monitor"].waitForExistence(timeout: 5))
    }
}
