import XCTest
import UIKit
@testable import BoneShellDemo
import BoneShellKit

@MainActor
final class DemoIntegrationTests: XCTestCase {
    func testPrimaryNavigationActionStaysVisibleOnPhoneWidth() {
        let page = NavigationDemoController()
        page.loadViewIfNeeded()
        page.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 650)
        page.view.setNeedsLayout()
        page.view.layoutIfNeeded()
        XCTAssertTrue(page.visibleActionIDs.contains("nav.0"))
        XCTAssertFalse(page.overflowActionIDs.contains("nav.0"))
        XCTAssertEqual(Set(page.visibleActionIDs + page.overflowActionIDs), Set(["leading", "nav.0", "nav.1", "nav.2"]))
    }

    func testRefreshingConfigurationPreservesInputAndContentIdentity() {
        let page = FormDemoController()
        page.loadViewIfNeeded()
        let originalContent = page.contentView
        let originalInput = page.input
        page.input.text = "keep this input"
        page.refreshScreenConfiguration()
        page.refreshScreenConfiguration()
        XCTAssertTrue(originalContent === page.contentView)
        XCTAssertTrue(originalInput === page.input)
        XCTAssertEqual(page.input.text, "keep this input")
        XCTAssertTrue(page.input.isDescendant(of: page.contentView))
    }

    func testTabsKeepIndependentNavigationStacks() {
        let first = FormDemoController()
        let second = MaterialDemoController()
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "first", title: "First", symbol: "1.circle", root: first),
            ShellTab(id: "second", title: "Second", symbol: "2.circle", root: second)
        ])
        tabs.loadViewIfNeeded()
        guard let navigation = tabs.viewControllers?.first as? UINavigationController else {
            return XCTFail("Each tab must own a navigation controller")
        }
        let detail = FormDemoController()
        detail.loadViewIfNeeded()
        detail.input.text = "retained"
        navigation.pushViewController(detail, animated: false)
        tabs.selectedIndex = 1
        tabs.selectedIndex = 0
        XCTAssertTrue(navigation.topViewController === detail)
        XCTAssertEqual(detail.input.text, "retained")
        XCTAssertEqual((tabs.viewControllers?[1] as? UINavigationController)?.viewControllers.count, 1)
    }

    func testMaterialUpdatesPreserveHostedContent() {
        let surface = ShellGlassView(material: .solid)
        let label = UILabel()
        label.text = "hosted"
        surface.contentView.addSubview(label)
        XCTAssertEqual(surface.resolution.resolved, .solid)
        surface.material = .frostedGlass
        surface.refreshMaterial()
        XCTAssertTrue(label.isDescendant(of: surface))
        XCTAssertEqual(surface.resolution.requested, .frostedGlass)
        surface.material = .solid
        XCTAssertEqual(surface.resolution.resolved, .solid)
        XCTAssertEqual(label.text, "hosted")
    }
}
