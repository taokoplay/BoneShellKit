import XCTest

/// Navigation settings live on one page, independent of the tab bar.
final class NavigationBarUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-classic-bars"]
        app.launch()
        let scene = app.buttons["scene.navigation-bars"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        reveal(scene)
        scene.tap()
        XCTAssertTrue(app.staticTexts["nav.status"].waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testEveryNavigationSettingIsOnOnePage() {
        for id in ["nav.title-size", "nav.title-color", "nav.subtitle",
                   "nav.large-title", "nav.button-size", "nav.presentation"] {
            reveal(app.segmentedControls[id])
            XCTAssertTrue(app.segmentedControls[id].exists, "Missing \(id)")
        }
        keepScreenshot("Navigation settings on one page")
    }

    func testTitleAndButtonChangesApplyImmediately() {
        reveal(app.segmentedControls["nav.title-size"])
        app.segmentedControls["nav.title-size"].buttons["24"].tap()
        waitForStatus(["标题：24 pt"])
        reveal(app.segmentedControls["nav.title-color"])
        app.segmentedControls["nav.title-color"].buttons["橙"].tap()
        waitForStatus(["标题：24 pt / 橙"])
        keepScreenshot("Navigation title 24 pt orange")
    }

    func testNavigationPresentationStaysIndependentOfTabs() {
        reveal(app.segmentedControls["nav.presentation"])
        app.segmentedControls["nav.presentation"].buttons["经典"].tap()
        waitForStatus(["形态：经典"])
        XCTAssertTrue(app.buttons["shell.classic.back"].exists || app.otherElements["shell.classic.navigation"].exists)
        keepScreenshot("Navigation forced to classic")
    }

    func testDetailKeepsInputAndNavigation() {
        reveal(app.buttons["nav.detail"])
        app.buttons["nav.detail"].tap()
        let input = app.textFields["state.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8))
        input.tap()
        input.typeText("Nav123")
        app.buttons["action.save"].tap()
        XCTAssertTrue(app.staticTexts["form.status"].label.contains("已保存：Nav123"))
        app.buttons["tab.about"].tap()
        XCTAssertTrue(app.staticTexts["about.backgrounds"].waitForExistence(timeout: 5))
        app.buttons["tab.examples"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Nav123")
    }

    // MARK: - Helpers

    private func reveal(_ element: XCUIElement, upward: Bool = true) {
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            if upward { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func waitForStatus(_ snippets: [String]) {
        let label = app.staticTexts["nav.status"]
        let predicate = NSPredicate { _, _ in label.exists && snippets.allSatisfy { label.label.contains($0) } }
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 10), .completed)
    }

    private func keepScreenshot(_ name: String) {
        guard app != nil else { return }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
