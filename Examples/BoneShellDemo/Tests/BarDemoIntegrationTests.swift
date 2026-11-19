import XCTest
import UIKit
@testable import BoneShellKit
@testable import BoneShellDemo

@MainActor
final class BarDemoIntegrationTests: XCTestCase {
    // MARK: - Navigation bar scene

    func testNavigationSceneExposesEveryNavigationSetting() {
        let (tabs, navigation, page) = navigationScene()
        XCTAssertEqual(page.screenConfiguration.navigation.title, "导航栏")
        XCTAssertNotNil(page.screenConfiguration.navigation.subtitle)
        XCTAssertNotNil(page.screenConfiguration.navigation.style)
        XCTAssertTrue(navigation.topViewController === page)
        // Text and icon actions live on both sides.
        let items = barButtonItems(in: page.navigationItem)
        XCTAssertFalse(items.trailing.isEmpty)
        XCTAssertFalse(items.leading.isEmpty)
        XCTAssertTrue(tabs.viewControllers?.count == 3)
    }

    func testNavigationSettingChangesApplyWithoutRebuildingContent() {
        let (_, _, page) = navigationScene()
        page.loadViewIfNeeded()
        let identity = page.contentView
        page.setTitleSizeForTesting(24, colorIndex: 2)
        XCTAssertEqual(page.screenConfiguration.navigation.style?.title.font?.pointSize, 24)
        XCTAssertTrue(page.contentView === identity, "Style changes must not rebuild content")
        page.reset()
        XCTAssertNil(page.screenConfiguration.navigation.style?.title.font)
    }

    func testNavButtonControlsConfigureRealActionsAndResetToStandard() throws {
        let (tabs, _, page) = navigationScene()
        defer { withExtendedLifetime(tabs) {} }
        func select(_ key: String, _ index: Int) throws {
            let picker = try XCTUnwrap(view(withIdentifier: "navbutton.\(key)", in: page.view) as? UISegmentedControl)
            picker.selectedSegmentIndex = index
            picker.sendActions(for: .valueChanged)
        }
        try select("mode", 1)
        try select("size", 1)
        try select("vertical", 1)
        try select("group-width", 1)
        try select("order", 1)
        for (index, gap) in [0, 8, 16].enumerated() {
            try select("spacing", index + 1)
            XCTAssertEqual(page.screenConfiguration.navigation.navButtonLayout, .grouped(spacing: CGFloat(gap)))
        }
        for (index, effect) in [ShellNavButton.Effect.none, .blur, .liquidGlass].enumerated() {
            try select("effect", index)
            let actions = page.screenConfiguration.navigation.trailingActions
            XCTAssertEqual(actions.map(\.id), ["nav.share", "nav.mark", "nav.text"])
            let button = try XCTUnwrap(actions.last?.navButton)
            XCTAssertEqual(button.normal.effect, effect)
            XCTAssertEqual(button.normal.size, .preferred(CGSize(width: 56, height: 44)))
            XCTAssertEqual(button.vertical?.size, .preferred(CGSize(width: 44, height: 72)))
        }
        page.reset()
        XCTAssertEqual(page.screenConfiguration.navigation.navButtonLayout, .individual)
        XCTAssertTrue(page.screenConfiguration.navigation.trailingActions.allSatisfy { $0.navButton == nil })
    }

    func testNavigationTitleAndButtonSizesAreIndependent() throws {
        let (_, _, page) = navigationScene()
        let titlePicker = try XCTUnwrap(view(withIdentifier: "nav.title-size", in: page.view) as? UISegmentedControl)
        let buttonPicker = try XCTUnwrap(view(withIdentifier: "nav.button-size", in: page.view) as? UISegmentedControl)
        let steps: [(UISegmentedControl, Int, CGFloat, CGFloat?)] = [
            (titlePicker, 3, 24, nil),
            (buttonPicker, 1, 24, 15),
            (titlePicker, 1, 16, 15),
            (buttonPicker, 0, 16, nil)
        ]
        for (picker, segment, titleSize, buttonSize) in steps {
            picker.selectedSegmentIndex = segment
            picker.sendActions(for: .valueChanged)
            let style = try XCTUnwrap(page.screenConfiguration.navigation.style)
            XCTAssertEqual(style.title.font?.pointSize, titleSize)
            XCTAssertEqual(style.buttons.font?.pointSize, buttonSize)
            let item = try XCTUnwrap(barButtonItems(in: page.navigationItem).trailing.first {
                $0.accessibilityIdentifier == "action.nav.text"
            })
            let appliedFont = item.titleTextAttributes(for: .normal)?[.font] as? UIFont
            XCTAssertEqual(appliedFont, style.buttons.resolvedFont(for: .body, traits: page.traitCollection))
        }
    }

