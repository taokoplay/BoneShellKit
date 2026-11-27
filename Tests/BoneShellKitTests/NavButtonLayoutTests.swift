import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class NavButtonLayoutTests: XCTestCase {
    func testExplicitModulesKeepGroupAtomicAndUseGroupMaterial() throws {
        var filter = action("filter")
        filter.priority = 100
        filter.navButton?.normal.effect = .material(.systemGlass)
        var search = action("search")
        search.priority = -100
        search.navButton?.normal.effect = .material(.systemGlass)
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
    func testModuleSpacingIsExactBetweenCompatibilityModuleFrames() throws {
        let page = NavButtonPage()
        page.modules = [
            .group(NavigationButtonGroup(
                id: "tools",
                actions: [action("filter", width: 44), action("search", width: 44)],
                itemSpacing: 5,
                material: .systemGlass
            )),
            .button(action("more", width: 44))
        ]
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .system
        nav.loadViewIfNeeded()
        nav.view.frame = CGRect(x: 0, y: 0, width: 640, height: 640)
        page.loadViewIfNeeded()
        page.view.frame = nav.view.bounds
        page.refreshScreenConfiguration()
        nav.view.layoutIfNeeded()
        page.view.layoutIfNeeded()
        guard !page.usesSystemNavigationActionLayout else { throw XCTSkip("Compatibility spacing test runs below iOS 27") }
        let clusters = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.compactMap { $0.customView as? ShellNavButtonCluster })
        let frames = clusters.map { $0.convert($0.moduleVisualBounds, to: nav.navigationBar) }.sorted { $0.minX < $1.minX }
        XCTAssertEqual(frames.count, 2)
        guard frames.count == 2 else { XCTFail("Expected two module clusters"); return }
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 12, accuracy: 0.1)
        withExtendedLifetime(nav) {}
    }

    func testExplicitModulesSubmitOneNativeGroupPerModule() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native module groups require iOS 27") }
        var filter = action("filter")
        filter.navButton?.normal.effect = .material(.systemGlass)
        var search = action("search")
        search.navButton?.normal.effect = .material(.systemGlass)
        let group = NavigationButtonGroup(
            id: "tools",
            actions: [filter, search],
            itemSpacing: 5,
            material: .systemGlass
        )
        let page = NavButtonPage()
        var more = action("more")
        more.navButton?.normal.effect = .material(.systemGlass)
        page.modules = [.group(group), .button(more)]
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
        XCTAssertTrue(item.hidesSharedBackground)
        let standaloneItem = try XCTUnwrap(page.navigationItem.trailingItemGroups[1].barButtonItems.first)
        let standaloneCluster = try XCTUnwrap(standaloneItem.customView as? ShellNavButtonCluster)
        XCTAssertTrue(standaloneItem.hidesSharedBackground)
        // 独立玻璃按钮的表面由 SDK 的 ShellGlassView 统一绘制，不再直接挂裸的 UIVisualEffectView。
        XCTAssertTrue(standaloneCluster.buttons.allSatisfy { button in
            button.subviews.contains { view in
                guard let surface = view as? ShellGlassView else { return false }
                return !surface.isHidden
            }
        })
        cluster.layoutIfNeeded()
        // 组表面始终是 SDK 的一整块 ShellGlassView：系统玻璃与回退材质只在裁剪和效果上不同。
        let surface = try XCTUnwrap(cluster.subviews.compactMap { $0 as? ShellGlassView }.first)
        XCTAssertFalse(surface.isHidden)
        XCTAssertGreaterThan(surface.layer.cornerRadius, 0)
        XCTAssertEqual(surface.contentView.layer.cornerRadius, surface.layer.cornerRadius)
        XCTAssertTrue(surface.contentView.layer.masksToBounds)
        if #available(iOS 26.0, *) { XCTAssertFalse(surface.layer.masksToBounds) }
        else { XCTAssertTrue(surface.layer.masksToBounds) }
        withExtendedLifetime(nav) {}
    }



    func testSystemGlassGroupIsOneContinuousSurfaceAcrossItsWholeModule() throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("Native groups require iOS 16") }
        var bookmark = action("bookmark")
        bookmark.navButton?.normal.effect = .none
        var share = action("share")
        share.navButton?.normal.effect = .none
        let group = NavigationButtonGroup(id: "tools", actions: [bookmark, share],
                                          itemSpacing: 8, material: .systemGlass)
        let page = NavButtonPage()
        page.modules = [.group(group)]
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .system
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds.size = CGSize(width: 900, height: 650)
        page.refreshScreenConfiguration()
        let item = try XCTUnwrap(page.navigationItem.trailingItemGroups.first?.barButtonItems.first)
        let cluster = try XCTUnwrap(item.customView as? ShellNavButtonCluster)
        cluster.layoutIfNeeded()
        // 组只画一整块表面：组内没有分隔线，多个玻璃元素相接会凹下或叠出暗带。
        let surfaces = cluster.subviews.compactMap { $0 as? ShellGlassView }.filter { !$0.isHidden }
        XCTAssertEqual(surfaces.count, 1)
        XCTAssertTrue(cluster.subviews.compactMap { $0 as? UIVisualEffectView }.isEmpty)
        let surface = try XCTUnwrap(surfaces.first)
        // 表面覆盖整个模块可见范围（含两侧 44 pt 触控补偿），内部按钮不再各自带表面。
        XCTAssertEqual(surface.frame, cluster.bounds)
        XCTAssertTrue(cluster.buttons.allSatisfy { button in
            button.subviews.compactMap { $0 as? ShellGlassView }.allSatisfy(\.isHidden)
        })
        // 胶囊圆角等于厚度的一半，整条轮廓是一条直线边而不是凹口。
        XCTAssertEqual(surface.layer.cornerRadius, surface.frame.height / 2, accuracy: 0.5)
        // 组内按钮在胶囊里左右对称，图标不会偏向一端。
        XCTAssertEqual(cluster.buttons[0].frame.minX,
                       surface.frame.maxX - cluster.buttons[1].frame.maxX, accuracy: 0.5)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(surface.resolution.resolved, .systemGlass)
            XCTAssertFalse(surface.layer.masksToBounds, "System glass draws its highlight outside its bounds")
        }
        withExtendedLifetime(nav) {}
    }

    func testGroupSurfaceAndItsIconsFollowTheModuleOffset() throws {
        // 模块间距归一化只做视觉校正：组的胶囊与组内图标必须一起平移，槽位（触控区）不动。
        // 此前组的胶囊完全不参与偏移，导致独立按钮平移、组原地不动，末位按钮的胶囊被推出槽位。
        let bookmark = NavigationAction(id: "bookmark", title: "标记",
                                        navButton: .init(normal: .init(size: .preferred(.init(width: 44, height: 44)))),
                                        icon: .systemSymbol("bookmark")) {}
        let share = NavigationAction(id: "share", title: "分享",
                                     navButton: .init(normal: .init(size: .preferred(.init(width: 44, height: 44)))),
                                     icon: .systemSymbol("square.and.arrow.up")) {}
        let buttons = [bookmark, share].map { action -> ShellNavButtonHost in
            let button = ShellNavButtonHost(frame: .zero)
            button.update(action: action, textStyle: ShellTextStyle(), perform: {})
            return button
        }
        let cluster = ShellNavButtonCluster()
        cluster.update(buttons: buttons, spacing: 8, tracksNativePlacement: false, groupMaterial: .systemGlass)
        cluster.frame = CGRect(x: 0, y: 0, width: 96, height: 44)
        cluster.layoutIfNeeded()
        let surface = try XCTUnwrap(cluster.subviews.compactMap { $0 as? ShellGlassView }.first)
        let baseSlots = buttons.map(\.frame)
        let baseIcons = buttons.map { $0.imageView?.frame.minX ?? 0 }

        for offset in [6, -6] as [CGFloat] {
            cluster.setModuleVisualOffset(offset)
            cluster.layoutIfNeeded()
            XCTAssertEqual(surface.frame.minX, offset, accuracy: 0.5, "surface offset=\(offset)")
            XCTAssertEqual(surface.frame.width, 96, accuracy: 0.5)
            for (index, button) in buttons.enumerated() {
                XCTAssertEqual(button.frame, baseSlots[index],
                               "Slots stay put; only the visual surface moves")
                XCTAssertEqual(button.imageView?.frame.minX ?? 0, baseIcons[index] + offset, accuracy: 0.5,
                               "Icons must follow the surface, offset=\(offset)")
            }
            XCTAssertEqual(cluster.moduleVisualBounds.minX, offset, accuracy: 0.5)
        }
    }

    func testVerticalGroupUsesSquareItemsAsWideAsTheGroup() throws {
        // 侧栏里按钮组整体竖排：每个按钮与组玻璃同宽、并且是正方形，不额外加内边距。
        // 图标大小因此完全由调用方的 `iconSize` / `contentInsets` 控制。
        let bookmark = NavigationAction(id: "bookmark", title: "标记",
                                        navButton: .init(normal: .init(size: .preferred(.init(width: 44, height: 44)),
                                                                       iconSize: .init(width: 20, height: 20))),
                                        icon: .systemSymbol("bookmark")) {}
        let share = NavigationAction(id: "share", title: "分享",
                                     navButton: .init(normal: .init(size: .preferred(.init(width: 44, height: 44)),
                                                                    iconSize: .init(width: 20, height: 20))),
                                     icon: .systemSymbol("square.and.arrow.up")) {}
        let buttons = [bookmark, share].map { action -> ShellNavButtonHost in
            let button = ShellNavButtonHost(frame: .zero)
            button.update(action: action, textStyle: ShellTextStyle(), perform: {})
            return button
        }
        let cluster = ShellNavButtonCluster()
        cluster.update(buttons: buttons, spacing: 8, tracksNativePlacement: false, groupMaterial: .systemGlass)
        cluster.setVerticalForLayoutTesting(true)
        cluster.layoutIfNeeded()
        let surface = try XCTUnwrap(cluster.subviews.compactMap { $0 as? ShellGlassView }.first)
        // 玻璃宽 = 侧轨槽位 44 + 4；组高 = 两枚 48 方形 + 组内净距 8。
        XCTAssertEqual(surface.frame.width, 48, accuracy: 0.5)
        XCTAssertEqual(surface.frame.height, 48 * 2 + 8, accuracy: 0.5)
        for button in buttons {
            XCTAssertEqual(button.frame.width, 48, accuracy: 0.5, "\(button.actionID) 与组同宽")
            XCTAssertEqual(button.frame.height, 48, accuracy: 0.5, "\(button.actionID) 为正方形")
            XCTAssertEqual(button.frame.minX, surface.frame.minX, accuracy: 0.5, "左右无内边距")
        }
        // 上下两端也不留额外内边距：首枚贴玻璃顶端，末枚贴底端。
        XCTAssertEqual(buttons[0].frame.minY, surface.frame.minY, accuracy: 0.5)
        XCTAssertEqual(buttons[1].frame.maxY, surface.frame.maxY, accuracy: 0.5)
        // 组内按钮不自带表面，由组表面统一绘制。
        for button in buttons {
            let own = button.subviews.compactMap { $0 as? ShellGlassView }.first
            XCTAssertTrue(own?.isHidden ?? true, "\(button.actionID) must not paint its own surface")
        }
        // 图标仍按用户声明的 20×20 绘制，不随按钮变大而拉伸。
        let glyph = try XCTUnwrap(buttons[0].imageView)
        XCTAssertLessThanOrEqual(glyph.frame.width, 20.5)
        XCTAssertLessThanOrEqual(glyph.frame.height, 20.5)
        XCTAssertGreaterThan(glyph.frame.width, 5)
    }

    func testGlassSurfaceMatchesTheSystemBarItemHeight() throws {
        let action = NavigationAction(id: "done", title: "完成",
                                      navButton: .init(normal: .init(size: .preferred(.init(width: 72, height: 44)),
                                                                     effect: .material(.systemGlass))),
                                      role: .confirmation) {}
        let button = ShellNavButtonHost(frame: .zero)
        button.update(action: action, textStyle: ShellTextStyle(), perform: {})
        let cluster = ShellNavButtonCluster()
        // Duo 的横栏 58 pt 高，系统条目玻璃 48 pt；我们拿到的槽位只有 44 pt。
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 466, height: 900))
        let bar = UINavigationBar(frame: CGRect(x: 0, y: 40, width: 466, height: 58))
        window.addSubview(bar)
        window.makeKeyAndVisible()
        cluster.navigationBar = bar
        cluster.update(buttons: [button], spacing: 0, tracksNativePlacement: false)
        cluster.frame = CGRect(x: 0, y: 0, width: 72, height: 44)
        cluster.layoutIfNeeded()
        let surface = try XCTUnwrap(button.subviews.compactMap { $0 as? ShellGlassView }.first)
        XCTAssertEqual(surface.frame.height, 48, accuracy: 0.5,
                       "Glass must match the system item so heights are consistent")
        XCTAssertEqual(surface.frame.width, 72, accuracy: 0.5)
        XCTAssertEqual(surface.frame.midX, button.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(surface.frame.midY, button.bounds.midY, accuracy: 0.5)

        // 普通 iPhone 的栏高 44 pt：表面不能反而变高。
        let shortBar = UINavigationBar(frame: CGRect(x: 0, y: 40, width: 390, height: 44))
        window.addSubview(shortBar)
        cluster.navigationBar = shortBar
        cluster.setNeedsLayout()
        cluster.layoutIfNeeded()
        XCTAssertEqual(surface.frame.height, 44, accuracy: 0.5)
    }

    func testOverflowedModuleDoesNotShiftVisibleOnes() throws {
        // 进入溢出菜单的模块仍留在 item group 里。若参与间距归一化，会按幽灵位置求出
        // 一个巨大偏移，把可见模块推到相邻条目上（「完成」压在返回键上、文字跑出按钮）。
        let page = NavButtonPage()
        page.modules = [.button(action("a")), .button(action("b")), .button(action("c"))]
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .classic
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds.size = CGSize(width: 320, height: 640)
        page.refreshScreenConfiguration()
        // 经典模式把模块放在左侧槽位，而不是 item.customView。
        let cluster = try XCTUnwrap((page.navigationItem.rightBarButtonItems ?? [])
            .compactMap { ($0 as? ShellNavigationBarItem)?.classicSlot }.first)
        cluster.layoutIfNeeded()
        let surface = try XCTUnwrap(cluster.subviews.compactMap { $0 as? ShellGlassView }.first)
        // 只有一个可见模块时不做归一化：表面必须与模块自身重合，不能被推走。
        XCTAssertEqual(surface.frame, cluster.bounds)
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
