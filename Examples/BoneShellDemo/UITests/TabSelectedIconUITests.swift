import XCTest
import CoreGraphics

final class TabSelectedIconUITests: XCTestCase {
    private var app: XCUIApplication!
    override func tearDownWithError() throws {
        if let app = app, testRun?.hasSucceeded != true {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Selected icon end state"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app?.terminate()
    }

    func testSelectedColorAndOriginalImageInClassicBars() {
        exercise(system: false)
    }

    func testSelectedColorAndOriginalImageInSystemBars() {
        exercise(system: true)
    }

    private func exercise(system: Bool) {
        app = XCUIApplication()
        app.launchArguments = system ? ["-ui-testing", "-system-bars"] : ["-ui-testing"]
        app.launch()
        let scene = app.buttons["scene.bar-style"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        reveal(scene)
        scene.tap()
        XCTAssertTrue(app.segmentedControls["bar-style.icons"].waitForExistence(timeout: 5))
        choose("bar-style.icons", "资源图片")
        choose("bar-style.tab-colors", "蓝 / 橙")
        choose("bar-style.selected-icon-mode", "选中颜色")
        waitForStatus("选中图标：选中颜色")
        XCTAssertTrue(app.buttons["tab.examples"].isSelected)
        keepScreenshot(system ? "System selected color outline" : "Classic selected color outline")
        choose("bar-style.selected-icon-mode", "选中图片")
        waitForStatus("选中图标：选中图片")
        keepScreenshot(system ? "System selected original image" : "Classic selected original image")
        tapVisibleTab("tab.about")
        XCTAssertTrue(app.staticTexts["about.backgrounds"].waitForExistence(timeout: 5))
        tapVisibleTab("tab.examples")
        waitForStatus("选中图标：选中图片")
        XCTAssertTrue(app.segmentedControls["bar-style.selected-icon-mode"].buttons["选中图片"].isSelected)
    }

    private func choose(_ id: String, _ title: String) {
        let control = app.segmentedControls[id].buttons[title]
        reveal(control)
        control.tap()
        XCTAssertTrue(control.isSelected)
    }

    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<7 {
            var safe = scroll.frame.insetBy(dx: 0, dy: 12)
            let header = app.otherElements["shell.classic.navigation"]
            if header.exists {
                let bottom = safe.maxY
                safe.origin.y = max(safe.minY, header.frame.maxY + 8)
                safe.size.height = max(0, bottom - safe.minY)
            }
            let classic = app.otherElements["shell.classic.tabs"]
            let native = app.tabBars.firstMatch
            if classic.exists { safe.size.height = max(0, min(safe.maxY, classic.frame.minY - 8) - safe.minY) }
            else if native.exists { safe.size.height = max(0, min(safe.maxY, native.frame.minY - 8) - safe.minY) }
            if element.exists && element.isHittable && safe.contains(element.frame) { return }
            if element.exists && element.frame.minY < safe.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func tapVisibleTab(_ id: String) {
        let tab = app.buttons[id]
        for _ in 0..<3 {
            if tab.exists && tab.isHittable { break }
            app.scrollViews["demo.scroll"].firstMatch.swipeDown()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.exists && tab.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        tab.tap()
    }

    private func waitForStatus(_ text: String) {
        let label = app.staticTexts["bar-style.status"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in label.exists && label.label.contains(text) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func keepScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
