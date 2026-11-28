import UIKit
import XCTest
@testable import BoneShellKit

@MainActor
final class NavigationTitleViewTests: XCTestCase {
    private var window: UIWindow?

    func testTitleKeepsItsViewAcrossRenderersAndRestoresStandardContent() throws {
        let page = NavigationTitleFixture()
        let button = makeButton("Choose a source")
        page.customTitle = button
        page.usesLargeTitle = true
        let navigation = show(page, presentation: .system)
        let host = try XCTUnwrap(page.navigationItem.titleView as? ShellNavigationTitleHost)
        XCTAssertTrue(host.content === button)
        XCTAssertTrue(button.isDescendant(of: navigation.navigationBar))
        XCTAssertEqual(page.navigationItem.title, "Semantic title")
        XCTAssertEqual(page.navigationItem.largeTitleDisplayMode, .never)
        if #available(iOS 26.0, *) { XCTAssertNil(page.navigationItem.subtitle) }
        let source = button.menu
        page.refreshScreenConfiguration()
        XCTAssertTrue(page.navigationItem.titleView === host)
        XCTAssertTrue(button.menu === source)

        navigation.barPresentation = .classic
        settle(navigation)
        let bar = try XCTUnwrap(navigation.classicNavigationBarView)
        XCTAssertNil(page.navigationItem.titleView)
        XCTAssertTrue(host.superview === bar)
        XCTAssertTrue(bar.subviews.compactMap { $0 as? UILabel }.allSatisfy(\.isHidden))
        let hit = bar.hitTest(button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: bar), with: nil)
        XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true)
        XCTAssertTrue(button.menu === source)

        navigation.barPresentation = .system
        settle(navigation)
        XCTAssertTrue(page.navigationItem.titleView === host)
        XCTAssertTrue(button.isDescendant(of: navigation.navigationBar))
        XCTAssertFalse(button.isDescendant(of: bar))
        page.customTitle = nil
        page.refreshScreenConfiguration()
        settle(navigation)
        XCTAssertNil(button.superview)
        XCTAssertTrue(button.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(page.navigationItem.largeTitleDisplayMode, .always)
        if #available(iOS 26.0, *) {
            XCTAssertNil(page.navigationItem.titleView)
            XCTAssertEqual(page.navigationItem.subtitle, "Standard subtitle")
        } else {
            XCTAssertNotNil(page.navigationItem.titleView)
        }
        page.customTitle = button
        page.refreshScreenConfiguration()
        settle(navigation)
        XCTAssertTrue(button.isDescendant(of: navigation.navigationBar))
    }

    func testNativeTitleSizeUsesTheBudgetAndPreservesSystemCompression() {
        let button = ResizableTitleButton()
        button.preferredWidth = 160
        let host = ShellNavigationTitleHost(content: button)
        let bar = UINavigationBar()
        host.maximumWidth = 96
        host.syncNativeSizeIfNeeded(in: bar)
        XCTAssertEqual(host.bounds.size, CGSize(width: 96, height: 44))

        host.bounds.size.width = 72
        host.syncNativeSizeIfNeeded(in: bar)
        XCTAssertEqual(host.bounds.width, 72)

        host.maximumWidth = 80
        host.syncNativeSizeIfNeeded(in: bar)
        XCTAssertEqual(host.bounds.width, 80)
    }

    func testSystemTitleResizesTheMountedViewAfterRefresh() throws {
        let page = NavigationTitleFixture()
        let button = ResizableTitleButton()
        button.setTitle("Source", for: .normal)
        button.menu = UIMenu(children: [UIAction(title: "Option") { _ in }])
        var tapCount = 0
        button.addAction(UIAction { _ in tapCount += 1 }, for: .touchUpInside)
        page.customTitle = button
        let navigation = show(page, presentation: .system)
        let host = try XCTUnwrap(page.navigationItem.titleView as? ShellNavigationTitleHost)
        let window = try XCTUnwrap(navigation.navigationBar.window)
        let menu = try XCTUnwrap(button.menu)

        for width: CGFloat in [44, 100, 60] {
            button.preferredWidth = width
            page.refreshScreenConfiguration()
            settle(navigation)

            XCTAssertEqual(host.intrinsicContentSize.width, width, accuracy: 0.5)
            XCTAssertEqual(host.bounds.width, width, accuracy: 0.5)
            XCTAssertEqual(button.bounds.width, width, accuracy: 0.5)
            XCTAssertTrue(page.navigationItem.titleView === host)
            XCTAssertTrue(host.content === button)
            XCTAssertTrue(button.window === window)
            XCTAssertTrue(button.menu === menu)
        }
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(tapCount, 1)
    }

    func testCustomTitleFollowsTextAndFontChangesWithoutRefreshingThePage() throws {
        let page = NavigationTitleFixture()
        if #available(iOS 16.0, *) { page.navigationItem.style = .browser }
        let button = makeButton("I")
        var configuration = UIButton.Configuration.plain()
        configuration.title = "I"
        configuration.contentInsets = .zero
        button.configuration = configuration
        page.customTitle = button
        let navigation = show(page, presentation: .system)
        let host = try XCTUnwrap(button.superview as? ShellNavigationTitleHost)
        let menu = try XCTUnwrap(button.menu)

        func expectWidthChange(growing: Bool, line: UInt = #line, _ update: () -> Void) {
            let previousWidth = host.bounds.width
            update()
            let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let currentWidth = host.bounds.width
                let change = currentWidth - previousWidth
                let resized = growing ? change > 1 : change < -1
                return resized && abs(currentWidth - host.intrinsicContentSize.width) <= 1
                    && abs(button.bounds.width - currentWidth) <= 1
            }, object: nil)
            let result = XCTWaiter.wait(for: [resized], timeout: 4)
            XCTAssertEqual(result, .completed,
                           "Previous \(previousWidth), host \(host.bounds.width), content \(button.bounds.width), target \(host.intrinsicContentSize.width)", line: line)
            XCTAssertTrue(host.content === button)
            XCTAssertTrue(button.menu === menu)
            XCTAssertTrue(button.window === navigation.navigationBar.window)
        }

        for presentation in [ShellBarPresentation.system, .classic] {
            navigation.barPresentation = presentation
            settle(navigation)
            expectWidthChange(growing: true) { button.configuration?.title = "Sources" }
            expectWidthChange(growing: true) {
                button.configuration?.titleTextAttributesTransformer = .init { incoming in
                    var attributes = incoming
                    attributes.font = .systemFont(ofSize: 24)
                    return attributes
                }
            }
            expectWidthChange(growing: false) { button.configuration = configuration }
            XCTAssertEqual(host.bounds.width, 44, accuracy: 0.5)
        }
    }

    func testCustomTitleFollowsChangesToItsLayoutConstraints() throws {
        let page = NavigationTitleFixture()
        let title = UIView()
        let width = title.widthAnchor.constraint(equalToConstant: 52)
        NSLayoutConstraint.activate([width, title.heightAnchor.constraint(equalToConstant: 24)])
        page.customTitle = title
        let navigation = show(page, presentation: .classic)
        let host = try XCTUnwrap(title.superview as? ShellNavigationTitleHost)
        XCTAssertEqual(host.bounds.width, 52, accuracy: 0.5)
        width.constant = 96

        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(host.bounds.width - 96) < 0.5 && abs(title.bounds.width - 96) < 0.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 2), .completed)
        XCTAssertTrue(host.superview === navigation.classicNavigationBarView)
    }

    /// 模拟原生转场移除标题宿主，验证页面显示完成后复用并恢复原有标题。
    func testSystemTitleReattachesAfterAppearanceCompletes() throws {
        let page = NavigationTitleFixture()
        let button = makeButton("Choose a source")
        page.customTitle = button
        let navigation = show(page, presentation: .system)
        let host = try XCTUnwrap(page.navigationItem.titleView as? ShellNavigationTitleHost)
        let window = try XCTUnwrap(navigation.navigationBar.window)
        let menu = try XCTUnwrap(button.menu)
        var tapCount = 0
        button.addAction(UIAction { _ in tapCount += 1 }, for: .touchUpInside)
        XCTAssertTrue(button.isDescendant(of: navigation.navigationBar))
        XCTAssertTrue(button.window === window)

        host.removeFromSuperview()
        XCTAssertTrue(page.navigationItem.titleView === host)
        XCTAssertNil(host.window)

        page.viewDidAppear(false)
        settle(navigation)

        XCTAssertTrue(page.navigationItem.titleView === host)
        XCTAssertTrue(host.content === button)
        XCTAssertTrue(button.isDescendant(of: navigation.navigationBar))
        XCTAssertTrue(button.window === window)
        XCTAssertTrue(button.menu === menu)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(tapCount, 1)
    }

    func testClassicTitleDoesNotOverlapControlsAtNarrowWidthsInEitherDirection() throws {
        let bar = ShellClassicNavigationBar()
        let button = makeButton("A title view that wants more space than is available")
        let host = ShellNavigationTitleHost(content: button)
        let icon = UIImage(systemName: "gear")
        bar.update(title: "Title", subtitle: nil, largeTitle: false, showsBack: true,
                   leadingItems: [UIBarButtonItem(image: icon, style: .plain, target: nil, action: nil)],
                   trailingItems: [UIBarButtonItem(image: icon, style: .plain, target: nil, action: nil)],
                   style: ShellNavigationStyle(), material: .automatic, showsMediaBackground: false,
                   customTitleView: host)
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            bar.semanticContentAttribute = direction
            bar.frame = CGRect(x: 0, y: 0, width: 240, height: 44)
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
            let controls = bar.subviews.compactMap { $0 as? UIButton }.filter { !$0.isHidden }
            XCTAssertEqual(controls.count, 3)
            XCTAssertGreaterThan(host.bounds.width, 0)
            XCTAssertLessThan(host.bounds.width, host.preferredWidth)
            for control in controls { XCTAssertFalse(host.frame.intersects(control.frame)) }
            XCTAssertTrue(bar.bounds.contains(host.frame))
            if direction == .forceLeftToRight {
                let leadingEdge = controls.filter { $0.frame.minX < bar.bounds.midX }
                    .map(\.frame.maxX).max() ?? 0
                XCTAssertEqual(host.frame.minX, leadingEdge + 4, accuracy: 1)
            }
            XCTAssertEqual(button.convert(button.bounds, to: host), host.bounds)
        }
        bar.frame.size.width = 600
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        XCTAssertGreaterThan(host.bounds.width, 100)
    }

    func testPushPopAndReplacingTheConfiguredViewUseTheCurrentPage() throws {
        let page = NavigationTitleFixture()
        let original = makeButton("Original source")
        page.customTitle = original
        let navigation = show(page, presentation: .classic)
        let bar = try XCTUnwrap(navigation.classicNavigationBarView)
        let originalHost = try XCTUnwrap(original.superview)
        XCTAssertTrue(originalHost.superview === bar)
        let detail = NavigationTitleFixture()
        let detailTitle = makeButton("Detail source")
        detail.customTitle = detailTitle
        navigation.pushViewController(detail, animated: false)
        settle(navigation)
        XCTAssertFalse(original.isDescendant(of: bar))
        XCTAssertTrue(detailTitle.isDescendant(of: bar))
        XCTAssertTrue(bar.subviews.contains { $0.accessibilityIdentifier == "shell.classic.back" && !$0.isHidden })
        XCTAssertTrue(navigation.popViewController(animated: false) === detail)
        settle(navigation)
        XCTAssertTrue(original.superview === originalHost)
        XCTAssertTrue(originalHost.superview === bar)
        XCTAssertFalse(detailTitle.isDescendant(of: bar))

        let replacement = makeButton("Replacement")
        page.customTitle = replacement
        page.refreshScreenConfiguration()
        settle(navigation)
        XCTAssertNil(original.superview)
        XCTAssertTrue(replacement.isDescendant(of: bar))
    }

    private func makeButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [UIAction(title: "Option") { _ in }])
        return button
    }

    private func show(_ page: BoneViewController, presentation: ShellBarPresentation) -> BoneNavigationController {
        let navigation = BoneNavigationController(rootViewController: page)
        navigation.barPresentation = presentation
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        self.window = window
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        settle(navigation)
        return navigation
    }

    private func settle(_ navigation: BoneNavigationController) {
        navigation.view.setNeedsLayout()
        navigation.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        navigation.view.layoutIfNeeded()
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }
}

private final class ResizableTitleButton: UIButton {
    var preferredWidth: CGFloat = 44 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: preferredWidth, height: 44) }
}

private final class NavigationTitleFixture: BoneViewController {
    var customTitle: UIView?
    var usesLargeTitle = false

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Semantic title"
        screen.navigation.subtitle = "Standard subtitle"
        screen.navigation.usesLargeTitle = usesLargeTitle
        screen.navigation.titleView = customTitle
    }
}
