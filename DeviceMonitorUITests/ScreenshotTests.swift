import Foundation
import XCTest

/// Captures App Store / README screenshots from demo data in light and dark appearance.
/// A capture is taken only after its screen's marker appears; a missing marker fails without a capture,
/// so a wrong screen is never saved. Run manually (the CI "Screenshots" job), never in the unit-test lane.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureScreensLight() throws {
        captureAll(appearance: "light")
    }

    @MainActor
    func testCaptureScreensDark() throws {
        captureAll(appearance: "dark")
    }

    /// Each capture follows its own navigation and is skipped, with a failure, when that navigation fails.
    @MainActor
    private func captureAll(appearance: String) {
        let app = UITest.launch(appearance: appearance)
        // Overview is the first tab. Its latency section exists with or without a chart, so it only proves the
        // screen; the offline counter reads 2 once the first demo round has filled in statuses and latency.
        if app.element("overview.latency").waitForExistence(timeout: 30) {
            capture("01-overview-\(appearance)", app: app, marker: "overview.counter.offline", label: "2", timeout: 30, settle: 5)
        } else {
            XCTFail("01-overview-\(appearance): overview.latency missing")
        }

        if app.openTab(.devices) {
            capture("02-devices-\(appearance)", app: app, marker: "filter.all", timeout: 10, settle: 2)
        } else {
            XCTFail("02-devices-\(appearance): screen.devices missing")
        }

        if app.openDevice(host: DemoHost.nas, name: "DiskStation") {
            capture("03-device-detail-\(appearance)", app: app, marker: "detail.hero", label: "DiskStation", timeout: 10, settle: 2)
        } else {
            XCTFail("03-device-detail-\(appearance): deviceRow.\(DemoHost.nas) did not open detail.hero")
        }

        app.backToDevices()
        app.scrollToTop(in: "screen.devices")
        // activity.online is a List row below the journal: reaching it proves the screen, then the capture shows the top.
        if app.openTab(.activity), app.scrollTo("activity.online", in: "screen.activity").exists {
            app.scrollToTop(in: "screen.activity")
            capture("04-activity-\(appearance)", app: app, marker: "screen.activity", timeout: 10, settle: 2)
        } else {
            XCTFail("04-activity-\(appearance): screen.activity or activity.online missing")
        }

        if app.openTab(.insights) {
            capture("05-insights-\(appearance)", app: app, marker: "insights.score", timeout: 10, settle: 2)
        } else {
            XCTFail("05-insights-\(appearance): screen.insights missing")
        }

        if app.openTab(.settings) {
            capture("06-settings-\(appearance)", app: app, marker: "settings.header", timeout: 10, settle: 1)
        } else {
            XCTFail("06-settings-\(appearance): screen.settings missing")
        }

        let scan = app.element("toolbar.scan")
        if app.openTab(.devices), scan.waitForExistence(timeout: 10) {
            scan.tap()
            // Long enough for the zoom, the stage card's exit and the Found list to settle.
            if !capture("07-scan-\(appearance)", app: app, marker: "scan.status", label: "Finished", timeout: 60, settle: 2) {
                XCTFail("07-scan-\(appearance): scan.status \(app.element("scan.status").failureDescription)")
            }
        } else {
            XCTFail("07-scan-\(appearance): screen.devices or toolbar.scan missing")
        }
        app.terminate()
    }

    /// Attaches a screenshot named `name` once `marker` exists (and, with `label`, reads it), after `settle` seconds.
    /// Records a failure and attaches nothing when the marker does not appear in time.
    @MainActor @discardableResult
    func capture(_ name: String, app: XCUIApplication, marker: String, label: String? = nil, timeout: TimeInterval, settle: TimeInterval) -> Bool {
        let element = app.element(marker)
        var found = element.waitForExistence(timeout: timeout)
        if found, let label {
            found = app.waitForText(label, in: element, timeout: timeout)
        }
        guard found else {
            XCTFail("\(name): \(marker) missing")
            return false
        }
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return true
    }
}
