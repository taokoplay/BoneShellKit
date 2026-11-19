import UIKit
import XCTest
@testable import BoneShellKit

@MainActor
final class NavButtonAppearanceTests: XCTestCase {
    func testOriginalImageAndFittingSizeAreIndependentOfTouchTarget() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }.withRenderingMode(.alwaysOriginal)
        var action = NavigationAction(id: "icon", title: "Share", icon: .image(image)) {}
        action.navButton = .init()
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 36, height: 18))
        XCTAssertEqual(host.intrinsicContentSize, host.preferredVisualSize)
        XCTAssertTrue(host.image(for: .normal) === image)
        XCTAssertNil(host.title(for: .normal))
        XCTAssertEqual(host.accessibilityLabel, "Share")
        XCTAssertTrue(materials(in: host).isEmpty)

        action.navButton = .init(normal: .init(size: .preferred(CGSize(width: 72, height: 44)),
                                               iconSize: CGSize(width: 30, height: 30),
                                               contentInsets: .init(top: 3, leading: 11, bottom: 7, trailing: 1)),
                                 vertical: .init(size: .fitting))
        host.update(action: action, textStyle: .init()) {}
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 72, height: 44))
        host.setVertical(true)
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 42, height: 40))
        XCTAssertEqual(host.sizeThatFits(CGSize(width: 18, height: 50)), CGSize(width: 18, height: 40))
        host.bounds.size = host.preferredVisualSize
        for (direction, x) in [(UISemanticContentAttribute.forceLeftToRight, CGFloat(11)), (.forceRightToLeft, 1)] {
            host.semanticContentAttribute = direction
            host.setNeedsLayout()
            host.layoutIfNeeded()
            let imageView = try XCTUnwrap(host.imageView)
            let rect = imageView.convert(imageView.bounds, to: host)
            XCTAssertEqual(rect.minX, x, accuracy: 0.5)
            XCTAssertEqual(rect.width, 30, accuracy: 0.5)
            XCTAssertEqual(rect.height, 15, accuracy: 0.5)
        }
    }

    func testVerticalStyleCanReplaceNormalTitleWithItsOwnIcon() throws {
        let action = NavigationAction(id: "done", title: "完成", navButton: .init(
            normal: .init(size: .preferred(CGSize(width: 72, height: 44))),
            vertical: .init(size: .preferred(CGSize(width: 44, height: 72)), icon: .systemSymbol("checkmark"))
        )) {}
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init(size: 17, scalesWithDynamicType: false)) {}
        XCTAssertNil(host.currentImage)
        XCTAssertEqual(host.currentTitle, "完成")
        host.setVertical(true)
        XCTAssertTrue(host.currentImage?.isSymbolImage == true)
        XCTAssertNil(host.currentTitle)
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 44, height: 72))
    }

    func testSidebarKeepsShortTitleAtConfiguredFontWhenOnlyPaddingNeedsCompression() throws {
        let action = NavigationAction(id: "done", title: "完成", navButton: .init(
            normal: .init(size: .preferred(CGSize(width: 72, height: 44)))
        )) {}
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init(size: 17, scalesWithDynamicType: false)) {}
        host.setVertical(true)
        host.frame.size = CGSize(width: 38, height: 44)
        host.layoutIfNeeded()
        let label = try XCTUnwrap(host.titleLabel)
        XCTAssertEqual(label.font.pointSize, 17)
        let measured = (action.title as NSString).size(withAttributes: [.font: label.font as UIFont]).width
        XCTAssertGreaterThanOrEqual(label.bounds.width, ceil(measured))
        XCTAssertEqual(host.contentRect(forBounds: CGRect(x: 0, y: 0, width: 72, height: 44)).minX, 8)
    }

    func testMissingImageFitsTitleWithButtonFontAndInvalidDimensionsStayFinite() {
        var action = NavigationAction(id: "text", title: "Save", icon: .asset("missing-navbutton-fixture", bundle: .main)) {}
        let navigationStyle = ShellNavigationStyle(title: .init(size: 50), buttons: .init(size: 16, scalesWithDynamicType: false))
        action.navButton = .init(normal: .init(contentInsets: .zero))
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: navigationStyle.buttons) {}
        XCTAssertEqual(host.currentTitle, "Save")
        XCTAssertNil(host.currentImage)
        XCTAssertEqual(host.titleLabel?.font.pointSize, 16)
        let fitted = host.preferredVisualSize
        XCTAssertGreaterThan(fitted.width, 0)
        XCTAssertLessThan(fitted.height, 44)
        action.navButton?.normal.size = .preferred(CGSize(width: CGFloat.nan, height: 22))
        action.navButton?.normal.contentInsets = .init(top: .infinity, leading: -10, bottom: 0, trailing: .nan)
        host.update(action: action, textStyle: navigationStyle.buttons) {}
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: fitted.width, height: 22))
        action.navButton?.normal.size = .preferred(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .infinity))
        host.update(action: action, textStyle: navigationStyle.buttons) {}
        XCTAssertLessThan(host.preferredVisualSize.width, 10_000)
        XCTAssertEqual(host.preferredVisualSize.height, fitted.height)
    }

    func testInheritedAndExplicitCustomContentKeepTheirOwnRevisionAndDetachSafely() {
        let normal = PartialSizeView(frame: CGRect(x: 0, y: 0, width: 32, height: 0))
        let vertical = UIView()
        NSLayoutConstraint.activate([vertical.widthAnchor.constraint(equalToConstant: 22),
                                     vertical.heightAnchor.constraint(equalToConstant: 40)])
        var normalMakes = 0, verticalMakes = 0
        var action = NavigationAction(id: "custom", title: "Done", symbol: "checkmark") {}
        action.navButton = .init(normal: .init(contentInsets: .zero, content: .custom(revision: 1) {
            normalMakes += 1; return normal
        }), vertical: .init(effect: .none))
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 32, height: 14))
        XCTAssertNil(host.currentImage)
        XCTAssertNil(host.currentTitle)
        host.setVertical(true)
        host.update(action: action, textStyle: .init()) {}
        XCTAssertEqual(normalMakes, 1)
        XCTAssertTrue(normal.isDescendant(of: host))
        action.navButton?.vertical?.content = .standard
        host.update(action: action, textStyle: .init()) {}
        XCTAssertNil(normal.superview)
        XCTAssertNotNil(host.currentImage)

        action.navButton?.vertical?.content = .custom(revision: 1) { verticalMakes += 1; return vertical }
        host.update(action: action, textStyle: .init()) {}
        XCTAssertNil(normal.superview)
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 22, height: 40))
        XCTAssertTrue(vertical.isDescendant(of: host))
        host.setVertical(false)
        host.setVertical(true)
        XCTAssertEqual(normalMakes, 1)
        XCTAssertEqual(verticalMakes, 1)
        let replacement = UIView()
        action.navButton?.vertical?.content = .custom(revision: 2) { replacement }
        host.update(action: action, textStyle: .init()) {}
        XCTAssertNil(vertical.superview)
        XCTAssertTrue(replacement.isDescendant(of: host))

        let otherOwner = UIView()
        otherOwner.addSubview(vertical)
        action.navButton?.vertical?.content = .custom(revision: 3) { vertical }
        host.update(action: action, textStyle: .init()) {}
        XCTAssertTrue(vertical.superview === otherOwner)
        XCTAssertNil(replacement.superview)
        XCTAssertNil(host.currentImage, "An unavailable custom view must not inject a standard glyph")
        XCTAssertNil(host.currentTitle)
        host.setVertical(false)
        XCTAssertTrue(normal.isDescendant(of: host))
        host.unmount()
        XCTAssertNil(normal.superview)
        XCTAssertTrue(vertical.superview === otherOwner)
        XCTAssertEqual(host.preferredVisualSize, .zero)
    }

    func testMaterialSwitchesBetweenOneEffectAndSolidOrTransparentWithoutChangingDeviceSettings() throws {
        var action = NavigationAction(id: "done", title: "Done") {}
        action.navButton = .init(normal: .init(size: .preferred(CGSize(width: 72, height: 44)), effect: .blur),
                                 vertical: .init(size: .preferred(CGSize(width: 44, height: 72)), effect: .liquidGlass))
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        host.bounds.size = host.preferredVisualSize
        host.updateMaterial(reduceTransparency: false)
        host.layoutIfNeeded()
        let blur = try XCTUnwrap(materials(in: host).first)
        XCTAssertTrue(blur.effect is UIBlurEffect)
        XCTAssertEqual(materials(in: host).count, 1)
        XCTAssertEqual(blur.frame, host.bounds)
        XCTAssertTrue(host.clipsToBounds)
        XCTAssertEqual(host.layer.cornerRadius, 22)
        host.updateMaterial(reduceTransparency: false)
        XCTAssertTrue(materials(in: host).first === blur)
        host.setVertical(true)
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 44, height: 72))
        host.bounds.size = host.preferredVisualSize
        host.layoutIfNeeded()
        host.updateMaterial(reduceTransparency: false)
        XCTAssertEqual(materials(in: host).count, 1)
        let effect = try XCTUnwrap(materials(in: host).first?.effect)
        if #available(iOS 26.0, *) { XCTAssertTrue(effect is UIGlassEffect) }
        else { XCTAssertTrue(effect is UIBlurEffect) }
        for vertical in [true, false] {
            host.setVertical(vertical)
            host.updateMaterial(reduceTransparency: true)
            XCTAssertTrue(materials(in: host).isEmpty)
            XCTAssertEqual(host.backgroundColor, .secondarySystemBackground)
        }
        action.navButton?.normal.effect = .none
        host.update(action: action, textStyle: .init()) {}
        for reduce in [true, false] {
            host.updateMaterial(reduceTransparency: reduce)
            XCTAssertTrue(materials(in: host).isEmpty)
            XCTAssertEqual(host.backgroundColor, .clear)
        }
    }

    private func materials(in host: ShellNavButtonHost) -> [UIVisualEffectView] {
        host.subviews.compactMap { $0 as? UIVisualEffectView }
    }
}

private final class PartialSizeView: UIView {
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: 8, height: 14) }
}
