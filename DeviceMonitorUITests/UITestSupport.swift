import Foundation
import XCTest

/// Demo hosts from DemoFixtures: these identifiers are stable across launches.
enum DemoHost {
    static let nas = "192.168.178.2"
    static let printer = "192.168.178.52"
    static let playStation = "192.168.178.89"
    static let stranger = "192.168.178.117"
}

/// The app's tabs, with the identifiers of their tab button and their screen.
enum AppTab: String, CaseIterable {
    case overview, devices, activity, insights, settings

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var marker: String { "screen.\(rawValue)" }
    var identifier: String { "tab.\(rawValue)" }
}

/// The sections of Insights, a test-side mirror of the app's InsightsSection: segments "insights.section.<raw>".
enum InsightsSectionID: String, CaseIterable {
    case security, map, presence
}

enum UITest {
    /// Launches with -demo -uitest -screenshots -appearance <appearance> and waits for .runningForeground (60 s).
    @MainActor static func launch(appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-uitest", "-screenshots", "-appearance", appearance]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "the app did not reach the foreground")
        return app
    }
}

extension XCUIApplication {
    /// Any element with this accessibility identifier.
    @MainActor func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for the identifier; on timeout records a failure naming it.
    @MainActor @discardableResult
    func require(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        if !found.waitForExistence(timeout: timeout) {
            XCTFail("\(identifier) did not appear within \(Int(timeout)) s", file: file, line: line)
        }
        return found
    }

    /// Swipes the named container (a screen marker such as "screen.devices") up until the element is hittable.
    /// Naming the container matters on iPad, where the sidebar List and the detail ScrollView both exist.
    @MainActor @discardableResult
    func scrollTo(_ identifier: String, in container: String, swipes: Int = 6) -> XCUIElement {
        let target = element(identifier)
        let scroller = element(container)
        var count = 0
        while !(target.exists && target.isHittable) && count < swipes && scroller.exists {
            scroller.swipeUp()
            count += 1
        }
        return target
    }

    /// Two swipeDown() on the container: back to the top, which also restores a tab bar minimised on scroll.
    @MainActor func scrollToTop(in container: String) {
        let scroller = element(container)
        for _ in 0..<2 where scroller.exists {
            scroller.swipeDown()
        }
    }

    /// Taps the tab (identifier, then title) and waits for its screen marker; 3 attempts. Before a retry: when the tab
    /// button is not hittable, scrollToTop(in:) on whichever screen marker exists, else tap tabBars.firstMatch to expand
    /// a minimised bar. For .devices while that tab is selected, or on a retry, calls backToDevices() first: queries
    /// for absent identifiers walk the whole tree, which slow CI hosts can time out on.
    /// (Not named open(_:), which would overload XCUIApplication.open(_ url: URL).)
    @MainActor @discardableResult
    func openTab(_ tab: AppTab) -> Bool {
        let marker = element(tab.marker)
        for attempt in 1...3 {
            if tab == .devices, attempt > 1 || tabButton(.devices).isSelected {
                backToDevices()
            }
            let button = tabButton(tab)
            if button.exists, button.isHittable {
                button.tap()
                if marker.waitForExistence(timeout: 10) {
                    return true
                }
            }
            guard attempt < 3 else { break }
            let retry = tabButton(tab)
            if !(retry.exists && retry.isHittable) {
                if let screen = visibleScreen() {
                    scrollToTop(in: screen)
                } else if tabBars.firstMatch.exists {
                    tabBars.firstMatch.tap()
                }
            }
        }
        return marker.exists
    }

    /// Devices → scrollTo the row for `host` in screen.devices → tap → detail.hero labelled with `name`.
    /// iPhone pushes; iPad selects in the sidebar.
    @MainActor @discardableResult
    func openDevice(host: String, name: String) -> Bool {
        guard openTab(.devices) else { return false }
        let row = scrollTo("deviceRow.\(host)", in: "screen.devices")
        guard row.exists, row.isHittable else { return false }
        row.tap()
        return waitForText(name, in: element("detail.hero"), timeout: 10)
    }

