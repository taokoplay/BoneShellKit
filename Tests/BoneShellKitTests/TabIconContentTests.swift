import UIKit
import XCTest
@testable import BoneShellKit

@MainActor
final class TabIconContentTests: XCTestCase {
    private var window: UIWindow?

    func testEveryDestinationOwnsTheWholeSlotAndPreservesSelection() throws {
        for presentation in [ShellBarPresentation.classic, .capsule] {
            let ids = ["one", "two", "three"]
            var icons: [String: IconProbe] = [:]
            var creationCount = 0
            let tabs = BoneTabBarController(tabs: ids.map { id in
                let content = ShellTabBarCustomContent {
                    creationCount += 1
                    let view = IconProbe()
                    icons[id] = view
                    return view
                }
                return ShellTab(id: id, item: .init(title: id, customContent: content), root: BoneViewController())
            })
            tabs.barPresentation = presentation
            show(tabs)
            let bar = try XCTUnwrap(tabs.classicTabBarView ?? tabs.capsuleTabBarView)
            let controllers = try XCTUnwrap(tabs.viewControllers)
            let middle = try XCTUnwrap(findButton("tab.two", in: bar))
            controllers[1].tabBarItem.badgeValue = "2"
            tabs.refreshBarPresentation()
            tabs.view.layoutIfNeeded()
            XCTAssertEqual(middle.accessibilityValue, "2")
            XCTAssertEqual(middle.accessibilityLabel, "two")
            XCTAssertEqual(creationCount, 3)
            for (index, id) in ids.enumerated() {
                let icon = try XCTUnwrap(icons[id])
                let button = try XCTUnwrap(findButton("tab.\(id)", in: bar))
                XCTAssertTrue(icon.isDescendant(of: button))
                XCTAssertEqual(tabs.tabItemContentMode(for: id), .customView)
                XCTAssertEqual(icon.states.last?.isVisible, true)
                XCTAssertEqual(icon.states.last?.isSelected, index == 0)
                XCTAssertTrue(button.hitTest(CGPoint(x: button.bounds.midX, y: button.bounds.midY), with: nil) === button)
                XCTAssertEqual(icon.superview?.accessibilityElementsHidden, true)
                XCTAssertEqual(icon.convert(icon.bounds, to: button), button.bounds)
                XCTAssertTrue(button.subviews.compactMap { $0 as? UILabel }.allSatisfy(\.isHidden))
                XCTAssertTrue(button.subviews.compactMap { $0 as? UIImageView }.allSatisfy(\.isHidden))
            }
            middle.sendActions(for: .touchUpInside)
            tabs.view.layoutIfNeeded()
            XCTAssertEqual(tabs.selectedIndex, 1)
            XCTAssertTrue(tabs.selectedViewController === controllers[1])
            XCTAssertEqual(icons["one"]?.states.last?.isSelected, false)
            XCTAssertEqual(icons["two"]?.states.last?.isSelected, true)
            XCTAssertTrue(middle.accessibilityTraits.contains(.selected))
            middle.isHighlighted = true
            XCTAssertEqual(icons["two"]?.states.last?.isHighlighted, true)
            middle.isHighlighted = false

            let nav = try XCTUnwrap(tabs.selectedViewController as? UINavigationController)
            let detail = UIViewController()
            detail.hidesBottomBarWhenPushed = true
            nav.pushViewController(detail, animated: false)
            settle(tabs)
            XCTAssertTrue(icons.values.allSatisfy { $0.states.last?.isVisible == false })
            nav.popViewController(animated: false)
            tabs.overrideUserInterfaceStyle = .dark
            settle(tabs)
            XCTAssertTrue(icons.values.allSatisfy { $0.states.last?.isVisible == true })
            XCTAssertTrue(findButton("tab.two", in: bar) === middle)
            XCTAssertEqual(creationCount, 3)
            controllers[2].tabBarItem.isEnabled = false
            tabs.refreshBarPresentation()
            XCTAssertEqual(icons["three"]?.states.last?.isEnabled, false)
            findButton("tab.three", in: bar)?.sendActions(for: .touchUpInside)
            XCTAssertEqual(tabs.selectedIndex, 1)
        }
    }

