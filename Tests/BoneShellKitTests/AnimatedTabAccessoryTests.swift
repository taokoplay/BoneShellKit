import UIKit
import XCTest
@testable import BoneShellKit

@MainActor
final class AnimatedTabAccessoryTests: XCTestCase {
    private var windows: [UIWindow] = []

    func testCapsuleUsesTheWholeActionSlotWithoutRestartingMotionOnRefresh() throws {
        let tabs = showTabs(.capsule)
        let id = "animated"
        let selected = tabs.selectedViewController
        var actions: [Int] = []
        var created = 0
        weak var installed: MotionProbe?
        let custom = ShellTabBarCustomContent {
            created += 1
            let view = MotionProbe()
            installed = view
            return view
        }
        var accessory = ShellTabBarAccessory(id: id, customContent: custom,
                                             position: .trailing, accessibilityLabel: "Assistant") { actions.append(1) }
        tabs.tabBarAccessories = [accessory]
        settle(tabs)
        let button = try XCTUnwrap(findButton(id, in: tabs.view))
        let content = try XCTUnwrap(installed)
        let originalFrame = button.convert(button.bounds, to: tabs.view)
        XCTAssertEqual(content.convert(content.bounds, to: button), button.bounds)
        XCTAssertEqual((button as? ShellTabAccessoryButton)?.hasOwnBackdrop, false)
        XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: id), .customView)
        XCTAssertEqual(content.visibility.last, true)
        XCTAssertEqual(content.layer.animationKeys(), ["pulse"])
        let events = content.visibility

        accessory.handler = { actions.append(2) }
        tabs.tabBarAccessories = [accessory]
        tabs.overrideUserInterfaceStyle = .dark
        tabs.refreshBarPresentation()
        settle(tabs)
        XCTAssertEqual(content.bounds.size, button.bounds.size)
        XCTAssertEqual(button.convert(button.bounds, to: tabs.view), originalFrame)
        XCTAssertTrue(findButton(id, in: tabs.view) === button)
        XCTAssertEqual(button.bounds.width, button.bounds.height, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        XCTAssertEqual(button.accessibilityLabel, "Assistant")
        XCTAssertTrue(button.isAccessibilityElement)
        XCTAssertEqual(content.superview?.accessibilityElementsHidden, true)
        XCTAssertTrue(button.hitTest(CGPoint(x: button.bounds.midX, y: button.bounds.midY), with: nil) === button)
        XCTAssertEqual(content.visibility, events)
        XCTAssertEqual(created, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(actions, [2])
        XCTAssertTrue(tabs.selectedViewController === selected)

        accessory.isEnabled = false
        tabs.tabBarAccessories = [accessory]
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(actions, [2])
        XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(created, 1)
    }

    func testSiblingInsertionAndReorderKeepContentInClassicAndCapsule() throws {
        for presentation in [ShellBarPresentation.classic, .capsule] {
            let tabs = showTabs(presentation)
            let content = MotionProbe()
            var created = 0
            let action = ShellTabBarAccessory(id: "animated", customContent: ShellTabBarCustomContent {
                created += 1
                return content
            }, position: .trailing, accessibilityLabel: "Assistant") { }
            let sibling = ShellTabBarAccessory(id: "plain", icon: .systemSymbol("plus"), position: .trailing) { }
            tabs.tabBarAccessories = [action]
            settle(tabs)
            let button = try XCTUnwrap(findButton(action.id, in: tabs.view))
            let events = content.visibility
            tabs.tabBarAccessories = [sibling, action]
            settle(tabs)
            tabs.tabBarAccessories = [action, sibling]
            settle(tabs)
            tabs.tabBarAccessories = [action]
            settle(tabs)
            XCTAssertTrue(findButton(action.id, in: tabs.view) === button)
            XCTAssertTrue(content.isDescendant(of: button))
            XCTAssertEqual(created, 1)
            XCTAssertEqual(content.visibility, events)
        }
    }

    func testExplicitStandardModeRestoresCaptionAndReleasesCustomView() throws {
        weak var installed: MotionProbe?
        try autoreleasepool {
            let tabs = showTabs(.classic)
            let id = "animated"
            let standard = ShellTabBarAccessory(id: id, icon: .systemSymbol("waveform"),
                                               title: "Assistant", position: .trailing) { }
            tabs.tabBarAccessories = [standard]
            settle(tabs)
            let button = try XCTUnwrap(findButton(id, in: tabs.view))
            let caption = try XCTUnwrap(button.subviews.compactMap { $0 as? UILabel }.first)
            let icon = try XCTUnwrap(button.subviews.compactMap { $0 as? UIImageView }.first)
            XCTAssertFalse(icon.isHidden)
            XCTAssertFalse(caption.isHidden)
            XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: id), .standard)

            var custom = standard
            custom.customContent = ShellTabBarCustomContent {
                let view = MotionProbe()
                installed = view
                return view
            }
            tabs.tabBarAccessories = [custom]
            settle(tabs)
            let clip = try XCTUnwrap(installed?.superview)
            XCTAssertTrue(clip.clipsToBounds)
            XCTAssertEqual(clip.frame, button.bounds)
            XCTAssertTrue(icon.isHidden)
            XCTAssertTrue(caption.isHidden)
            XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: id), .customView)

            tabs.tabBarAccessories = [standard]
            XCTAssertNil(installed?.superview)
            XCTAssertFalse(icon.isHidden)
            XCTAssertFalse(caption.isHidden)
            XCTAssertEqual(caption.text, "Assistant")
            XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: id), .standard)
        }
        XCTAssertNil(installed)
    }

    func testHiddenOnPushResumesOnReturnAndStopsWhenUnmounted() throws {
        for presentation in [ShellBarPresentation.classic, .capsule] {
            let tabs = showTabs(presentation)
            let nav = try XCTUnwrap(tabs.selectedViewController as? UINavigationController)
            let probe = MotionProbe()
            let accessory = ShellTabBarAccessory(id: "animated", customContent: ShellTabBarCustomContent { probe },
                                                 position: .trailing, accessibilityLabel: "Assistant") { }
            tabs.tabBarAccessories = [accessory]
            settle(tabs)
            XCTAssertEqual(probe.visibility.last, true)
            let detail = UIViewController()
            detail.hidesBottomBarWhenPushed = true
            nav.pushViewController(detail, animated: false)
            settle(tabs)
            XCTAssertEqual(probe.visibility.last, false)
            XCTAssertNil(probe.layer.animationKeys())
            XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: accessory.id), .customView)
            nav.popViewController(animated: false)
            settle(tabs)
            XCTAssertEqual(probe.visibility.last, true)
            XCTAssertEqual(probe.layer.animationKeys(), ["pulse"])
            tabs.tabBarAccessories = []
            XCTAssertEqual(probe.visibility.last, false)
            XCTAssertNil(probe.superview)
        }
    }

    func testSystemUsesNativeAccessorySlotOrSDKBarWithoutChangingCustomContent() throws {
        weak var installed: MotionProbe?
        try autoreleasepool {
            let tabs = showTabs(.system)
            let selected = tabs.selectedViewController
            var created = 0
            let accessory = ShellTabBarAccessory(id: "animated", customContent: ShellTabBarCustomContent {
                created += 1
                let view = MotionProbe()
                installed = view
                return view
            }, position: .trailing, accessibilityLabel: "Assistant") { }
            tabs.tabBarAccessories = [accessory]
            settle(tabs)
            if #available(iOS 26.0, *) {
                let slot = try XCTUnwrap(tabs.bottomAccessory)
                let button = try XCTUnwrap(findButton(accessory.id, in: slot.contentView))
                XCTAssertEqual(installed?.visibility.last, true)
                XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: accessory.id), .customView)
                tabs.overrideUserInterfaceStyle = .dark
                settle(tabs)
                XCTAssertTrue(tabs.bottomAccessory === slot)
                XCTAssertTrue(findButton(accessory.id, in: slot.contentView) === button)
                XCTAssertEqual(created, 1)
                slot.contentView.traitOverrides.tabAccessoryEnvironment = .none
                settle(tabs)
                XCTAssertEqual(installed?.visibility.last, false)
                XCTAssertNil(installed?.layer.animationKeys())
                slot.contentView.traitOverrides.tabAccessoryEnvironment = .inline
                settle(tabs)
                XCTAssertEqual(installed?.visibility.last, true)
                XCTAssertEqual(created, 1)
            } else {
                XCTAssertNotNil(tabs.classicTabBarView)
                XCTAssertNil(tabs.nativeTabAccessoryView)
                XCTAssertEqual(created, 1)
                XCTAssertEqual(installed?.visibility.last, true)
            }
            XCTAssertEqual(tabs.tabBarAccessoryContentMode(for: accessory.id), .customView)
            XCTAssertTrue(tabs.selectedViewController === selected)
            tabs.tabBarAccessories = []
            settle(tabs)
            XCTAssertNil(installed?.superview)
            XCTAssertEqual(tabs.resolvedBarPresentation, .system)
        }
        XCTAssertNil(installed)
    }

    func testSeparateWindowsDoNotShareOneContentInstance() throws {
        let shared = MotionProbe()
        let accessory = ShellTabBarAccessory(id: "animated", customContent: ShellTabBarCustomContent { shared },
                                             position: .trailing, accessibilityLabel: "Assistant") { }
        let first = showTabs(.classic)
        first.tabBarAccessories = [accessory]
        let originalHost = try XCTUnwrap(shared.superview)
        let second = showTabs(.classic)
        second.tabBarAccessories = [accessory]
        XCTAssertTrue(shared.superview === originalHost)
        XCTAssertEqual(first.tabBarAccessoryContentMode(for: accessory.id), .customView)
        XCTAssertEqual(second.tabBarAccessoryContentMode(for: accessory.id), .unavailable)
    }

    private func showTabs(_ presentation: ShellBarPresentation) -> BoneTabBarController {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "one", title: "One", symbol: "circle", root: BoneViewController()),
            ShellTab(id: "two", title: "Two", symbol: "square", root: BoneViewController()),
            ShellTab(id: "three", title: "Three", symbol: "triangle", root: BoneViewController())
        ])
        tabs.barPresentation = presentation
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        windows.append(window)
        settle(tabs)
        return tabs
    }

    private func settle(_ tabs: BoneTabBarController) {
        tabs.view.setNeedsLayout()
        tabs.view.layoutIfNeeded()
        // The native dock publishes measured capsule geometry on the next run-loop turn.
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        tabs.view.layoutIfNeeded()
    }

    private func findButton(_ id: String, in view: UIView) -> UIButton? {
        if view.accessibilityIdentifier == id { return view as? UIButton }
        return view.subviews.lazy.compactMap { self.findButton(id, in: $0) }.first
    }

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }
}

private final class MotionProbe: UIView, ShellTabBarContentUpdating {
    private(set) var visibility: [Bool] = []

    func tabBarContentDidChange(_ state: ShellTabBarCustomContent.State) {
        if visibility.last != state.isVisible { visibility.append(state.isVisible) }
        if state.isVisible && state.isEnabled {
            guard layer.animation(forKey: "pulse") == nil else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.35
            pulse.toValue = 1
            pulse.duration = 1.2
            pulse.repeatCount = .infinity
            layer.add(pulse, forKey: "pulse")
        } else {
            layer.removeAnimation(forKey: "pulse")
        }
    }
}