    func testNavigationPresentationOnlyAffectsNavigation() {
        let (tabs, navigation, page) = navigationScene()
        page.loadViewIfNeeded()
        page.setPresentationIndexForTesting(2)
        XCTAssertEqual(navigation.barPresentation, .classic)
        XCTAssertEqual(navigation.resolvedBarPresentation, .classic)
        // The tab bar keeps its own presentation.
        XCTAssertEqual(tabs.barPresentation, .system)
        page.setPresentationIndexForTesting(0)
        XCTAssertNil(navigation.barPresentation)
    }

    func testNavigationIconAndAxisPickersApplyConfigurationAndResolveImages() throws {
        let (tabs, navigation, page) = navigationScene()
        let icons = try XCTUnwrap(view(withIdentifier: "nav.icon", in: page.view) as? UISegmentedControl)
        let axes = try XCTUnwrap(view(withIdentifier: "nav.axis", in: page.view) as? UISegmentedControl)
        let status = try XCTUnwrap(view(withIdentifier: "nav.status", in: page.view) as? UILabel)
        let source = try XCTUnwrap(UIImage(named: "BarStyle-Orbit", in: .main, compatibleWith: page.traitCollection))
        let imageData = try XCTUnwrap(source.pngData())
        let iconNames = ["符号", "本地图片", "UIImage"]
        let axisNames = ["自动", "仅横向", "优先侧边"]
        let behaviors: [ShellNavigationActionAxisBehavior] = [.automatic, .horizontalOnly, .verticalPreferred]
        XCTAssertEqual(icons.numberOfSegments, 3)
        XCTAssertEqual(axes.numberOfSegments, 3)
        XCTAssertEqual(icons.selectedSegmentIndex, 0)
        XCTAssertEqual(axes.selectedSegmentIndex, 0)

        for index in 0..<3 {
            XCTAssertEqual(icons.titleForSegment(at: index), iconNames[index])
            XCTAssertEqual(axes.titleForSegment(at: index), axisNames[index])
            icons.selectedSegmentIndex = index
            icons.sendActions(for: .valueChanged)
            let detail = try XCTUnwrap(page.screenConfiguration.navigation.trailingActions.first { $0.id == "nav.detail" })
            let icon = try XCTUnwrap(detail.icon)
            let resolved = try XCTUnwrap(actionImage(id: "nav.detail", in: page.navigationItem))
            switch icon {
            case .systemSymbol(let name):
                XCTAssertEqual(index, 0)
                XCTAssertEqual(name, "arrow.right")
                XCTAssertTrue(resolved.isSymbolImage)
            case .asset(let name, let bundle):
                XCTAssertEqual(index, 1)
                XCTAssertEqual(name, "BarStyle-Orbit")
                XCTAssertEqual(bundle, .main)
                XCTAssertEqual(try XCTUnwrap(resolved.pngData()), imageData)
            case .image(let image):
                XCTAssertEqual(index, 2)
                XCTAssertEqual(image.renderingMode, .alwaysOriginal)
                XCTAssertEqual(resolved.renderingMode, .alwaysOriginal)
                XCTAssertEqual(try XCTUnwrap(resolved.pngData()), imageData)
            }

            axes.selectedSegmentIndex = index
            axes.sendActions(for: .valueChanged)
            let updated = try XCTUnwrap(page.screenConfiguration.navigation.trailingActions.first { $0.id == "nav.detail" })
            XCTAssertEqual(updated.axisBehavior, behaviors[index])
            XCTAssertTrue(status.text?.contains("图标：\(iconNames[index]) / 方向：\(axisNames[index])") == true)
        }
        XCTAssertTrue(tabs.selectedViewController === navigation)
    }

