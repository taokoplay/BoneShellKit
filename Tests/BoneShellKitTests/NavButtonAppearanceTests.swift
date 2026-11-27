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
        XCTAssertEqual(surface(in: host)?.isHidden, true)

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

    func testNegativeVisualOffsetKeepsImageInsideButtonHost() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }.withRenderingMode(.alwaysOriginal)
        var action = NavigationAction(id: "offset", title: "More", icon: .image(image)) {}
        action.navButton = .init(normal: .init(
            size: .preferred(CGSize(width: 44, height: 44)),
            iconSize: CGSize(width: 20, height: 20),
            contentInsets: .init(top: 4, leading: 8, bottom: 4, trailing: 8)
        ))
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        host.bounds.size = host.preferredVisualSize
        host.setModuleVisualOffset(-13, vertical: false)
        host.layoutIfNeeded()
        let imageView = try XCTUnwrap(host.imageView)
        let frame = imageView.convert(imageView.bounds, to: host)
        // 透明按钮没有表面可跟随，可见边界就是内容本身：负偏移仍必须把图标留在槽位内。
        // 被槽位裁掉的部分会按比例缩小绘制框，而不是让图标整体越界。
        XCTAssertGreaterThanOrEqual(frame.minX, host.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(frame.maxX, host.bounds.maxX + 0.5)
        XCTAssertLessThanOrEqual(frame.width, 20)
        XCTAssertEqual(frame.height, 20, accuracy: 0.5)
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
        action.navButton = .init(normal: .init(size: .preferred(CGSize(width: 72, height: 44)),
                                               effect: .material(.systemDefault)),
                                 vertical: .init(size: .preferred(CGSize(width: 44, height: 72)),
                                                 effect: .material(.systemGlass)))
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        host.bounds.size = host.preferredVisualSize
        host.updateMaterial(reduceTransparency: false)
        host.layoutIfNeeded()
        let blur = try XCTUnwrap(effectViews(in: host).first)
        XCTAssertTrue(blur.effect is UIBlurEffect)
        XCTAssertEqual(effectViews(in: host).count, 1)
        XCTAssertEqual(blur.superview?.frame, host.bounds)
        XCTAssertTrue(host.clipsToBounds)
        XCTAssertEqual(host.layer.cornerRadius, 22)
        host.updateMaterial(reduceTransparency: false)
        XCTAssertTrue(effectViews(in: host).first === blur)
        host.setVertical(true)
        XCTAssertEqual(host.preferredVisualSize, CGSize(width: 44, height: 72))
        host.bounds.size = host.preferredVisualSize
        host.layoutIfNeeded()
        host.updateMaterial(reduceTransparency: false)
        XCTAssertEqual(effectViews(in: host).count, 1)
        let effect = try XCTUnwrap(effectViews(in: host).first?.effect)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(effect is UIGlassEffect)
            // 系统玻璃自己画出边缘高光，宿主不能再裁剪。
            XCTAssertFalse(host.clipsToBounds)
            let surface = try XCTUnwrap(surface(in: host))
            XCTAssertFalse(surface.clipsToBounds)
        } else {
            XCTAssertTrue(effect is UIBlurEffect)
            XCTAssertTrue(host.clipsToBounds)
        }
        for vertical in [true, false] {
            host.setVertical(vertical)
            host.updateMaterial(reduceTransparency: true)
            XCTAssertTrue(effectViews(in: host).first?.effect == nil)
            XCTAssertEqual(surface(in: host)?.backgroundColor, .clear)
            XCTAssertEqual(host.clipsToBounds, true)
        }
        action.navButton?.normal.effect = .none
        action.navButton?.vertical?.effect = .none
        host.update(action: action, textStyle: .init()) {}
        for reduce in [true, false] {
            host.updateMaterial(reduceTransparency: reduce)
            XCTAssertTrue(surface(in: host)?.isHidden ?? true)
            XCTAssertEqual(host.backgroundColor, .clear)
        }
    }

    func testGlassSurfaceCarriesTintAndSkipsClipping() throws {
        var action = NavigationAction(id: "tinted", title: "Tinted") {}
        action.navButton = .init(normal: .init(size: .preferred(CGSize(width: 72, height: 44)),
                                               effect: .material(.systemGlass),
                                               tintColor: .systemOrange))
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        host.bounds.size = host.preferredVisualSize
        host.updateMaterial(reduceTransparency: false)
        host.layoutIfNeeded()
        let surface = try XCTUnwrap(surface(in: host))
        XCTAssertEqual(surface.glassTintColor, .systemOrange)
        guard #available(iOS 26.0, *) else { return }
        XCTAssertEqual((effectViews(in: host).first?.effect as? UIGlassEffect)?.tintColor, .systemOrange)
        XCTAssertFalse(host.clipsToBounds)
    }


    func testSurfaceMovesWithModuleOffsetSoTheGlyphStaysCentered() throws {
        let action = NavigationAction(id: "detail", title: "详情",
            navButton: .init(normal: .init(size: .preferred(CGSize(width: 44, height: 44)),
                                           iconSize: CGSize(width: 20, height: 20),
                                           contentInsets: .init(top: 0, leading: 4, bottom: 0, trailing: 4),
                                           effect: .material(.systemGlass))),
            icon: .systemSymbol("arrow.right")) {}
        let host = ShellNavButtonHost()
        host.update(action: action, textStyle: .init()) {}
        host.bounds.size = host.preferredVisualSize
        for offset in [0, 6, -6] as [CGFloat] {
            host.setModuleVisualOffset(offset, vertical: false)
            host.layoutIfNeeded()
            let surface = try XCTUnwrap(surface(in: host))
            let glyph = try XCTUnwrap(host.imageView)
            let surfaceCenter = CGPoint(x: surface.frame.midX, y: surface.frame.midY)
            let glyphCenter = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)
            XCTAssertEqual(surfaceCenter.x, glyphCenter.x, accuracy: 0.5, "offset=\(offset)")
            XCTAssertEqual(surfaceCenter.y, glyphCenter.y, accuracy: 0.5, "offset=\(offset)")
            // 表面跟着模块视觉偏移移动，可见边界才会等于按钮表面。
            XCTAssertEqual(surface.frame.minX, offset, accuracy: 0.5)
            XCTAssertEqual(host.moduleVisualBounds.minX, offset, accuracy: 0.5)
            XCTAssertEqual(host.moduleVisualBounds.width, 44, accuracy: 0.5)
        }
    }

    func testTitleAndIconStayInsideTheirSurfaceAtEveryOffset() throws {
        // 文字按钮和图标按钮都必须在表面内，不能被模块间距归零推到边缘之外。
        let text = NavigationAction(id: "done", title: "完成",
            navButton: .init(normal: .init(effect: .material(.systemGlass)))) {}
        let icon = NavigationAction(id: "detail", title: "详情",
            navButton: .init(normal: .init(size: .preferred(CGSize(width: 44, height: 44)),
                                           iconSize: CGSize(width: 20, height: 20),
                                           effect: .material(.systemGlass))),
            icon: .systemSymbol("arrow.right")) {}
        for action in [text, icon] {
            let host = ShellNavButtonHost()
            host.update(action: action, textStyle: .init()) {}
            host.bounds.size = host.preferredVisualSize
            for offset in [0, 12, -12] as [CGFloat] {
                host.setModuleVisualOffset(offset, vertical: false)
                host.layoutIfNeeded()
                let surface = try XCTUnwrap(surface(in: host))
                let glyph = try XCTUnwrap(host.imageView)
                let label = try XCTUnwrap(host.titleLabel)
                let content = label.text?.isEmpty == false ? label.frame : glyph.frame
                XCTAssertGreaterThanOrEqual(content.minX, surface.frame.minX - 0.5,
                                            "\(action.id) offset=\(offset) content=\(content) surface=\(surface.frame)")
                XCTAssertLessThanOrEqual(content.maxX, surface.frame.maxX + 0.5,
                                         "\(action.id) offset=\(offset) content=\(content) surface=\(surface.frame)")
                // 文字宽度必须完整保留，不能被压缩成省略号式的窄框。
                if label.text?.isEmpty == false {
                    let needed = ceil((label.text! as NSString).size(withAttributes: [.font: label.font]).width)
                    XCTAssertGreaterThanOrEqual(content.width, needed - 0.5)
                }
            }
        }
    }


    func testEveryTitleAndGlyphStayCenteredInTheirSurfaceInsideARealBar() throws {
        // 真实导航栏里三个模块会触发间距归一化（表面随模块边界平移），
        // 文字与图标必须始终相对各自表面居中，不能被推到表面之外。
        let page = RealBarPage()
        let nav = BoneNavigationController(rootViewController: page)
        nav.barPresentation = .system
        nav.loadViewIfNeeded()
        page.loadViewIfNeeded()
        page.view.bounds.size = CGSize(width: 393, height: 700)
        page.refreshScreenConfiguration()
        var items: [UIBarButtonItem] = page.navigationItem.rightBarButtonItems ?? []
        if #available(iOS 27.0, *) {
            items = page.navigationItem.trailingItemGroups.flatMap(\.barButtonItems)
                + (page.navigationItem.pinnedTrailingGroup?.barButtonItems ?? [])
        }
        var checked = 0
        for item in items {
            guard let cluster = item.customView as? ShellNavButtonCluster else { continue }
            cluster.layoutIfNeeded()
            for button in cluster.buttons {
                button.layoutIfNeeded()
                guard let surface = button.subviews.compactMap({ $0 as? ShellGlassView }).first,
                      !surface.isHidden else { continue }
                if let label = button.titleLabel, let text = label.text, !text.isEmpty, !label.frame.isEmpty {
                    let title = label.frame
                    XCTAssertEqual(title.midX, surface.frame.midX, accuracy: 0.5,
                                   "\(button.actionID): title=\(title) surface=\(surface.frame)")
                    XCTAssertGreaterThanOrEqual(title.minX, surface.frame.minX - 0.5)
                    XCTAssertLessThanOrEqual(title.maxX, surface.frame.maxX + 0.5)
                    // 标题必须按需求宽度完整排布，不能被压缩成省略号。
                    let needed = ceil((text as NSString).size(
                        withAttributes: [.font: label.font ?? UIFont.preferredFont(forTextStyle: .body)]).width)
                    XCTAssertGreaterThanOrEqual(title.width - 8, needed - 0.5)
                    // 标题在自身 label 内也必须居中，否则会在一侧贴边。
                    let textRect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: 1)
                    XCTAssertEqual(textRect.midX, label.bounds.midX, accuracy: 0.5,
                                   "\(button.actionID): textRect=\(textRect) label=\(label.bounds)")
                    checked += 1
                }
                if let glyph = button.imageView, !glyph.frame.isEmpty {
                    XCTAssertEqual(glyph.frame.midX, surface.frame.midX, accuracy: 0.5)
                    XCTAssertEqual(glyph.frame.midY, surface.frame.midY, accuracy: 0.5)
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "Expected at least one rendered title or glyph")
        withExtendedLifetime(nav) {}
    }

    private func surface(in host: ShellNavButtonHost) -> ShellGlassView? {
        host.subviews.compactMap { $0 as? ShellGlassView }.first
    }

    private func effectViews(in host: ShellNavButtonHost) -> [UIVisualEffectView] {
        surface(in: host)?.subviews.compactMap { $0 as? UIVisualEffectView } ?? []
    }
}

