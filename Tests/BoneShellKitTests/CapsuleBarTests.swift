import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class CapsuleBarTests: XCTestCase {
    // MARK: - Resolution

    func testAutomaticFollowsSystemCapability() {
        XCTAssertEqual(ShellBarPresentation.automatic.resolved(supportsNativeCapsule: true), .capsule)
        XCTAssertEqual(ShellBarPresentation.automatic.resolved(supportsNativeCapsule: false), .classic)
        // The current runtime resolution matches its own capability.
        let expected: ShellBarPresentation = ShellBarPresentation.supportsNativeCapsule ? .capsule : .classic
        XCTAssertEqual(ShellBarPresentation.automatic.resolvedForCurrentSystem, expected)
    }

    func testExplicitPresentationKeepsItsAppearanceOnEverySystem() {
        for capability in [true, false] {
            XCTAssertEqual(ShellBarPresentation.classic.resolved(supportsNativeCapsule: capability), .classic)
            XCTAssertEqual(ShellBarPresentation.capsule.resolved(supportsNativeCapsule: capability), .capsule)
            XCTAssertEqual(ShellBarPresentation.system.resolved(supportsNativeCapsule: capability), .system)
        }
    }

    func testRenderersUseNativeCapsuleOnlyWhenAvailable() {
        XCTAssertEqual(ShellBarRendering.tabBar(.classic, supportsNativeCapsule: true), .classic)
        XCTAssertEqual(ShellBarRendering.tabBar(.classic, supportsNativeCapsule: false), .classic)
        XCTAssertEqual(ShellBarRendering.tabBar(.capsule, supportsNativeCapsule: true), .native)
        XCTAssertEqual(ShellBarRendering.tabBar(.capsule, supportsNativeCapsule: false), .capsule)
        XCTAssertEqual(ShellBarRendering.tabBar(.automatic, supportsNativeCapsule: true), .native)
        XCTAssertEqual(ShellBarRendering.tabBar(.automatic, supportsNativeCapsule: false), .classic)
        XCTAssertEqual(ShellBarRendering.tabBar(.system, supportsNativeCapsule: false), .native)
    }

    func testNavigationHasNoCapsuleFormBelowIOS26() {
        XCTAssertEqual(ShellBarRendering.navigation(.capsule, supportsNativeCapsule: true), .native)
        XCTAssertEqual(ShellBarRendering.navigation(.capsule, supportsNativeCapsule: false), .classic)
        XCTAssertEqual(ShellBarRendering.navigation(.automatic, supportsNativeCapsule: true), .native)
        XCTAssertEqual(ShellBarRendering.navigation(.automatic, supportsNativeCapsule: false), .classic)
        XCTAssertEqual(ShellBarRendering.navigation(.classic, supportsNativeCapsule: true), .classic)
    }

    // MARK: - Containers

    func testClassicStaysClassicAndCapsuleStaysCapsuleRegardlessOfSystem() {
        let page = CapsuleFixture()
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "one", title: "一", symbol: "circle", root: page)])
        tabs.loadViewIfNeeded()
        tabs.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

        tabs.barPresentation = .classic
        XCTAssertEqual(tabs.resolvedBarPresentation, .classic)
        XCTAssertNotNil(tabs.classicTabBarView)
        XCTAssertNil(tabs.capsuleTabBarView)

        tabs.barPresentation = .capsule
        XCTAssertEqual(tabs.resolvedBarPresentation, .capsule)

        tabs.barPresentation = .automatic
        let expected: ShellBarPresentation = ShellBarPresentation.supportsNativeCapsule ? .capsule : .classic
        XCTAssertEqual(tabs.resolvedBarPresentation, expected)

        tabs.barPresentation = .system
        XCTAssertEqual(tabs.resolvedBarPresentation, .system)
    }

    func testCapsuleBarFloatsAndKeepsItsOwnSafeAreaContribution() throws {
        let page = CapsuleFixture()
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "one", title: "一", symbol: "circle", root: page),
            ShellTab(id: "two", title: "二", symbol: "square", root: CapsuleFixture()),
            ShellTab(id: "three", title: "三", symbol: "triangle", root: CapsuleFixture())
        ])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        tabs.loadViewIfNeeded()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.layoutIfNeeded()

        tabs.barPresentation = .capsule
        guard let capsule = tabs.capsuleTabBarView else {
            // iOS 26+ uses the system capsule; there is no self-drawn view to measure.
            XCTAssertTrue(ShellBarPresentation.supportsNativeCapsule)
            XCTAssertEqual(tabs.extraBottomSpace, 0)
            return
        }
        XCTAssertEqual(capsule.frame.minX, 12, accuracy: 0.5)
        XCTAssertEqual(capsule.frame.maxX, tabs.view.bounds.maxX - 12, accuracy: 0.5)
        XCTAssertLessThan(capsule.frame.maxY, tabs.view.bounds.maxY)
        XCTAssertEqual(tabs.extraBottomSpace, 56 + 8, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(capsule.frame.width, 300)

        tabs.barPresentation = .system
        XCTAssertEqual(tabs.extraBottomSpace, 0, accuracy: 0.5)
        XCTAssertNil(tabs.capsuleTabBarView)
        window.isHidden = true
    }

    func testCapsuleSelectionKeepsControllersAndNavigationStacks() {
        let page = CapsuleFixture()
        let (tabs, navigation) = capsuleContainers(page)
        let detail = CapsuleFixture()
        detail.loadViewIfNeeded()
        navigation.pushViewController(detail, animated: false)
        let roots = tabs.viewControllers!
        tabs.selectedIndex = 1
        let selected = tabs.selectedViewController
        for _ in 0..<3 {
            tabs.barPresentation = .capsule
            tabs.barPresentation = .automatic
        }
        XCTAssertEqual(tabs.selectedIndex, 1)
        XCTAssertTrue(tabs.selectedViewController === selected)
        for (left, right) in zip(tabs.viewControllers!, roots) { XCTAssertTrue(left === right) }
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertTrue(navigation.topViewController === detail)
    }

    func testCapsuleModeRestoresNativeTabBarAndAccessibility() {
        let page = CapsuleFixture()
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "one", title: "一", symbol: "circle", root: page)])
        tabs.loadViewIfNeeded()
        tabs.view.layoutIfNeeded()
        let alpha = tabs.tabBar.alpha
        let hidden = tabs.tabBar.accessibilityElementsHidden
        tabs.barPresentation = .capsule
        if ShellBarPresentation.supportsNativeCapsule {
            // iOS 26+ draws the capsule natively, so the native bar stays fully functional.
            XCTAssertEqual(tabs.tabBar.alpha, alpha)
            XCTAssertEqual(tabs.tabBar.accessibilityElementsHidden, hidden)
            XCTAssertNil(tabs.capsuleTabBarView)
        } else {
            XCTAssertEqual(tabs.tabBar.alpha, 0)
            XCTAssertTrue(tabs.tabBar.accessibilityElementsHidden)
            XCTAssertNotNil(tabs.capsuleTabBarView)
        }
        tabs.barPresentation = .system
        XCTAssertEqual(tabs.tabBar.alpha, alpha)
        XCTAssertEqual(tabs.tabBar.accessibilityElementsHidden, hidden)
        XCTAssertEqual(tabs.extraBottomSpace, 0, accuracy: 0.5)
    }

    func testCapsuleRendererBelowIOS26OwnsFloatingGeometryAndSelection() {
        // Inject the pre-iOS 26 capability so the SDK capsule renderer runs on any test device.
        ShellBarPresentation.capabilityOverride = false
        defer { ShellBarPresentation.capabilityOverride = nil }
        let page = CapsuleFixture()
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "one", title: "一", symbol: "circle", root: page),
            ShellTab(id: "two", title: "二", symbol: "square", root: CapsuleFixture()),
            ShellTab(id: "three", title: "三", symbol: "triangle", root: CapsuleFixture())
        ])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        tabs.loadViewIfNeeded()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.layoutIfNeeded()
        tabs.barPresentation = .capsule
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(tabs.resolvedBarPresentation, .capsule)
        XCTAssertEqual(tabs.tabBar.alpha, 0)
        guard let capsule = tabs.capsuleTabBarView else {
            XCTFail("The SDK capsule renderer should be visible below iOS 26")
            window.isHidden = true
            return
        }
        // Floats inside the container instead of spanning edge to edge.
        XCTAssertEqual(capsule.frame.minX, 12, accuracy: 0.5)
        XCTAssertEqual(capsule.frame.maxX, tabs.view.bounds.maxX - 12, accuracy: 0.5)
        XCTAssertLessThan(capsule.frame.maxY, tabs.view.bounds.maxY)
        XCTAssertGreaterThanOrEqual(capsule.frame.height, 52)
        // Reserves only the floating height, not a full-width bar.
        XCTAssertEqual(tabs.extraBottomSpace, capsule.frame.height + 8, accuracy: 0.5)
        // Every destination stays reachable inside the capsule.
        let elements = capsule.accessibilityElements as? [UIView] ?? []
        XCTAssertEqual(elements.count, 3)
        for element in elements {
            XCTAssertGreaterThanOrEqual(element.frame.width, 44)
            XCTAssertTrue(capsule.bounds.insetBy(dx: -1, dy: -1).contains(element.frame))
        }
        XCTAssertTrue(elements.first?.accessibilityTraits.contains(.selected) == true)

        tabs.selectedIndex = 2
        tabs.view.layoutIfNeeded()
        let updated = capsule.accessibilityElements as? [UIView] ?? []
        XCTAssertEqual(updated.count, 3)
        XCTAssertTrue(updated[2].accessibilityTraits.contains(.selected))
        XCTAssertFalse(updated[0].accessibilityTraits.contains(.selected))

        tabs.barPresentation = .system
        XCTAssertNil(tabs.capsuleTabBarView)
        XCTAssertEqual(tabs.extraBottomSpace, 0, accuracy: 0.5)
        XCTAssertEqual(tabs.tabBar.alpha, 1)
        window.isHidden = true
    }

    func testPrimaryScrollContentPassesUnderCapsuleAndRestoresClassic() throws {
        let nativeCapability = ShellBarPresentation.supportsNativeCapsule
        defer { ShellBarPresentation.capabilityOverride = nil }
        for capability in [nativeCapability, false] {
            ShellBarPresentation.capabilityOverride = capability
            let page = CapsuleScrollFixture()
            let tabs = BoneTabBarController(tabs: [
                ShellTab(id: "one", title: "一", symbol: "circle", root: page),
                ShellTab(id: "two", title: "二", symbol: "square", root: CapsuleFixture())
            ])
            tabs.barPresentation = .classic
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = tabs
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            tabs.view.layoutIfNeeded()
            let content = page.contentView
            page.scrollView.contentInset.bottom = 13
            if #available(iOS 26.0, *) { page.scrollView.bottomEdgeEffect.isHidden = false }

            let action = ShellTabBarAccessory(id: "test.action", icon: .systemSymbol("plus"), position: .trailing) { }
            for actions in [[ShellTabBarAccessory](), [action]] {
                tabs.tabBarAccessories = actions
                tabs.barPresentation = .capsule
                tabs.view.layoutIfNeeded()
                page.view.layoutIfNeeded()
                let viewport = page.scrollView.convert(page.scrollView.bounds, to: page.view)
                XCTAssertEqual(viewport.maxY, page.view.bounds.maxY, accuracy: 0.5,
                               "Capsule lists must continue through the reserved bar area")
                XCTAssertEqual(page.scrollView.contentInsetAdjustmentBehavior, .always)
                XCTAssertGreaterThanOrEqual(page.scrollView.adjustedContentInset.bottom,
                                             page.view.safeAreaInsets.bottom,
                                             "The last row must still scroll clear of the capsule")
                XCTAssertEqual(page.scrollView.contentInset.bottom, 13, "Preserve the host's own inset")
                XCTAssertNotNil(page.contentView.layer.mask, "Floating lists have a bottom opacity fade")
                page.fadeHeight = 0
                page.refreshScreenConfiguration()
                page.view.layoutIfNeeded()
                XCTAssertNil(page.contentView.layer.mask, "Setting the fade height to zero disables it")
                page.fadeHeight = 80
                page.refreshScreenConfiguration()
                page.view.layoutIfNeeded()
                XCTAssertNotNil(page.contentView.layer.mask)
                if #available(iOS 26.0, *) { XCTAssertTrue(page.scrollView.bottomEdgeEffect.isHidden) }
                if #available(iOS 17.0, *) {
                    XCTAssertEqual(page.view.keyboardLayoutGuide.layoutFrame.minY, page.view.bounds.maxY, accuracy: 0.5,
                                   "A dismissed keyboard must not shorten the under-glass viewport")
                }

                tabs.barPresentation = .classic
                tabs.view.layoutIfNeeded()
                page.view.layoutIfNeeded()
                XCTAssertEqual(page.contentView.frame.maxY,
                               page.view.bounds.maxY - page.view.safeAreaInsets.bottom, accuracy: 0.5)
                XCTAssertEqual(page.scrollView.contentInsetAdjustmentBehavior, .never)
                XCTAssertNil(page.contentView.layer.mask, "Classic bars restore unmasked content")
                if #available(iOS 26.0, *) { XCTAssertFalse(page.scrollView.bottomEdgeEffect.isHidden) }
                XCTAssertGreaterThanOrEqual(page.view.keyboardLayoutGuide.layoutFrame.minY,
                                             page.contentView.frame.maxY - 0.5,
                                             "Classic content remains above the keyboard guide and bar safe area")
                XCTAssertTrue(page.contentView === content, "Mode changes preserve business content")
            }
        }
    }

    func testNonScrollingCapsuleContentKeepsItsSafeBottom() {
        let page = CapsuleFixture()
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "one", title: "一", symbol: "circle", root: page)])
        tabs.barPresentation = .capsule
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "test.action", icon: .systemSymbol("plus"), position: .trailing) { }
        ]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        tabs.view.layoutIfNeeded()
        page.view.layoutIfNeeded()
        XCTAssertEqual(page.contentView.frame.maxY,
                       page.view.bounds.maxY - page.view.safeAreaInsets.bottom, accuracy: 0.5)
    }

    func testBottomFadeRespectsAndPreservesCustomMasks() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 240))
        let custom = CALayer()
        view.layer.mask = custom
        let fade = ShellScrollBottomFade()
        fade.update(in: view, height: 80)
        XCTAssertTrue(view.layer.mask === custom)
        fade.remove()
        XCTAssertTrue(view.layer.mask === custom)

        view.layer.mask = nil
        fade.update(in: view, height: 80)
        XCTAssertNotNil(view.layer.mask)
        view.layer.mask = custom
        fade.update(in: view, height: 0)
        XCTAssertTrue(view.layer.mask === custom, "Removing the SDK fade cannot remove a newer host mask")
    }

    // MARK: - Helpers

    private func capsuleContainers(_ page: CapsuleFixture) -> (BoneTabBarController, BoneNavigationController) {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "one", title: "一", symbol: "circle", root: page),
            ShellTab(id: "two", title: "二", symbol: "square", root: CapsuleFixture())
        ])
        tabs.barPresentation = .capsule
        tabs.loadViewIfNeeded()
        tabs.view.layoutIfNeeded()
        guard let navigation = tabs.viewControllers?.first as? BoneNavigationController else {
            XCTFail("Expected the first tab to be a BoneNavigationController")
            return (tabs, BoneNavigationController(rootViewController: page))
        }
        return (tabs, navigation)
    }
}

@MainActor
private final class CapsuleFixture: BoneViewController {
    let input = UITextField()
    override func viewDidLoad() {
        super.viewDidLoad()
        input.text = "kept"
        contentView.addSubview(input)
    }
}

private extension BoneTabBarController {
    /// Bottom safe-area height this container adds on top of the host's own inset.
    var extraBottomSpace: CGFloat { additionalSafeAreaInsets.bottom }
}

@MainActor
private final class CapsuleScrollFixture: BoneViewController {
    let scrollView = UIScrollView()
    var fadeHeight: CGFloat = 80

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.avoidsKeyboard = true
        screen.floatingTabBarFadeHeight = fadeHeight
    }

    override func buildContent(in contentView: UIView) {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        scrollView.contentSize = CGSize(width: 390, height: 2000)
        registerPrimaryScrollView(scrollView)
    }
}
