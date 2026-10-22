import Foundation
import XCTest

/// Drives every main feature on demo data, on iPhone and iPad. Each test launches the app fresh, and the
/// in-memory demo store starts every launch from the same network.
final class FlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOverviewShowsNetwork() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.overview), "screen.overview missing")
        app.require("overview.header")
        for identifier in ["overview.latency", "overview.availability"] {
            XCTAssertTrue(app.scrollTo(identifier, in: "screen.overview").exists, "\(identifier) missing")
        }
        // The first demo round marks the printer and the PlayStation offline.
        XCTAssertTrue(app.waitForText("2", in: app.element("overview.counter.offline"), timeout: 30), "overview.counter.offline never read 2")
    }

    @MainActor
    func testCounterOpensOfflineDevices() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.overview), "screen.overview missing")
        let counter = app.element("overview.counter.offline")
        XCTAssertTrue(app.waitForText("2", in: counter, timeout: 30), "overview.counter.offline never read 2")
        counter.tap()
        // On a fresh launch Devices builds its model here, so the pending filter is applied as the model is created.
        app.require("screen.devices", timeout: 10)
        for host in [DemoHost.printer, DemoHost.playStation] {
            XCTAssertTrue(app.element("deviceRow.\(host)").waitForExistence(timeout: 5), "deviceRow.\(host) missing after overview.counter.offline")
        }
        XCTAssertTrue(app.element("deviceRow.\(DemoHost.nas)").waitForNonExistence(timeout: 5), "deviceRow.\(DemoHost.nas) shown after overview.counter.offline")
        XCTAssertTrue(app.waitForSelected(app.element("filter.offline"), timeout: 5), "filter.offline not selected after overview.counter.offline")
    }

    @MainActor
    func testAttentionRowOpensDevice() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.overview), "screen.overview missing")
        let identifier = "overviewRow.\(DemoHost.printer)"
        // The attention card appears once the first demo round finds the printer offline.
        XCTAssertTrue(app.element(identifier).waitForExistence(timeout: 30), "\(identifier) missing")
        let row = app.scrollTo(identifier, in: "screen.overview")
        XCTAssertTrue(row.exists && row.isHittable, "\(identifier) not hittable")
        row.tap()
        XCTAssertTrue(app.waitForText("Office Printer", in: app.element("detail.hero"), timeout: 10), "\(identifier) did not open detail.hero labelled Office Printer")
    }

    @MainActor
    func testShortcutOpensInsightsMap() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.overview), "screen.overview missing")
        // The section and its tiles exist below the fold; the swipes start on the latency chart.
        let section = app.require("overview.shortcuts")
        let sectionBefore = section.failureDescription
        let shortcut = app.scrollTo("overview.shortcut.map", in: "screen.overview")
        XCTAssertTrue(shortcut.exists && shortcut.isHittable, "overview.shortcut.map not hittable: tile \(shortcut.failureDescription), shortcuts \(sectionBefore) before scrolling and \(section.failureDescription) after, window \(app.windows.firstMatch.failureDescription)")
        shortcut.tap()
        app.require("screen.insights", timeout: 10)
        XCTAssertTrue(app.waitForSelected(app.element("insights.section.map"), timeout: 5), "insights.section.map not selected after overview.shortcut.map")
        app.require("insights.map", timeout: 5)
    }

    @MainActor
    func testOpenDeviceShowsDetail() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openDevice(host: DemoHost.nas, name: "DiskStation"), "deviceRow.\(DemoHost.nas) did not open detail.hero labelled DiskStation")
        XCTAssertTrue(app.scrollTo("detail.latencyCard", in: "screen.detail").exists, "detail.latencyCard missing")
    }

    @MainActor
    func testPingShowsResult() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openDevice(host: DemoHost.nas, name: "DiskStation"), "deviceRow.\(DemoHost.nas) did not open detail.hero labelled DiskStation")
        app.require("detail.ping").tap()
        let result = app.element("detail.pingResult")
        if !result.waitForExistence(timeout: 15) {
            app.scrollTo("detail.pingResult", in: "screen.detail")
        }
        XCTAssertTrue(result.exists, "detail.pingResult missing after tapping detail.ping")
    }

    @MainActor
    func testCheckNowConfirms() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openDevice(host: DemoHost.nas, name: "DiskStation"), "deviceRow.\(DemoHost.nas) did not open detail.hero labelled DiskStation")
        app.require("detail.checkNow").tap()
        // The tile's value says "Checked" once a check has finished; its label does so for only 2 s.
        XCTAssertTrue(app.waitForText("Checked", in: app.element("detail.checkNow"), timeout: 15), "detail.checkNow never reported Checked")
    }

    @MainActor
    func testLatencyWindowChanges() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openDevice(host: DemoHost.nas, name: "DiskStation"), "deviceRow.\(DemoHost.nas) did not open detail.hero labelled DiskStation")
        let sixHours = app.scrollTo("detail.window.sixHours", in: "screen.detail")
        XCTAssertTrue(sixHours.exists && sixHours.isHittable, "detail.window.sixHours not hittable")
        sixHours.tap()
        XCTAssertTrue(app.waitForSelected(app.element("detail.window.sixHours"), timeout: 5), "detail.window.sixHours not selected after the tap")
    }

    @MainActor
    func testEditOpensAndCancels() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openDevice(host: DemoHost.nas, name: "DiskStation"), "deviceRow.\(DemoHost.nas) did not open detail.hero labelled DiskStation")
        // Until Edit… is chosen, the editor's buttons exist nowhere, the detail's navigation bar included.
        for identifier in ["edit.save", "edit.cancel"] {
            XCTAssertTrue(app.element(identifier).waitForNonExistence(timeout: 5), "\(identifier) shown before Edit…")
        }
        XCTAssertTrue(app.navigationBars.buttons["Save"].firstMatch.waitForNonExistence(timeout: 5), "a Save button in the navigation bar before Edit…")
        app.require("detail.more").tap()
        app.require("detail.edit", timeout: 5).tap()
        // A sheet, or the inspector beside a regular-width detail column of 700 pt or more: both carry these identifiers.
        app.require("screen.editDevice")
        app.require("edit.cancel").tap()
        XCTAssertTrue(app.element("screen.editDevice").waitForNonExistence(timeout: 5), "screen.editDevice did not close")
    }

    @MainActor
    func testAddDeviceRejectsInvalidAddress() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.devices), "screen.devices missing")
        app.require("toolbar.addDevice").tap()
        app.require("screen.addDevice")
        app.typeInto("addDevice.name", "Test NAS")
        app.typeInto("addDevice.address", "300.1.1.1")
        let validation = app.element("addDevice.validation")
        let save = app.element("addDevice.save")
        XCTAssertTrue(app.waitForText("valid IPv4", in: validation, timeout: 5), "addDevice.validation did not ask for a valid IPv4 address")
        XCTAssertFalse(save.isEnabled, "addDevice.save is enabled with an invalid address")

        let address = app.element("addDevice.address")
        address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9))
        address.typeText("192.168.178.200")
        XCTAssertTrue(validation.waitForNonExistence(timeout: 5), "addDevice.validation still shown for a valid address")
        XCTAssertTrue(save.isEnabled, "addDevice.save is disabled for a valid address")

        app.require("addDevice.cancel").tap()
        XCTAssertTrue(app.element("screen.addDevice").waitForNonExistence(timeout: 5), "screen.addDevice did not close")
    }

    @MainActor
    func testSearchFindsDevice() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.devices), "screen.devices missing")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the Devices search field missing")
        app.typeInto(search, "Disk")
        let result = app.element("deviceRow.\(DemoHost.nas)")
        XCTAssertTrue(result.waitForExistence(timeout: 10), "deviceRow.\(DemoHost.nas) missing for Disk")
        XCTAssertTrue(app.element("deviceRow.\(DemoHost.printer)").waitForNonExistence(timeout: 5), "deviceRow.\(DemoHost.printer) shown for Disk")
        result.tap()
        XCTAssertTrue(app.waitForText("DiskStation", in: app.element("detail.hero"), timeout: 10), "detail.hero not labelled DiskStation")
    }

    @MainActor
    func testOfflineFilterShowsOnlyOfflineDevices() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.devices), "screen.devices missing")
        app.require("filter.offline").tap()
        XCTAssertTrue(app.waitForSelected(app.element("filter.offline"), timeout: 5), "filter.offline not selected after the tap")
        for host in [DemoHost.printer, DemoHost.playStation] {
            XCTAssertTrue(app.element("deviceRow.\(host)").waitForExistence(timeout: 5), "deviceRow.\(host) missing under filter.offline")
        }
        XCTAssertTrue(app.element("deviceRow.\(DemoHost.nas)").waitForNonExistence(timeout: 5), "deviceRow.\(DemoHost.nas) shown under filter.offline")

        app.require("filter.all").tap()
        XCTAssertTrue(app.scrollTo("deviceRow.\(DemoHost.nas)", in: "screen.devices").exists, "deviceRow.\(DemoHost.nas) missing under filter.all")
    }

    @MainActor
    func testActivityAndInsightsOpen() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.activity), "screen.activity missing")
        XCTAssertTrue(app.scrollTo("activity.online", in: "screen.activity").exists, "activity.online missing")
        XCTAssertTrue(app.openTab(.insights), "screen.insights missing")
        for identifier in ["insights.score", "insights.checklist"] {
            XCTAssertTrue(app.scrollTo(identifier, in: "screen.insights").exists, "\(identifier) missing")
        }
        app.openInsightsSection(.map)
        app.require("insights.map", timeout: 5)
        app.openInsightsSection(.presence)
        app.require("insights.presence", timeout: 5)
    }

    @MainActor
    func testTrustStranger() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.insights), "screen.insights missing")
        let trust = app.scrollTo("insights.trust.\(DemoHost.stranger)", in: "screen.insights")
        XCTAssertTrue(trust.exists && trust.isHittable, "insights.trust.\(DemoHost.stranger) missing")
        trust.tap()
        XCTAssertTrue(trust.waitForNonExistence(timeout: 5), "insights.trust.\(DemoHost.stranger) still shown after Trust")
        XCTAssertTrue(app.waitForText("Every device is trusted", in: app.element("insights.strangers.empty"), timeout: 5), "insights.strangers.empty missing")
    }

    @MainActor
    func testScanFinishes() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.devices), "screen.devices missing")
        app.require("toolbar.scan").tap()
        app.require("screen.scan")
        let status = app.require("scan.status")
        XCTAssertTrue(app.waitForText("Finished", in: status, timeout: 60), "scan not finished after 60 s; scan.status \(status.failureDescription)")
        XCTAssertTrue(app.scrollTo("scanRow.\(DemoHost.stranger)", in: "screen.scan").exists, "scanRow.\(DemoHost.stranger) missing")
        app.require("scan.close").tap()
        XCTAssertTrue(app.element("screen.scan").waitForNonExistence(timeout: 10), "screen.scan did not close")
    }

    @MainActor
    func testCheckIntervalChanges() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.settings), "screen.settings missing")
        let picker = app.require("settings.checkInterval")
        let shown = "\(picker.label) \((picker.value as? String) ?? "")"
        let target = shown.localizedCaseInsensitiveContains("1 minute") ? "2 minutes" : "1 minute"
        // The demo settings persist between launches: put back the interval the captures expect, even after a failure.
        addTeardownBlock { @MainActor in
            let running = XCUIApplication()
            guard running.wait(for: .runningForeground, timeout: 1), running.openTab(.settings) else { return }
            let interval = running.element("settings.checkInterval")
            guard interval.exists, !running.waitForText("30 seconds", in: interval, timeout: 1) else { return }
            interval.tap()
            running.tapMenuItem("30 seconds")
        }
        picker.tap()
        XCTAssertTrue(app.tapMenuItem(target), "menu item \(target) missing for settings.checkInterval")
        XCTAssertTrue(app.waitForText(target, in: app.element("settings.checkInterval"), timeout: 5), "settings.checkInterval does not show \(target)")
    }

    @MainActor
    func testSettingsSubPageAndSearch() throws {
        let app = UITest.launch()
        XCTAssertTrue(app.openTab(.settings), "screen.settings missing")
        app.require("settings.row.sensitivity").tap()
        app.require("settings.giveUpAfter", timeout: 5)
        // Back: the button titled Settings, else the bar's first button, as backToDevices() does.
        let back = app.navigationBars.buttons["Settings"].firstMatch
        let first = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "no back button on the Sensitivity page")
        (back.exists ? back : first).tap()
        XCTAssertTrue(app.element("settings.giveUpAfter").waitForNonExistence(timeout: 5), "settings.giveUpAfter still shown after going back")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the Settings search field missing")
        app.typeInto(search, "interval")
        // The results replace the groups: the matching control shows, and an unrelated one goes.
        app.require("settings.checkInterval", timeout: 5)
        XCTAssertTrue(app.element("settings.haptics").waitForNonExistence(timeout: 5), "settings.haptics still shown while searching for interval")
    }
}