private final class PartialSizeView: UIView {
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: 8, height: 14) }
}

@MainActor
private final class RealBarPage: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.barPresentation = .system
        screen.navigation.title = "导航栏"
        func style(_ width: CGFloat?) -> ShellNavButton.Style {
            .init(size: width.map { .preferred(CGSize(width: $0, height: 44)) } ?? .fitting,
                  contentInsets: .init(top: 0, leading: 4, bottom: 0, trailing: 4),
                  effect: .material(.systemGlass))
        }
        let done = NavigationAction(id: "done", title: "完成", navButton: .init(normal: style(72)),
                                    priority: 30, role: .confirmation) {}
        let detail = NavigationAction(id: "detail", title: "详情", navButton: .init(normal: style(44)),
                                      icon: .systemSymbol("arrow.right"), priority: 20) {}
        let icons = ShellNavButton(normal: style(44))
        let group = NavigationButtonGroup(id: "tools", actions: [
            NavigationAction(id: "mark", title: "标记", navButton: icons,
                             icon: .systemSymbol("bookmark"), priority: 10) {},
            NavigationAction(id: "share", title: "分享", navButton: icons,
                             icon: .systemSymbol("square.and.arrow.up"), priority: 10) {}
        ], itemSpacing: 8, material: .systemGlass)
        screen.navigation.moduleSpacing = 8
        screen.navigation.trailingModules = [.group(group), .button(detail), .button(done)]
    }
}
