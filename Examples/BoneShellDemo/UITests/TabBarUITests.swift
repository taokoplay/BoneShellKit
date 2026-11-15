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
        for id in ["tabbar.size", "tabbar.colors", "tabbar.labels", "tabbar.icons", "tabbar.selected-mode",
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

    func testLabelDisplayModesAcrossClassicNativeCapsuleAndDock() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("The native capsule and dock screenshot matrix requires iOS 26 or later")
        }
        let renderers = [("经典", "classic", "无"),
                         ("胶囊", "native-capsule", "无"),
                         ("胶囊", "native-dock", "左右")]
        let modes = [("始终显示", "always"), ("始终隐藏", "never"),
                     ("仅选中", "selectedOnly"), ("仅未选中", "unselectedOnly")]
        for (presentation, renderer, accessories) in renderers {
            choose("tabbar.presentation", presentation)
            choose("tabbar.accessories", accessories)
            waitForStatus(["形态：\(presentation)", "附加按钮：\(accessories)"])
            for (title, mode) in modes {
                choose("tabbar.labels", title)
                waitForStatus(["文字：\(title)"])
                assertTabAccessibilityAndSelection("tab.examples")
                if mode == "selectedOnly" {
                    app.buttons["tab.about"].tap()
                    XCTAssertTrue(app.staticTexts["about.backgrounds"].waitForExistence(timeout: 5))
                    keepScreenshot("Tab labels \(renderer) selectedOnly about")
                    assertTabAccessibilityAndSelection("tab.about")
                    app.buttons["tab.examples"].tap()
                    XCTAssertTrue(app.segmentedControls["tabbar.labels"].waitForExistence(timeout: 5))
                    waitForStatus(["文字：仅选中", "形态：\(presentation)", "附加按钮：\(accessories)"])
                    XCTAssertTrue(app.segmentedControls["tabbar.labels"].buttons["仅选中"].isSelected)
                    assertTabAccessibilityAndSelection("tab.examples")
                }
                if renderer == "classic" {
                    XCTAssertTrue(app.otherElements["shell.classic.tabs"].exists)
                } else {
                    XCTAssertEqual(app.tabBars.count, 1)
                    XCTAssertEqual(app.tabBars["shell.dock.tabs"].exists, renderer == "native-dock")
                }
                XCTAssertEqual(app.buttons["accessory.compose"].exists, accessories == "左右")
                XCTAssertEqual(app.buttons["accessory.search"].exists, accessories == "左右")
                // AX names stay semantic even when captions are hidden. Review actual pixels
                // and icon centering in these twelve screen captures, not in the AX tree.
                keepScreenshot("Tab labels \(renderer) \(mode)")
            }
        }
        let reset = app.buttons["tabbar.reset"]
        reveal(reset)
        reset.tap()
        waitForStatus(["文字：始终显示", "形态：自动", "附加按钮：无"])
        XCTAssertTrue(app.segmentedControls["tabbar.labels"].buttons["始终显示"].isSelected)
    }

    // MARK: - Helpers

    private func choose(_ id: String, _ title: String) {
        let segment = app.segmentedControls[id].buttons[title]
        reveal(segment)
        if !segment.isSelected { segment.tap() }
        XCTAssertTrue(segment.isSelected)
    }

    private func assertTabAccessibilityAndSelection(_ selectedID: String) {
        for (id, title) in [("tab.examples", "示例"), ("tab.materials", "材质"), ("tab.about", "关于")] {
            let tab = app.buttons[id]
            XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
            XCTAssertTrue(tab.isHittable)
            XCTAssertEqual(tab.label, title, "Hidden captions must retain their accessibility names")
            XCTAssertEqual(tab.isSelected, id == selectedID)
        }
    }

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
            if element.exists { element.frame.minY < safe.minY ? scroll.swipeDown() : scroll.swipeUp() }
            else if upward { scroll.swipeUp() }
            else { scroll.swipeDown() }
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
