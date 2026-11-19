import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class NavButtonLayoutTests: XCTestCase {
    func testOnlyAdjacentCompatibleItemsGroupInDeclarationOrder() {
        let a = action("a"), b = action("b"), c = action("c")
        let regular = NavigationAction(id: "text", title: "Text") {}
        var horizontal = action("horizontal"); horizontal.axisBehavior = .horizontalOnly
        var done = action("done"); done.role = .confirmation
        var low = action("low"); low.priority = -1
        let items = [b, a, regular, c, horizontal, low, done]
        let runs = ShellNavButtonRun.collect(items, layout: .grouped(spacing: 8))
        XCTAssertEqual(runs.map { $0.actions.map(\.id) }, [["b", "a"], ["text"], ["c"], ["horizontal"], ["low"], ["done"]])
        XCTAssertEqual(ShellNavButtonRun.collect(items, layout: .individual).count, items.count)
        XCTAssertEqual(a.axisBehavior, .verticalPreferred)
        XCTAssertEqual(regular.axisBehavior, .automatic)
    }

    func testVisualSpacingAndSeparateTargetsInBothDirections() {
        let items = [action("short", width: 24), action("wide", width: 60)]
        let buttons = items.map { action -> ShellNavButtonHost in
            let button = ShellNavButtonHost(frame: .zero)
            button.update(action: action, textStyle: ShellTextStyle(), perform: {})
            return button
        }
        let cluster = ShellNavButtonCluster()
        for gap: CGFloat in [0, 8, 16] {
            for rtl in [false, true] {
                cluster.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
                cluster.update(buttons: buttons, spacing: gap, tracksNativePlacement: false)
                cluster.frame.size = cluster.intrinsicContentSize
                cluster.layoutIfNeeded()
                let first = buttons[0].frame, second = buttons[1].frame
                XCTAssertEqual(first.width, 24)
                XCTAssertEqual(second.width, 60)
                XCTAssertEqual(rtl ? first.minX - second.maxX : second.minX - first.maxX, gap, accuracy: 0.01)
                let targets = buttons.map { button in cluster.convert(cluster.touchRect(for: button)!, from: button) }
                XCTAssertGreaterThanOrEqual(targets[0].width, 44)
                XCTAssertGreaterThanOrEqual(targets[0].height, 44)
                XCTAssertTrue(targets[0].intersection(targets[1]).width <= 0)
                XCTAssertTrue(cluster.hitTest(.init(x: rtl ? targets[0].maxX - 1 : targets[0].minX + 1,
                                                    y: targets[0].midY), with: nil) === buttons[0])
            }
        }
    }

    func testClassicNarrowBarReservesBackAndMoreAndDispatchesEachMenuActionOnce() throws {
        let page = NavButtonPage()
        var calls: [String] = []
        let done = NavigationAction(id: "done", title: "Done", navButton: .init(normal: .init(size: .preferred(.init(width: 58, height: 32)))), role: .confirmation) { calls.append("done") }
        page.actions = [done, action("a") { calls.append("a") }, action("b") { calls.append("b") }]
        let nav = BoneNavigationController(rootViewController: UIViewController())
        nav.barPresentation = .classic
        nav.loadViewIfNeeded()
        nav.pushViewController(page, animated: false)
        page.loadViewIfNeeded()
        page.view.bounds.size = CGSize(width: 320, height: 640)
        page.refreshScreenConfiguration()
        XCTAssertEqual(page.visibleActionIDs, ["done"])
        XCTAssertEqual(page.overflowActionIDs, ["a", "b"])
        let more = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first { $0.accessibilityIdentifier == "shell.overflow" }?.menu)
        let entries = more.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(entries.map(\.identifier.rawValue), ["action.a", "action.b"])
        entries.forEach(invoke)
        XCTAssertEqual(calls, ["a", "b"])
        let doneSlot = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.compactMap { ($0 as? ShellNavigationBarItem)?.classicSlot }.first)
        doneSlot.buttons.first?.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(calls, ["a", "b", "done"])
        XCTAssertFalse(page.navigationItem.hidesBackButton)
        page.actions = [done]
        page.refreshScreenConfiguration()
        entries.forEach(invoke)
        XCTAssertEqual(calls, ["a", "b", "done"])
        withExtendedLifetime(nav) {}
    }

    func testGroupReordersByIDMigratesBetweenRenderersAndRestoresStandardItem() throws {
        let page = NavButtonPage()
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .system
        nav.loadViewIfNeeded()
        nav.view.frame.size = CGSize(width: 800, height: 700)
        page.loadViewIfNeeded()
        page.view.bounds.size = nav.view.bounds.size
        var hits = 0
        let a = action("a") { hits += 1 }, b = action("b")
        page.actions = [a, b]
        page.refreshScreenConfiguration()
        func groupItem() throws -> ShellNavigationBarItem {
            if #available(iOS 27.0, *), page.usesSystemNavigationActionLayout {
                return try XCTUnwrap(page.navigationItem.trailingItemGroups.first?.barButtonItems.first as? ShellNavigationBarItem)
            }
            return try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first as? ShellNavigationBarItem)
        }
        let initial = try groupItem()
        let original = try XCTUnwrap((initial.customView as? ShellNavButtonCluster)?.buttons.first)
        if #available(iOS 16.0, *) {
            let menu = try XCTUnwrap(initial.menuRepresentation as? UIMenu)
            XCTAssertEqual(menu.children.compactMap { ($0 as? UIAction)?.identifier.rawValue }, ["action.a", "action.b"])
        }
        var updated = action("a") { hits += 10 }
        page.actions = [b, updated]
        page.refreshScreenConfiguration()
        let cluster = try XCTUnwrap(try groupItem().customView as? ShellNavButtonCluster)
        XCTAssertEqual(cluster.buttons.map(\.actionID), ["b", "a"])
        XCTAssertTrue(cluster.buttons.last === original)
        original.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(hits, 10)
        nav.barPresentation = .classic
        page.refreshScreenConfiguration()
        XCTAssertNil(try groupItem().customView)
        XCTAssertTrue(try groupItem().classicSlot === cluster)
        XCTAssertTrue(cluster.superview === nav.classicNavigationBarView)
        nav.barPresentation = .system
        page.refreshScreenConfiguration()
        XCTAssertTrue(try groupItem().customView === cluster)
        updated.isEnabled = false
        page.actions = [updated]
        page.refreshScreenConfiguration()
        original.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(hits, 10)
        page.actions = [NavigationAction(id: "a", title: "Standard") {}]
        page.refreshScreenConfiguration()
        XCTAssertNil(try groupItem().customView)
        XCTAssertNil(original.superview)
        withExtendedLifetime(nav) {}
    }

    private func action(_ id: String, width: CGFloat = 48, handler: @escaping () -> Void = {}) -> NavigationAction {
        NavigationAction(id: id, title: id, navButton: ShellNavButton(normal: .init(size: .preferred(.init(width: width, height: 32)))), handler: handler)
    }

    private func invoke(_ action: UIAction) {
        let control = UIButton()
        control.addAction(action, for: .primaryActionTriggered)
        control.sendActions(for: .primaryActionTriggered)
    }
}

private final class NavButtonPage: BoneViewController {
    var actions: [NavigationAction] = []
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Source"
        screen.navigation.navButtonLayout = .grouped(spacing: 8)
        screen.navigation.trailingActions = actions
    }
}
