import XCTest

final class BoneShellDemoUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["scene.navigation"].waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws {
        if let run = testRun, run.hasSucceeded == false {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.lifetime = .keepAlways
            add(image)
        }
        app.terminate()
    }
    private func openScene(_ id: String) {
        let row = app.buttons["scene.\(id)"]
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<4 {
            var visible = scroll.frame.insetBy(dx: 0, dy: 16)
            let tabs = app.tabBars.firstMatch
            if tabs.exists { visible.size.height = max(0, min(visible.maxY, tabs.frame.minY - 16) - visible.minY) }
            if row.exists && row.isHittable && visible.contains(row.frame) { break }
            if row.exists && row.frame.minY < visible.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        row.tap()
    }
    func testPrimaryAndOverflowActionsExecuteExactlyOnce() {
        openScene("navigation")
        let primary = app.buttons["action.nav.0"]
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        primary.tap()
        XCTAssertEqual(app.staticTexts["navigation.event"].label, "已触发 1 次：新增")
        for _ in 0..<5 { app.buttons["navigation.add-action"].tap() }
        let overflow = app.buttons["shell.overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 5))
        overflow.tap()
        let help = app.buttons["帮助"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertEqual(app.staticTexts["navigation.event"].label, "已触发 2 次：帮助")
    }
    func testTabSwitchRetainsFormAndNavigationStack() {
        openScene("form")
        let input = app.textFields["state.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("BoneShell123")
        app.buttons["action.save"].tap()
        app.tabBars.buttons["材质"].tap()
        XCTAssertTrue(app.segmentedControls["material.picker"].waitForExistence(timeout: 5))
        app.tabBars.buttons["示例"].tap()
        XCTAssertEqual(app.textFields["state.input"].value as? String, "BoneShell123")
        XCTAssertEqual(app.staticTexts["form.status"].label, "已保存：BoneShell123")
    }
    func testMaterialSwitchAndInteraction() {
        app.tabBars.buttons["材质"].tap()
        let picker = app.segmentedControls["material.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["实色"].tap()
        XCTAssertTrue(app.staticTexts["material.status"].label.contains("实际：实色"))
        picker.buttons["原生玻璃"].tap()
        XCTAssertTrue(app.staticTexts["material.status"].label.contains("请求：原生玻璃"))
        app.buttons["material.press"].tap()
        XCTAssertEqual(app.staticTexts["material.feedback"].label, "已点按 1 次")
    }
    func testSheetClosesAndReturnsToOriginalScreen() {
        openScene("transitions")
        app.buttons["transition.sheet"].tap()
        let close = app.buttons["action.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.buttons["transition.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transition.sheet"].isHittable)
    }
}
