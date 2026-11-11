import XCTest

final class BarStyleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-system-bars"]
        app.launch()
        let scene = app.buttons["scene.bar-style"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        reveal(scene)
        scene.tap()
        XCTAssertTrue(app.segmentedControls["bar-style.nav-font"].waitForExistence(timeout: 5))
        waitForStatus(["导航：系统 / 系统", "标签：系统 / 系统", "图标：SF 图标"])
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded != true, app != nil {
            keepScreenshot("Bar style failure")
        }
        app?.terminate()
    }

    func testCustomizationChangesTypographyAndBothImageVariants() {
        choose("bar-style.nav-font", "20")
        choose("bar-style.nav-color", "蓝色")
        choose("bar-style.tab-font", "14")
        choose("bar-style.tab-colors", "蓝 / 橙")
        keepScreenshot("Bar style colored SF symbols")
        choose("bar-style.icons", "资源图片")
        waitForStatus(["导航：20 pt / 蓝色", "标签：14 pt / 蓝 / 橙", "图标：资源图片"])
        XCTAssertTrue(app.tabBars.buttons["tab.examples"].isSelected)
        keepScreenshot("Bar style resource icons selected")

        choose("bar-style.icons", "彩色图片")
        waitForStatus(["图标：彩色图片"])
        reveal(app.staticTexts["bar-style.status"], swipingUp: false)
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
        XCTAssertTrue(app.buttons["action.bar-style.next"].isHittable)
        keepScreenshot("Bar style customized fonts and original colors")
    }

    func testDetailIconUpdateAndTabSwitchRetainInputAndNavigation() {
        choose("bar-style.nav-font", "20")
        choose("bar-style.tab-font", "12")
        let next = app.buttons["action.bar-style.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let input = app.textFields["bar-style.detail.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("KeepStyle123")
        let done = app.buttons["action.bar-style.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let changeIcons = app.buttons["bar-style.detail.icons"]
        reveal(changeIcons)
        changeIcons.tap()
        waitForStatus(["图标：彩色图片"], id: "bar-style.detail.status")
        XCTAssertEqual(input.value as? String, "KeepStyle123")

        let about = app.tabBars.buttons["tab.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        tapVisibleTab(about)
        waitUntilSelected(about)
        tapVisibleTab(app.tabBars.buttons["tab.examples"])
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "KeepStyle123")
        waitForStatus(["图标：彩色图片"], id: "bar-style.detail.status")
        keepScreenshot("Bar style detail and input retained")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.segmentedControls["bar-style.nav-font"].waitForExistence(timeout: 5))
        waitForStatus(["导航：20 pt / 系统", "标签：12 pt / 系统", "图标：彩色图片"])
    }

    func testResetReturnsToSystemFontsColorsAndOriginalTabs() {
        choose("bar-style.nav-font", "24")
        choose("bar-style.nav-color", "橙色")
        choose("bar-style.tab-font", "14")
        choose("bar-style.tab-colors", "灰 / 蓝")
        choose("bar-style.icons", "彩色图片")
        waitForStatus(["导航：24 pt / 橙色", "标签：14 pt / 灰 / 蓝", "图标：彩色图片"])
        let reset = app.buttons["bar-style.reset"]
        reveal(reset, swipingUp: false)
        reset.tap()
        waitForStatus(["导航：系统 / 系统", "标签：系统 / 系统", "图标：SF 图标"])
        XCTAssertTrue(app.segmentedControls["bar-style.nav-font"].buttons["系统"].isSelected)
        XCTAssertTrue(app.segmentedControls["bar-style.nav-color"].buttons["系统"].isSelected)
        reveal(app.segmentedControls["bar-style.tab-font"])
        XCTAssertTrue(app.segmentedControls["bar-style.tab-font"].buttons["系统"].isSelected)
        XCTAssertTrue(app.segmentedControls["bar-style.tab-colors"].buttons["系统"].isSelected)
        reveal(app.segmentedControls["bar-style.icons"])
        XCTAssertTrue(app.segmentedControls["bar-style.icons"].buttons["SF 图标"].isSelected)
        XCTAssertEqual(app.tabBars.buttons["tab.examples"].label, "示例")
        XCTAssertEqual(app.tabBars.buttons["tab.materials"].label, "材质")
        XCTAssertEqual(app.tabBars.buttons["tab.about"].label, "关于")
        reveal(app.staticTexts["bar-style.status"], swipingUp: false)
        keepScreenshot("Bar style reset to system")
    }

    private func choose(_ id: String, _ title: String) {
        let control = app.segmentedControls[id].buttons[title]
        reveal(control)
        control.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in control.exists && control.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
    }

    private func reveal(_ element: XCUIElement, swipingUp: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<8 {
            var safe = scroll.frame.insetBy(dx: 0, dy: 12)
            let native = app.tabBars.firstMatch
            if native.exists { safe.size.height = max(0, min(safe.maxY, native.frame.minY - 12) - safe.minY) }
            if element.exists && element.isHittable && safe.contains(element.frame) { return }
            if element.exists && element.frame.minY < safe.minY { scroll.swipeDown() }
            else if swipingUp { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control must be visible and tappable", file: file, line: line)
    }

    private func waitForStatus(_ snippets: [String], id: String = "bar-style.status") {
        let status = app.staticTexts[id]
        let predicate = NSPredicate { _, _ in status.exists && snippets.allSatisfy { status.label.contains($0) } }
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 8), .completed)
    }

    private func tapVisibleTab(_ tab: XCUIElement) {
        for _ in 0..<3 {
            if tab.exists && tab.isHittable { break }
            app.scrollViews["demo.scroll"].firstMatch.swipeDown()
        }
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.exists && tab.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        tab.tap()
    }

    private func waitUntilSelected(_ tab: XCUIElement) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tab.exists && tab.isSelected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 5), .completed)
    }

    private func keepScreenshot(_ name: String) {
        let screenshot = app.screenshot()
        let diagnostic = FileManager.default.temporaryDirectory.appendingPathComponent("BoneShell-style-last.png")
        try? screenshot.pngRepresentation.write(to: diagnostic)
        print("BONESHELL_UI_DIAGNOSTIC " + diagnostic.path)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
