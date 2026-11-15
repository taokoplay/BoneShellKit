import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class TabLabelDisplayTests: XCTestCase {
    private var windows: [UIWindow] = []
    private weak var previousKeyWindow: UIWindow?

    override func setUp() {
        super.setUp()
        previousKeyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    override func tearDown() {
        windows.forEach { $0.isHidden = true; $0.rootViewController = nil }
        windows.removeAll()
        previousKeyWindow?.makeKeyAndVisible()
        ShellBarPresentation.capabilityOverride = nil
        super.tearDown()
    }

    func testFourPoliciesAndSourceCompatibleDefaults() {
        let expectations: [(ShellTabLabelDisplayMode, Bool, Bool)] = [
            (.always, true, true), (.never, false, false),
            (.selectedOnly, true, false), (.unselectedOnly, false, true)
        ]
        XCTAssertEqual(ShellTabLabelDisplayMode.allCases.count, 4)
        for (mode, selected, normal) in expectations {
            XCTAssertEqual(mode.isVisible(isSelected: true), selected)
            XCTAssertEqual(mode.isVisible(isSelected: false), normal)
        }
        XCTAssertEqual(ShellTabBarStyle().labelDisplayMode, .always)
        XCTAssertNil(ShellTabItemConfiguration(title: "首页").labelDisplayMode)
        XCTAssertNil(ShellTab(id: "home", title: "首页", symbol: "house", root: LabelFixture()).item.labelDisplayMode)
        XCTAssertEqual(ShellTab(id: "home", title: "首页", icon: .systemSymbol("house"),
            labelDisplayMode: .never, root: LabelFixture()).item.labelDisplayMode, .never)
    }

    func testNativeTitlesFollowSelectionWithoutChangingSemanticConfiguration() throws {
        let tabs = makeTabs(presentation: .system)
        let controllers = try XCTUnwrap(tabs.viewControllers)
        for mode in ShellTabLabelDisplayMode.allCases {
            tabs.tabBarStyle.labelDisplayMode = mode
            for selection in [0, 1] {
                tabs.selectedIndex = selection
                tabs.view.layoutIfNeeded()
                for (index, controller) in controllers.enumerated() {
                    let id = ["home", "materials", "about"][index]
                    let title = ["首页", "材质", "关于"][index]
                    XCTAssertEqual(tabs.tabItemConfiguration(for: id)?.title, title)
                    XCTAssertEqual(controller.tabBarItem.title,
                        mode.isVisible(isSelected: index == selection) ? title : nil)
                    if mode != .always { XCTAssertEqual(controller.tabBarItem.accessibilityLabel, title) }
                    XCTAssertEqual(controller.tabBarItem.accessibilityIdentifier, "tab.\(id)")
                }
            }
        }
    }

    func testPerItemOverrideAndCustomAccessibilitySurviveRenameAndRestoration() throws {
        let tabs = makeTabs(presentation: .system)
        let home = try XCTUnwrap(tabs.viewControllers?.first)
        home.tabBarItem.accessibilityLabel = "个人主页入口"
        tabs.tabBarStyle.labelDisplayMode = .never
        XCTAssertNil(home.tabBarItem.title)
        XCTAssertEqual(home.tabBarItem.accessibilityLabel, "个人主页入口")
        var item = try XCTUnwrap(tabs.tabItemConfiguration(for: "home"))
        item.title = "新的首页"
        item.labelDisplayMode = .always
        XCTAssertTrue(tabs.updateTabItem(id: "home", configuration: item))
        XCTAssertEqual(home.tabBarItem.title, "新的首页")
        XCTAssertEqual(home.tabBarItem.accessibilityLabel, "个人主页入口")
        item.labelDisplayMode = nil
        XCTAssertTrue(tabs.updateTabItem(id: "home", configuration: item))
        XCTAssertNil(home.tabBarItem.title)
        tabs.tabBarStyle = ShellTabBarStyle()
        XCTAssertEqual(home.tabBarItem.title, "新的首页")
        XCTAssertEqual(home.tabBarItem.accessibilityLabel, "个人主页入口")
        XCTAssertTrue(tabs.viewControllers?.first === home)
    }

    func testClassicAndCompatibilityCapsuleHideRealLabelsAndCenterIcons() throws {
        ShellBarPresentation.capabilityOverride = false
        for presentation in [ShellBarPresentation.classic, .capsule] {
            let tabs = makeTabs(presentation: presentation)
            let controllers = try XCTUnwrap(tabs.viewControllers)
            for mode in ShellTabLabelDisplayMode.allCases {
                tabs.tabBarStyle.labelDisplayMode = mode
                for selection in [0, 1] {
                    tabs.selectedIndex = selection
                    tabs.view.layoutIfNeeded()
                    let bar = try XCTUnwrap(tabs.classicTabBarView ?? tabs.capsuleTabBarView)
                    bar.layoutIfNeeded()
                    for (index, controller) in controllers.enumerated() {
                        let button = try XCTUnwrap(find(controller.tabBarItem.accessibilityIdentifier!, in: bar))
                        button.layoutIfNeeded()
                        let label = try XCTUnwrap(button.subviews.compactMap { $0 as? UILabel }
                            .first { $0.text == controller.tabBarItem.title })
                        let visible = mode.isVisible(isSelected: index == selection)
                        XCTAssertEqual(label.isHidden, !visible)
                        XCTAssertEqual(button.accessibilityLabel, controller.tabBarItem.title)
                        if !visible {
                            let icon = try XCTUnwrap(button.subviews.compactMap { $0 as? UIImageView }.first)
                            XCTAssertEqual(icon.frame.midY, button.bounds.midY, accuracy: 0.5)
                            XCTAssertEqual(label.frame, .zero)
                        }
                    }
                }
            }
        }
    }

    func testNativeDockKeepsOriginalTitlesAndStableModelsForStateChanges() throws {
        guard ShellBarPresentation.supportsNativeCapsule else { throw XCTSkip("Native dock requires iOS 26") }
        let tabs = makeTabs(presentation: .capsule)
        tabs.tabBarAccessories = [ShellTabBarAccessory(id: "compose", icon: .systemSymbol("plus"), position: .trailing) {}]
        tabs.view.layoutIfNeeded()
        let dock = try XCTUnwrap(tabs.dockBarView as? ShellNativeDockBar)
        let originalItems = try XCTUnwrap(tabs.viewControllers?.map(\.tabBarItem))
        let displayedItems = try XCTUnwrap(dock.tabBar.items)
        for mode in ShellTabLabelDisplayMode.allCases {
            tabs.tabBarStyle.labelDisplayMode = mode
            for selection in [0, 1] {
                tabs.selectedIndex = selection
                tabs.view.layoutIfNeeded()
                dock.layoutIfNeeded()
                for (index, source) in originalItems.enumerated() {
                    let displayed = try XCTUnwrap(dock.tabBar.items?[index])
                    XCTAssertTrue(displayed === displayedItems[index])
                    XCTAssertEqual(source?.title, ["首页", "材质", "关于"][index])
                    XCTAssertEqual(displayed.title,
                        mode.isVisible(isSelected: index == selection) ? source?.title : nil)
                    XCTAssertEqual(displayed.accessibilityLabel, ["首页", "材质", "关于"][index])
                }
                XCTAssertTrue(dock.tabBar.selectedItem === dock.tabBar.items?[selection])
            }
        }
    }

    func testPageOverrideClearAndPolicySwitchPreserveContentAndNavigationStack() throws {
        let tabs = makeTabs(presentation: .system)
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? BoneNavigationController)
        let detail = LabelFixture()
        detail.loadViewIfNeeded()
        navigation.view.layoutIfNeeded()
        navigation.pushViewController(detail, animated: false)
        detail.input.text = "保留输入"
        let content = detail.contentView
        tabs.tabBarStyle.labelDisplayMode = .never
        detail.overrideStyle = ShellTabBarStyle(labelDisplayMode: .selectedOnly)
        detail.refreshScreenConfiguration()
        XCTAssertEqual(navigation.tabBarItem.title, "首页")
        detail.overrideStyle = nil
        detail.refreshScreenConfiguration()
        XCTAssertNil(navigation.tabBarItem.title)
        for mode in ShellTabLabelDisplayMode.allCases {
            tabs.tabBarStyle.labelDisplayMode = mode
            XCTAssertTrue(navigation.topViewController === detail)
            XCTAssertTrue(detail.contentView === content)
            XCTAssertEqual(detail.input.text, "保留输入")
        }
        XCTAssertEqual(navigation.viewControllers.count, 2)
    }

    func testMoreDestinationRetainsItsNameWhenItsCaptionIsHidden() throws {
        let tabs = makeTabs(presentation: .classic, count: 8)
        tabs.tabBarStyle.labelDisplayMode = .never
        tabs.selectedIndex = 6
        tabs.view.layoutIfNeeded()
        let bar = try XCTUnwrap(tabs.classicTabBarView)
        let more = try XCTUnwrap(find("tab.more", in: bar))
        more.layoutIfNeeded()
        XCTAssertEqual(more.accessibilityLabel, "更多")
        XCTAssertTrue(more.accessibilityTraits.contains(.selected))
        let caption = try XCTUnwrap(more.subviews.compactMap { $0 as? UILabel }.first { $0.text == "更多" })
        XCTAssertTrue(caption.isHidden)
    }

    func testNativeMorePolicyPreservesOverflowDestinationNames() throws {
        let tabs = makeTabs(presentation: .system, count: 8)
        let controllers = try XCTUnwrap(tabs.viewControllers)
        let more = tabs.moreNavigationController
        let item = try XCTUnwrap(more.tabBarItem)
        let moreTitle = try XCTUnwrap(item.title)
        XCTAssertTrue(tabs.tabBar.items?.contains(where: { $0 === item }) == true)
        for mode in ShellTabLabelDisplayMode.allCases {
            tabs.tabBarStyle.labelDisplayMode = mode
            for selection in [0, 6] {
                tabs.selectedIndex = selection
                tabs.view.layoutIfNeeded()
                XCTAssertEqual(item.title, mode.isVisible(isSelected: selection == 6) ? moreTitle : nil)
                if mode != .always { XCTAssertEqual(item.accessibilityLabel, moreTitle) }
                for index in 4..<controllers.count {
                    XCTAssertEqual(controllers[index].tabBarItem.title, "项目\(index)")
                }
            }
        }
        tabs.tabBarStyle.labelDisplayMode = .never
        item.accessibilityLabel = "所有页面"
        tabs.tabBarStyle.labelDisplayMode = .selectedOnly
        XCTAssertEqual(item.accessibilityLabel, "所有页面")
        tabs.tabBarStyle = ShellTabBarStyle()
        XCTAssertEqual(item.title, moreTitle)
        XCTAssertEqual(item.accessibilityLabel, "所有页面")
    }

    private func makeTabs(presentation: ShellBarPresentation, count: Int = 3) -> BoneTabBarController {
        let ids = ["home", "materials", "about"]
        let titles = ["首页", "材质", "关于"]
        let tabs = BoneTabBarController(tabs: (0..<count).map { index in
            ShellTab(id: index < 3 ? ids[index] : "item\(index)",
                     title: index < 3 ? titles[index] : "项目\(index)", symbol: "circle", root: LabelFixture())
        })
        tabs.barPresentation = presentation
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.layoutIfNeeded()
        windows.append(window)
        return tabs
    }

    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews {
            if let found = find(identifier, in: child) { return found }
        }
        return nil
    }
}

@MainActor
private final class LabelFixture: BoneViewController {
    let input = UITextField()
    var overrideStyle: ShellTabBarStyle?
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "文字策略"
        screen.tabBarStyle = overrideStyle
    }
    override func buildContent(in contentView: UIView) {
        input.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(input)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            input.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            input.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        ])
    }
}
