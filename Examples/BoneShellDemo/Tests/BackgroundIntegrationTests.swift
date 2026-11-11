import XCTest
import UIKit
import WebKit
import BoneShellKit
@testable import BoneShellDemo

@MainActor
final class BackgroundIntegrationTests: XCTestCase {
    func testPageNavigationAndTabsReceiveBackgroundConfiguration() {
        let page = BackgroundDemoController()
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "backgrounds", title: "Backgrounds", symbol: "photo", root: page)])
        tabs.loadViewIfNeeded()
        let nav = tabs.viewControllers!.first as! BoneNavigationController
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 700)
        page.selectScope(4)
        XCTAssertEqual(page.screenConfiguration.backgroundComposition, .independent)
        XCTAssertFalse(page.usesUnifiedBackground)
        XCTAssertEqual(page.backgroundView.configuration?.source.kindName, "image")
        XCTAssertEqual(nav.backgroundView?.configuration?.source.kindName, "image")
        XCTAssertEqual(tabs.backgroundView?.configuration?.source.kindName, "image")
        for scope in 0...2 {
            page.selectScope(scope)
            XCTAssertEqual(page.screenConfiguration.backgroundComposition, .independent)
            XCTAssertFalse(page.usesUnifiedBackground)
            XCTAssertEqual(page.backgroundView.configuration?.source.kindName, scope == 0 ? "image" : nil)
            XCTAssertEqual(nav.backgroundView?.configuration?.source.kindName, scope == 1 ? "image" : nil)
            XCTAssertEqual(tabs.backgroundView?.configuration?.source.kindName, scope == 2 ? "image" : nil)
        }
    }
    func testDemoDefaultsToUnifiedCanvasWithoutDuplicateRegionConfigurations() {
        let page = BackgroundDemoController()
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "backgrounds", title: "Backgrounds", symbol: "photo", root: page)])
        tabs.loadViewIfNeeded()
        let nav = tabs.viewControllers!.first as! BoneNavigationController
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds = CGRect(x: 0, y: 0, width: 390, height: 700)
        page.refreshScreenConfiguration()
        XCTAssertEqual(page.scopeIndex, 3)
        XCTAssertEqual(page.screenConfiguration.backgroundComposition, .unified)
        XCTAssertTrue(page.usesUnifiedBackground)
        XCTAssertEqual(page.screenConfiguration.background?.source.kindName, "image")
        XCTAssertNil(page.screenConfiguration.navigation.background)
        XCTAssertNil(page.screenConfiguration.tabBarBackground)
        XCTAssertEqual(page.activeBackgroundView.configuration?.source.kindName, "image")
        XCTAssertNil(page.backgroundView.configuration)
        XCTAssertNil(nav.backgroundView?.configuration)
        XCTAssertNil(tabs.backgroundView?.configuration)
        XCTAssertFalse(page.activeBackgroundView.isPlaybackRunning)
    }
    func testBackgroundChangesPreserveBusinessContentIdentity() {
        let page = BackgroundDemoController()
        page.loadViewIfNeeded()
        let content = page.contentView
        let scroll = page.scrollView
        XCTAssertTrue(page.usesUnifiedBackground)
        for source in [1, 2, 3, 0] {
            page.selectSource(source)
            XCTAssertNil(page.backgroundView.configuration)
            XCTAssertNotNil(page.activeBackgroundView.configuration)
            XCTAssertFalse(page.activeBackgroundView.isPlaybackRunning)
        }
        XCTAssertTrue(page.contentView === content)
        XCTAssertTrue(page.scrollView === scroll)
        XCTAssertEqual(page.activeBackgroundView.configuration?.source.kindName, "image")
    }
    func testHTMLDoesNotCreateWebViewWhileInactive() {
        let view = ShellBackgroundView()
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        view.apply(ShellBackgroundConfiguration(source: .htmlString("<html><body>test</body></html>", baseURL: nil)))
        view.setPlaybackActive(false)
        func containsWebView(_ node: UIView) -> Bool { node is WKWebView || node.subviews.contains(where: containsWebView) }
        XCTAssertFalse(containsWebView(view))
        XCTAssertFalse(view.isPlaybackRunning)
        view.stopAndRelease()
    }
    func testContainerDefaultCanBeOverriddenWithExplicitNone() {
        XCTAssertEqual(ScreenConfiguration().backgroundComposition, .independent)
        let page = BackgroundDefaultFixture()
        let nav = BoneNavigationController(rootViewController: page)
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        nav.backgroundConfiguration = ShellBackgroundConfiguration(source: .color(.red))
        page.refreshScreenConfiguration()
        XCTAssertFalse(page.usesUnifiedBackground)
        XCTAssertEqual(nav.backgroundView?.configuration?.source.kindName, "color")
        page.clearNavigation = true
        page.refreshScreenConfiguration()
        XCTAssertNil(nav.backgroundView?.configuration)
    }
}

@MainActor
private final class BackgroundDefaultFixture: BoneViewController {
    var clearNavigation = false
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Background fixture"
        if clearNavigation { screen.navigation.background = ShellBackgroundConfiguration(source: .none) }
    }
}
