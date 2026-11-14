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

    func testTabPresentationAndResetRestoreDefaults() {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        page.setPresentationIndexForTesting(1)
        XCTAssertEqual(tabs.barPresentation, .classic)
        page.setPresentationIndexForTesting(2)
        XCTAssertEqual(tabs.barPresentation, .capsule)
        page.reset()
        XCTAssertEqual(tabs.barPresentation, .automatic)
        XCTAssertTrue(tabs.tabBarAccessories.isEmpty)
        XCTAssertNil(page.screenConfiguration.tabBarStyle?.normal.font)
    }

    // MARK: - Helpers

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
