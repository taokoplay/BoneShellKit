import XCTest
import CoreGraphics

final class BarPresentationUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let scene = app.buttons["scene.presentation"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        reveal(scene)
        var previous = CGRect.null
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard scene.exists && scene.isHittable else { return false }
            let frame = scene.frame
            let stable = frame == previous
            previous = frame
            return stable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        scene.tap()
        XCTAssertTrue(app.segmentedControls["presentation.picker"].waitForExistence(timeout: 5))
        waitForStatus(["导航：经典", "标签：经典"])
    }
    override func tearDownWithError() throws {
        if testRun?.hasSucceeded != true { keepScreenshot("Bar presentation end state") }
        app?.terminate()
    }

    func testClassicDefaultAndSystemSwitch() {
        XCTAssertTrue(app.buttons["shell.classic.back"].isHittable)
        XCTAssertTrue(app.buttons["tab.about"].isHittable)
        keepScreenshot("Classic full width navigation and tabs")
        app.segmentedControls["presentation.picker"].buttons["系统"].tap()
        waitForStatus(["导航：系统", "标签：系统"])
        XCTAssertTrue(app.tabBars.buttons["tab.about"].isHittable)
        keepScreenshot("System presentation restored")
        app.segmentedControls["presentation.picker"].buttons["经典"].tap()
        waitForStatus(["导航：经典", "标签：经典"])
        XCTAssertTrue(app.buttons["shell.classic.back"].isHittable)
    }

    func testInputAndTabStateSurvivePresentationChanges() {
        app.buttons["action.presentation.next"].tap()
        let input = app.textFields["state.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Classic123")
        app.buttons["action.save"].tap()
        app.buttons["action.presentation.toggle"].tap()
        XCTAssertTrue(app.tabBars.buttons["tab.about"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Classic123")
        app.buttons["action.presentation.toggle"].tap()
        XCTAssertTrue(app.buttons["shell.classic.back"].waitForExistence(timeout: 5))
        app.buttons["tab.about"].tap()
        XCTAssertTrue(app.staticTexts["about.backgrounds"].waitForExistence(timeout: 5))
        app.buttons["tab.examples"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Classic123")
        XCTAssertTrue(app.staticTexts["form.status"].label.contains("已保存：Classic123"))
        keepScreenshot("Classic input and navigation retained")
        app.buttons["shell.classic.back"].tap()
        XCTAssertTrue(app.segmentedControls["presentation.picker"].waitForExistence(timeout: 5))
    }

    func testClassicKeepsNativeEdgeBackGesture() {
        app.buttons["action.presentation.next"].tap()
        XCTAssertTrue(app.textFields["state.input"].waitForExistence(timeout: 5))
        let region = app.scrollViews["demo.scroll"].firstMatch
        let start = region.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = region.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.segmentedControls["presentation.picker"].waitForExistence(timeout: 8))
        waitForStatus(["导航：经典", "标签：经典"])
    }

    func testClassicWholeBackgroundRemainsOneCanvas() {
        let background = app.buttons["presentation.background"]
        reveal(background)
        background.tap()
        waitForStatus(["背景：整体画布", "整体：image / ready"])
        keepScreenshot("Classic bars over one unified background")
        reveal(app.segmentedControls["presentation.picker"], upward: false)
        app.segmentedControls["presentation.picker"].buttons["系统"].tap()
        waitForStatus(["导航：系统", "标签：系统", "整体：image / ready"])
        app.segmentedControls["presentation.picker"].buttons["经典"].tap()
        waitForStatus(["导航：经典", "标签：经典", "整体：image / ready"])
    }

    private func reveal(_ element: XCUIElement, upward: Bool = true) {
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<6 {
            if element.exists && element.isHittable {
                var safe = scroll.frame.insetBy(dx: 0, dy: 12)
                let header = app.otherElements["shell.classic.navigation"]
                if header.exists {
                    let bottom = safe.maxY
                    safe.origin.y = max(safe.minY, header.frame.maxY + 12)
                    safe.size.height = max(0, bottom - safe.minY)
                }
                let classic = app.otherElements["shell.classic.tabs"]
                let native = app.tabBars.firstMatch
                if classic.exists { safe.size.height = max(0, min(safe.maxY, classic.frame.minY - 12) - safe.minY) }
                else if native.exists { safe.size.height = max(0, min(safe.maxY, native.frame.minY - 12) - safe.minY) }
                if safe.contains(element.frame) { return }
            }
            if upward { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func waitForStatus(_ snippets: [String]) {
        let label = app.staticTexts["presentation.status"]
        let predicate = NSPredicate { _, _ in label.exists && snippets.allSatisfy { label.label.contains($0) } }
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 12), .completed)
    }
    private func keepScreenshot(_ name: String) {
        guard app != nil else { return }
        let screenshot = app.screenshot()
        let diagnostic = FileManager.default.temporaryDirectory.appendingPathComponent("BoneShell-presentation-last.png")
        try? screenshot.pngRepresentation.write(to: diagnostic)
        print("BONESHELL_UI_DIAGNOSTIC " + diagnostic.path)
        let image = XCTAttachment(screenshot: screenshot)
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
