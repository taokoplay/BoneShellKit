import XCTest

final class NavButtonUITests: XCTestCase {
    private var app: XCUIApplication!
    private var done: XCUIElement { app.buttons["action.nav.text"].firstMatch }
    private var status: XCUIElement { app.staticTexts["nav.status"] }
    private var scroll: XCUIElement { app.scrollViews["demo.scroll"].firstMatch }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, app.state == .runningForeground {
            capture("NavButton-failure")
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Accessibility tree on failure"
            tree.lifetime = .keepAlways
            add(tree)
        }
        app.terminate()
    }

    func testMaterialsAndSizeOnBarRecordEachTapOnce() {
        XCUIDevice.shared.orientation = .portrait
        for effect in ["none", "blur", "glass"] {
            openSettings(["-navbutton", "-navbutton-horizontal-bar", "-navbutton-effect", effect])
            assertHorizontalDone(width: 72)
            capture("NavButton-material-\(effect)", button: done)
            done.tap()
            expectReceipt(1, "完成")
        }
    }

    func testGroupSpacingAndReorderOnBar() {
        let original = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = original == .unknown ? .portrait : original }
        let flags = ["-navbutton", "-navbutton-horizontal-bar", "-navbutton-gap"]
        let mark = app.buttons["action.nav.mark"].firstMatch
        let share = app.buttons["action.nav.share"].firstMatch

        func checkGap(_ gap: CGFloat, reversed: Bool) {
            let first = reversed ? share : mark
            let second = reversed ? mark : share
            for button in [first, second] {
                XCTAssertTrue(button.exists && button.isHittable, "Group child must be on the bar")
                XCTAssertTrue(geometry(of: button).inTopBar)
            }
            XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 2)
            XCTAssertEqual(second.frame.minX - first.frame.maxX, gap, accuracy: 1.5)
        }
        for gap in [0, 8, 16] {
            openSettings(flags + [String(gap)])
            checkGap(CGFloat(gap), reversed: false)
        }
        openSettings(flags + ["16", "-navbutton-reversed"])
        checkGap(16, reversed: true)
        capture("NavButton-group-reversed-16pt")
        share.tap()
        expectReceipt(1, "分享")
        mark.tap()
        expectReceipt(2, "标记")
    }

    func testGroupedOverflowListsBothChildrenAndInvokesEachOnce() throws {
        // Two real 400 pt items and a 16 pt gap. Nothing in the app forces a menu open.
        openSettings(["-navbutton-overflow", "-navbutton-horizontal-bar"])
        let children = [("nav.mark", "标记"), ("nav.share", "分享")]
        if done.exists && done.isHittable {
            XCTAssertTrue(geometry(of: done).inTopBar)
            done.tap()
        } else {
            openOverflow()
            try menuAction(id: "nav.text", title: "完成").tap()
        }
        expectReceipt(1, "完成")
        for (index, target) in children.enumerated() {
            for (id, _) in children {
                let candidates = app.buttons.matching(identifier: "action.\(id)").allElementsBoundByIndex
                XCTAssertFalse(candidates.contains { $0.isHittable }, "The entire group must actually overflow")
            }
            openOverflow()
            for (id, title) in children { _ = try menuAction(id: id, title: title) }
            if index == 0 { capture("NavButton-overflow-both-children") }
            try menuAction(id: target.0, title: target.1).tap()
            expectReceipt(index + 2, target.1)
        }
    }

    func testDuoHorizontalBarUsesNormal72x44() throws {
        try requireDuoRuntime()
        // Even with a vertical override, a real horizontal bar must render the normal style.
        openSettings(["-navbutton-vertical-capsule", "-navbutton-horizontal-bar"])
        assertHorizontalDone(width: 72)
        capture("NavButton-Duo-horizontal-72x44", button: done)
        done.tap()
        expectReceipt(1, "完成")
        capture("NavButton-Duo-horizontal-receipt")
    }

    func testDuoSidebarUsesVertical44x72() throws {
        try requireDuoRuntime()
        openSettings(["-navbutton-vertical-capsule"])
        revealSidebar(done, title: "完成")
        // On the Duo's outer display UIKit grants 38 pt to a 44 pt visual.
        XCTAssertGreaterThanOrEqual(done.frame.width, 36)
        XCTAssertLessThanOrEqual(done.frame.width, 46)
        XCTAssertEqual(done.frame.height, 72, accuracy: 2)
        capture("NavButton-Duo-sidebar-44x72", button: done)
        done.tap()
        expectReceipt(1, "完成")
        capture("NavButton-Duo-sidebar-capsule-receipt")
    }

    func testDuoSidebarInheritsNormalContentAndHeight() throws {
        try requireDuoRuntime()
        openSettings(["-navbutton"])
        revealSidebar(done, title: "完成")
        // A narrow rail can constrain the normal 72 pt width; it must not grow to the 72 pt capsule height.
        XCTAssertEqual(done.frame.height, 44, accuracy: 2)
        XCTAssertGreaterThanOrEqual(done.frame.width, 36)
        XCTAssertLessThanOrEqual(done.frame.width, 74)
        capture("NavButton-Duo-sidebar-inherited", button: done)
        done.tap()
        expectReceipt(1, "完成")
        capture("NavButton-Duo-sidebar-inherited-receipt")
    }

    func testDuoDefaultIconIsCircularAndOpensDetailsOnBothAxes() throws {
        try requireDuoRuntime()
        XCUIDevice.shared.orientation = .portrait
        for sidebar in [false, true] {
            let flags = ["-navbutton", "-navbutton-effect", "glass"]
            openSettings(sidebar ? flags : flags + ["-navbutton-horizontal-bar"])
            let detail = app.buttons["action.nav.detail"].firstMatch
            if sidebar {
                revealSidebar(detail, title: "详情")
            } else {
                XCTAssertTrue(detail.waitForExistence(timeout: 5) && detail.isHittable)
                XCTAssertTrue(geometry(of: detail).inTopBar)
            }
            XCTAssertEqual(detail.frame.width, detail.frame.height, accuracy: 1)
            XCTAssertGreaterThanOrEqual(detail.frame.height, 38)
            capture(sidebar ? "圆形详情-侧栏" : "圆形详情-横栏", button: detail)
            detail.tap()
            XCTAssertTrue(app.textFields["state.input"].waitForExistence(timeout: 8))
        }
    }

    // MARK: - Actual system placement

    private struct Geometry: CustomStringConvertible {
        let window: CGRect
        let content: CGRect
        let bars: [CGRect]
        let button: CGRect
        private var center: CGPoint { CGPoint(x: button.midX, y: button.midY) }

        var inTopBar: Bool {
            guard window.contains(center), !button.isEmpty else { return false }
            return bars.contains { bar in
                bar.width > bar.height * 2 && bar.midY < window.minY + window.height / 3 && bar.contains(center)
            }
        }

        var inSideBar: Bool {
            guard window.contains(center), !button.isEmpty else { return false }
            let edgeDistance = min(center.x - window.minX, window.maxX - center.x)
            guard edgeDistance <= 90 else { return false }
            if bars.contains(where: { $0.height > $0.width * 2 && $0.contains(center) }) { return true }
            // Some systems expose only the children of the rail. Check the actual column
            // reserved beside the scroll view, excluding horizontal bars at either end.
            let inGutter = button.maxX <= content.minX + 2 || button.minX >= content.maxX - 2
            let inHorizontalBar = bars.contains { $0.width > $0.height * 2 && $0.contains(center) }
            return !content.isEmpty && inGutter && !inHorizontalBar && (content.minY...content.maxY).contains(center.y)
        }

        var description: String { "window=\(window), scroll=\(content), bars=\(bars), button=\(button)" }
    }

    private func geometry(of button: XCUIElement) -> Geometry {
        let bars = [app.navigationBars, app.toolbars, app.tabBars].flatMap { $0.allElementsBoundByIndex }
        return Geometry(window: app.frame, content: scroll.frame, bars: bars.map(\.frame).filter { !$0.isEmpty }, button: button.frame)
    }

    private func assertHorizontalDone(width: CGFloat) {
        XCTAssertTrue(done.waitForExistence(timeout: 5) && done.isHittable)
        XCTAssertEqual(done.label, "完成")
        let observed = geometry(of: done)
        XCTAssertTrue(observed.inTopBar, "Expected a live horizontal bar: \(observed)")
        XCTAssertEqual(observed.button.width, width, accuracy: 2)
        // A compact native navigation bar may cap this 44 pt request at 40 pt.
        XCTAssertGreaterThanOrEqual(observed.button.height, 38)
        XCTAssertLessThanOrEqual(observed.button.height, 46)
    }

    private func revealSidebar(_ button: XCUIElement, title: String) {
        func onRail() -> Bool { button.exists && button.isHittable && geometry(of: button).inSideBar }
        if !onRail() {
            let titles = ["Show Sidebar", "Show Side Bar", "Show Controls", "Show Toolbar", "Expand Sidebar", "Sidebar",
                          "显示侧边栏", "显示边栏", "展开侧边栏", "显示控制项", "显示工具栏", "侧边栏"]
            let show = app.buttons.matching(NSPredicate(format: "label IN[c] %@", titles)).allElementsBoundByIndex.first { $0.isHittable }
            show?.tap()
        }
        if !onRail() {
            // Leave the Duo in its current posture. A collapsed edge rail can be revealed by a real inward drag.
            let window = app.frame, content = scroll.frame
            let left = content.minX - window.minX > window.maxX - content.maxX
            for fromLeft in [left, !left] {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromLeft ? 0.01 : 0.99, dy: 0.52))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: fromLeft ? 0.24 : 0.76, dy: 0.52))
                start.press(forDuration: 0.1, thenDragTo: end)
                if onRail() { break }
            }
        }
        XCTAssertTrue(onRail(), "Expected a hittable action in the real side rail, not a top bar or overflow menu: \(app.debugDescription)")
        XCTAssertEqual(button.label, title)
    }

    private func requireDuoRuntime() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Run the side-bar cases on iPhone Duo / iOS 27.1+") }
        // These are destination-specific cases. A missing rail on a Duo is a failure, never a skip.
        if let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"], !device.localizedCaseInsensitiveContains("Duo") {
            throw XCTSkip("Requires an iPhone Duo destination; current simulator: \(device)")
        }
    }

    // MARK: - User interactions

    private func openSettings(_ arguments: [String]) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-system-bars", "-open-navbutton-demo"] + arguments
        app.launch()
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Expected the real navigation demo")
    }

    private func expectReceipt(_ count: Int, _ title: String) {
        XCTAssertTrue(status.exists)
        let expected = ["NavButton 点击：\(count) 次", "已触发：\(title)"]
        let predicate = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", expected[0], expected[1])
        let receipt = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [receipt], timeout: 5), .completed, "Expected \(expected); got \(status.label)")
    }

    private func openOverflow() {
        let more = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "shell.overflow",
                                                    ["More", "More Actions", "更多", "更多操作"])).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5) && more.isHittable, "A real overflow menu must be available")
        more.tap()
    }

    private func menuAction(id: String, title: String) throws -> XCUIElement {
        // iOS 26 may append menu metadata to the accessible label; the stable action ID wins.
        let entries = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label CONTAINS %@", "action.\(id)", title))
        let entry = try XCTUnwrap(entries.allElementsBoundByIndex.first { $0.isHittable || $0.waitForExistence(timeout: 1) }, "Missing menu child: \(title)")
        XCTAssertTrue(entry.label.contains(title), "Unexpected menu label: \(entry.label)")
        return entry
    }

    private func capture(_ name: String, button: XCUIElement? = nil) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        if let button {
            let crop = XCTAttachment(screenshot: button.screenshot())
            crop.name = name + "-button"
            crop.lifetime = .keepAlways
            add(crop)
            let frames = XCTAttachment(string: geometry(of: button).description)
            frames.name = name + "-frames"
            frames.lifetime = .keepAlways
            add(frames)
        }
    }
}
