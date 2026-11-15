import XCTest
import UIKit
@testable import BoneShellKit
@testable import BoneShellDemo

@MainActor
final class BarDemoIntegrationTests: XCTestCase {
    // MARK: - Navigation bar scene

    func testNavigationSceneExposesEveryNavigationSetting() {
        let (tabs, navigation, page) = navigationScene()
        XCTAssertEqual(page.screenConfiguration.navigation.title, "导航栏")
        XCTAssertNotNil(page.screenConfiguration.navigation.subtitle)
        XCTAssertNotNil(page.screenConfiguration.navigation.style)
        // Text and icon actions live on both sides.
        let trailing = navigation.topViewController?.navigationItem.rightBarButtonItems ?? []
        XCTAssertFalse(trailing.isEmpty)
        XCTAssertFalse((navigation.topViewController?.navigationItem.leftBarButtonItems ?? []).isEmpty)
        XCTAssertTrue(tabs.viewControllers?.count == 3)
    }

    func testNavigationSettingChangesApplyWithoutRebuildingContent() {
        let (_, _, page) = navigationScene()
        page.loadViewIfNeeded()
        let identity = page.contentView
        page.setTitleSizeForTesting(24, colorIndex: 2)
        XCTAssertEqual(page.screenConfiguration.navigation.style?.title.font?.pointSize, 24)
        XCTAssertTrue(page.contentView === identity, "Style changes must not rebuild content")
        page.reset()
        XCTAssertNil(page.screenConfiguration.navigation.style?.title.font)
    }

    func testNavigationPresentationOnlyAffectsNavigation() {
        let (tabs, navigation, page) = navigationScene()
        page.loadViewIfNeeded()
        page.setPresentationIndexForTesting(2)
        XCTAssertEqual(navigation.barPresentation, .classic)
        XCTAssertEqual(navigation.resolvedBarPresentation, .classic)
        // The tab bar keeps its own presentation.
        XCTAssertEqual(tabs.barPresentation, .system)
        page.setPresentationIndexForTesting(0)
        XCTAssertNil(navigation.barPresentation)
    }

    // MARK: - Tab bar scene