    func testNavigationResetRestoresIconAndAxisWithoutReplacingContentOrStack() throws {
        let (_, navigation, page) = navigationScene()
        navigation.setViewControllers([UIViewController(), page], animated: false)
        let stack = navigation.viewControllers
        let content = page.contentView
        let rows = page.stack.arrangedSubviews
        let icons = try XCTUnwrap(view(withIdentifier: "nav.icon", in: page.view) as? UISegmentedControl)
        let axes = try XCTUnwrap(view(withIdentifier: "nav.axis", in: page.view) as? UISegmentedControl)
        for (identifier, index) in [
            ("nav.title-size", 3), ("nav.title-color", 2), ("nav.subtitle", 0), ("nav.large-title", 1),
            ("nav.button-size", 3), ("nav.presentation", 2), ("nav.icon", 2), ("nav.axis", 2)
        ] {
            let picker = try XCTUnwrap(view(withIdentifier: identifier, in: page.view) as? UISegmentedControl)
            picker.selectedSegmentIndex = index
            picker.sendActions(for: .valueChanged)
        }
        page.note("重置前")
        XCTAssertEqual(icons.selectedSegmentIndex, 2)
        XCTAssertEqual(axes.selectedSegmentIndex, 2)
        let reset = try XCTUnwrap(view(withIdentifier: "nav.reset", in: page.view) as? UIButton)
        reset.sendActions(for: .touchUpInside)

        XCTAssertNil(page.titleSize)
        XCTAssertEqual(page.colorIndex, 0)
        XCTAssertTrue(page.showsSubtitle)
        XCTAssertFalse(page.usesLargeTitle)
        XCTAssertNil(page.buttonSize)
        XCTAssertEqual(page.presentationIndex, 0)
        XCTAssertNil(navigation.barPresentation)
        XCTAssertNil(page.message)
        XCTAssertNil(page.screenConfiguration.navigation.style?.title.font)
        XCTAssertEqual(icons.selectedSegmentIndex, 0)
        XCTAssertEqual(axes.selectedSegmentIndex, 0)
        let detail = try XCTUnwrap(page.screenConfiguration.navigation.trailingActions.first { $0.id == "nav.detail" })
        XCTAssertEqual(detail.axisBehavior, .automatic)
        guard case .systemSymbol(let name)? = detail.icon else {
            return XCTFail("Reset must restore the original symbol")
        }
        XCTAssertEqual(name, "arrow.right")
        let status = try XCTUnwrap(view(withIdentifier: "nav.status", in: page.view) as? UILabel)
        XCTAssertTrue(status.text?.contains("图标：符号 / 方向：自动") == true)
        XCTAssertTrue(page.contentView === content)
        XCTAssertTrue(view(withIdentifier: "nav.icon", in: page.view) === icons)
        XCTAssertTrue(view(withIdentifier: "nav.axis", in: page.view) === axes)
        XCTAssertEqual(page.stack.arrangedSubviews.count, rows.count)
        for (before, after) in zip(rows, page.stack.arrangedSubviews) { XCTAssertTrue(before === after) }
        XCTAssertEqual(navigation.viewControllers.count, stack.count)
        for (before, after) in zip(stack, navigation.viewControllers) { XCTAssertTrue(before === after) }
        XCTAssertTrue(navigation.topViewController === page)
    }

