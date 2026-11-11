import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class BarPresentationTests: XCTestCase {
    func testDefaultInheritanceAndPageOverrideRestoreNativeState() throws {
        let page = PresentationFixture()
        let (tabs, navigation) = containers(page)
        let nativeAlpha = navigation.navigationBar.alpha
        let tabAlpha = tabs.tabBar.alpha
        let accessibility = tabs.tabBar.accessibilityElementsHidden
        XCTAssertEqual(tabs.barPresentation, .system)
        XCTAssertNil(navigation.barPresentation)
        XCTAssertEqual(page.resolvedBarPresentation, .system)
        tabs.barPresentation = .classic
        XCTAssertEqual(page.resolvedBarPresentation, .classic)
        XCTAssertNotNil(navigation.classicNavigationBarView)
        XCTAssertNotNil(tabs.classicTabBarView)
        XCTAssertEqual(navigation.navigationBar.alpha, 0)
        XCTAssertEqual(tabs.tabBar.alpha, 0)
        page.presentation = .system
        page.refreshScreenConfiguration()
        XCTAssertEqual(tabs.resolvedBarPresentation, .system)
        XCTAssertEqual(navigation.resolvedBarPresentation, .system)
        XCTAssertEqual(navigation.navigationBar.alpha, nativeAlpha)
        XCTAssertEqual(tabs.tabBar.alpha, tabAlpha)
        XCTAssertEqual(tabs.tabBar.accessibilityElementsHidden, accessibility)
        page.presentation = nil
        page.refreshScreenConfiguration()
        XCTAssertEqual(page.resolvedBarPresentation, .classic)
        tabs.barPresentation = .system
    }

    func testRepeatedSwitchingPreservesControllersStackInputAndSelectedTab() {
        let page = PresentationFixture()
        let (tabs, navigation) = containers(page)
        let detail = PresentationFixture()
        detail.loadViewIfNeeded()
        detail.input.text = "retained input"
        navigation.pushViewController(detail, animated: false)
        let roots = tabs.viewControllers!
        tabs.selectedIndex = 1
        let selected = tabs.selectedViewController
        for _ in 0..<4 { tabs.barPresentation = .classic; tabs.barPresentation = .system }
        XCTAssertEqual(tabs.selectedIndex, 1)
        XCTAssertTrue(tabs.selectedViewController === selected)
        XCTAssertEqual(tabs.viewControllers?.count, roots.count)
        for (left, right) in zip(tabs.viewControllers!, roots) { XCTAssertTrue(left === right) }
        XCTAssertTrue(navigation.topViewController === detail)
        XCTAssertEqual(detail.input.text, "retained input")
        XCTAssertEqual(navigation.viewControllers.count, 2)
    }

    func testClassicFullWidthBarTracksGeometryAndOwnsOnlyItsSafeAreaContribution() throws {
        let page = PresentationFixture()
        let (tabs, navigation) = containers(page)
        tabs.additionalSafeAreaInsets.bottom = 7
        let oldKey = keyWindow()
        let window = show(tabs)
        defer { window.isHidden = true; window.rootViewController = nil; oldKey?.makeKeyAndVisible() }
        tabs.barPresentation = .classic
        tabs.view.layoutIfNeeded()
        let bar = try XCTUnwrap(tabs.classicTabBarView)
        XCTAssertEqual(bar.frame.minX, tabs.view.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(bar.frame.width, tabs.view.bounds.width, accuracy: 0.5)
        XCTAssertEqual(bar.frame.maxY, tabs.view.bounds.maxY, accuracy: 0.5)
        if #available(iOS 18.0, *) {
            XCTAssertTrue(tabs.isTabBarHidden)
            XCTAssertGreaterThan(tabs.additionalSafeAreaInsets.bottom, 7)
        }
        XCTAssertTrue(navigation.navigationBar.accessibilityElementsHidden)
        let header = try XCTUnwrap(navigation.classicNavigationBarView)
        let headerBottom = header.convert(header.bounds, to: tabs.view).maxY
        let contentTop = page.contentView.convert(page.contentView.bounds, to: tabs.view).minY
        XCTAssertGreaterThanOrEqual(contentTop, headerBottom - 0.5,
            "Classic header must not cover safe-area content: content=\(page.contentView.frame), safe=\(page.view.safeAreaInsets), header=\(header.frame)")
        XCTAssertLessThanOrEqual(contentTop, headerBottom + 0.5, "Classic top contribution must not double the navigation reservation")
        var external = tabs.additionalSafeAreaInsets
        external.bottom += 5
        tabs.additionalSafeAreaInsets = external
        tabs.barPresentation = .system
        XCTAssertEqual(tabs.additionalSafeAreaInsets.bottom, 12, accuracy: 0.5)
        if #available(iOS 18.0, *) { XCTAssertFalse(tabs.isTabBarHidden) }
        XCTAssertNil(tabs.classicTabBarView?.superview)
    }

    func testClassicActionsAndRuntimeItemsUseExistingModels() throws {
        let page = PresentationFixture()
        let (tabs, navigation) = containers(page)
        tabs.barPresentation = .classic
        let header = try XCTUnwrap(navigation.classicNavigationBarView)
        let action = try XCTUnwrap(controls(in: header).first { $0.accessibilityIdentifier == "action.presentation.increment" })
        action.sendActions(for: .touchUpInside)
        XCTAssertEqual(page.events, 1)
        page.refreshScreenConfiguration()
        let updated = try XCTUnwrap(controls(in: header).first { $0.accessibilityIdentifier == "action.presentation.increment" })
        updated.sendActions(for: .touchUpInside)
        XCTAssertEqual(page.events, 2, "Model refresh must not install duplicate handlers")
        XCTAssertTrue(tabs.updateTabItem(id: "first", configuration: ShellTabItemConfiguration(title: "替换标题", icon: .systemSymbol("star"), selectedIcon: .systemSymbol("star.fill"))))
        let tab = try XCTUnwrap(controls(in: tabs.classicTabBarView!).first { $0.accessibilityIdentifier == "tab.first" })
        XCTAssertEqual(tab.accessibilityLabel, "替换标题")
        let other = try XCTUnwrap(controls(in: tabs.classicTabBarView!).first { $0.accessibilityIdentifier == "tab.second" })
        other.sendActions(for: .touchUpInside)
        XCTAssertEqual(tabs.selectedIndex, 1)
        tabs.barPresentation = .system
    }

    func testUnifiedCanvasAndTextStylesSurvivePresentationChanges() throws {
        let page = PresentationFixture()
        page.shared = true
        let (tabs, navigation) = containers(page)
        let canvas = try XCTUnwrap(tabs.unifiedBackgroundView)
        let originalContent = page.contentView
        tabs.tabBarStyle = ShellTabBarStyle(normal: ShellTextStyle(size: 12, color: .gray, scalesWithDynamicType: false), selected: ShellTextStyle(size: 14, color: .orange, scalesWithDynamicType: false))
        tabs.barPresentation = .classic
        XCTAssertTrue(page.activeBackgroundView === canvas)
        XCTAssertTrue(page.contentView === originalContent)
        XCTAssertEqual(canvas.configuration?.source, .color(.cyan))
        let header = try XCTUnwrap(navigation.classicNavigationBarView)
        let label = try XCTUnwrap(descendants(header).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == "shell.classic.title" })
        header.layoutIfNeeded()
        XCTAssertEqual(label.font.pointSize, 20, accuracy: 0.5)
        XCTAssertTrue(label.textColor.isEqual(UIColor.systemBlue))
        tabs.barPresentation = .system
        XCTAssertTrue(page.activeBackgroundView === canvas)
        XCTAssertTrue(page.contentView === originalContent)
    }

    func testClassicBottomBarFollowsHidesBottomBarWhenPushed() throws {
        let page = PresentationFixture()
        let (tabs, navigation) = containers(page)
        tabs.barPresentation = .classic
        let initial = tabs.additionalSafeAreaInsets.bottom
        let detail = PresentationFixture()
        detail.hidesBottomBarWhenPushed = true
        detail.loadViewIfNeeded()
        navigation.pushViewController(detail, animated: false)
        detail.refreshScreenConfiguration()
        tabs.view.layoutIfNeeded()
        XCTAssertTrue(tabs.classicTabBarView?.isHidden == true)
        XCTAssertLessThanOrEqual(tabs.additionalSafeAreaInsets.bottom, initial)
        navigation.popViewController(animated: false)
        page.refreshScreenConfiguration()
        XCTAssertTrue(tabs.classicTabBarView?.isHidden == false)
        tabs.barPresentation = .system
    }

    func testClassicManyTabsProvideMoreDestinationEntry() throws {
        let tabs = BoneTabBarController(tabs: (0..<8).map { ShellTab(id: "item\($0)", title: "Item \($0)", symbol: "circle", root: PresentationFixture()) })
        tabs.loadViewIfNeeded()
        tabs.barPresentation = .classic
        let bar = try XCTUnwrap(tabs.classicTabBarView)
        let entries = controls(in: bar).filter { $0.accessibilityIdentifier?.hasPrefix("tab.") == true }
        XCTAssertEqual(entries.count, 5)
        XCTAssertNotNil(entries.first { $0.accessibilityIdentifier == "tab.more" })
        tabs.selectedIndex = 7
        XCTAssertEqual(tabs.viewControllers?.count, 8)
        let more = try XCTUnwrap(controls(in: bar).first { $0.accessibilityIdentifier == "tab.more" })
        XCTAssertTrue(more.accessibilityTraits.contains(.selected))
        tabs.barPresentation = .system
    }

    private func containers(_ page: PresentationFixture) -> (BoneTabBarController, BoneNavigationController) {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "first", title: "First", symbol: "1.circle", root: page),
            ShellTab(id: "second", title: "Second", symbol: "2.circle", root: PresentationFixture())
        ])
        tabs.loadViewIfNeeded()
        let navigation = tabs.viewControllers!.first as! BoneNavigationController
        navigation.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 700)
        page.refreshScreenConfiguration()
        return (tabs, navigation)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
    private func controls(in view: UIView) -> [UIControl] { descendants(view).compactMap { $0 as? UIControl } }
    private func keyWindow() -> UIWindow? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) }
    private func show(_ root: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) { window = UIWindow(windowScene: scene) }
        else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return window
    }
}

@MainActor
private final class PresentationFixture: BoneViewController {
    let input = UITextField()
    var presentation: ShellBarPresentation?
    var events = 0
    var shared = false
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.barPresentation = presentation
        screen.navigation.title = "类型与状态"
        screen.navigation.style = ShellNavigationStyle(title: ShellTextStyle(size: 20, color: .systemBlue, scalesWithDynamicType: false))
        screen.navigation.trailingActions = [NavigationAction(id: "presentation.increment", title: "增加", symbol: "plus", priority: 20, handler: { [weak self] in self?.events += 1 })]
        if shared { screen.backgroundComposition = .unified; screen.background = ShellBackgroundConfiguration(source: .color(.cyan)) }
    }
    override func buildContent(in contentView: UIView) {
        input.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(input)
        NSLayoutConstraint.activate([input.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), input.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), input.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20), input.heightAnchor.constraint(equalToConstant: 44)])
    }
}
