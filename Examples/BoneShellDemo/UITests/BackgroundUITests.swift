import XCTest
import UIKit

final class BackgroundUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let scene = app.buttons["scene.backgrounds"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        scene.tap()
        XCTAssertTrue(app.segmentedControls["background.source"].waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws {
        if testRun?.hasSucceeded != true {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app.terminate()
    }
    private func waitForStatus(_ snippets: [String], id: String = "background.status", timeout: TimeInterval = 15) {
        let label = app.staticTexts[id]
        let predicate = NSPredicate { _, _ in label.exists && snippets.allSatisfy { label.label.contains($0) } }
        expectation(for: predicate, evaluatedWith: nil)
        waitForExpectations(timeout: timeout)
    }
    private func waitForUnifiedStatus(_ source: String, playing: Int = 0, budget: Int = 1, id: String = "background.status", timeout: TimeInterval = 15) {
        waitForStatus(["模式：整体画布", "画布：1", "整体：\(source) / ready", "页面：共享画布", "导航：共享画布", "标签：共享画布", "播放：\(playing)/\(budget)"], id: id, timeout: timeout)
    }
    private func assertNavigationTitleIsRendered(file: StaticString = #filePath, line: UInt = #line) {
        let title = app.navigationBars.staticTexts["背景与切页"]
        XCTAssertTrue(title.exists, file: file, line: line)
        guard let image = title.screenshot().image.cgImage else {
            XCTFail("Navigation title screenshot is unavailable", file: file, line: line)
            return
        }
        let width = image.width
        let height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let darkPixels = rgba.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: pixels.count, by: 4).reduce(0) { count, offset in
                count + (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2]) < 180
                    && pixels[offset + 3] > 200 ? 1 : 0)
            }
        }
        // Demo fixtures use light backgrounds: black native title glyphs must be visible.
        XCTAssertGreaterThan(darkPixels, 20, "Background covered the native navigation title", file: file, line: line)
    }
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testUnifiedImageAndBackRestoration() {
        waitForUnifiedStatus("image")
        XCTAssertTrue(app.segmentedControls["background.scope"].buttons["全部"].isSelected)
        assertNavigationTitleIsRendered()
        keepScreenshot("Unified image background")
        app.buttons["action.background.next"].tap()
        waitForUnifiedStatus("image", id: "background.detail.status")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.segmentedControls["background.source"].waitForExistence(timeout: 5))
        waitForUnifiedStatus("image")
        XCTAssertTrue(app.segmentedControls["background.scope"].buttons["全部"].isSelected)
    }
    func testGIFBudgetAndStopWhenSwitchingTabs() {
        app.segmentedControls["background.source"].buttons["动图"].tap()
        waitForUnifiedStatus("animatedImage", playing: 1)
        app.tabBars.buttons["关于"].tap()
        let label = app.staticTexts["about.backgrounds"]
        expectation(for: NSPredicate { _, _ in label.exists && label.label.contains("动态背景运行：0") }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        app.tabBars.buttons["示例"].tap()
        waitForUnifiedStatus("animatedImage", playing: 1)
    }
    func testUnifiedGIFKeepsOnePlaybackWithBudgetThreeAcrossPushAndPop() {
        app.segmentedControls["background.source"].buttons["动图"].tap()
        waitForUnifiedStatus("animatedImage", playing: 1)
        app.segmentedControls["background.budget"].buttons["3 个"].tap()
        waitForUnifiedStatus("animatedImage", playing: 1, budget: 3)
        assertNavigationTitleIsRendered()
        keepScreenshot("Unified GIF background")
        app.buttons["action.background.next"].tap()
        waitForUnifiedStatus("animatedImage", playing: 1, budget: 3, id: "background.detail.status")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.segmentedControls["background.source"].waitForExistence(timeout: 5))
        waitForUnifiedStatus("animatedImage", playing: 1, budget: 3)
        XCTAssertTrue(app.segmentedControls["background.scope"].buttons["全部"].isSelected)
    }
    func testVideoAndHTMLRemainInteractive() {
        let picker = app.segmentedControls["background.source"]
        picker.buttons["MP4"].tap()
        waitForUnifiedStatus("video", playing: 1, timeout: 20)
        picker.buttons["HTML"].tap()
        waitForUnifiedStatus("html", playing: 1, timeout: 25)
        app.buttons["action.background.next"].tap()
        waitForUnifiedStatus("html", playing: 1, id: "background.detail.status", timeout: 25)
        XCTAssertTrue(app.textFields["background.detail.input"].isHittable)
    }
    func testDynamicBudgetRebalancesFromThreeToOne() {
        app.segmentedControls["background.scope"].buttons["分区"].tap()
        app.segmentedControls["background.source"].buttons["动图"].tap()
        app.segmentedControls["background.budget"].buttons["3 个"].tap()
        waitForStatus(["页面：animatedImage / ready", "导航：animatedImage / ready", "标签：animatedImage / ready", "播放：3/3"])
        assertNavigationTitleIsRendered()
        keepScreenshot("Three animated backgrounds")
        app.segmentedControls["background.budget"].buttons["1 个"].tap()
        waitForStatus(["页面：animatedImage / ready", "导航：animatedImage / paused", "标签：animatedImage / paused", "播放：1/1"])
    }
    func testNativeBarMediaCanRunIndependently() {
        let source = app.segmentedControls["background.source"]
        let scope = app.segmentedControls["background.scope"]
        scope.buttons["导航"].tap()
        source.buttons["HTML"].tap()
        waitForStatus(["页面：none / idle", "导航：html / ready", "标签：none / idle", "播放：1/1"], timeout: 25)
        assertNavigationTitleIsRendered()
        keepScreenshot("HTML navigation background")
        scope.buttons["标签"].tap()
        waitForStatus(["导航：none / idle", "标签：html / ready", "播放：1/1"], timeout: 25)
        source.buttons["MP4"].tap()
        waitForStatus(["页面：none / idle", "导航：none / idle", "标签：video / ready", "播放：1/1"], timeout: 20)
        keepScreenshot("MP4 tab background")
    }
    func testRapidChangesKeepLatestImage() {
        let cycle = app.buttons["background.cycle"]
        if !cycle.isHittable { app.scrollViews["demo.scroll"].firstMatch.swipeUp() }
        cycle.tap()
        waitForUnifiedStatus("image", timeout: 20)
    }
}
