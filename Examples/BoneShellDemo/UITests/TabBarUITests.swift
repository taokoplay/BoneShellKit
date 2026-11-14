import XCTest
import UIKit

/// Tab-bar settings live on one page: text, icons, selected policy, presentation, accessories.
final class TabBarUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-classic-bars"]
        app.launch()
        let scene = app.buttons["scene.tab-bars"]
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        reveal(scene)
        scene.tap()
        XCTAssertTrue(app.staticTexts["tabbar.status"].waitForExistence(timeout: 5))
    }
    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testEveryTabSettingIsOnOnePage() {
        for id in ["tabbar.size", "tabbar.colors", "tabbar.icons", "tabbar.selected-mode",
                   "tabbar.presentation", "tabbar.accessories"] {
            reveal(app.segmentedControls[id])
            XCTAssertTrue(app.segmentedControls[id].exists, "Missing \(id)")
        }
        keepScreenshot("Tab bar settings on one page")
    }

    func testIconPolicyAndPresentationUpdateStatus() {
        reveal(app.segmentedControls["tabbar.size"], upward: true)
        app.segmentedControls["tabbar.size"].buttons["14"].tap()
        reveal(app.segmentedControls["tabbar.colors"])
        app.segmentedControls["tabbar.colors"].buttons["蓝 / 橙"].tap()
        reveal(app.segmentedControls["tabbar.icons"], upward: true)
        app.segmentedControls["tabbar.icons"].buttons["资源图片"].tap()
        reveal(app.segmentedControls["tabbar.selected-mode"])
        app.segmentedControls["tabbar.selected-mode"].buttons["选中图片"].tap()
        waitForStatus(["图标：资源图片", "选中：选中图片"])
        reveal(app.segmentedControls["tabbar.presentation"])
        app.segmentedControls["tabbar.presentation"].buttons["胶囊"].tap()
        waitForStatus(["形态：胶囊"])
        keepScreenshot("Tab bar with assets and capsule")
        reveal(app.segmentedControls["tabbar.accessories"])
        app.segmentedControls["tabbar.accessories"].buttons["左右"].tap()
        waitForStatus(["字号：14 pt", "附加按钮：左右"])
        keepScreenshot("Styled dock inherits native tab typography")
        assertReadableTabCaption("tab.materials")
    }

    func testAccessoryButtonsAppearBesideTheBar() {
        reveal(app.segmentedControls["tabbar.accessories"])
        app.segmentedControls["tabbar.accessories"].buttons["左右"].tap()
        XCTAssertTrue(app.buttons["accessory.compose"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accessory.search"].waitForExistence(timeout: 5))
        app.buttons["accessory.search"].tap()
        waitForStatus(["附加按钮：左右", "已触发：搜索"])
        XCTAssertTrue(app.buttons["tab.examples"].isSelected, "Accessories stay actions")
        keepScreenshot("Accessories on the tab bar page")
    }

    /// Capture the screen while switching in both directions, including back to none.
    func testCapsuleAccessoriesMakeASingleDockRow() {
        reveal(app.segmentedControls["tabbar.presentation"])
        // Launch uses classic bars, while this page's picker initially highlights automatic.
        // Change the value first so UIKit sends valueChanged and applies the requested renderer.
        app.segmentedControls["tabbar.presentation"].buttons["胶囊"].tap()
        app.segmentedControls["tabbar.presentation"].buttons["自动"].tap()
        reveal(app.segmentedControls["tabbar.accessories"])
        let picker = app.segmentedControls["tabbar.accessories"]
        let states = [("无", "none", false, false), ("左", "leading", true, false),
                      ("右", "trailing", false, true), ("左右", "both", true, true),
                      ("无", "cleared", false, false)]
        for (title, name, hasLeft, hasRight) in states {
            picker.buttons[title].tap()
            waitForStatus(["附加按钮：\(title)"])
            keepScreenshot("Dock auto \(name)")
            XCTAssertEqual(app.buttons["accessory.compose"].exists, hasLeft)
            XCTAssertEqual(app.buttons["accessory.search"].exists, hasRight)
            if hasLeft || hasRight {
                XCTAssertEqual(app.tabBars.count, 1, "The dock must expose one standalone tab bar")
                let bar = app.tabBars["shell.dock.tabs"]
                let surface = bar.children(matching: .other).allElementsBoundByIndex.map(\.frame).first {
                    $0.width > 0 && $0.width < bar.frame.width - 1 && $0.height >= 44
                }
                XCTAssertNotNil(surface, "The visible native capsule must be measurable")
                if let surface = surface {
                    for id in [hasLeft ? "accessory.compose" : nil, hasRight ? "accessory.search" : nil].compactMap({ $0 }) {
                        let button = app.buttons[id].frame
                        XCTAssertEqual(button.height, surface.height, accuracy: 1)
                        XCTAssertEqual(button.minY, surface.minY, accuracy: 1)
                        XCTAssertEqual(button.maxY, surface.maxY, accuracy: 1)
                    }
                }
            }
            for id in ["tab.examples", "tab.materials", "tab.about"] {
                XCTAssertEqual(app.buttons.matching(identifier: id).count, 1, "\(id) must appear exactly once")
                XCTAssertTrue(app.buttons[id].isHittable, "\(id) must have a usable hit target")
            }
            if hasLeft {
                app.buttons["accessory.compose"].tap()
                waitForStatus(["已触发：新建"])
            }
            if hasRight {
                app.buttons["accessory.search"].tap()
                waitForStatus(["已触发：搜索"])
            }
            XCTAssertTrue(app.buttons["tab.examples"].isSelected)
        }
        picker.buttons["左右"].tap()
        app.buttons["tab.about"].tap()
        XCTAssertTrue(app.staticTexts["about.backgrounds"].waitForExistence(timeout: 5))
        app.buttons["tab.examples"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.count, 1)
    }

    func testCapsuleListScrollsUnderGlassWithoutABottomStrip() {
        reveal(app.segmentedControls["tabbar.presentation"])
        app.segmentedControls["tabbar.presentation"].buttons["胶囊"].tap()
        reveal(app.segmentedControls["tabbar.accessories"])
        app.segmentedControls["tabbar.accessories"].buttons["左右"].tap()
        waitForStatus(["附加按钮：左右"])

        let scroll = app.scrollViews["demo.scroll"].firstMatch
        // Move away from the end of the list so real rows, rather than the end padding, pass
        // behind the glass. Both screenshots are screen captures from the running simulator.
        scroll.swipeDown()
        keepScreenshot("Capsule list underlay A")
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        keepScreenshot("Capsule list underlay B")
        XCTAssertEqual(scroll.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1,
                       "The list viewport must continue below the capsule to the screen bottom")
        XCTAssertTrue(app.buttons["accessory.compose"].isHittable)
        XCTAssertTrue(app.buttons["accessory.search"].isHittable)
        app.buttons["accessory.search"].tap()
        waitForStatus(["已触发：搜索"])
        reveal(app.segmentedControls["tabbar.accessories"])
        app.segmentedControls["tabbar.accessories"].buttons["无"].tap()
        waitForStatus(["附加按钮：无"])
        scroll.swipeDown()
        keepScreenshot("Capsule native underlay A")
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        keepScreenshot("Capsule native underlay B")
        XCTAssertEqual(scroll.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1)
        XCTAssertFalse(app.buttons["accessory.compose"].exists)
        XCTAssertFalse(app.buttons["accessory.search"].exists)
    }

    // MARK: - Helpers

    private func assertReadableTabCaption(_ id: String) {
        let item = app.buttons[id]
        guard let image = item.screenshot().image.cgImage else { return XCTFail("Missing tab screenshot") }
        let scale = CGFloat(image.height) / max(1, item.frame.height)
        let height = min(image.height, Int(20 * scale))
        guard let caption = image.cropping(to: CGRect(x: 0, y: image.height - height,
                                                      width: image.width, height: height)) else {
            return XCTFail("Missing caption crop")
        }
        let width = caption.width
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let inkRows = rgba.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(caption, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = bytes.bindMemory(to: UInt8.self)
            return (0..<height).filter { y in
                (0..<width).contains { x in
                    let offset = (y * width + x) * 4
                    let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
                    return red + green + blue < 360 || (blue > red + 40 && blue > green + 30)
                }
            }.count
        }
        // Below the icon, a 14-point Chinese caption needs more than a cropped 7-point strip.
        XCTAssertGreaterThanOrEqual(inkRows, Int(8 * scale), "The native dock cropped its styled caption")
    }

    private func reveal(_ element: XCUIElement, upward: Bool = true) {
        let scroll = app.scrollViews["demo.scroll"].firstMatch
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            if upward { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func waitForStatus(_ snippets: [String]) {
        let label = app.staticTexts["tabbar.status"]
        let predicate = NSPredicate { _, _ in label.exists && snippets.allSatisfy { label.label.contains($0) } }
        let condition = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 10), .completed,
                       "Expected \(snippets), actual status: \(label.exists ? label.label : "missing")")
    }

    private func keepScreenshot(_ name: String) {
        guard app != nil else { return }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