    func testNavigationActionsUseConfirmationAndCancellationSemantics() throws {
        let (_, navigation, page) = navigationScene()
        let done = try XCTUnwrap(page.screenConfiguration.navigation.trailingActions.first { $0.id == "nav.text" })
        let mark = try XCTUnwrap(page.screenConfiguration.navigation.leadingActions.first { $0.id == "nav.mark" })
        let detail = try XCTUnwrap(page.screenConfiguration.navigation.trailingActions.first { $0.id == "nav.detail" })
        XCTAssertEqual(done.role, .confirmation)
        XCTAssertEqual(mark.role, .normal)
        XCTAssertEqual(detail.role, .normal)
        let doneItem = try XCTUnwrap(barButtonItems(in: page.navigationItem).trailing.first { $0.accessibilityIdentifier == "action.nav.text" })
        XCTAssertEqual(doneItem.style, .done)
        done.handler()
        XCTAssertEqual(page.message, "已触发：完成")
        mark.handler()
        XCTAssertEqual(page.message, "已触发：标记")

        detail.handler()
        let form = try XCTUnwrap(navigation.topViewController as? FormDemoController)
        form.loadViewIfNeeded()
        XCTAssertEqual(form.pageTitle, "导航与输入")
        XCTAssertFalse(form.screenConfiguration.navigation.leadingActions.contains { $0.id == "close" })
        let save = try XCTUnwrap(form.screenConfiguration.navigation.trailingActions.first { $0.id == "save" })
        XCTAssertEqual(save.role, .confirmation)
        form.input.text = "保留保存行为"
        save.handler()
        let status = try XCTUnwrap(view(withIdentifier: "form.status", in: form.view) as? UILabel)
        XCTAssertEqual(status.text, "已保存：保留保存行为")

        let sheet = FormDemoController()
        sheet.showsCloseButton = true
        let (_, sheetNavigation) = containers(sheet)
        let close = try XCTUnwrap(sheet.screenConfiguration.navigation.leadingActions.first { $0.id == "close" })
        XCTAssertEqual(close.role, .cancellation)
        XCTAssertEqual(sheet.screenConfiguration.navigation.trailingActions.first { $0.id == "save" }?.role, .confirmation)
        let sheetItems = barButtonItems(in: sheet.navigationItem)
        XCTAssertNotNil(sheetItems.leading.first { $0.accessibilityIdentifier == "action.close" })
        let saveItem = try XCTUnwrap(sheetItems.trailing.first { $0.accessibilityIdentifier == "action.save" })
        XCTAssertEqual(saveItem.style, .done)
        XCTAssertTrue(sheetNavigation.topViewController === sheet)

        let multipleActions = NavigationDemoController()
        multipleActions.loadViewIfNeeded()
        XCTAssertEqual(multipleActions.screenConfiguration.navigation.leadingActions.first { $0.id == "leading" }?.role, .normal)
    }

    // MARK: - Tab bar scene

