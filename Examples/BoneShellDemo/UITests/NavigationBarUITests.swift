import XCTest

/// Navigation settings live on one page, independent of the tab bar.
final class NavigationBarUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func openNavigationSettings(arguments: [String] = ["-ui-testing", "-classic-bars"]) {
        app.launchArguments = arguments
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
        openNavigationSettings()
        for id in ["nav.title-size", "nav.title-color", "nav.subtitle",
                   "nav.large-title", "nav.button-size", "nav.presentation"] {
            reveal(app.segmentedControls[id])
            XCTAssertTrue(app.segmentedControls[id].exists, "Missing \(id)")
        }
        keepScreenshot("Navigation settings on one page")
    }

    func testTitleAndButtonChangesApplyImmediately() {
        openNavigationSettings()
        exerciseTitleSizeWithoutChangingButtons()
        let orange = app.segmentedControls["nav.title-color"].buttons["橙"]
        reveal(orange)
        orange.press(forDuration: 0.2)
        waitForStatus(["标题：24 pt / 橙"])
        keepScreenshot("Navigation title 24 pt orange")
    }

    func testTitleSizeKeepsButtonSizeInSystemNavigation() {
        openNavigationSettings(arguments: ["-ui-testing", "-system-bars"])
        exerciseTitleSizeWithoutChangingButtons()
    }

    private func exerciseTitleSizeWithoutChangingButtons() {
        let titleSize = app.segmentedControls["nav.title-size"].buttons["24"]
        let done = app.buttons["action.nav.text"]
        reveal(titleSize)
        waitForStatus(["标题：系统", "按钮：系统"])
        XCTAssertTrue(done.isHittable)
        keepScreenshot("System title size and system button size")

        titleSize.press(forDuration: 0.2)
        waitForStatus(["标题：24 pt", "按钮：系统"])
        XCTAssertTrue(done.isHittable)
        keepScreenshot("24 pt title and system button size")
    }

    func testNavigationPresentationStaysIndependentOfTabs() {
        openNavigationSettings()
        reveal(app.segmentedControls["nav.presentation"])
        app.segmentedControls["nav.presentation"].buttons["经典"].tap()
        waitForStatus(["形态：经典"])
        XCTAssertTrue(app.buttons["shell.classic.back"].exists || app.otherElements["shell.classic.navigation"].exists)
        keepScreenshot("Navigation forced to classic")
    }

    func testCustomTitleMenuInClassicNavigation() {
        openNavigationSettings(arguments: ["-classic-bars"])
        XCTAssertTrue(app.otherElements["shell.classic.navigation"].exists)
        exerciseCustomTitleMenu(restoredTitle: app.staticTexts["shell.classic.title"])
    }

    func testCustomTitleMenuInSystemNavigation() {
        openNavigationSettings(arguments: ["-system-bars"])
        let titleLabels = NSPredicate(format: "label IN %@", ["导航栏", "导航栏, 标题、按钮与形态"])
        let standardTitle = app.navigationBars.firstMatch.descendants(matching: .any).matching(titleLabels).firstMatch
        exerciseCustomTitleMenu(restoredTitle: standardTitle)
    }

    private func exerciseCustomTitleMenu(restoredTitle: XCUIElement) {
        let titleMode = app.segmentedControls["nav.title-view"]
        let customMode = titleMode.buttons["自定义"]
        reveal(customMode)
        // A brief press lets the scroll view deliver the touch to the segmented control.
        customMode.press(forDuration: 0.2)
        waitForStatus(["自定义标题：全部来源"])
        XCTAssertTrue(customMode.isSelected)
        let title = app.buttons["nav.custom-title-button"]
        XCTAssertEqual(app.buttons.matching(identifier: "nav.custom-title-button").count, 1)
        XCTAssertTrue(title.isHittable)
        title.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
                                                       "本地来源", "nav.custom-title-button")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        keepScreenshot("Open custom title menu")
        choice.tap()
        waitForStatus(["自定义标题：本地来源"])
        XCTAssertTrue(choice.waitForNonExistence(timeout: 5))
        XCTAssertEqual(title.label, "本地来源")
        let standardMode = titleMode.buttons["文字"]
        reveal(standardMode, upward: false)
        standardMode.press(forDuration: 0.2)
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(standardMode.isSelected)
        XCTAssertTrue(restoredTitle.waitForExistence(timeout: 5))
        keepScreenshot("Restored standard navigation title")
    }

    func testDetailKeepsInputAndNavigation() {
        openNavigationSettings()
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
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 10), .completed,
                       "Expected \(snippets) in navigation status")
    }

    private func keepScreenshot(_ name: String) {
        guard app != nil else { return }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
