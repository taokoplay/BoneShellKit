import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class NavButtonLayoutTests: XCTestCase {
    func testExplicitModulesKeepGroupAtomicAndUseGroupMaterial() throws {
        var filter = action("filter")
        filter.priority = 100
        filter.navButton?.normal.effect = .liquidGlass
        var search = action("search")
        search.priority = -100
        search.navButton?.normal.effect = .liquidGlass
        let more = action("more")
        let group = NavigationButtonGroup(
            id: "tools",
            actions: [filter, search],
            itemSpacing: 5,
            material: .systemGlass
        )
        let runs = ShellNavButtonRun.collect(
            [.group(group), .button(more)],
            moduleSpacing: 12
        )
        XCTAssertEqual(runs.map { $0.actions.map(\.id) }, [["filter", "search"], ["more"]])
        XCTAssertEqual(runs[0].groupID, "tools")
        XCTAssertEqual(runs[0].itemSpacing, 5)
        XCTAssertEqual(runs[0].moduleSpacingAfter, 12)
        XCTAssertNil(runs[1].groupID)

        let page = NavButtonPage()
        page.modules = [.group(group)]
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .classic
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds.size = CGSize(width: 640, height: 640)
        page.refreshScreenConfiguration()
        let item = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first as? ShellNavigationBarItem)
        let cluster = try XCTUnwrap(item.classicSlot)
        XCTAssertTrue(cluster.subviews.contains { $0 is ShellGlassView })
        XCTAssertTrue(cluster.buttons.allSatisfy { button in
            button.subviews.compactMap { $0 as? UIVisualEffectView }.isEmpty
        })
        withExtendedLifetime(nav) {}
    }
    func testExplicitModulesSubmitOneNativeGroupPerModule() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native module groups require iOS 27") }
        var filter = action("filter")
        filter.navButton?.normal.effect = .liquidGlass
        var search = action("search")
        search.navButton?.normal.effect = .liquidGlass
        let group = NavigationButtonGroup(
            id: "tools",
            actions: [filter, search],
            itemSpacing: 5,
            material: .systemGlass
        )
        let page = NavButtonPage()
        page.modules = [.group(group), .button(action("more"))]
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .system
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds.size = CGSize(width: 900, height: 650)
        page.refreshScreenConfiguration()
        XCTAssertTrue(page.usesSystemNavigationActionLayout)
        XCTAssertEqual(page.navigationItem.trailingItemGroups.count, 2)
        let item = try XCTUnwrap(page.navigationItem.trailingItemGroups.first?.barButtonItems.first)
        let cluster = try XCTUnwrap(item.customView as? ShellNavButtonCluster)
        XCTAssertTrue(cluster.buttons.allSatisfy { button in
            button.subviews.compactMap { $0 as? UIVisualEffectView }.isEmpty
        })
        XCTAssertFalse(item.hidesSharedBackground)
        withExtendedLifetime(nav) {}
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
        page.modules = [.button(done), .button(action("a") { calls.append("a") }), .button(action("b") { calls.append("b") })]
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
        let doneItem = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first { $0.accessibilityIdentifier == "action.done" })
        XCTAssertEqual(doneItem.style, .plain)
        XCTAssertNil(doneItem.primaryAction)
        let doneCluster = try XCTUnwrap(doneItem.customView as? ShellNavButtonCluster)
        XCTAssertEqual(doneCluster.buttons.first?.currentTitle, "Done")
        let doneSlot = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.compactMap { ($0 as? ShellNavigationBarItem)?.classicSlot }.first)
        doneSlot.buttons.first?.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(calls, ["a", "b", "done"])
        XCTAssertFalse(page.navigationItem.hidesBackButton)
        page.modules = [.button(done)]
        page.refreshScreenConfiguration()
        entries.forEach(invoke)
        XCTAssertEqual(calls, ["a", "b", "done"])
        withExtendedLifetime(nav) {}
    }

    func testExplicitGroupReordersBetweenRenderersAndRestoresStandardItem() throws {
        let page = NavButtonPage()
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .system
        nav.loadViewIfNeeded()
        nav.view.frame.size = CGSize(width: 800, height: 700)
        page.loadViewIfNeeded()
        page.view.bounds.size = nav.view.bounds.size
        var hits = 0
        let a = action("a") { hits += 1 }
        let b = action("b")
        func group(_ actions: [NavigationAction]) -> NavigationButtonGroup {
            NavigationButtonGroup(id: "actions", actions: actions, itemSpacing: 8, material: .systemGlass)
        }
        page.modules = [.group(group([a, b]))]
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
        page.modules = [.group(group([b, updated]))]
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
        page.modules = [.group(group([b, updated]))]
        page.refreshScreenConfiguration()
        original.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(hits, 10)
        page.modules = [.button(NavigationAction(id: "a", title: "Standard") {})]
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
    var modules: [NavigationModule] = []

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Source"
        screen.navigation.moduleSpacing = 12
        screen.navigation.trailingModules = modules
    }
}
