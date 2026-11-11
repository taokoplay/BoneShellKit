import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class BarStyleTests: XCTestCase {
    func testDynamicTypeUsesTargetTraitsAndFixedFontsRemainFixed() throws {
        let normal = UITraitCollection(preferredContentSizeCategory: .large)
        let accessible = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let base = UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        let scalable = ShellTextStyle(font: base)
        let small = try XCTUnwrap(scalable.resolvedFont(for: .headline, traits: normal))
        let large = try XCTUnwrap(scalable.resolvedFont(for: .headline, traits: accessible))
        XCTAssertGreaterThan(large.pointSize, small.pointSize)
        XCTAssertEqual(large.fontDescriptor.symbolicTraits, small.fontDescriptor.symbolicTraits)
        let fixed = ShellTextStyle(font: base, scalesWithDynamicType: false)
        XCTAssertEqual(fixed.resolvedFont(for: .headline, traits: accessible)?.pointSize, 18)
        XCTAssertEqual(fixed.resolvedFont(for: .headline, traits: normal)?.pointSize, 18)
    }

    func testTemplateColorsProduceVisiblePixelsAndOriginalImagesKeepTheirColor() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "test", title: "Test",
            icon: .image(source.withRenderingMode(.alwaysTemplate)), root: BoneViewController())])
        tabs.loadViewIfNeeded()
        tabs.tabBarStyle = ShellTabBarStyle(normalIconColor: .systemBlue, selectedIconColor: .systemOrange)
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        try assertPixelColor(item.image, matches: .systemBlue, traits: tabs.traitCollection)
        try assertPixelColor(item.selectedImage, matches: .systemOrange, traits: tabs.traitCollection)
        XCTAssertNil(tabs.tabItemConfiguration(for: "test")?.selectedIcon)
        let original = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in
            UIColor.systemPink.resolvedColor(with: tabs.traitCollection).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.withRenderingMode(.alwaysOriginal)
        XCTAssertTrue(tabs.updateTabItem(id: "test", configuration: ShellTabItemConfiguration(title: "Test", icon: .image(original))))
        try assertPixelColor(item.image, matches: .systemPink, traits: tabs.traitCollection)
        try assertPixelColor(item.selectedImage, matches: .systemPink, traits: tabs.traitCollection)
        XCTAssertTrue(tabs.updateTabItem(id: "test", configuration: ShellTabItemConfiguration(title: "Test", icon: .systemSymbol("circle.fill"))))
        let corner = try XCTUnwrap(item.image?.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertEqual(pixel[3], 0, "Symbol corners must remain transparent after coloring")
    }

    private func assertPixelColor(_ image: UIImage?, matches color: UIColor, traits: UITraitCollection,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let cg = try XCTUnwrap(image?.cgImage, file: file, line: line)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        for (actual, expected) in zip(pixel, [red, green, blue, alpha]) {
            XCTAssertEqual(CGFloat(actual) / 255, expected, accuracy: 0.025, file: file, line: line)
        }
    }

    func testLongTextActionsStayReachableWhenLargeFontsOverflow() {
        let page = StyledActionFixture()
        page.loadViewIfNeeded()
        for width in [CGFloat(320), 390, 768] {
            page.view.bounds = CGRect(x: 0, y: 0, width: width, height: 600)
            page.refreshScreenConfiguration()
            page.view.layoutIfNeeded()
            let all = page.visibleActionIDs + page.overflowActionIDs
            XCTAssertEqual(Set(all), Set(["save", "share", "archive"]))
            XCTAssertEqual(all.count, 3)
            if !page.overflowActionIDs.isEmpty {
                XCTAssertTrue(page.navigationItem.rightBarButtonItems?.contains {
                    $0.accessibilityIdentifier == "shell.overflow" && $0.menu != nil
                } == true)
            }
        }
    }

    func testNavigationButtonTintRestoresOnPushAndReturnsOnPop() {
        let root = TintFixture()
        let navigation = BoneNavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        navigation.navigationBar.tintColor = .systemGreen
        root.style = ShellNavigationStyle(buttons: ShellTextStyle(color: .systemBlue))
        root.loadViewIfNeeded()
        root.refreshScreenConfiguration()
        XCTAssertTrue(navigation.navigationBar.tintColor.isEqual(UIColor.systemBlue))
        let detail = TintFixture()
        detail.style = ShellNavigationStyle()
        navigation.pushViewController(detail, animated: false)
        detail.loadViewIfNeeded()
        detail.refreshScreenConfiguration()
        XCTAssertTrue(navigation.navigationBar.tintColor.isEqual(UIColor.systemGreen))
        navigation.popViewController(animated: false)
        root.refreshScreenConfiguration()
        XCTAssertTrue(navigation.navigationBar.tintColor.isEqual(UIColor.systemBlue))
        root.style = ShellNavigationStyle()
        root.refreshScreenConfiguration()
        XCTAssertTrue(navigation.navigationBar.tintColor.isEqual(UIColor.systemGreen))
    }
}

@MainActor
private final class StyledActionFixture: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "使用较大字体的导航标题"
        screen.navigation.style = ShellNavigationStyle(
            title: ShellTextStyle(size: 28, scalesWithDynamicType: false),
            buttons: ShellTextStyle(size: 24, scalesWithDynamicType: false))
        screen.navigation.trailingActions = [
            NavigationAction(id: "save", title: "保存", priority: 20, handler: {}),
            NavigationAction(id: "share", title: "分享完整内容", handler: {}),
            NavigationAction(id: "archive", title: "归档这条记录", handler: {})
        ]
    }
}

@MainActor
private final class TintFixture: BoneViewController {
    var style: ShellNavigationStyle?
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Tint"
        screen.navigation.style = style
    }
}