    func testTabSceneExposesEveryTabSetting() {
        let (tabs, _, page) = tabScene()
        XCTAssertEqual(page.screenConfiguration.navigation.title, "标签栏")
        XCTAssertNotNil(page.screenConfiguration.tabBarStyle)
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.title, "示例")
    }

    func testTabLabelPickerAppliesAllModesWithoutRebuildingRoots() throws {
        let (tabs, navigation, page) = tabScene()
        let picker = try XCTUnwrap(view(withIdentifier: "tabbar.labels", in: page.view) as? UISegmentedControl)
        let status = try XCTUnwrap(view(withIdentifier: "tabbar.status", in: page.view) as? UILabel)
        let modes: [ShellTabLabelDisplayMode] = [.always, .never, .selectedOnly, .unselectedOnly]
        let titles = ["始终显示", "始终隐藏", "仅选中", "仅未选中"]
        let roots = tabs.viewControllers ?? []
        let stack = navigation.viewControllers
        let content = page.contentView
        XCTAssertEqual(picker.numberOfSegments, 4)
        XCTAssertEqual(picker.selectedSegmentIndex, 0)
        XCTAssertEqual(page.labelDisplayMode, .always)
        for (index, mode) in modes.enumerated() {
            XCTAssertEqual(picker.titleForSegment(at: index), titles[index])
            picker.selectedSegmentIndex = index
            picker.sendActions(for: .valueChanged)
            XCTAssertEqual(page.labelDisplayMode, mode)
            XCTAssertEqual(page.screenConfiguration.tabBarStyle?.labelDisplayMode, mode)
            XCTAssertEqual(tabs.tabBarStyle.labelDisplayMode, mode)
            XCTAssertTrue(status.text?.contains("文字：\(titles[index])") == true)
            XCTAssertEqual(tabs.selectedIndex, 0)
            XCTAssertEqual(tabs.viewControllers?.count, roots.count)
            for (before, after) in zip(roots, tabs.viewControllers ?? []) { XCTAssertTrue(before === after) }
            XCTAssertEqual(navigation.viewControllers.count, stack.count)
            for (before, after) in zip(stack, navigation.viewControllers) { XCTAssertTrue(before === after) }
            XCTAssertTrue(page.contentView === content)
            for (id, title) in [("examples", "示例"), ("materials", "材质"), ("about", "关于")] {
                XCTAssertEqual(tabs.tabItemConfiguration(for: id)?.title, title)
                XCTAssertNil(tabs.tabItemConfiguration(for: id)?.labelDisplayMode, "Tabs inherit the current style")
            }
        }
    }

    func testTabSelectedOnlyLabelsPreserveSettingsAndNavigationAfterTabSwitch() throws {
        let (tabs, navigation, page) = tabScene()
        navigation.setViewControllers([UIViewController(), page], animated: false)
        let size = try XCTUnwrap(view(withIdentifier: "tabbar.size", in: page.view) as? UISegmentedControl)
        let colors = try XCTUnwrap(view(withIdentifier: "tabbar.colors", in: page.view) as? UISegmentedControl)
        let background = try XCTUnwrap(view(withIdentifier: "tabbar.background", in: page.view) as? UIButton)
        size.selectedSegmentIndex = 3
        size.sendActions(for: .valueChanged)
        colors.selectedSegmentIndex = 2
        colors.sendActions(for: .valueChanged)
        XCTAssertTrue(page.setIconMode(1))
        XCTAssertTrue(page.setSelectedIconMode(.selectedImage))
        page.setPresentationIndexForTesting(2)
        page.setAccessoryIndexForTesting(3)
        background.sendActions(for: .touchUpInside)
        page.note("保留")
        var item = try XCTUnwrap(tabs.tabItemConfiguration(for: "materials"))
        item.labelDisplayMode = .never
        XCTAssertTrue(tabs.updateTabItem(id: "materials", configuration: item))
        let roots = tabs.viewControllers ?? []
        let stack = navigation.viewControllers
        let content = page.contentView

        page.setLabelDisplayModeForTesting(.selectedOnly)
        tabs.selectedIndex = 2
        XCTAssertEqual(tabs.selectedIndex, 2)
        XCTAssertTrue(tabs.selectedViewController === roots[2])
        XCTAssertEqual(tabs.tabBarStyle.labelDisplayMode, .selectedOnly)
        tabs.selectedIndex = 0
        XCTAssertEqual(tabs.selectedIndex, 0)
        XCTAssertTrue(navigation.topViewController === page)
        XCTAssertEqual(navigation.viewControllers.count, stack.count)
        for (before, after) in zip(stack, navigation.viewControllers) { XCTAssertTrue(before === after) }
        XCTAssertEqual(tabs.viewControllers?.count, roots.count)
        for (before, after) in zip(roots, tabs.viewControllers ?? []) { XCTAssertTrue(before === after) }
        XCTAssertTrue(page.contentView === content)
        XCTAssertEqual(page.labelDisplayMode, .selectedOnly)
        XCTAssertEqual(page.screenConfiguration.tabBarStyle?.labelDisplayMode, .selectedOnly)
        XCTAssertEqual(page.screenConfiguration.tabBarStyle?.normal.font?.pointSize, 14)
        XCTAssertEqual(page.tabColorIndex, 2)
        XCTAssertEqual(page.iconMode, 1)
        XCTAssertEqual(page.selectedIconMode, .selectedImage)
        XCTAssertEqual(page.presentationIndex, 2)
        XCTAssertEqual(page.accessoryIndex, 3)
        XCTAssertTrue(page.showsBackground)
        XCTAssertEqual(page.message, "已触发：保留")
        XCTAssertEqual(tabs.tabItemConfiguration(for: "materials")?.labelDisplayMode, .never)
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.selectedIconMode, .selectedImage)
        let labels = try XCTUnwrap(view(withIdentifier: "tabbar.labels", in: page.view) as? UISegmentedControl)
        XCTAssertEqual(labels.selectedSegmentIndex, 2)
        for (controller, title) in zip(roots, ["示例", "材质", "关于"]) {
            XCTAssertEqual(controller.tabBarItem.accessibilityLabel, title)
        }
    }

    func testTabIconModesAndSelectedPolicyApplyToExistingItems() {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        let roots = tabs.viewControllers
        XCTAssertTrue(page.setIconMode(1))
        XCTAssertEqual(page.iconMode, 1)
        XCTAssertTrue(page.setSelectedIconMode(.selectedImage))
        XCTAssertEqual(tabs.tabItemConfiguration(for: "examples")?.selectedIconMode, .selectedImage)
        // Destinations and selection survive.
        for (left, right) in zip(tabs.viewControllers ?? [], roots ?? []) { XCTAssertTrue(left === right) }
        XCTAssertTrue(page.setIconMode(0))
        XCTAssertTrue(page.setSelectedIconMode(.automatic))
    }

    func testTabAccessoriesFollowTheAccessoryPicker() {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        page.setAccessoryIndexForTesting(3)
        XCTAssertEqual(tabs.tabBarAccessories.count, 2)
        XCTAssertEqual(tabs.tabBarAccessories.first?.position, .leading)
        XCTAssertEqual(tabs.tabBarAccessories.last?.position, .trailing)
        page.setAccessoryIndexForTesting(0)
        XCTAssertTrue(tabs.tabBarAccessories.isEmpty)
    }

    func testTabPresentationAndResetRestoreDefaults() throws {
        let (tabs, _, page) = tabScene()
        page.loadViewIfNeeded()
        page.setPresentationIndexForTesting(1)
        XCTAssertEqual(tabs.barPresentation, .classic)
        page.setPresentationIndexForTesting(2)
        XCTAssertEqual(tabs.barPresentation, .capsule)
        page.setAccessoryIndexForTesting(3)
        page.setLabelDisplayModeForTesting(.never)
        page.reset()
        XCTAssertEqual(tabs.barPresentation, .automatic)
        XCTAssertTrue(tabs.tabBarAccessories.isEmpty)
        XCTAssertNil(page.screenConfiguration.tabBarStyle?.normal.font)
        XCTAssertEqual(page.labelDisplayMode, .always)
        XCTAssertEqual(page.screenConfiguration.tabBarStyle?.labelDisplayMode, .always)
        XCTAssertEqual(tabs.tabBarStyle.labelDisplayMode, .always)
        let picker = try XCTUnwrap(view(withIdentifier: "tabbar.labels", in: page.view) as? UISegmentedControl)
        XCTAssertEqual(picker.selectedSegmentIndex, 0)
        let status = try XCTUnwrap(view(withIdentifier: "tabbar.status", in: page.view) as? UILabel)
        XCTAssertTrue(status.text?.contains("文字：始终显示") == true)
    }

    // MARK: - Helpers

    private func barButtonItems(in item: UINavigationItem) -> (leading: [UIBarButtonItem], trailing: [UIBarButtonItem]) {
        var leading = item.leftBarButtonItems ?? []
        var trailing = item.rightBarButtonItems ?? []
        if #available(iOS 16.0, *) {
            leading += item.leadingItemGroups.flatMap(\.barButtonItems)
            trailing += item.trailingItemGroups.flatMap(\.barButtonItems)
            trailing += item.pinnedTrailingGroup?.barButtonItems ?? []
        }
        return (leading, trailing)
    }

    private func actionImage(id: String, in item: UINavigationItem) -> UIImage? {
        let identifier = "action.\(id)"
        func action(in menu: UIMenu) -> UIAction? {
            for child in menu.children {
                if let action = child as? UIAction, action.identifier.rawValue == identifier { return action }
                if let submenu = child as? UIMenu, let match = action(in: submenu) { return match }
            }
            return nil
        }
        let items = barButtonItems(in: item)
        for button in items.leading + items.trailing {
            if button.accessibilityIdentifier == identifier { return button.image }
            if let menu = button.menu, let match = action(in: menu) { return match.image }
        }
        return nil
    }

    private func view(withIdentifier identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier { return root }
        for child in root.subviews {
            if let match = view(withIdentifier: identifier, in: child) { return match }
        }
        return nil
    }

    private func navigationScene() -> (BoneTabBarController, BoneNavigationController, NavigationBarDemoController) {
        let page = NavigationBarDemoController()
        let (tabs, navigation) = containers(page)
        return (tabs, navigation, page)
    }

    private func tabScene() -> (BoneTabBarController, BoneNavigationController, TabBarDemoController) {
        let page = TabBarDemoController()
        let (tabs, navigation) = containers(page)
        return (tabs, navigation, page)
    }

    private func containers(_ page: BoneViewController) -> (BoneTabBarController, BoneNavigationController) {
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "examples", title: "示例", symbol: "square.grid.2x2", root: page),
            ShellTab(id: "materials", title: "材质", symbol: "circle.lefthalf.filled", root: UIViewController()),
            ShellTab(id: "about", title: "关于", symbol: "info.circle", root: UIViewController())
        ])
        tabs.loadViewIfNeeded()
        tabs.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let navigation = tabs.viewControllers?.first as! BoneNavigationController
        navigation.loadViewIfNeeded()
        // Loading the page runs its configuration, which is what these assertions inspect.
        page.loadViewIfNeeded()
        navigation.view.layoutIfNeeded()
        return (tabs, navigation)
    }
}
