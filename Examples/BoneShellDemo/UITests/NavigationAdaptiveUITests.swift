import XCTest

/// 相同用例运行于普通 iPhone 和 Duo，验证真实控件、菜单及尺寸变化后的页面状态。
final class NavigationAdaptiveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-system-bars", "-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["scene.navigation"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            keepScreenshot("Adaptive navigation failure")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Adaptive navigation accessibility tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testCustomImagesAndAxisKeepNavigationAndInputAfterRotation() {
        openScene("navigation-bars")
        let icons = app.segmentedControls["nav.icon"]
        reveal(icons)
        icons.buttons.element(boundBy: 1).tap()
        let axis = app.segmentedControls["nav.axis"]
        reveal(axis)
        axis.buttons.element(boundBy: 2).tap()
        keepActionScreenshot("Navigation asset image vertical preference", actionID: "action.nav.detail")
        reveal(icons)
        icons.buttons.element(boundBy: 2).tap()
        keepActionScreenshot("Navigation UIImage vertical preference", actionID: "action.nav.detail")

        let detail = app.buttons["action.nav.detail"]
        if !detail.isHittable { openOverflow() }
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.isHittable)
        detail.tap()
        let input = app.textFields["state.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        reveal(input)
        input.press(forDuration: 0.1)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            input.tap()
        }
        input.typeText("DuoNavigation")
        let save = app.buttons["action.save"]
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.staticTexts["form.status"].label.contains("已保存：DuoNavigation"))
        keepScreenshot("Navigation custom image opens saved form")

        XCUIDevice.shared.orientation = .landscapeLeft
        waitForStableWindow()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "DuoNavigation")
        XCTAssertTrue(app.buttons["action.save"].isHittable)
        keepScreenshot("Navigation form landscape retains input")
        XCUIDevice.shared.orientation = .portrait
        waitForStableWindow()
        XCTAssertEqual(input.value as? String, "DuoNavigation")
        XCTAssertTrue(app.staticTexts["form.status"].label.contains("已保存：DuoNavigation"))
        keepScreenshot("Navigation form portrait retains input")
    }

    func testNativeOverflowKeepsAllActionsReachableAndExecutesExactlyOnce() {
        openScene("navigation")
        let primary = app.buttons["action.nav.0"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.isHittable)
        primary.tap()
        XCTAssertEqual(app.staticTexts["navigation.event"].label, "已触发 1 次：新增")
        for _ in 0..<5 {
            let add = app.buttons["navigation.add-action"]
            reveal(add)
            add.tap()
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForStableWindow()
        keepScreenshot("Navigation eight actions before overflow")
        openOverflow()
        let menuHelp = app.buttons.matching(identifier: "action.nav.7").allElementsBoundByIndex.first { $0.isHittable }
            ?? app.buttons.matching(NSPredicate(format: "label == %@", "帮助")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(menuHelp, app.debugDescription)
        keepScreenshot("Navigation eight actions reachable")
        menuHelp?.tap()
        XCTAssertEqual(app.staticTexts["navigation.event"].label, "已触发 2 次：帮助")
        XCUIDevice.shared.orientation = .portrait
        waitForStableWindow()
        XCTAssertEqual(app.staticTexts["navigation.event"].label, "已触发 2 次：帮助")
        keepScreenshot("Navigation action result after rotation")
    }

    private func waitForStableWindow() {
        var previousFrame: CGRect?
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.app.frame
            guard !frame.isEmpty else { return false }
            if frame != previousFrame {
                previousFrame = frame
                stableSince = Date()
                return false
            }
            return Date().timeIntervalSince(stableSince) >= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
        let geometry = XCTAttachment(string: "Observed window after orientation request: \(app.frame)")
        geometry.name = "Observed window geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func openScene(_ id: String) {
        let row = app.buttons["scene.\(id)"]
        let destination = app.staticTexts[id == "navigation" ? "navigation.event" : "nav.status"]
        for _ in 0..<2 {
            reveal(row)
            row.press(forDuration: 0.1)
            if destination.waitForExistence(timeout: 5) { return }
            if !row.exists || !row.isHittable { break }
        }
        XCTAssertTrue(destination.exists, "Scene must open before checking navigation actions: \(app.debugDescription)")
    }

    private func reveal(_ element: XCUIElement) {
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<8 {
            if element.exists && element.isHittable && scroll.frame.insetBy(dx: 0, dy: 12).contains(element.frame) { return }
            if element.exists && element.frame.minY < scroll.frame.minY + 12 { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func openOverflow() {
        let predicate = NSPredicate(format: "identifier == %@ OR label IN %@", "shell.overflow", ["More", "更多", "More Actions", "更多操作"])
        let overflow = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(overflow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(overflow.isHittable)
        overflow.tap()
    }

    private func keepActionScreenshot(_ name: String, actionID: String) {
        if app.buttons[actionID].isHittable {
            keepScreenshot(name)
        } else {
            openOverflow()
            keepScreenshot(name + " in overflow")
            // 点到内容边缘以收起菜单，避开页面内的业务控件。
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        }
    }

    private func keepScreenshot(_ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
