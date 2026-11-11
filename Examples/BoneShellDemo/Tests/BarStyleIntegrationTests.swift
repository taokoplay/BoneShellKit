import XCTest
import UIKit
import BoneShellKit
@testable import BoneShellDemo

@MainActor
final class BarStyleIntegrationTests: XCTestCase {
    func testNavigationTitleLargeTitleAndTextActionUseSelectedStyle() throws {
        let page = BarStyleDemoController()
        let tabs = makeTabs(root: page)
        let navigation = try navigation(in: tabs)
        page.setNavigationFontSize(20, scalesWithDynamicType: false)
        page.setNavigationColor(1)

        let appearance = navigationAppearance(page, navigation)
        try assertFont(appearance.titleTextAttributes, size: 20)
        try assertFont(appearance.largeTitleTextAttributes, size: 30)
        assertColor(appearance.titleTextAttributes[.foregroundColor] as? UIColor, .systemBlue)
        let action = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first {
            $0.accessibilityIdentifier == "action.bar-style.next"
        })
        XCTAssertEqual(action.title, "详情")
        XCTAssertNil(action.image, "The font sample must be a native text action")
        let attributes = action.titleTextAttributes(for: .normal)
            ?? appearance.buttonAppearance.normal.titleTextAttributes
        try assertFont(attributes, size: 20)
        assertColor(attributes[.foregroundColor] as? UIColor, .systemBlue)
        XCTAssertTrue(page.visibleActionIDs.contains("bar-style.next"))
    }

    func testTabFontsTextColorsAndIconTintsReachEveryNativeLayout() throws {
        let page = BarStyleDemoController()
        let tabs = makeTabs(root: page)
        page.setTabFontSize(14, scalesWithDynamicType: false)
        page.setTabColors(2)

        for layout in tabLayouts(tabAppearance(tabs)) {
            try assertFont(layout.normal.titleTextAttributes, size: 14)
            try assertFont(layout.selected.titleTextAttributes, size: 14)
            assertColor(layout.normal.titleTextAttributes[.foregroundColor] as? UIColor, .systemBlue)
            assertColor(layout.selected.titleTextAttributes[.foregroundColor] as? UIColor, .systemOrange)
            assertColor(layout.normal.iconColor, .systemBlue)
            assertColor(layout.selected.iconColor, .systemOrange)
        }
    }

    func testNilStylesInheritAndEmptyStylesOverrideContainerDefaults() throws {
        let page = BarStyleFixtureController()
        let tabs = makeTabs(root: page)
        let navigation = try navigation(in: tabs)
        let baselineTitle = navigationAppearance(page, navigation).titleTextAttributes
        let baselineTab = tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes
        navigation.navigationStyle = ShellNavigationStyle(
            title: ShellTextStyle(size: 23, color: .systemPurple, scalesWithDynamicType: false))
        tabs.tabBarStyle = ShellTabBarStyle(
            normal: ShellTextStyle(size: 11, scalesWithDynamicType: false),
            selected: ShellTextStyle(size: 13, color: .systemOrange, scalesWithDynamicType: false))
        page.refreshScreenConfiguration()
        XCTAssertNil(page.screenConfiguration.navigation.style)
        XCTAssertNil(page.screenConfiguration.tabBarStyle)
        try assertFont(navigationAppearance(page, navigation).titleTextAttributes, size: 23)
        try assertFont(tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes, size: 13)

        page.navigationOverride = ShellNavigationStyle()
        page.tabOverride = ShellTabBarStyle()
        page.refreshScreenConfiguration()
        assertSameTextAttributes(navigationAppearance(page, navigation).titleTextAttributes, baselineTitle)
        assertSameTextAttributes(tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes, baselineTab)

        page.navigationOverride = nil
        page.tabOverride = nil
        page.refreshScreenConfiguration()
        try assertFont(navigationAppearance(page, navigation).titleTextAttributes, size: 23)
        assertColor(navigationAppearance(page, navigation).titleTextAttributes[.foregroundColor] as? UIColor, .systemPurple)
        try assertFont(tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes, size: 13)
    }

    func testSceneResetRestoresSystemAppearanceAndOriginalExampleIcons() throws {
        let page = BarStyleDemoController()
        let tabs = makeTabs(root: page)
        let navigation = try navigation(in: tabs)
        let baselineTitle = navigationAppearance(page, navigation).titleTextAttributes
        let baselineLargeTitle = navigationAppearance(page, navigation).largeTitleTextAttributes
        let baselineAction = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first)
        let baselineButton = baselineAction.titleTextAttributes(for: .normal)
            ?? navigationAppearance(page, navigation).buttonAppearance.normal.titleTextAttributes
        let baselineLayouts = tabLayouts(tabAppearance(tabs)).map {
            ($0.normal.titleTextAttributes, $0.selected.titleTextAttributes, $0.normal.iconColor, $0.selected.iconColor)
        }
        page.setNavigationFontSize(24, scalesWithDynamicType: false)
        page.setNavigationColor(2)
        page.setTabFontSize(14, scalesWithDynamicType: false)
        page.setTabColors(2)
        XCTAssertTrue(page.setIconMode(2))
        XCTAssertTrue(page.resetStyles())

        assertSameTextAttributes(navigationAppearance(page, navigation).titleTextAttributes, baselineTitle)
        assertSameTextAttributes(navigationAppearance(page, navigation).largeTitleTextAttributes, baselineLargeTitle)
        let resetAction = try XCTUnwrap(page.navigationItem.rightBarButtonItems?.first)
        let resetButton = resetAction.titleTextAttributes(for: .normal)
            ?? navigationAppearance(page, navigation).buttonAppearance.normal.titleTextAttributes
        assertSameTextAttributes(resetButton, baselineButton)
        for (layout, baseline) in zip(tabLayouts(tabAppearance(tabs)), baselineLayouts) {
            assertSameTextAttributes(layout.normal.titleTextAttributes, baseline.0)
            assertSameTextAttributes(layout.selected.titleTextAttributes, baseline.1)
            assertOptionalColor(layout.normal.iconColor, baseline.2)
            assertOptionalColor(layout.selected.iconColor, baseline.3)
        }
        XCTAssertNotNil(page.screenConfiguration.navigation.style, "Reset explicitly opts out of inherited styling")
        XCTAssertNil(page.screenConfiguration.navigation.style?.title.font)
        XCTAssertNotNil(page.screenConfiguration.tabBarStyle)
        XCTAssertNil(page.screenConfiguration.tabBarStyle?.selected.font)
        let originals = [("examples", "示例", "square.grid.2x2"),
                         ("materials", "材质", "circle.lefthalf.filled"),
                         ("about", "关于", "info.circle")]
        for (index, original) in originals.enumerated() {
            let configuration = try XCTUnwrap(tabs.tabItemConfiguration(for: original.0))
            XCTAssertEqual(configuration.title, original.1)
            if case let .systemSymbol(name)? = configuration.icon {
                XCTAssertEqual(name, original.2)
            } else {
                XCTFail("Reset must restore the original SF Symbol for \(original.0)")
            }
            XCTAssertNil(configuration.selectedIcon)
            let item = try XCTUnwrap(tabs.tabBar.items?[index])
            XCTAssertEqual(item.title, original.1)
            XCTAssertEqual(item.image?.isSymbolImage, true)
            XCTAssertEqual(item.accessibilityIdentifier, "tab.\(original.0)")
        }
    }

    func testBackgroundCompositionKeepsNavigationAndTabTypography() throws {
        let page = BarStyleFixtureController()
        page.navigationOverride = ShellNavigationStyle(
            title: ShellTextStyle(size: 22, color: .systemBlue, scalesWithDynamicType: false))
        page.tabOverride = ShellTabBarStyle(
            selected: ShellTextStyle(size: 12, color: .systemOrange, scalesWithDynamicType: false),
            selectedIconColor: .systemOrange)
        let tabs = makeTabs(root: page)
        let navigation = try navigation(in: tabs)
        page.navigationBackground = ShellBackgroundConfiguration(source: .color(.systemYellow))
        page.tabBackground = ShellBackgroundConfiguration(source: .color(.systemTeal))
        page.refreshScreenConfiguration()

        XCTAssertEqual(navigation.backgroundView?.configuration?.source.kindName, "color")
        XCTAssertEqual(tabs.backgroundView?.configuration?.source.kindName, "color")
        try assertFont(navigationAppearance(page, navigation).titleTextAttributes, size: 22)
        assertColor(navigationAppearance(page, navigation).titleTextAttributes[.foregroundColor] as? UIColor, .systemBlue)
        try assertFont(tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes, size: 12)
        assertColor(tabAppearance(tabs).stackedLayoutAppearance.selected.iconColor, .systemOrange)

        page.navigationBackground = nil
        page.tabBackground = nil
        page.refreshScreenConfiguration()
        XCTAssertNil(navigation.backgroundView?.configuration)
        XCTAssertNil(tabs.backgroundView?.configuration)
        try assertFont(navigationAppearance(page, navigation).titleTextAttributes, size: 22)
        try assertFont(tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes, size: 12)
        assertColor(tabAppearance(tabs).stackedLayoutAppearance.selected.iconColor, .systemOrange)
    }

    func testAssetInitializerAndSceneImageModesUseSeparateSelectedArtwork() throws {
        let normal = try XCTUnwrap(BarStyleDemoIcons.image(selected: false), "Normal icon must be bundled")
        let selected = try XCTUnwrap(BarStyleDemoIcons.image(selected: true), "Selected icon must be bundled")
        let assetTabs = BoneTabBarController(tabs: [ShellTab(
            id: "asset", title: "资源", icon: .asset(BarStyleDemoIcons.assetName(selected: false), bundle: .main),
            selectedIcon: .asset(BarStyleDemoIcons.assetName(selected: true), bundle: .main), root: BoneViewController())])
        assetTabs.loadViewIfNeeded()
        let assetItem = try XCTUnwrap(assetTabs.tabBar.items?.first)
        XCTAssertEqual(assetItem.image?.pngData(), normal.pngData())
        XCTAssertEqual(assetItem.selectedImage?.pngData(), selected.pngData())
        XCTAssertEqual(assetItem.image?.renderingMode, .alwaysTemplate)
        XCTAssertEqual(assetItem.selectedImage?.renderingMode, .alwaysTemplate)
        XCTAssertNotEqual(normal.pngData(), selected.pngData())

        let page = BarStyleDemoController()
        let tabs = makeTabs(root: page)
        XCTAssertTrue(page.setIconMode(1))
        let assetConfiguration = try XCTUnwrap(tabs.tabItemConfiguration(for: "examples"))
        if case let .asset(name, bundle)? = assetConfiguration.icon {
            XCTAssertEqual(name, BarStyleDemoIcons.assetName(selected: false))
            XCTAssertEqual(bundle.bundleURL, Bundle.main.bundleURL)
        } else {
            XCTFail("Resource mode must use ShellTabIcon.asset")
        }
        XCTAssertEqual(tabs.tabBar.items?.first?.selectedImage?.pngData(), selected.pngData())

        XCTAssertTrue(page.setIconMode(2))
        let imageConfiguration = try XCTUnwrap(tabs.tabItemConfiguration(for: "examples"))
        if case let .image(image)? = imageConfiguration.icon {
            XCTAssertEqual(image.renderingMode, .alwaysOriginal)
        } else {
            XCTFail("Color mode must use ShellTabIcon.image")
        }
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        XCTAssertEqual(item.image?.renderingMode, .alwaysOriginal)
        XCTAssertEqual(item.selectedImage?.renderingMode, .alwaysOriginal)
        XCTAssertEqual(item.image?.pngData(), normal.pngData())
        XCTAssertEqual(item.selectedImage?.pngData(), selected.pngData())
        XCTAssertTrue(page.setIconMode(0))
        XCTAssertEqual(tabs.tabBar.items?.first?.image?.isSymbolImage, true)
        XCTAssertNil(tabs.tabItemConfiguration(for: "examples")?.selectedIcon)
    }

    func testRuntimeItemUpdatePreservesSelectionControllersDetailStackAndInput() throws {
        let page = BarStyleDemoController()
        let tabs = makeTabs(root: page)
        let navigation = try navigation(in: tabs)
        page.setNavigationFontSize(20, scalesWithDynamicType: false)
        page.setTabFontSize(12, scalesWithDynamicType: false)
        let detail = page.openDetail(animated: false)
        detail.loadViewIfNeeded()
        let input = detail.input
        input.text = "KeepStyle123"
        let controllers = try XCTUnwrap(tabs.viewControllers)
        let originalTag = navigation.tabBarItem.tag
        tabs.selectedIndex = 1
        let selectedController = tabs.selectedViewController
        var configuration = try XCTUnwrap(tabs.tabItemConfiguration(for: "examples"))
        configuration.title = "新图标"
        configuration.icon = .image(try XCTUnwrap(BarStyleDemoIcons.image(selected: false)).withRenderingMode(.alwaysOriginal))
        configuration.selectedIcon = .image(try XCTUnwrap(BarStyleDemoIcons.image(selected: true)).withRenderingMode(.alwaysOriginal))
        XCTAssertTrue(tabs.updateTabItem(id: "examples", configuration: configuration))

        XCTAssertEqual(tabs.selectedIndex, 1)
        XCTAssertTrue(tabs.selectedViewController === selectedController)
        XCTAssertEqual(tabs.viewControllers?.count, controllers.count)
        for (index, controller) in controllers.enumerated() {
            XCTAssertTrue(tabs.viewControllers?[index] === controller)
        }
        XCTAssertEqual(navigation.tabBarItem.title, "新图标")
        XCTAssertEqual(navigation.tabBarItem.tag, originalTag)
        XCTAssertEqual(navigation.tabBarItem.accessibilityIdentifier, "tab.examples")
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.title, "新图标")
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.viewControllers.first === page)
        XCTAssertTrue(navigation.topViewController === detail)
        XCTAssertTrue(detail.input === input)
        XCTAssertEqual(input.text, "KeepStyle123")
        XCTAssertTrue(input.isDescendant(of: detail.contentView))
        tabs.selectedIndex = 0
        XCTAssertTrue(navigation.topViewController === detail)
        XCTAssertEqual(detail.input.text, "KeepStyle123")
        try assertFont(navigationAppearance(detail, navigation).titleTextAttributes, size: 20)
        try assertFont(tabAppearance(tabs).stackedLayoutAppearance.selected.titleTextAttributes, size: 12)
    }

    func testUnknownIDIsNoOpAndNilSelectedIconUsesNormalImage() throws {
        let page = BarStyleDemoController()
        let tabs = makeTabs(root: page)
        let originalTitles = tabs.tabBar.items?.map(\.title)
        let controllers = try XCTUnwrap(tabs.viewControllers)
        tabs.selectedIndex = 2
        XCTAssertFalse(tabs.updateTabItem(id: "missing", configuration: ShellTabItemConfiguration(title: "Missing")))
        XCTAssertNil(tabs.tabItemConfiguration(for: "missing"))
        XCTAssertEqual(tabs.selectedIndex, 2)
        XCTAssertEqual(tabs.tabBar.items?.map(\.title), originalTitles)
        for (index, controller) in controllers.enumerated() {
            XCTAssertTrue(tabs.viewControllers?[index] === controller)
        }

        let image = try XCTUnwrap(BarStyleDemoIcons.image(selected: false)).withRenderingMode(.alwaysOriginal)
        XCTAssertTrue(tabs.updateTabItem(id: "examples", configuration: ShellTabItemConfiguration(title: "示例", icon: .image(image))))
        XCTAssertNil(tabs.tabItemConfiguration(for: "examples")?.selectedIcon)
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        XCTAssertEqual(item.image?.pngData(), image.pngData())
        XCTAssertEqual((item.selectedImage ?? item.image)?.pngData(), image.pngData())
    }

    private func makeTabs(root: BoneViewController) -> BoneTabBarController {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "examples", title: "示例", symbol: "square.grid.2x2", root: root),
            ShellTab(id: "materials", title: "材质", symbol: "circle.lefthalf.filled", root: BoneViewController()),
            ShellTab(id: "about", title: "关于", symbol: "info.circle", root: BoneViewController())
        ])
        tabs.loadViewIfNeeded()
        tabs.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        tabs.viewControllers?.forEach { $0.loadViewIfNeeded() }
        root.loadViewIfNeeded()
        root.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 700)
        root.refreshScreenConfiguration()
        tabs.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        return tabs
    }

    private func navigation(in tabs: BoneTabBarController) throws -> BoneNavigationController {
        try XCTUnwrap(tabs.viewControllers?.first as? BoneNavigationController)
    }

    private func navigationAppearance(_ page: BoneViewController, _ navigation: BoneNavigationController) -> UINavigationBarAppearance {
        page.navigationItem.standardAppearance ?? navigation.navigationBar.standardAppearance
    }

    private func tabAppearance(_ tabs: BoneTabBarController) -> UITabBarAppearance {
        tabs.selectedViewController?.tabBarItem.standardAppearance ?? tabs.tabBar.standardAppearance
    }

    private func tabLayouts(_ appearance: UITabBarAppearance) -> [UITabBarItemAppearance] {
        [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance]
    }

    private func assertFont(_ attributes: [NSAttributedString.Key: Any], size: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let font = try XCTUnwrap(attributes[.font] as? UIFont, file: file, line: line)
        XCTAssertEqual(font.pointSize, size, accuracy: 0.01, file: file, line: line)
    }

    private func assertColor(_ actual: UIColor?, _ expected: UIColor,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let actual = actual else { return XCTFail("Missing appearance color", file: file, line: line) }
        let traits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(actual.resolvedColor(with: traits), expected.resolvedColor(with: traits), file: file, line: line)
    }

    private func assertOptionalColor(_ actual: UIColor?, _ expected: UIColor?,
                                     file: StaticString = #filePath, line: UInt = #line) {
        if let expected = expected {
            assertColor(actual, expected, file: file, line: line)
        } else {
            XCTAssertNil(actual, file: file, line: line)
        }
    }

    private func assertSameTextAttributes(_ actual: [NSAttributedString.Key: Any], _ expected: [NSAttributedString.Key: Any],
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((actual[.font] as? UIFont)?.pointSize, (expected[.font] as? UIFont)?.pointSize, file: file, line: line)
        XCTAssertEqual((actual[.font] as? UIFont)?.fontName, (expected[.font] as? UIFont)?.fontName, file: file, line: line)
        assertOptionalColor(actual[.foregroundColor] as? UIColor, expected[.foregroundColor] as? UIColor, file: file, line: line)
    }
}

@MainActor
private final class BarStyleFixtureController: BoneViewController {
    var navigationOverride: ShellNavigationStyle?
    var tabOverride: ShellTabBarStyle?
    var navigationBackground: ShellBackgroundConfiguration?
    var tabBackground: ShellBackgroundConfiguration?

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "栏位测试"
        screen.navigation.style = navigationOverride
        screen.tabBarStyle = tabOverride
        screen.navigation.background = navigationBackground
        screen.tabBarBackground = tabBackground
    }
}