    func testSystemHostsTheCustomViewUntilStandardModeIsExplicitlyRestored() throws {
        let tabs = makeTabs()
        tabs.barPresentation = .system
        show(tabs)
        let standard = try XCTUnwrap(tabs.tabItemConfiguration(for: "one"))
        let artwork = IconProbe()
        let original = tabs.selectedViewController
        let configuration = ShellTabItemConfiguration(title: "one", customContent: ShellTabBarCustomContent { artwork })
        XCTAssertTrue(tabs.updateTabItem(id: "one", configuration: configuration))
        settle(tabs)
        XCTAssertEqual(tabs.resolvedBarPresentation, ShellBarPresentation.supportsNativeCapsule ? .capsule : .classic)
        XCTAssertEqual(tabs.tabItemContentMode(for: "one"), .customView)
        XCTAssertNil(tabs.viewControllers?.first?.tabBarItem.image)
        let neighbour = try XCTUnwrap(findButton("tab.two", in: tabs.view))
        XCTAssertEqual(tabs.tabItemContentMode(for: "two"), .standard)
        XCTAssertTrue(neighbour.subviews.contains { ($0 as? UILabel)?.text == "two" && !$0.isHidden })
        XCTAssertTrue(neighbour.subviews.contains { ($0 as? UIImageView)?.image != nil && !$0.isHidden })
        XCTAssertEqual(artwork.states.last?.isVisible, true)

        XCTAssertTrue(tabs.updateTabItem(id: "one", configuration: standard))
        settle(tabs)
        XCTAssertNil(artwork.superview)
        XCTAssertEqual(artwork.states.last?.isVisible, false)
        XCTAssertEqual(tabs.tabItemContentMode(for: "one"), .standard)
        XCTAssertEqual(tabs.resolvedBarPresentation, .system)
        XCTAssertNotNil(tabs.viewControllers?.first?.tabBarItem.image)
        XCTAssertTrue(tabs.selectedViewController === original)
        XCTAssertNil(tabs.tabItemContentMode(for: "missing"))
    }

    func testRevisionReplacesViewAndRemovingLastConfigurationRestoresNativeDock() throws {
        let tabs = makeTabs()
        tabs.barPresentation = .capsule
        let accessory = ShellTabBarAccessory(id: "add", icon: .systemSymbol("plus"), position: .trailing) { }
        tabs.tabBarAccessories = [accessory]
        show(tabs)
        let destinations = try XCTUnwrap(tabs.viewControllers)
        tabs.selectedIndex = 1
        let navigation = try XCTUnwrap(destinations[1] as? UINavigationController)
        let detail = UIViewController()
        navigation.pushViewController(detail, animated: false)
        let artwork = IconProbe()
        var calls = 0
        var item = try XCTUnwrap(tabs.tabItemConfiguration(for: "one"))
        let initial = IconProbe()
        item.customContent = ShellTabBarCustomContent { calls += 1; return initial }
        XCTAssertTrue(tabs.updateTabItem(id: "one", configuration: item))
        settle(tabs)
        XCTAssertEqual(tabs.tabItemContentMode(for: "one"), .customView)
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(findButton("add", in: tabs.view))
        item.customContent?.makeView = { calls += 1; return artwork }
        XCTAssertTrue(tabs.updateTabItem(id: "one", configuration: item))
        XCTAssertEqual(calls, 1)
        item.customContent?.revision += 1
        XCTAssertTrue(tabs.updateTabItem(id: "one", configuration: item))
        settle(tabs)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(tabs.tabItemContentMode(for: "one"), .customView)
        XCTAssertNotNil(artwork.superview)
        XCTAssertNil(initial.superview)
        item.customContent = nil
        XCTAssertTrue(tabs.updateTabItem(id: "one", configuration: item))
        settle(tabs)
        XCTAssertNil(artwork.superview)
        XCTAssertEqual(tabs.tabItemContentMode(for: "one"), .standard)
        if ShellBarPresentation.supportsNativeCapsule { XCTAssertNotNil(tabs.dockBarView) }
        XCTAssertTrue(tabs.selectedViewController === navigation)
        XCTAssertTrue(navigation.topViewController === detail)
    }

    func testAnOverflowOnlyConfigurationDoesNotMountAView() throws {
        let tabs = makeTabs(count: 6)
        tabs.barPresentation = .capsule
        show(tabs)
        var configuration = try XCTUnwrap(tabs.tabItemConfiguration(for: "tab-5"))
        configuration.customContent = ShellTabBarCustomContent { XCTFail("No slot for the overflow destination"); return IconProbe() }
        XCTAssertTrue(tabs.updateTabItem(id: "tab-5", configuration: configuration))
        XCTAssertEqual(tabs.tabItemContentMode(for: "tab-5"), .unavailable)
        if ShellBarPresentation.supportsNativeCapsule { XCTAssertNil(tabs.capsuleTabBarView) }
    }

    private func makeTabs(count: Int = 3) -> BoneTabBarController {
        let ids = count == 3 ? ["one", "two", "three"] : (0..<count).map { "tab-\($0)" }
        return BoneTabBarController(tabs: ids.map { ShellTab(id: $0, title: $0, symbol: "star", root: BoneViewController()) })
    }

    private func show(_ tabs: BoneTabBarController) {
        window?.isHidden = true
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        self.window = window
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        settle(tabs)
    }

    private func settle(_ tabs: BoneTabBarController) {
        tabs.view.setNeedsLayout()
        tabs.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        tabs.view.layoutIfNeeded()
    }

    private func findButton(_ id: String, in view: UIView) -> UIButton? {
        if view.accessibilityIdentifier == id { return view as? UIButton }
        return view.subviews.lazy.compactMap { self.findButton(id, in: $0) }.first
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }
}

private final class IconProbe: UIView, ShellTabBarContentUpdating {
    private(set) var states: [ShellTabBarCustomContent.State] = []

    func tabBarContentDidChange(_ state: ShellTabBarCustomContent.State) {
        states.append(state)
    }
}