    /// Requires screen.insights, scrolls it to the top (the segmented control is its first child), waits up to 5 s
    /// for the section's segment to be hittable, taps it and waits up to 5 s for it to read as selected.
    /// Every failure is recorded with the identifier it concerns.
    @MainActor @discardableResult
    func openInsightsSection(_ section: InsightsSectionID) -> Bool {
        guard require("screen.insights").exists else { return false }
        scrollToTop(in: "screen.insights")
        let identifier = "insights.section.\(section.rawValue)"
        let segment = element(identifier)
        let end = Date().addingTimeInterval(5)
        while !(segment.exists && segment.isHittable) && Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        guard segment.exists, segment.isHittable else {
            XCTFail("\(identifier) was not hittable within 5 s")
            return false
        }
        segment.tap()
        guard waitForSelected(segment, timeout: 5) else {
            XCTFail("\(identifier) was not selected within 5 s of the tap")
            return false
        }
        return true
    }

    /// With a detail shown and the list not beside it (iPhone): taps navigationBars.buttons["Devices"] (fallback: the
    /// navigation bar's first button), then requires screen.devices. Otherwise nothing. It asks for the detail first,
    /// which exists in that state, rather than the list, which does not.
    @MainActor func backToDevices() {
        guard element("screen.detail").exists else { return }
        let back = navigationBars.buttons["Devices"].firstMatch
        if back.exists {
            back.tap()
        } else {
            let list = element("screen.devices")
            if list.exists, list.isHittable { return }
            let first = navigationBars.firstMatch.buttons.firstMatch
            if first.exists {
                first.tap()
            }
        }
        require("screen.devices")
    }

    /// A menu item by title: buttons first, then menuItems.
    @MainActor @discardableResult
    func tapMenuItem(_ title: String) -> Bool {
        let button = buttons[title].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
            return true
        }
        let item = menuItems[title].firstMatch
        if item.waitForExistence(timeout: 2) {
            item.tap()
            return true
        }
        return false
    }

    /// Taps the field; if a first-run keyboard tip shows a "Continue" button within 1 s, taps it; then types.
    @MainActor func typeInto(_ identifier: String, _ text: String) {
        typeInto(require(identifier), text)
    }

    @MainActor func typeInto(_ field: XCUIElement, _ text: String) {
        field.tap()
        let tip = buttons["Continue"].firstMatch
        if tip.waitForExistence(timeout: 1) {
            tip.tap()
        }
        field.typeText(text)
    }

    /// Polls every 0.25 s until `label` or a String `value` contains `text` (case-insensitive).
    @MainActor func waitForText(_ text: String, in element: XCUIElement, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists,
               element.label.localizedCaseInsensitiveContains(text)
                || ((element.value as? String)?.localizedCaseInsensitiveContains(text) ?? false) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < end
        return false
    }

    /// Polls every 0.25 s until the element exists and is selected.
    @MainActor func waitForSelected(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < end
        return false
    }

    /// The tab's button: by identifier, then by title in the tab bar, then any button with that title.
    @MainActor private func tabButton(_ tab: AppTab) -> XCUIElement {
        let byIdentifier = element(tab.identifier)
        if byIdentifier.exists {
            return byIdentifier
        }
        let inTabBar = tabBars.buttons[tab.title].firstMatch
        return inTabBar.exists ? inTabBar : buttons[tab.title].firstMatch
    }

    /// The marker of the screen currently shown, if any.
    @MainActor private func visibleScreen() -> String? {
        (AppTab.allCases.map(\.marker) + ["screen.detail"]).first { element($0).exists }
    }
}

extension XCUIElement {
    /// The label and frame from one snapshot, or "missing", for failure messages. A snapshot throws for an element
    /// that has gone, where reading `label` or `frame` would record a failure of its own.
    @MainActor var failureDescription: String {
        guard let snapshot = try? self.snapshot() else { return "missing" }
        return "\"\(snapshot.label)\" at \(snapshot.frame)"
    }
}
