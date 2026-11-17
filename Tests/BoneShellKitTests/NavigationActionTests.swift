import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class NavigationActionTests: XCTestCase {
    private var retainedNavigation: BoneNavigationController?

    func testImageOverrideMissingAssetFallbackAndLegacySymbolRestoration() throws {
        let page = ActionFixture()
        let image = glyph().withRenderingMode(.alwaysOriginal)
        var action = NavigationAction(id: "image", title: "自定义图片", symbol: "star") {}
        action.icon = .image(image)
        page.trailing = [action]
        host(page, presentation: .classic)
        let item = try XCTUnwrap(items(page).first)
        XCTAssertTrue(item.image === image)
        XCTAssertEqual(item.image?.renderingMode, .alwaysOriginal)
        XCTAssertEqual(item.accessibilityLabel, action.title)

        page.trailing[0].icon = .asset("missing-navigation-test-image", bundle: .main)
        page.refreshScreenConfiguration()
        XCTAssertNil(items(page).first?.image)
        XCTAssertEqual(items(page).first?.title, "自定义图片")
        XCTAssertTrue(items(page).first === item)

        page.trailing[0].icon = nil
        page.refreshScreenConfiguration()
        XCTAssertNotNil(items(page).first?.image)
        XCTAssertTrue(items(page).first === item)
    }

    func testConfirmationRoleSurvivesClassicWidthBudgetBeforeOrdinaryPriority() throws {
        let page = ActionFixture()
        page.trailing = [
            NavigationAction(id: "other", title: "其它", symbol: "star", priority: Int.max) {},
            NavigationAction(id: "done", title: "完成", symbol: "checkmark", role: .confirmation) {}
        ]
        host(page, presentation: .classic)
        page.view.bounds = CGRect(x: 0, y: 0, width: 320, height: 600)
        page.refreshScreenConfiguration()
        XCTAssertFalse(page.usesSystemNavigationActionLayout)
        XCTAssertTrue(page.visibleActionIDs.contains("done"))
        XCTAssertFalse(page.overflowActionIDs.contains("done"))
        XCTAssertEqual(items(page).first { $0.accessibilityIdentifier == "action.done" }?.style, .done)
        XCTAssertEqual(Set(page.visibleActionIDs + page.overflowActionIDs), ["other", "done"])
    }

    func testSystemLayoutSubmitsEveryUniqueActionWithoutHorizontalPruning() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("System action layout requires iOS 27") }
        let page = ActionFixture()
        page.trailing = (0..<12).map { index in
            NavigationAction(id: "item.\(index)", title: "操作 \(index)", symbol: "star", priority: index) {}
        }
        page.trailing.append(NavigationAction(id: "item.0", title: "重复项", priority: Int.max) {})
        host(page)
        page.view.bounds = CGRect(x: 0, y: 0, width: 240, height: 400)
        page.viewDidLayoutSubviews()
        XCTAssertTrue(page.usesSystemNavigationActionLayout)
        XCTAssertEqual(page.visibleActionIDs, (0..<12).map { "item.\($0)" })
        XCTAssertTrue(page.overflowActionIDs.isEmpty, "UIKit owns overflow; this array only records SDK decisions")
        XCTAssertEqual(page.navigationItem.trailingItemGroups.count, 12)
        XCTAssertTrue(page.navigationItem.trailingItemGroups.allSatisfy(\.alwaysAvailable))
        XCTAssertFalse(items(page).contains { $0.accessibilityIdentifier == "shell.overflow" })
        XCTAssertEqual(items(page).first?.title, "操作 0", "Duplicate IDs retain the first declaration")
        XCTAssertEqual(items(page).map(\.visibilityPriority.rawValue), Array(0..<12))
    }

    func testRolesRouteCancellationLeadingAndOnlyFirstConfirmationIsPinned() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native groups require iOS 27") }
        let page = ActionFixture()
        page.leading = [NavigationAction(id: "done", title: "完成", symbol: "checkmark", role: .confirmation) {}]
        page.trailing = [
            NavigationAction(id: "close", title: "关闭", symbol: "xmark", role: .cancellation) {},
            NavigationAction(id: "share", title: "分享", symbol: "square.and.arrow.up") {},
            NavigationAction(id: "save", title: "另存", symbol: "square.and.arrow.down", role: .confirmation) {}
        ]
        host(page)
        XCTAssertEqual(page.navigationItem.leadingItemGroups.flatMap(\.barButtonItems).map(\.accessibilityIdentifier), ["action.close"])
        XCTAssertEqual(page.navigationItem.pinnedTrailingGroup?.barButtonItems.map(\.accessibilityIdentifier), ["action.done"])
        XCTAssertEqual(page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems).map(\.accessibilityIdentifier), ["action.share", "action.save"])
        XCTAssertFalse(page.navigationItem.hidesBackButton)
        XCTAssertEqual(Set(items(page).compactMap(\.accessibilityIdentifier)).count, 4)
    }

    func testResizePreservesNativeItemsGroupsAndMenuRepresentations() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native groups require iOS 27") }
        let page = ActionFixture()
        page.trailing = [NavigationAction(id: "share", title: "分享", symbol: "square.and.arrow.up") {}]
        host(page)
        let group = try XCTUnwrap(page.navigationItem.trailingItemGroups.first)
        let item = try XCTUnwrap(group.barButtonItems.first)
        let action = item.primaryAction
        let menu = item.menuRepresentation
        let content = page.contentView
        for size in [CGSize(width: 320, height: 500), CGSize(width: 900, height: 600), CGSize(width: 600, height: 900)] {
            page.view.bounds.size = size
            page.viewDidLayoutSubviews()
            XCTAssertTrue(page.navigationItem.trailingItemGroups.first === group)
            XCTAssertTrue(items(page).first === item)
            XCTAssertTrue(item.primaryAction === action)
            XCTAssertTrue(item.menuRepresentation === menu)
            XCTAssertTrue(page.contentView === content)
        }
    }

    func testRefreshingSameIDReusesItemAndInvokesOnlyLatestEnabledHandler() throws {
        let page = ActionFixture()
        var originalCalls = 0
        var latestCalls = 0
        page.trailing = [NavigationAction(id: "same", title: "原操作", symbol: "star") { originalCalls += 1 }]
        host(page)
        let item = try XCTUnwrap(items(page).first)
        let retainedAction = try XCTUnwrap(item.primaryAction)
        page.trailing = [NavigationAction(id: "same", title: "新操作", icon: .image(glyph()), role: .confirmation) { latestCalls += 1 }]
        for _ in 0..<3 { page.refreshScreenConfiguration() }
        XCTAssertTrue(items(page).first === item)
        XCTAssertEqual(item.title, "新操作")
        trigger(retainedAction)
        trigger(try XCTUnwrap(item.primaryAction))
        XCTAssertEqual(originalCalls, 0)
        XCTAssertEqual(latestCalls, 2)
        page.trailing[0].isEnabled = false
        page.refreshScreenConfiguration()
        trigger(retainedAction)
        trigger(try XCTUnwrap(item.primaryAction))
        XCTAssertEqual(latestCalls, 2)
        XCTAssertFalse(item.isEnabled)
        if #available(iOS 16.0, *) {
            let representation = try XCTUnwrap(item.menuRepresentation as? UIAction)
            XCTAssertTrue(representation.attributes.contains(.disabled))
        }
    }

    func testRemovedActionReleasesHandlerAndRetainedMenuCannotExecuteIt() throws {
        let page = ActionFixture()
        var token: HandlerToken? = HandlerToken()
        weak var releasedToken = token
        page.trailing = [NavigationAction(id: "removed", title: "删除", symbol: "trash") { [captured = token] in
            captured?.calls += 1
        }]
        host(page)
        let retainedAction = try XCTUnwrap(items(page).first?.primaryAction)
        token = nil
        XCTAssertNotNil(releasedToken)
        page.trailing = []
        page.refreshScreenConfiguration()
        XCTAssertNil(releasedToken, "Removing an action releases the captured business callback")
        trigger(retainedAction)
        XCTAssertTrue(items(page).isEmpty)
        XCTAssertTrue(page.visibleActionIDs.isEmpty)
        XCTAssertTrue(page.overflowActionIDs.isEmpty)
    }

    func testSwitchingClassicAndNativeClearsPinnedGroupsAndKeepsInputAndItem() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native groups require iOS 27") }
        let page = ActionFixture()
        page.trailing = [NavigationAction(id: "done", title: "完成", symbol: "checkmark", role: .confirmation) {}]
        host(page)
        let item = try XCTUnwrap(items(page).first)
        let input = UITextField()
        input.text = "保留输入"
        page.contentView.addSubview(input)
        let content = page.contentView
        for _ in 0..<3 {
            page.presentation = .classic
            page.refreshScreenConfiguration()
            XCTAssertFalse(page.usesSystemNavigationActionLayout)
            XCTAssertNil(page.navigationItem.pinnedTrailingGroup)
            XCTAssertTrue(items(page).first === item)
            page.presentation = .system
            page.refreshScreenConfiguration()
            XCTAssertTrue(page.usesSystemNavigationActionLayout)
            XCTAssertEqual(page.navigationItem.pinnedTrailingGroup?.barButtonItems.count, 1)
            XCTAssertTrue(items(page).first === item)
            XCTAssertTrue(page.contentView === content)
            XCTAssertEqual(input.text, "保留输入")
            XCTAssertEqual(retainedNavigation?.viewControllers.count, 1)
        }
    }

    func testAxisOverrideUpdatesAndReturnsToAutomaticOnSameItem() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Axis preferences require iOS 27.1") }
        let page = ActionFixture()
        page.trailing = [NavigationAction(id: "axis", title: "方向", symbol: "star", priority: Int.min) {}]
        host(page)
        let item = try XCTUnwrap(items(page).first)
        let pairs: [(ShellNavigationActionAxisBehavior, UIBarButtonItem.AxisBehavior)] = [
            (.horizontalOnly, .horizontalOnly), (.verticalPreferred, .verticalPreferred), (.automatic, .automatic)
        ]
        for (declared, expected) in pairs {
            page.trailing[0].axisBehavior = declared
            page.refreshScreenConfiguration()
            XCTAssertTrue(items(page).first === item)
            XCTAssertEqual(item.axisBehavior, expected)
            XCTAssertEqual(item.visibilityPriority.rawValue, Int.min)
        }
    }

    func testSizeClassChangesPreserveNativeActionAndMenuIdentity() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native layout requires iOS 27") }
        let page = ActionFixture()
        page.trailing = [NavigationAction(id: "stable", title: "稳定动作", symbol: "star") {}]
        host(page)
        let item = try XCTUnwrap(items(page).first)
        let primary = item.primaryAction
        let representation = item.menuRepresentation
        let previous = UITraitCollection(traitsFrom: [page.traitCollection,
            UITraitCollection(horizontalSizeClass: page.traitCollection.horizontalSizeClass == .regular ? .compact : .regular),
            UITraitCollection(verticalSizeClass: page.traitCollection.verticalSizeClass == .regular ? .compact : .regular)])
        page.traitCollectionDidChange(previous)
        XCTAssertTrue(items(page).first === item)
        XCTAssertTrue(item.primaryAction === primary)
        XCTAssertTrue(item.menuRepresentation === representation)
        page.trailing[0].title = "已更新动作"
        page.refreshScreenConfiguration()
        XCTAssertTrue(items(page).first === item)
        XCTAssertEqual(item.primaryAction?.title, "已更新动作")
    }

    func testClassicContainersDisableVerticalBarsForOrdinaryControllers() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Vertical bars require iOS 27.1") }
        let ordinary = UIViewController()
        let navigation = BoneNavigationController(rootViewController: ordinary)
        navigation.barPresentation = .classic
        XCTAssertEqual(navigation.preferredVerticalBarBehavior, .disabled)
        XCTAssertNil(navigation.childForPreferredVerticalBarBehavior)
        navigation.barPresentation = .system
        XCTAssertEqual(navigation.preferredVerticalBarBehavior, .automatic)
        XCTAssertTrue(navigation.childForPreferredVerticalBarBehavior === ordinary)

        let tabs = BoneTabBarController(tabs: [ShellTab(id: "ordinary", title: "普通页", symbol: "star", root: UIViewController())])
        tabs.barPresentation = .classic
        XCTAssertEqual(tabs.preferredVerticalBarBehavior, .disabled)
        XCTAssertNil(tabs.childForPreferredVerticalBarBehavior)
        tabs.barPresentation = .system
        XCTAssertEqual(tabs.preferredVerticalBarBehavior, .automatic)
        XCTAssertTrue(tabs.childForPreferredVerticalBarBehavior === tabs.selectedViewController)
    }

    private func host(_ page: ActionFixture, presentation: ShellBarPresentation = .system) {
        page.presentation = presentation
        let navigation = BoneNavigationController(rootViewController: page)
        retainedNavigation = navigation
        navigation.loadViewIfNeeded()
        navigation.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        page.loadViewIfNeeded()
        page.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 650)
        page.refreshScreenConfiguration()
    }

    private func items(_ page: ActionFixture) -> [UIBarButtonItem] {
        if #available(iOS 27.0, *), page.usesSystemNavigationActionLayout {
            return page.navigationItem.leadingItemGroups.flatMap(\.barButtonItems)
                + page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
                + (page.navigationItem.pinnedTrailingGroup?.barButtonItems ?? [])
        }
        return ((page.navigationItem.leftBarButtonItems ?? []) + (page.navigationItem.rightBarButtonItems ?? []))
            .filter { $0.accessibilityIdentifier != "shell.overflow" }
    }

    private func trigger(_ action: UIAction) {
        let button = UIButton(type: .system)
        button.addAction(action, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
    }

    private func glyph() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
            UIColor.systemOrange.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 18, height: 18)).fill()
        }
    }
}

@MainActor
private final class ActionFixture: BoneViewController {
    var leading: [NavigationAction] = []
    var trailing: [NavigationAction] = []
    var presentation: ShellBarPresentation = .system
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.barPresentation = presentation
        screen.navigation.title = "动作适配"
        screen.navigation.leadingActions = leading
        screen.navigation.trailingActions = trailing
    }
}

@MainActor
private final class HandlerToken {
    var calls = 0
}