    func testTabSceneExposesEveryTabSetting() {
        let (tabs, _, page) = tabScene()
        XCTAssertEqual(page.screenConfiguration.navigation.title, "标签栏")
        XCTAssertNotNil(page.screenConfiguration.tabBarStyle)
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.title, "示例")
    }

    func testTabLabelPickerAppliesAllModesWithoutRebuildingRoots() throws {
        let (tabs, navigation, page) = tabScene()
        let picker = try XCTUnwrap(view(withIdentifier: "tabbar.labels", in: page.view) as? UISegmentedControl)
        let status = try XCTUnwrap(view(withIdentifier: "tabbar.status", in: page.view) as? UILabel)
        let modes: [ShellTabLabelDisplayMode] = [.always, .never, .selectedOnly, .unselectedOnly]
        let titles = ["始终显示", "始终隐藏", "仅选中", "仅未选中"]
        let roots = tabs.viewControllers ?? []
        let stack = navigation.viewControllers
        let content = page.contentView
        XCTAssertEqual(picker.numberOfSegments, 4)
        XCTAssertEqual(picker.selectedSegmentIndex, 0)
        XCTAssertEqual(page.labelDisplayMode, .always)
        for (index, mode) in modes.enumerated() {
            XCTAssertEqual(picker.titleForSegment(at: index), titles[index])
            picker.selectedSegmentIndex = index
            picker.sendActions(for: .valueChanged)
            XCTAssertEqual(page.labelDisplayMode, mode)
            XCTAssertEqual(page.screenConfiguration.tabBarStyle?.labelDisplayMode, mode)
            XCTAssertEqual(tabs.tabBarStyle.labelDisplayMode, mode)
            XCTAssertTrue(status.text?.contains("文字：\(titles[index])") == true)
            XCTAssertEqual(tabs.selectedIndex, 0)
            XCTAssertEqual(tabs.viewControllers?.count, roots.count)
            for (before, after) in zip(roots, tabs.viewControllers ?? []) { XCTAssertTrue(before === after) }
            XCTAssertEqual(navigation.viewControllers.count, stack.count)
            for (before, after) in zip(stack, navigation.viewControllers) { XCTAssertTrue(before === after) }
            XCTAssertTrue(page.contentView === content)
            for (id, title) in [("examples", "示例"), ("materials", "材质"), ("about", "关于")] {
                XCTAssertEqual(tabs.tabItemConfiguration(for: id)?.title, title)
                XCTAssertNil(tabs.tabItemConfiguration(for: id)?.labelDisplayMode, "Tabs inherit the current style")
            }
        }
    }

    func testTabSelectedOnlyLabelsPreserveSettingsAndNavigationAfterTabSwitch() throws {
        let (tabs, navigation, page) = tabScene()
        navigation.setViewControllers([UIViewController(), page], animated: false)
        let size = try XCTUnwrap(view(withIdentifier: "tabbar.size", in: page.view) as? UISegmentedControl)
        let colors = try XCTUnwrap(view(withIdentifier: "tabbar.colors", in: page.view) as? UISegmentedControl)
        let background = try XCTUnwrap(view(withIdentifier: "tabbar.background", in: page.view) as? UIButton)
        size.selectedSegmentIndex = 3
        size.sendActions(for: .valueChanged)
        colors.selectedSegmentIndex = 2
        colors.sendActions(for: .valueChanged)
        XCTAssertTrue(page.setIconMode(1))
        XCTAssertTrue(page.setSelectedIconMode(.selectedImage))
        page.setPresentationIndexForTesting(2)
        page.setAccessoryIndexForTesting(3)
        background.sendActions(for: .touchUpInside)
        page.note("保留")
        var item = try XCTUnwrap(tabs.tabItemConfiguration(for: "materials"))
        item.labelDisplayMode = .never
        XCTAssertTrue(tabs.updateTabItem(id: "materials", configuration: item))
        let roots = tabs.viewControllers ?? []
        let stack = navigation.viewControllers
        let content = page.contentView

        page.setLabelDisplayModeForTesting(.selectedOnly)
        tabs.selectedIndex = 2
        XCTAssertEqual(tabs.selectedIndex, 2)
        XCTAssertTrue(tabs.selectedViewController === roots[2])
        XCTAssertEqual(tabs.tabBarStyle.labelDisplayMode, .selectedOnly)
        tabs.selectedIndex = 0
        XCTAssertEqual(tabs.selectedIndex, 0)
        XCTAssertTrue(navigation.topViewController === page)
        XCTAssertEqual(navigation.viewControllers.count, stack.count)
        for (before, after) in zip(stack, navigation.viewControllers) { XCTAssertTrue(before === after) }
        XCTAssertEqual(tabs.viewControllers?.count, roots.count)
        for (before, after) in zip(roots, tabs.viewControllers ?? []) { XCTAssertTrue(before === after) }
        XCTAssertTrue(page.contentView === content)
        XCTAssertEqual(page.labelDisplayMode, .selectedOnly)
        XCTAssertEqual(page.screenConfiguration.tabBarStyle?.labelDisplayMode, .selectedOnly)
        XCTAssertEqual(page.screenConfiguration.tabBarStyle?.normal.font?.pointSize, 14)
        XCTAssertEqual(page.tabColorIndex, 2)
        XCTAssertEqual(page.iconMode, 1)
        XCTAssertEqual(page.selectedIconMode, .selectedImage)
        XCTAssertEqual(page.presentationIndex, 2)
        XCTAssertEqual(page.accessoryIndex, 3)
        XCTAssertTrue(page.showsBackground)
        XCTAssertEqual(page.message, "已触发：保留")
        XCTAssertEqual(tabs.tabItemConfiguration(for: "materials")?.labelDisplayMode, .never)
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.selectedIconMode, .selectedImage)
        let labels = try XCTUnwrap(view(withIdentifier: "tabbar.labels", in: page.view) as? UISegmentedControl)
        XCTAssertEqual(labels.selectedSegmentIndex, 2)
        for (controller, title) in zip(roots, ["示例", "材质", "关于"]) {
            XCTAssertEqual(controller.tabBarItem.accessibilityLabel, title)
        }
    }

    func testTabIconModesAndSelectedPolicyApplyToExistingItems() {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        let roots = tabs.viewControllers
        XCTAssertTrue(page.setIconMode(1))
        XCTAssertEqual(page.iconMode, 1)
        XCTAssertTrue(page.setSelectedIconMode(.selectedImage))
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.selectedIconMode, .selectedImage)
        // Destinations and selection survive.
        for (left, right) in zip(tabs.viewControllers ?? [], roots ?? []) { XCTAssertTrue(left === right) }
        XCTAssertTrue(page.setIconMode(0))
        XCTAssertTrue(page.setSelectedIconMode(.automatic))
    }

    func testTabAccessoriesFollowTheAccessoryPicker() {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        page.setAccessoryIndexForTesting(3)
        XCTAssertEqual(tabs.tabBarAccessories.count, 2)
        XCTAssertEqual(tabs.tabBarAccessories.first?.position, .leading)
        XCTAssertEqual(tabs.tabBarAccessories.last?.position, .trailing)
        page.setAccessoryIndexForTesting(0)
        XCTAssertTrue(tabs.tabBarAccessories.isEmpty)
    }

    func testTabPresentationAndResetRestoreDefaults() throws {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        page.setPresentationIndexForTesting(1)
        XCTAssertEqual(tabs.barPresentation, .classic)
        page.setPresentationIndexForTesting(2)
        XCTAssertEqual(tabs.barPresentation, .capsule)
        page.setAccessoryIndexForTesting(3)
        page.setLabelDisplayModeForTesting(.never)
        page.reset()
        XCTAssertEqual(tabs.barPresentation, .automatic)
        XCTAssertTrue(tabs.tabBarAccessories.isEmpty)
        XCTAssertNil(page.screenConfiguration.tabBarStyle?.normal.font)
        XCTAssertEqual(page.labelDisplayMode, .always)
        XCTAssertEqual(page.screenConfiguration.tabBarStyle?.labelDisplayMode, .always)
        XCTAssertEqual(tabs.tabBarStyle.labelDisplayMode, .always)
        let picker = try XCTUnwrap(view(withIdentifier: "tabbar.labels", in: page.view) as? UISegmentedControl)
        XCTAssertEqual(picker.selectedSegmentIndex, 0)
        let status = try XCTUnwrap(view(withIdentifier: "tabbar.status", in: page.view) as? UILabel)
        XCTAssertTrue(status.text?.contains("文字：始终显示") == true)
    }

    // MARK: - Helpers

    private func view(withIdentifier identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier { return root }
        for child in root.subviews {
            if let match = view(withIdentifier: identifier, in: child) { return match }
        }
        return nil
    }

    private func navigationScene() -> (BoneTabBarController, BoneNavigationController, NavigationBarDemoController) {
        let page = NavigationBarDemoController()
        let (tabs, navigation) = containers(page)
        return (tabs, navigation, page)
    }

    private func tabScene() -> (BoneTabBarController, BoneNavigationController, TabBarDemoController) {
        let page = TabBarDemoController()
        let (tabs, navigation) = containers(page)
        return (tabs, navigation, page)
    }

    private func containers(_ page: BoneViewController) -> (BoneTabBarController, BoneNavigationController) {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "examples", title: "示例", symbol: "square.grid.2x2", root: page),
            ShellTab(id: "materials", title: "材质", symbol: "circle.lefthalf.filled", root: UIViewController()),
            ShellTab(id: "about", title: "关于", symbol: "info.circle", root: UIViewController())
        ])
        tabs.loadViewIfNeeded()
        tabs.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let navigation = tabs.viewControllers?.first as! BoneNavigationController
        navigation.loadViewIfNeeded()
        // Loading the page runs its configuration, which is what these assertions inspect.
        page.loadViewIfNeeded()
        navigation.view.layoutIfNeeded()
        return (tabs, navigation)
    }
}
