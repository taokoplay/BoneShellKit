import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class TabSelectedIconTests: XCTestCase {
    func testSelectedColorKeepsNormalArtworkAndOverridesOriginalRendering() throws {
        let normal = artwork(selected: false)
        let selected = artwork(selected: true)
        let tabs = makeTabs(normal: normal, selected: selected, mode: .selectedColor)
        tabs.tabBarStyle = ShellTabBarStyle(selectedIconColor: .blue)
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        try assertColor(item.image, at: CGPoint(x: 1.5, y: 3.5), equals: .red)
        try assertColor(item.selectedImage, at: CGPoint(x: 1.5, y: 3.5), equals: .blue)
        try assertColor(item.selectedImage, at: CGPoint(x: 5.5, y: 3.5), equals: .blue)
        XCTAssertEqual(try pixel(item.selectedImage, at: CGPoint(x: 3.5, y: 3.5))[3], 0, "Normal icon's hole must stay transparent")
        XCTAssertEqual(try pixel(item.selectedImage, at: CGPoint(x: 0.5, y: 0.5))[3], 0)
        XCTAssertEqual(item.selectedImage?.renderingMode, .alwaysOriginal)
    }

    func testSelectedImagePreservesColorsPatternAndNormalFallback() throws {
        let tabs = makeTabs(normal: artwork(selected: false), selected: artwork(selected: true), mode: .selectedImage)
        tabs.tabBarStyle = ShellTabBarStyle(selectedIconColor: .blue)
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        try assertColor(item.selectedImage, at: CGPoint(x: 1.5, y: 3.5), equals: .yellow)
        try assertColor(item.selectedImage, at: CGPoint(x: 5.5, y: 3.5), equals: .magenta)
        XCTAssertEqual(try pixel(item.selectedImage, at: CGPoint(x: 0.5, y: 0.5))[3], 0)
        var configuration = try XCTUnwrap(tabs.tabItemConfiguration(for: "first"))
        configuration.selectedIcon = nil
        XCTAssertTrue(tabs.updateTabItem(id: "first", configuration: configuration))
        try assertColor(item.selectedImage, at: CGPoint(x: 1.5, y: 3.5), equals: .red)
        try assertColor(item.selectedImage, at: CGPoint(x: 5.5, y: 3.5), equals: .green)
        XCTAssertEqual(try pixel(item.selectedImage, at: CGPoint(x: 3.5, y: 3.5))[3], 0)
    }

    func testSelectedColorUsesConfiguredIconColorThenSelectedTextColor() throws {
        let tabs = makeTabs(normal: artwork(selected: false), selected: nil, mode: .selectedColor)
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        tabs.tabBarStyle = ShellTabBarStyle(selected: ShellTextStyle(color: .green))
        try assertColor(item.selectedImage, at: CGPoint(x: 1.5, y: 3.5), equals: .green)
        tabs.tabBarStyle = ShellTabBarStyle(selected: ShellTextStyle(color: .green), selectedIconColor: .red)
        try assertColor(item.selectedImage, at: CGPoint(x: 1.5, y: 3.5), equals: .red)
    }

    func testExplicitModesPreventAutomaticFilledSymbolSubstitution() throws {
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "first", title: "First",
            icon: .systemSymbol("circle"), selectedIcon: .systemSymbol("circle.fill"),
            selectedIconMode: .selectedColor, root: BoneViewController())])
        tabs.loadViewIfNeeded()
        tabs.tabBarStyle = ShellTabBarStyle(selectedIconColor: .blue)
        let item = try XCTUnwrap(tabs.tabBar.items?.first)
        let outline = try XCTUnwrap(item.selectedImage)
        XCTAssertFalse(outline.isSymbolImage)
        let center = CGPoint(x: outline.size.width / 2, y: outline.size.height / 2)
        XCTAssertEqual(try pixel(outline, at: center)[3], 0)
        var configuration = try XCTUnwrap(tabs.tabItemConfiguration(for: "first"))
        configuration.selectedIconMode = .selectedImage
        XCTAssertTrue(tabs.updateTabItem(id: "first", configuration: configuration))
        let filled = try XCTUnwrap(item.selectedImage)
        XCTAssertFalse(filled.isSymbolImage)
        XCTAssertGreaterThan(try pixel(filled, at: CGPoint(x: filled.size.width / 2, y: filled.size.height / 2))[3], 240)
        configuration.selectedIcon = nil
        XCTAssertTrue(tabs.updateTabItem(id: "first", configuration: configuration))
        let fallback = try XCTUnwrap(item.selectedImage)
        XCTAssertEqual(try pixel(fallback, at: CGPoint(x: fallback.size.width / 2, y: fallback.size.height / 2))[3], 0)
    }

    func testRuntimeModesKeepStateAndAutomaticCompatibilityInBothPresentations() throws {
        let first = BoneViewController()
        let normal = artwork(selected: false)
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "first", title: "First", icon: .image(normal), root: first),
            ShellTab(id: "second", title: "Second", symbol: "gearshape", root: BoneViewController())
        ])
        tabs.loadViewIfNeeded()
        let navigation = try XCTUnwrap(tabs.viewControllers?.first as? BoneNavigationController)
        let detail = BoneViewController()
        detail.loadViewIfNeeded()
        let input = UITextField()
        input.text = "keep selected mode input"
        detail.contentView.addSubview(input)
        navigation.pushViewController(detail, animated: false)
        let controllers = tabs.viewControllers!
        tabs.selectedIndex = 1
        let selectedController = tabs.selectedViewController
        for presentation: ShellBarPresentation in [.system, .classic] {
            tabs.barPresentation = presentation
            for mode: ShellTabSelectedIconMode in [.selectedColor, .selectedImage, .automatic] {
                var item = try XCTUnwrap(tabs.tabItemConfiguration(for: "first"))
                item.selectedIconMode = mode
                XCTAssertTrue(tabs.updateTabItem(id: "first", configuration: item))
                XCTAssertEqual(tabs.tabItemConfiguration(for: "first")?.selectedIconMode, mode)
                XCTAssertEqual(tabs.selectedIndex, 1)
                XCTAssertTrue(tabs.selectedViewController === selectedController)
                XCTAssertTrue(navigation.topViewController === detail)
                XCTAssertEqual(input.text, "keep selected mode input")
                for (left, right) in zip(controllers, tabs.viewControllers!) { XCTAssertTrue(left === right) }
            }
        }
        XCTAssertEqual(tabs.tabItemConfiguration(for: "first")?.selectedIconMode, .automatic)
        XCTAssertNil(tabs.tabItemConfiguration(for: "first")?.selectedIcon, "Automatic mode retains the previous unspecified-selected-icon configuration")
        let actual = navigation.tabBarItem.selectedImage ?? navigation.tabBarItem.image
        try assertColor(actual, at: CGPoint(x: 1.5, y: 3.5), equals: .red)
        try assertColor(actual, at: CGPoint(x: 5.5, y: 3.5), equals: .green)
        XCTAssertEqual(try pixel(actual, at: CGPoint(x: 3.5, y: 3.5))[3], 0)
        tabs.barPresentation = .system
    }

    private func makeTabs(normal: UIImage, selected: UIImage?, mode: ShellTabSelectedIconMode) -> BoneTabBarController {
        let tabs = BoneTabBarController(tabs: [ShellTab(id: "first", title: "First", icon: .image(normal),
            selectedIcon: selected.map(ShellTabIcon.image), selectedIconMode: mode, root: BoneViewController())])
        tabs.loadViewIfNeeded()
        return tabs
    }

    private func artwork(selected: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { _ in
            if selected {
                UIColor.yellow.setFill(); UIRectFill(CGRect(x: 1, y: 1, width: 3, height: 6))
                UIColor.magenta.setFill(); UIRectFill(CGRect(x: 4, y: 1, width: 3, height: 6))
            } else {
                UIColor.red.setFill(); UIRectFill(CGRect(x: 1, y: 1, width: 2, height: 6))
                UIColor.green.setFill(); UIRectFill(CGRect(x: 5, y: 1, width: 2, height: 6))
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private func pixel(_ image: UIImage?, at point: CGPoint) throws -> [UInt8] {
        let image = try XCTUnwrap(image)
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: Int(point.x * image.scale), y: Int(point.y * image.scale), width: 1, height: 1)))
        var result = [UInt8](repeating: 0, count: 4)
        result.withUnsafeMutableBytes { data in
            let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return result
    }

    private func assertColor(_ image: UIImage?, at point: CGPoint, equals color: UIColor,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try pixel(image, at: point)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        for (value, expected) in zip(actual, [red, green, blue, alpha]) {
            XCTAssertEqual(CGFloat(value) / 255, expected, accuracy: 0.03, file: file, line: line)
        }
    }
}
