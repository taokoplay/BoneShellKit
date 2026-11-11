import XCTest
import UIKit
import WebKit
import ImageIO
import UniformTypeIdentifiers
@testable import BoneShellKit

@MainActor
final class UnifiedBackgroundTests: XCTestCase {
    func testUnifiedCanvasSuppressesIndependentDefaultsAndRestoresSurfaces() throws {
        let page = UnifiedFixture()
        let tabs = makeTabs(page)
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? BoneNavigationController)
        tabs.loadViewIfNeeded()
        navigation.loadViewIfNeeded()
        page.loadViewIfNeeded()
        navigation.backgroundConfiguration = ShellBackgroundConfiguration(source: .color(.red))
        tabs.backgroundConfiguration = ShellBackgroundConfiguration(source: .color(.green))
        page.refreshScreenConfiguration()
        let canvas = try XCTUnwrap(tabs.unifiedBackgroundView)
        XCTAssertTrue(page.activeBackgroundView === canvas)
        XCTAssertTrue(canvas.superview === tabs.view)
        XCTAssertEqual(canvas.frame, tabs.view.bounds)
        XCTAssertNil(page.backgroundView.configuration)
        XCTAssertNil(navigation.backgroundView?.configuration)
        XCTAssertNil(tabs.backgroundView?.configuration)
        XCTAssertTrue(page.view.backgroundColor?.isEqual(UIColor.clear) == true)
        page.composition = .independent
        page.refreshScreenConfiguration()
        XCTAssertNil(tabs.unifiedBackgroundView)
        XCTAssertEqual(page.backgroundView.configuration?.source, .color(.blue))
        XCTAssertEqual(navigation.backgroundView?.configuration?.source, .color(.red))
        XCTAssertEqual(tabs.backgroundView?.configuration?.source, .color(.green))
        XCTAssertTrue(page.view.backgroundColor?.isEqual(UIColor.magenta) == true)
        XCTAssertTrue(canvas.isHidden)
    }

    func testSameBackgroundReusesOneCanvasAcrossPushAndPop() throws {
        let first = UnifiedFixture()
        let tabs = makeTabs(first)
        tabs.loadViewIfNeeded()
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? BoneNavigationController)
        navigation.loadViewIfNeeded()
        first.loadViewIfNeeded()
        first.refreshScreenConfiguration()
        let original = try XCTUnwrap(tabs.unifiedBackgroundView)
        let second = UnifiedFixture()
        second.configuration = first.configuration
        second.loadViewIfNeeded()
        navigation.pushViewController(second, animated: false)
        second.refreshScreenConfiguration()
        XCTAssertTrue(second.activeBackgroundView === original)
        XCTAssertTrue(tabs.unifiedBackgroundView === original)
        XCTAssertNil(second.backgroundView.configuration)
        navigation.popViewController(animated: false)
        first.refreshScreenConfiguration()
        XCTAssertTrue(first.activeBackgroundView === original)
        XCTAssertEqual(tabs.view.subviews.compactMap { $0 as? ShellBackgroundView }.filter { $0.configuration != nil }.count, 1)
    }

    func testUnifiedHTMLUsesOneBudgetSlotAndRetainsWebViewDuringSameSourcePush() async throws {
        let oldLimit = ShellBackgroundPlaybackBudget.maximumActivePerScene
        ShellBackgroundPlaybackBudget.maximumActivePerScene = 3
        defer { ShellBackgroundPlaybackBudget.maximumActivePerScene = oldLimit }
        let page = UnifiedFixture()
        page.configuration = ShellBackgroundConfiguration(
            source: .htmlString("<html><body style='margin:0;background:#3479b2'>shared</body></html>", baseURL: nil), transitionDuration: 0)
        let tabs = makeTabs(page)
        let oldKey = keyWindow()
        let window = show(tabs)
        defer { window.isHidden = true; window.rootViewController = nil; oldKey?.makeKeyAndVisible() }
        page.refreshScreenConfiguration()
        let canvas = try XCTUnwrap(tabs.unifiedBackgroundView)
        try await waitUntilReady(canvas)
        let web = try XCTUnwrap(canvas.subviews.compactMap { $0 as? WKWebView }.first)
        XCTAssertEqual(canvas.subviews.compactMap { $0 as? WKWebView }.count, 1)
        XCTAssertEqual(ShellBackgroundPlaybackBudget.activeCount(in: window.windowScene), 1)
        let detail = UnifiedFixture()
        detail.configuration = page.configuration
        detail.loadViewIfNeeded()
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? BoneNavigationController)
        navigation.pushViewController(detail, animated: false)
        detail.refreshScreenConfiguration()
        XCTAssertTrue(detail.activeBackgroundView === canvas)
        XCTAssertTrue(canvas.subviews.compactMap { $0 as? WKWebView }.first === web)
        XCTAssertEqual(ShellBackgroundPlaybackBudget.activeCount(in: window.windowScene), 1)
        detail.composition = .independent
        detail.configuration = nil
        detail.refreshScreenConfiguration()
        XCTAssertNil(tabs.unifiedBackgroundView)
        XCTAssertFalse(canvas.subviews.contains { $0 is WKWebView })
        XCTAssertEqual(ShellBackgroundPlaybackBudget.activeCount(in: window.windowScene), 0)
    }

    func testOneImageCoordinateSystemCoversBarsAndResizesWithContainer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BoneUnified-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bands.png")
        let colors: [UIColor] = [.red, .green, .blue, .yellow]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 800)).image { _ in
            for (index, color) in colors.enumerated() {
                color.setFill()
                UIRectFill(CGRect(x: 0, y: index * 200, width: 16, height: 200))
            }
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        let page = UnifiedFixture()
        page.configuration = ShellBackgroundConfiguration(source: .image(.file(url)), fallbackColor: .black,
            contentMode: .scaleToFill, transitionDuration: 0)
        let tabs = makeTabs(page)
        let oldKey = keyWindow()
        let window = show(tabs)
        defer { window.isHidden = true; window.rootViewController = nil; oldKey?.makeKeyAndVisible() }
        page.refreshScreenConfiguration()
        let canvas = try XCTUnwrap(tabs.unifiedBackgroundView)
        try await waitUntilReady(canvas)
        tabs.view.layoutIfNeeded()
        let snapshot = UIGraphicsImageRenderer(bounds: tabs.view.bounds).image { context in
            tabs.view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "Unified full-container band mapping"
        attachment.lifetime = .keepAlways
        add(attachment)
        let height = tabs.view.bounds.height
        for (fraction, color) in [(CGFloat(0.025), UIColor.red), (0.12, .red), (0.56, .blue), (0.975, .yellow)] {
            try assertPixel(snapshot, point: CGPoint(x: 2, y: height * fraction), matches: color)
        }
        XCTAssertEqual(canvas.frame, tabs.view.bounds)
        tabs.view.bounds.size = CGSize(width: 640, height: 400)
        tabs.view.setNeedsLayout()
        tabs.view.layoutIfNeeded()
        try await waitUntilReady(canvas)
        XCTAssertEqual(canvas.frame, tabs.view.bounds)
        XCTAssertTrue(page.activeBackgroundView === canvas)
    }

    private func makeTabs(_ page: BoneViewController) -> BoneTabBarController {
        BoneTabBarController(tabs: [ShellTab(id: "unified", title: "Shared", symbol: "photo", root: page)])
    }

    private func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
    }

    private func show(_ root: UIViewController) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
            window = UIWindow(windowScene: scene)
        } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)) }
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return window
    }

    private func waitUntilReady(_ canvas: ShellBackgroundView) async throws {
        if canvas.status.phase == .ready { return }
        let done = expectation(description: "Shared background is ready")
        canvas.onStatusChange = { [weak canvas] status in
            if status.phase == .ready || status.phase == .failed {
                canvas?.onStatusChange = nil
                done.fulfill()
            }
        }
        await fulfillment(of: [done], timeout: 12)
        canvas.onStatusChange = nil
        XCTAssertEqual(canvas.status.phase, .ready, canvas.status.detail ?? "No diagnostic")
    }

    private func assertPixel(_ image: UIImage, point: CGPoint, matches color: UIColor,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: Int(point.x * image.scale), y: Int(point.y * image.scale), width: 1, height: 1)), file: file, line: line)
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        for (actual, expected) in zip(bytes, [red, green, blue, alpha]) {
            XCTAssertEqual(CGFloat(actual) / 255, expected, accuracy: 0.03, file: file, line: line)
        }
    }
}

@MainActor
private final class UnifiedFixture: BoneViewController {
    var composition: ShellBackgroundComposition = .unified
    var configuration: ShellBackgroundConfiguration? = ShellBackgroundConfiguration(source: .color(.blue))
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Shared background"
        screen.backgroundComposition = composition
        screen.background = configuration
    }
    override func buildContent(in contentView: UIView) { view.backgroundColor = .magenta }
}
