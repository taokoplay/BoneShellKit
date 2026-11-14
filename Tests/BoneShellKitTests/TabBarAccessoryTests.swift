import XCTest
import UIKit
@testable import BoneShellKit

@MainActor
final class TabBarAccessoryTests: XCTestCase {
    func testClassicAccessoriesSitInsideTheBarEnds() {
        let tabs = makeTabs()
        var actions: [String] = []
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.avatar", icon: .systemSymbol("person.crop.circle"),
                                 position: .leading) { actions.append("avatar") },
            ShellTabBarAccessory(id: "accessory.plus", icon: .systemSymbol("plus"),
                                 position: .trailing) { actions.append("plus") }
        ]
        tabs.barPresentation = .classic
        tabs.view.layoutIfNeeded()

        guard let bar = tabs.classicTabBarView else { return XCTFail("Classic bar should be visible") }
        XCTAssertEqual(tabs.leadingAccessoryButtons.count, 1)
        XCTAssertEqual(tabs.trailingAccessoryButtons.count, 1)
        let leading = try! XCTUnwrap(tabs.leadingAccessoryButtons.first)
        let trailing = try! XCTUnwrap(tabs.trailingAccessoryButtons.first)
        // The classic bar keeps its edge-to-edge surface; buttons sit inside its two ends.
        XCTAssertEqual(bar.frame.width, tabs.view.bounds.width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(leading.frame.minX, bar.frame.minX)
        XCTAssertLessThanOrEqual(trailing.frame.maxX, bar.frame.maxX)
        let contentHeight = (bar as? ShellClassicTabBar)?.contentHeight ?? bar.bounds.height
        XCTAssertEqual(leading.frame.midY, bar.frame.minY + contentHeight / 2, accuracy: 1)
        XCTAssertEqual(trailing.frame.midY, bar.frame.minY + contentHeight / 2, accuracy: 1)
        // Tabs start after the leading button and stop before the trailing one.
        let tabsOnly = bar.accessibilityElements as? [UIView] ?? []
        XCTAssertEqual(tabsOnly.count, 3)
        XCTAssertGreaterThanOrEqual(tabsOnly[0].frame.minX, leading.frame.maxX - 0.5)
        // Inside-the-bar buttons must be drawn above the bar, not hidden behind it.
        if let barView = tabs.classicTabBarView, let superview = barView.superview {
            let barIndex = superview.subviews.firstIndex(of: barView) ?? 0
            let buttonIndex = superview.subviews.firstIndex(of: leading) ?? 0
            XCTAssertGreaterThan(buttonIndex, barIndex)
        }
        XCTAssertLessThanOrEqual(tabsOnly[2].frame.maxX, trailing.frame.minX + 0.5)

        (leading as? UIButton)?.sendActions(for: .touchUpInside)
        (trailing as? UIButton)?.sendActions(for: .touchUpInside)
        XCTAssertEqual(actions, ["avatar", "plus"])
        XCTAssertEqual(tabs.selectedIndex, 0, "Accessories are actions, not destinations")
    }

    func testCapsuleAccessoriesSitOutsideTheFloatingCapsule() {
        // Below iOS 26 the capsule is SDK-drawn, so buttons can sit beside it.
        ShellBarPresentation.capabilityOverride = false
        defer { ShellBarPresentation.capabilityOverride = nil }
        let tabs = makeTabs()
        var fired = 0
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.avatar", icon: .systemSymbol("person.crop.circle"),
                                 position: .leading) { fired += 1 }
        ]
        tabs.barPresentation = .capsule
        tabs.view.layoutIfNeeded()
        guard let capsule = tabs.capsuleTabBarView else {
            return XCTFail("Accessories force the SDK capsule renderer so space can be reserved")
        }
        let leading = try! XCTUnwrap(tabs.leadingAccessoryButtons.first)
        XCTAssertEqual(leading.frame.width, leading.frame.height, accuracy: 0.5,
                       "Beside the capsule the accessory stays a circular glyph")
        XCTAssertLessThanOrEqual(leading.frame.maxX, capsule.frame.minX + 0.5)
        XCTAssertLessThan(capsule.frame.maxX, tabs.view.bounds.maxX)
        XCTAssertEqual(leading.frame.midY, capsule.frame.midY, accuracy: 1)
        XCTAssertEqual(leading.frame.width, leading.frame.height, accuracy: 0.5, "Accessory renders as a circle")
        XCTAssertEqual((leading as? ShellTabAccessoryButton)?.blurStyle, .systemChromeMaterial,
                       "The capsule keeps its own chrome material for accessories")
        XCTAssertEqual(leading.frame.height, capsule.frame.height, accuracy: 0.5)
        XCTAssertEqual(leading.layer.shadowOpacity, capsule.layer.shadowOpacity)
        XCTAssertEqual(leading.layer.shadowRadius, capsule.layer.shadowRadius)
        XCTAssertEqual(leading.layer.shadowOffset, capsule.layer.shadowOffset)
        XCTAssertEqual(leading.layer.shadowColor, capsule.layer.shadowColor)
        XCTAssertFalse(leading.clipsToBounds, "Compatibility shadows must remain visible outside the surface")
        for element in capsule.accessibilityElements as? [UIView] ?? [] {
            XCTAssertTrue(capsule.bounds.intersects(element.frame))
        }
        (leading as? UIButton)?.sendActions(for: .touchUpInside)
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(tabs.selectedIndex, 0)
    }

    func testNativeAccessoryUsesSystemSlotOnIOS26() {
        ShellTabBarAccessoryHosting.slotOverride = true
        defer { ShellTabBarAccessoryHosting.slotOverride = nil }
        let tabs = makeTabs()
        tabs.barPresentation = .system
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.slot", icon: .systemSymbol("plus"), position: .trailing) { }
        ]
        tabs.view.layoutIfNeeded()
        XCTAssertTrue(tabs.supportsTabBarAccessories)
        if #available(iOS 26.0, *) {
            XCTAssertEqual(tabs.nativeTabAccessoryView?.accessibilityIdentifier, "shell.tabs.accessories")
            // The slot does not touch the destination list.
            XCTAssertEqual(tabs.viewControllers?.count, 3)
            XCTAssertNil(tabs.leadingAccessoryButtons.first)
        }
        tabs.tabBarAccessories = []
        tabs.view.layoutIfNeeded()
        XCTAssertNil(tabs.nativeTabAccessoryView)
    }

    func testCapsuleAccessoriesUseTheDockOnIOS26() {
        let tabs = makeTabs()
        var fired = 0
        tabs.barPresentation = .capsule
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.dock", icon: .systemSymbol("magnifyingglass"),
                                 position: .trailing) { fired += 1 }
        ]
        tabs.view.layoutIfNeeded()

        if ShellBarPresentation.supportsNativeCapsule {
            // iOS 26+: a real UITabBar plus a circular button, like the system search dock.
            guard let dock = tabs.dockBarView as? ShellNativeDockBar else {
                return XCTFail("Capsule accessories should use the dock on iOS 26")
            }
            XCTAssertEqual(dock.tabBar.items?.count, 3, "The dock keeps every destination")
            XCTAssertNotNil(dock.tabBar.superview, "The system bar is hosted inside the dock row")
            XCTAssertNil(tabs.capsuleTabBarView, "No SDK capsule is drawn when the dock is used")
            // The destination list stays untouched.
            XCTAssertEqual(tabs.viewControllers?.count, 3)
            let button = try! XCTUnwrap(find("accessory.dock", in: dock) as? UIButton)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(fired, 1, "One touch invokes the action exactly once")
            let host = dock.tabBar.superview
            tabs.selectedIndex = 2
            tabs.refreshBarPresentation()
            tabs.view.layoutIfNeeded()
            XCTAssertTrue(find("accessory.dock", in: dock) === button,
                          "A selection or style refresh must not rebuild an in-flight touch target")
            XCTAssertTrue(dock.tabBar.superview === host)
            XCTAssertTrue(dock.tabBar.selectedItem === dock.tabBar.items?[2])
        } else {
            XCTAssertNotNil(tabs.capsuleTabBarView)
        }
    }

    func testNativeAccessoryUsesTabItemsBelowIOS26() {
        ShellTabBarAccessoryHosting.slotOverride = false
        defer { ShellTabBarAccessoryHosting.slotOverride = nil }
        let tabs = makeTabs()
        tabs.barPresentation = .system
        tabs.selectedIndex = 1
        var actions: [String] = []
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.left", icon: .systemSymbol("person.crop.circle"),
                                 position: .leading) { actions.append("left") },
            ShellTabBarAccessory(id: "accessory.right", icon: .systemSymbol("plus"),
                                 position: .trailing) { actions.append("right") }
        ]
        tabs.view.layoutIfNeeded()

        // UIKit arranges them itself: leading first, trailing last.
        let controllers = try! XCTUnwrap(tabs.viewControllers)
        XCTAssertEqual(controllers.count, 5)
        XCTAssertEqual(controllers.first?.tabBarItem.accessibilityIdentifier, "accessory.left")
        XCTAssertEqual(controllers.last?.tabBarItem.accessibilityIdentifier, "accessory.right")
        XCTAssertEqual(tabs.selectedIndex, 2, "Accessory items do not shift the current tab")

        // Selecting an accessory runs the action instead of switching pages.
        let leading = try! XCTUnwrap(controllers.first)
        let allowed = tabs.tabBarController(tabs, shouldSelect: leading)
        XCTAssertFalse(allowed)
        XCTAssertEqual(actions, ["left"])
        XCTAssertEqual(tabs.selectedIndex, 2)
        XCTAssertEqual(tabs.selectedViewController, controllers[2])

        tabs.tabBarAccessories = []
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 3)
        XCTAssertEqual(tabs.viewControllers?.first?.tabBarItem.accessibilityIdentifier, "tab.one")
        XCTAssertEqual(tabs.selectedIndex, 1)
    }

    func testAccessoryStateSurvivesRenderingSwitch() {
        ShellTabBarAccessoryHosting.slotOverride = false
        defer { ShellTabBarAccessoryHosting.slotOverride = nil }
        let tabs = makeTabs()
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.left", icon: .systemSymbol("person.crop.circle"),
                                 position: .leading) { }
        ]
        tabs.barPresentation = .classic
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(tabs.leadingAccessoryButtons.count, 1)
        XCTAssertEqual(tabs.viewControllers?.count, 3, "Self-drawn bars keep the destination list clean")

        tabs.barPresentation = .system
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 4, "Native bars add the accessory as an item")
        XCTAssertTrue(tabs.leadingAccessoryButtons.isEmpty)

        tabs.barPresentation = .classic
        tabs.view.layoutIfNeeded()
        XCTAssertEqual(tabs.viewControllers?.count, 3)
        XCTAssertEqual(tabs.leadingAccessoryButtons.count, 1)
    }

    func testTitledAccessoryBecomesPillWithMaterialBackdrop() {
        let tabs = makeTabs()
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.write", icon: .systemSymbol("square.and.pencil"),
                                 title: "写", position: .leading) { }
        ]
        tabs.barPresentation = .classic
        tabs.view.layoutIfNeeded()
        let button = try! XCTUnwrap(tabs.leadingAccessoryButtons.first)
        XCTAssertGreaterThan(button.bounds.width, button.bounds.height,
                             "A titled accessory widens into a pill so the caption fits")
        XCTAssertTrue(button.subviews.contains { $0 is UIVisualEffectView || ($0 is UIView && $0.backgroundColor != nil) })
        // The caption keeps the bar readable instead of drawing a bare glyph.
        let labels = button.subviews.compactMap { $0 as? UILabel }
        let caption = labels.first { $0.text == "写" }
        XCTAssertNotNil(caption, "The accessory shows its title")
        XCTAssertEqual(caption?.frame.height ?? 0, ceil(caption?.font.lineHeight ?? 0), accuracy: 1)
        // The caption must not be squeezed into an ellipsis by the pill geometry.
        let captionWidth = caption?.frame.width ?? 0
        XCTAssertGreaterThanOrEqual(captionWidth, ceil(caption?.intrinsicContentSize.width ?? 0) - 0.5)
        XCTAssertFalse(caption?.text?.isEmpty ?? true)
        // Inside the classic bar the button uses the bar's surface and draws no background.
        XCTAssertEqual((button as? ShellTabAccessoryButton)?.hasOwnBackdrop, false)
    }

    func testClassicAccessoryOccupiesOneTabSlot() {
        let tabs = makeTabs()
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.plus", icon: .systemSymbol("plus"),
                                 position: .trailing) { }
        ]
        tabs.barPresentation = .classic
        tabs.view.layoutIfNeeded()
        let button = try! XCTUnwrap(tabs.trailingAccessoryButtons.first)
        // Three destinations plus one accessory split the classic bar into four equal slots.
        XCTAssertEqual((tabs.classicTabBarView?.bounds.width ?? 0) / 4, button.bounds.width, accuracy: 0.5)
        XCTAssertNotEqual(button.bounds.width, button.bounds.height)
    }

    /// Renders each compatibility bar and compares its accessory surface with the bar's.
    func testAccessorySurfaceMatchesItsBar() {
        for style in ["classic", "capsule"] {
            if style == "capsule" { ShellBarPresentation.capabilityOverride = false }
            defer { ShellBarPresentation.capabilityOverride = nil }
            let tabs = makeTabs()
            tabs.tabBarAccessories = [
                ShellTabBarAccessory(id: "accessory.write", icon: .systemSymbol("square.and.pencil"),
                                     title: "写", position: .leading) { },
                ShellTabBarAccessory(id: "accessory.search", icon: .systemSymbol("magnifyingglass"),
                                     title: "搜索", position: .trailing) { }
            ]
            tabs.barPresentation = style == "classic" ? .classic : .capsule
            tabs.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(bounds: tabs.view.bounds)
            let image = renderer.image { _ in
                tabs.view.drawHierarchy(in: tabs.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Accessory bar \(style)"
            attachment.lifetime = .keepAlways
            add(attachment)

            guard let bar = style == "classic" ? tabs.classicTabBarView : tabs.capsuleTabBarView,
                  let leading = tabs.leadingAccessoryButtons.first,
                  let button = leading as? ShellTabAccessoryButton else {
                return XCTFail("Missing bar or accessory for \(style)")
            }
            // Most common colour inside each surface: the background dominates, glyphs do not.
            guard let barColor = dominantColor(of: bar, in: tabs.view, image: image),
                  let buttonColor = dominantColor(of: button, in: tabs.view, image: image) else {
                return XCTFail("Could not sample \(style) pixels")
            }
            let perChannel = max(abs(barColor.r - buttonColor.r),
                                 abs(barColor.g - buttonColor.g),
                                 abs(barColor.b - buttonColor.b))
            XCTAssertLessThanOrEqual(perChannel, 6,
                                     "\(style) accessory surface differs from its bar by \(perChannel)/255 per channel")
        }
    }

    /// Most frequent colour in the view's area, sampled 3 pt inside its edges.
    private func dominantColor(of view: UIView, in container: UIView, image: UIImage) -> (r: Int, g: Int, b: Int)? {
        guard let cg = image.cgImage else { return nil }
        let scale = CGFloat(cg.width) / max(1, image.size.width)
        let frame = view.convert(view.bounds, to: container).insetBy(dx: 3, dy: 3)
        guard frame.width > 1, frame.height > 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let minX = Int(frame.minX * scale), minY = Int(frame.minY * scale)
        let width = max(1, Int(frame.width * scale)), height = max(1, Int(frame.height * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: -minX, y: -(cg.height - height - minY), width: cg.width, height: cg.height))
        var counts: [Int: Int] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let key = (Int(pixels[index]) << 16) | (Int(pixels[index + 1]) << 8) | Int(pixels[index + 2])
            counts[key, default: 0] += 1
        }
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return ((best >> 16) & 0xFF, (best >> 8) & 0xFF, best & 0xFF)
    }

    func testDockLaysOutSystemBarBesideTheCirclesWithoutOverlap() throws {
        guard ShellBarPresentation.supportsNativeCapsule else { throw XCTSkip("Dock requires iOS 26") }
        let tabs = makeTabs()
        tabs.barPresentation = .automatic
        tabs.view.layoutIfNeeded()
        tabs.tabBar.layoutIfNeeded()
        let nativeSurface = try XCTUnwrap(tabs.tabBar.subviews.filter {
            !$0.isHidden && $0.bounds.width > 0 && $0.bounds.height >= 44
                && $0.frame.width < tabs.tabBar.bounds.width - 0.5
                && abs($0.frame.midX - tabs.tabBar.bounds.midX) < 1
        }.max(by: { $0.frame.width < $1.frame.width }))
        let nativeCapsule = nativeSurface.convert(nativeSurface.bounds, to: tabs.view)
        let left = ShellTabBarAccessory(id: "accessory.left", icon: .systemSymbol("square.and.pencil"),
                                        position: .leading) { }
        let right = ShellTabBarAccessory(id: "accessory.right", icon: .systemSymbol("magnifyingglass"),
                                         position: .trailing) { }
        for accessories in [[left], [right], [left, right]] {
            tabs.tabBarAccessories = accessories
            let dock = try settleDock(in: tabs)
            let host = try XCTUnwrap(dock.tabBar.superview as? ShellDockTabHost)
            let capsule = dock.convert(host.capsuleFrame, from: host)
            let screenCapsule = dock.convert(capsule, to: tabs.view)
            XCTAssertEqual(screenCapsule.minY, nativeCapsule.minY, accuracy: 1,
                           "Accessories must not lift the capsule above UIKit's own position")
            XCTAssertEqual(screenCapsule.maxY, nativeCapsule.maxY, accuracy: 1)
            XCTAssertGreaterThanOrEqual(capsule.height, 44, "The visible capsule must fit glyphs and full captions")
            XCTAssertEqual(capsule.width, host.bounds.width, accuracy: 1, "The host hugs the visible surface")
            let nativeFrame = dock.tabBar.frame
            dock.setNeedsLayout()
            dock.layoutIfNeeded()
            XCTAssertEqual(dock.tabBar.frame, nativeFrame, "Reading or repeating layout must not shrink the fitted bar")

            for item in accessories {
                let button = try XCTUnwrap(find(item.id, in: dock))
                let frame = dock.convert(button.bounds, from: button)
                XCTAssertEqual(frame.width, dock.rowHeight, accuracy: 0.5)
                XCTAssertEqual(frame.width, frame.height, accuracy: 0.5)
                XCTAssertEqual(frame.height, capsule.height, accuracy: 0.5, "Circle and visible capsule must be equally tall")
                XCTAssertEqual(frame.minY, capsule.minY, accuracy: 0.5)
                XCTAssertEqual(frame.maxY, capsule.maxY, accuracy: 0.5)
                XCTAssertFalse(button.clipsToBounds, "The system glass shadow must not be clipped")
                let visibleGap = item.position == .leading ? capsule.minX - frame.maxX : frame.minX - capsule.maxX
                XCTAssertEqual(visibleGap, ShellNativeDockBar.gap, accuracy: 1, "Measure the final capsule, not an intermediate proposal")
                let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: tabs.view)
                let hit = try XCTUnwrap(tabs.view.hitTest(point, with: nil))
                XCTAssertTrue(hit === button || hit.isDescendant(of: button), "The native bar's transparent area must not steal accessory taps")
                let gapX = item.position == .leading ? frame.maxX + visibleGap / 2 : capsule.maxX + visibleGap / 2
                XCTAssertNil(dock.hitTest(CGPoint(x: gapX, y: dock.rowHeight / 2), with: nil),
                             "Transparent gaps must pass scroll gestures to the list underneath")
            }
            for label in visibleLabels(in: dock.tabBar) where ["一", "二", "三"].contains(label.text ?? "") {
                let frame = dock.convert(label.bounds, from: label)
                XCTAssertGreaterThanOrEqual(frame.minY, capsule.minY - 1)
                XCTAssertLessThanOrEqual(frame.maxY, capsule.maxY + 1, "Tab captions must remain fully inside the capsule")
            }
        }
    }

    func testLeavingDockRemovesItsViewsAndPreservesSelection() throws {
        guard ShellBarPresentation.supportsNativeCapsule else { throw XCTSkip("Dock requires iOS 26") }
        let tabs = makeTabs()
        tabs.selectedIndex = 1
        let selected = tabs.selectedViewController
        let action = ShellTabBarAccessory(id: "accessory.left", icon: .systemSymbol("plus"), position: .leading) { }
        for target in [ShellBarPresentation.system, .classic, .capsule] {
            tabs.barPresentation = .automatic
            tabs.tabBarAccessories = [action]
            tabs.view.layoutIfNeeded()
            let dock = try XCTUnwrap(tabs.dockBarView)
            tabs.barPresentation = target
            tabs.tabBarAccessories = []
            tabs.view.layoutIfNeeded()
            XCTAssertNil(dock.superview, "Leaving the dock must remove its bar and circular buttons")
            XCTAssertNil(find("shell.dock.row", in: tabs.view))
            XCTAssertNil(find("accessory.left", in: tabs.view))
            XCTAssertTrue(tabs.selectedViewController === selected)
            XCTAssertEqual(tabs.viewControllers?.count, 3)
        }
    }

    func testReplacingOnlyTheHandlerKeepsControlsAndUsesTheLatestAction() throws {
        defer {
            ShellBarPresentation.capabilityOverride = nil
            ShellTabBarAccessoryHosting.slotOverride = nil
        }
        let cases: [(ShellBarPresentation, Bool?, Bool?)] = [
            (.classic, nil, nil), (.capsule, false, nil), (.capsule, nil, nil),
            (.system, nil, true), (.system, nil, false)
        ]
        for (presentation, capability, slot) in cases {
            ShellBarPresentation.capabilityOverride = capability
            ShellTabBarAccessoryHosting.slotOverride = slot
            let tabs = makeTabs()
            tabs.barPresentation = presentation
            var calls: [Int] = []
            func accessory(_ value: Int) -> ShellTabBarAccessory {
                ShellTabBarAccessory(id: "accessory.live", icon: .systemSymbol("plus"),
                                     position: .leading, accessibilityLabel: "新建") { calls.append(value) }
            }
            tabs.tabBarAccessories = [accessory(1)]
            let selected = tabs.selectedViewController
            let placeholder = tabs.viewControllers?.first { $0.tabBarItem.accessibilityIdentifier == "accessory.live" }
            let surface = tabs.nativeTabAccessoryView ?? tabs.view!
            let button = find("accessory.live", in: surface) as? UIButton

            tabs.tabBarAccessories = [accessory(2)]
            if let placeholder = placeholder {
                XCTAssertTrue(tabs.viewControllers?.contains(where: { $0 === placeholder }) == true)
                XCTAssertFalse(tabs.tabBarController(tabs, shouldSelect: placeholder))
            } else {
                let button = try XCTUnwrap(button)
                XCTAssertTrue(find("accessory.live", in: surface) === button)
                button.sendActions(for: .touchUpInside)
            }
            XCTAssertEqual(calls, [2], "A callback-only replacement must take effect immediately")
            XCTAssertTrue(tabs.selectedViewController === selected)

            var renamed = tabs.tabBarAccessories[0]
            renamed.accessibilityLabel = "更新后的操作"
            tabs.tabBarAccessories = [renamed]
            if let item = tabs.viewControllers?.first(where: { $0.tabBarItem.accessibilityIdentifier == renamed.id }) {
                XCTAssertEqual(item.tabBarItem.accessibilityLabel, renamed.accessibilityLabel)
            } else {
                let updatedSurface = tabs.nativeTabAccessoryView ?? tabs.view!
                XCTAssertEqual(find(renamed.id, in: updatedSurface)?.accessibilityLabel, renamed.accessibilityLabel)
            }
        }
    }

    func testClearingDockAccessoriesReleasesCapturedObjects() throws {
        guard ShellBarPresentation.supportsNativeCapsule else { throw XCTSkip("Dock requires iOS 26") }
        let tabs = makeTabs()
        tabs.barPresentation = .capsule
        weak var captured: NSObject?
        do {
            let object = NSObject()
            captured = object
            tabs.tabBarAccessories = [
                ShellTabBarAccessory(id: "accessory.capture", icon: .systemSymbol("plus"),
                                     position: .trailing) { _ = object.description }
            ]
        }
        XCTAssertNotNil(tabs.dockBarView)
        XCTAssertNotNil(captured)
        tabs.tabBarAccessories = []
        XCTAssertNil(captured, "A cached dock must not retain a removed business callback")
    }

    func testDockInheritsAndUpdatesNativeTextAppearance() throws {
        guard ShellBarPresentation.supportsNativeCapsule else { throw XCTSkip("Dock requires iOS 26") }
        let tabs = makeTabs()
        tabs.barPresentation = .capsule
        let image = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { _ in
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 22, height: 22)).fill()
        }
        for (id, title) in [("one", "示例"), ("two", "材质"), ("three", "关于")] {
            _ = tabs.updateTabItem(id: id, configuration: ShellTabItemConfiguration(
                title: title, icon: .image(image), selectedIcon: .image(image), selectedIconMode: .selectedImage))
        }
        tabs.tabBarStyle = ShellTabBarStyle(
            normal: ShellTextStyle(size: 14, color: .systemRed),
            selected: ShellTextStyle(size: 14, color: .systemPurple),
            normalIconColor: .systemRed, selectedIconColor: .systemPurple)
        tabs.tabBarAccessories = [
            ShellTabBarAccessory(id: "accessory.style.left", icon: .systemSymbol("plus"), position: .leading) { },
            ShellTabBarAccessory(id: "accessory.style", icon: .systemSymbol("plus"), position: .trailing) { }
        ]
        let dock = try XCTUnwrap(tabs.dockBarView as? ShellNativeDockBar)
        func assertStyle(_ appearance: UITabBarAppearance?) throws {
            let appearance = try XCTUnwrap(appearance)
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                           appearance.compactInlineLayoutAppearance] {
                XCTAssertEqual((layout.normal.titleTextAttributes[.font] as? UIFont)?.pointSize, 14)
                XCTAssertEqual((layout.selected.titleTextAttributes[.font] as? UIFont)?.pointSize, 14)
                XCTAssertEqual(layout.normal.titleTextAttributes[.foregroundColor] as? UIColor, .systemRed)
                XCTAssertEqual(layout.selected.titleTextAttributes[.foregroundColor] as? UIColor, .systemPurple)
            }
        }
        try assertStyle(dock.tabBar.standardAppearance)
        try assertStyle(dock.tabBar.scrollEdgeAppearance)
        _ = try settleDock(in: tabs)
        XCTAssertEqual(dock.tabBar.safeAreaInsets.bottom, dock.window?.safeAreaInsets.bottom ?? 0, accuracy: 0.5)
        let host = try XCTUnwrap(dock.tabBar.superview as? ShellDockTabHost)
        let capsule = dock.convert(host.capsuleFrame, from: host)
        let captions = visibleLabels(in: dock.tabBar).filter { ["示例", "材质", "关于"].contains($0.text ?? "") }
        XCTAssertGreaterThanOrEqual(captions.count, 3)
        for label in captions {
            let frame = dock.convert(label.bounds, from: label)
            XCTAssertGreaterThanOrEqual(label.bounds.height, label.font.lineHeight - 0.5,
                                        "A caption must retain its full font line height")
            XCTAssertLessThanOrEqual(frame.maxY, capsule.maxY + 1,
                "Styled caption \(label.text ?? "") at \(frame), capsule \(capsule), bar \(dock.tabBar.frame), safe \(dock.tabBar.safeAreaInsets), font \(label.font.pointSize)")
        }
        tabs.tabBarStyle = ShellTabBarStyle()
        XCTAssertTrue(tabs.dockBarView === dock, "Style refreshes retain the live dock")
        let restored = dock.tabBar.standardAppearance.stackedLayoutAppearance
        let expected = tabs.tabBar.standardAppearance.stackedLayoutAppearance
        for (actual, reference) in [(restored.normal, expected.normal), (restored.selected, expected.selected)] {
            XCTAssertEqual(actual.titleTextAttributes[.font] as? UIFont, reference.titleTextAttributes[.font] as? UIFont)
            XCTAssertEqual(actual.titleTextAttributes[.foregroundColor] as? UIColor,
                           reference.titleTextAttributes[.foregroundColor] as? UIColor)
        }
        XCTAssertNil(dock.tabBar.scrollEdgeAppearance)
    }

    private func visibleLabels(in root: UIView) -> [UILabel] {
        guard !root.isHidden, root.alpha > 0.01 else { return [] }
        return (root as? UILabel).map { [$0] } ?? root.subviews.flatMap { visibleLabels(in: $0) }
    }

    private func find(_ identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier { return root }
        for child in root.subviews {
            if let match = find(identifier, in: child) { return match }
        }
        return nil
    }

    private func settleDock(in tabs: BoneTabBarController) throws -> ShellNativeDockBar {
        tabs.view.layoutIfNeeded()
        let dock = try XCTUnwrap(tabs.dockBarView as? ShellNativeDockBar)
        dock.layoutIfNeeded()
        let host = try XCTUnwrap(dock.tabBar.superview as? ShellDockTabHost)
        let predicate = NSPredicate { _, _ in
            host.capsuleFrame.height > 0 && abs(dock.rowHeight - host.capsuleFrame.height) <= 0.5
                && dock.nativeBottomPadding != nil
        }
        let settled = XCTNSPredicateExpectation(predicate: predicate, object: dock)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 2), .completed)
        tabs.view.layoutIfNeeded()
        dock.layoutIfNeeded()
        XCTAssertNotNil(dock.nativeBottomPadding)
        return dock
    }

    // MARK: - Helpers

    private func makeTabs() -> BoneTabBarController {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "one", title: "一", symbol: "circle", root: AccessoryFixture()),
            ShellTab(id: "two", title: "二", symbol: "square", root: AccessoryFixture()),
            ShellTab(id: "three", title: "三", symbol: "triangle", root: AccessoryFixture())
        ])
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        tabs.loadViewIfNeeded()
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.layoutIfNeeded()
        windows.append(window)
        return tabs
    }

    override func tearDown() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
        super.tearDown()
    }

    private var windows: [UIWindow] = []
}

@MainActor
private final class AccessoryFixture: BoneViewController {}
