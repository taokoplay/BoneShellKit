import UIKit
import BoneShellKit

/// Every navigation-bar setting in one place: title, subtitle, buttons and bar presentation.
@MainActor
final class NavigationBarDemoController: DemoStackController {
    private(set) var titleSize: CGFloat?
    private(set) var colorIndex = 0
    private(set) var showsSubtitle = true
    private(set) var usesLargeTitle = false
    private(set) var buttonSize: CGFloat?
    private(set) var presentationIndex = 0
    private(set) var materialIndex = 0
    private(set) var iconIndex = 0
    private(set) var sidebarIndex = NavigationBarDemoController.initialSidebarIndex(ProcessInfo.processInfo.arguments)
    private(set) var message: String?
    private var showsCustomTitle = false
    private var selectedTitle = "全部来源"

    /// 侧栏策略的初始档位。
    ///
    /// Demo 的 NavButton 页面在 Duo 上用于观察侧栏承载，两个测试钩子（`-navbutton`、
    /// `-navbutton-vertical-capsule`）显式选择「优先侧栏」，避免依赖 SDK 默认策略。
    static func initialSidebarIndex(_ arguments: [String]) -> Int {
        arguments.contains("-navbutton") || arguments.contains("-navbutton-vertical-capsule") ? 2 : 0
    }

    private struct NavButtonSettings {
        var mode = 0
        var size = 2
        var effect = 1
        var vertical = 0
        var groupWidth = 0
        var order = 0
        var spacing = 0

        static func initial(_ arguments: [String]) -> Self {
            var settings = Self()
            if arguments.contains("-navbutton") { settings.mode = 1 }
            if arguments.contains("-navbutton-vertical-capsule") {
                settings.mode = 1
                settings.vertical = 1
            }
            if arguments.contains("-navbutton-overflow") {
                settings.mode = 1
                settings.groupWidth = 2
                settings.spacing = 3
            }
            #if DEBUG
            func option(_ key: String) -> String? {
                guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
                return arguments[index + 1]
            }
            if let effect = option("-navbutton-effect"), let index = ["none", "blur", "glass"].firstIndex(of: effect) {
                settings.effect = index
            }
            if let gap = option("-navbutton-gap"), let index = ["0", "8", "16"].firstIndex(of: gap) {
                settings.groupWidth = 1
                settings.spacing = index + 1
            }
            if arguments.contains("-navbutton-reversed") { settings.order = 1 }
            #endif
            return settings
        }
    }

    private var navButtons = NavButtonSettings.initial(ProcessInfo.processInfo.arguments)
    private var navButtonTapCount = 0

    // A stable QA opt-out for this page. UIKit still supplies and positions the real bars.
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        ProcessInfo.processInfo.arguments.contains("-navbutton-horizontal-bar") ? .disabled : super.preferredVerticalBarBehavior
    }

    private let sizes: [CGFloat] = [16, 20, 24]
    private let buttonSizes: [CGFloat] = [15, 17, 19]
    private let colorNames = ["系统", "蓝", "橙"]
    private let presentationNames = ["跟随标签", "系统", "经典", "胶囊", "自动"]
    private let materialNames = ["自动", "系统默认", "系统玻璃", "模糊玻璃", "实色"]
    private let iconNames = ["符号", "本地图片", "UIImage"]
    private let sidebarNames = ["系统默认", "不启用", "优先侧栏"]
    private let sidebarBehaviors: [ShellNavigationSidebarBehavior] = [.system, .disabled, .preferred]

    private let sizePicker = UISegmentedControl(items: ["系统", "16", "20", "24"])
    private let colorPicker = UISegmentedControl(items: ["系统", "蓝", "橙"])
    private let subtitlePicker = UISegmentedControl(items: ["关", "开"])
    private let largeTitlePicker = UISegmentedControl(items: ["关", "开"])
    private let buttonSizePicker = UISegmentedControl(items: ["系统", "15", "17", "19"])
    private let presentationPicker = UISegmentedControl(items: ["跟随标签", "系统", "经典", "胶囊", "自动"])
    private let materialPicker = UISegmentedControl(items: ["自动", "系统默认", "系统玻璃", "模糊玻璃", "实色"])
    private let iconPicker = UISegmentedControl(items: ["符号", "本地图片", "UIImage"])
    private let sidebarPicker = UISegmentedControl(items: ["系统默认", "不启用", "优先侧栏"])
    private let customTitlePicker = UISegmentedControl(items: ["文字", "自定义"])
    private let navModePicker = UISegmentedControl(items: ["标准", "NavButton"])
    private let navSizePicker = UISegmentedControl(items: ["拟合", "56 × 44", "72 × 44"])
    private let navEffectPicker = UISegmentedControl(items: ["无", "系统默认", "系统玻璃"])
    private let navVerticalPicker = UISegmentedControl(items: ["沿用横栏", "44 × 72"])
    private let navGroupWidthPicker = UISegmentedControl(items: ["不显示", "44 pt", "400 pt"])
    private let navOrderPicker = UISegmentedControl(items: ["标记在前", "分享在前"])
    private let navSpacingPicker = UISegmentedControl(items: ["独立", "0 pt", "8 pt", "16 pt"])
    private var navButtonPickers: [(UISegmentedControl, String, WritableKeyPath<NavButtonSettings, Int>)] {
        [(navModePicker, "mode", \.mode), (navSizePicker, "size", \.size),
         (navEffectPicker, "effect", \.effect), (navVerticalPicker, "vertical", \.vertical),
         (navGroupWidthPicker, "group-width", \.groupWidth), (navOrderPicker, "order", \.order),
         (navSpacingPicker, "spacing", \.spacing)]
    }

    private lazy var titleButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        configuration.title = selectedTitle
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 5
        configuration.baseForegroundColor = .label
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = "nav.custom-title-button"
        button.accessibilityLabel = selectedTitle
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { completion([]); return }
            completion(["全部来源", "本地来源", "订阅来源"].map { option in
                UIAction(title: option, state: option == self.selectedTitle ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    self.selectedTitle = option
                    self.updateTitleButton()
                    self.updateStatus()
                }
            })
        }])
        return button
    }()
    private let status = DemoStyle.label("", style: .footnote, color: .secondaryLabel)

    private var color: UIColor? { [nil, UIColor.systemBlue, UIColor.systemOrange][colorIndex] }

    private var style: ShellNavigationStyle {
        func text(_ size: CGFloat?, weight: UIFont.Weight) -> ShellTextStyle {
            ShellTextStyle(font: size.map { .systemFont(ofSize: $0, weight: weight) }, color: color)
        }
        var buttonText = text(buttonSize, weight: .semibold)
        if navButtons.mode == 1, buttonText.color == nil { buttonText.color = .label }
        return ShellNavigationStyle(
            title: text(titleSize, weight: .semibold),
            largeTitle: text(titleSize.map { $0 + 10 }, weight: .bold),
            subtitle: text(titleSize.map { max(11, $0 - 6) }, weight: .regular),
            buttons: buttonText
        )
    }

    private var presentation: ShellBarPresentation? {
        [nil, .system, .classic, .capsule, .automatic][presentationIndex]
    }

    private var material: ShellMaterial {
        [.automatic, .systemDefault, .systemGlass, .frostedGlass, .solid][materialIndex]
    }

    private var detailIcon: ShellNavigationIcon {
        switch iconIndex {
        case 1:
            return .asset("BarStyle-Orbit", bundle: .main)
        case 2:
            guard let image = UIImage(named: "BarStyle-Orbit", in: .main, compatibleWith: traitCollection) else {
                return .systemSymbol("arrow.right")
            }
            return .image(image.withRenderingMode(.alwaysOriginal))
        default:
            return .systemSymbol("arrow.right")
        }
    }

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "导航栏"
        screen.navigation.subtitle = showsSubtitle ? "标题、按钮与形态" : nil
        screen.navigation.usesLargeTitle = usesLargeTitle
        if showsCustomTitle { screen.navigation.titleView = titleButton }
        screen.navigation.style = style
        screen.navigation.material = material
        if navButtons.mode == 1 {
            screen.navigation.moduleSpacing = 8
            screen.navigation.trailingModules = customModules()
            return
        }
        screen.navigation.trailingModules = [
            NavigationAction(id: "nav.text", title: "完成", priority: 30, role: .confirmation) { [weak self] in
                self?.note("完成")
            },
            NavigationAction(id: "nav.detail", title: "详情", icon: detailIcon, priority: 20,
                             sidebarBehavior: sidebarBehaviors[sidebarIndex]) { [weak self] in
                self?.openDetail()
            }
        ].map(\.asNavigationModule)
        screen.navigation.leadingModules = [
            NavigationAction(id: "nav.mark", title: "标记", symbol: "bookmark", priority: 10) { [weak self] in
                self?.note("标记")
            }
        ].map(\.asNavigationModule)
    }

    /// 按钮表面只声明材质，绘制与回退由 SDK 统一解析：系统玻璃在旧系统回退为磨砂。
    private let effects: [ShellNavButton.Effect] = [.none, .material(.systemDefault), .material(.systemGlass)]

    private func customModules() -> [NavigationModule] {
        func normalStyle(width: CGFloat?, iconSize: CGSize? = nil) -> ShellNavButton.Style {
            .init(size: width.map { .preferred(CGSize(width: $0, height: 44)) } ?? .fitting,
                  iconSize: iconSize, contentInsets: .init(top: 0, leading: 4, bottom: 0, trailing: 4),
                  effect: effects[navButtons.effect])
        }
        let widths: [CGFloat?] = [nil, 56, 72]
        let vertical: ShellNavButton.Style? = navButtons.vertical == 0 ? nil
            : .init(size: .preferred(CGSize(width: 44, height: 72)), icon: .systemSymbol("checkmark"), contentInsets: .zero)
        let done = NavigationAction(id: "nav.text", title: "完成",
                                    navButton: .init(normal: normalStyle(width: widths[navButtons.size]), vertical: vertical),
                                    priority: 30, role: .confirmation,
                                    sidebarBehavior: sidebarBehaviors[sidebarIndex]) { [weak self] in self?.recordNavButton("完成") }
        let detail = NavigationAction(
            id: "nav.detail", title: "详情",
            navButton: .init(normal: .init(iconSize: CGSize(width: 22, height: 22), effect: effects[navButtons.effect])),
            icon: .systemSymbol("arrow.right"), priority: 20,
            sidebarBehavior: sidebarBehaviors[sidebarIndex]
        ) { [weak self] in self?.openDetail() }
        guard navButtons.groupWidth != 0 else { return [.button(detail), .button(done)] }

        let icons = ShellNavButton(normal: normalStyle(
            width: navButtons.groupWidth == 1 ? 44 : 400,
            iconSize: CGSize(width: 20, height: 20)
        ))
        var actions = [("nav.mark", "标记", "bookmark"), ("nav.share", "分享", "square.and.arrow.up")].map { id, title, symbol in
            NavigationAction(id: id, title: title, navButton: icons, icon: .systemSymbol(symbol), priority: 10) { [weak self] in
                self?.recordNavButton(title)
            }
        }
        if navButtons.order == 1 { actions.reverse() }
        let group = NavigationButtonGroup(
            id: "nav.mark-share",
            actions: actions,
            itemSpacing: [0, 8, 16][max(0, min(2, navButtons.spacing))],
            material: .systemGlass,
            sidebarBehavior: sidebarBehaviors[sidebarIndex]
        )
        // QA 钩子：侧轨容量有限，只留按钮组以核对组员是否竖向堆叠。
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-navbutton-single-group") {
            return [.group(group)]
        }
        #endif
        return [.group(group), .button(detail), .button(done)]
    }

    private func recordNavButton(_ title: String) {
        navButtonTapCount += 1
        note(title)
    }

    override func buildDemo() {
        intro("导航栏的全部设置", "标题字号与颜色、副标题、大标题、按钮图标与方向，以及导航栏形态，都在这一页。")
        status.accessibilityIdentifier = "nav.status"
        card([status])
        button("恢复系统导航外观", symbol: "arrow.counterclockwise", id: "nav.reset") { [weak self] in
            self?.reset()
        }

        bind(customTitlePicker, id: "nav.title-view") { [weak self] index in
            guard let self else { return }
            self.showsCustomTitle = index == 1
            self.apply()
        }
        card([DemoStyle.label("标题内容", style: .headline), customTitlePicker])

        bind(sizePicker, id: "nav.title-size") { [weak self] index in
            guard let self = self else { return }
            self.titleSize = index == 0 ? nil : self.sizes[index - 1]
            self.apply()
        }
        bind(colorPicker, id: "nav.title-color") { [weak self] index in
            guard let self = self else { return }
            self.colorIndex = index
            self.apply()
        }
        card([DemoStyle.label("标题 / 大标题", style: .headline), sizePicker,
              DemoStyle.label("标题颜色", style: .subheadline), colorPicker])

        bind(subtitlePicker, id: "nav.subtitle") { [weak self] index in
            guard let self = self else { return }
            self.showsSubtitle = index == 1
            self.apply()
        }
        bind(largeTitlePicker, id: "nav.large-title") { [weak self] index in
            guard let self = self else { return }
            self.usesLargeTitle = index == 1
            self.apply()
        }
        card([DemoStyle.label("副标题与标题形态", style: .headline), subtitlePicker, largeTitlePicker])

        bind(buttonSizePicker, id: "nav.button-size") { [weak self] index in
            guard let self = self else { return }
            self.buttonSize = index == 0 ? nil : self.buttonSizes[index - 1]
            self.apply()
        }
        card([DemoStyle.label("按钮字号", style: .headline), buttonSizePicker,
              DemoStyle.label("“完成”为文字按钮，“详情”与“标记”为图标按钮。", style: .footnote, color: .secondaryLabel)])

        bind(iconPicker, id: "nav.icon") { [weak self] index in
            guard let self = self else { return }
            self.iconIndex = index
            self.apply()
        }
        bind(sidebarPicker, id: "nav.sidebar") { [weak self] index in
            guard let self = self else { return }
            self.sidebarIndex = index
            self.apply()
        }
        card([DemoStyle.label("详情图标", style: .headline), iconPicker,
              DemoStyle.label("侧栏策略", style: .subheadline), sidebarPicker,
              DemoStyle.label("切换“详情”的图标来源，UIImage 保留原色。侧栏策略同时作用于独立按钮和整个按钮组，实际位置仍由系统决定。", style: .footnote, color: .secondaryLabel)])

        bind(presentationPicker, id: "nav.presentation") { [weak self] index in
            guard let self = self else { return }
            self.presentationIndex = index
            self.apply()
        }
        card([DemoStyle.label("导航栏形态", style: .headline), presentationPicker,
              DemoStyle.label("“跟随标签”使用标签栏的形态；其它选项只作用于导航栏。", style: .footnote, color: .secondaryLabel)])
        bind(materialPicker, id: "nav.material") { [weak self] index in
            guard let self else { return }
            self.materialIndex = index
            self.apply()
        }
        card([DemoStyle.label("导航栏材质", style: .headline), materialPicker,
              DemoStyle.label("标准模式使用系统 UIBarButtonItem 共享玻璃，NavButton 模式使用自定义按钮材质。", style: .footnote, color: .secondaryLabel)])

        for (picker, id, key) in navButtonPickers {
            bind(picker, id: "navbutton.\(id)") { [weak self] index in
                guard let self else { return }
                self.navButtons[keyPath: key] = index
                self.apply()
            }
        }
        card([DemoStyle.label("导航按钮", style: .headline), navModePicker,
              DemoStyle.label("完成 · 横栏尺寸（pt）", style: .subheadline), navSizePicker,
              DemoStyle.label("完成 · 侧栏尺寸（pt）", style: .subheadline), navVerticalPicker,
              DemoStyle.label("按钮表面（系统玻璃在旧系统回退为磨砂）", style: .subheadline), navEffectPicker,
              DemoStyle.label("“详情”使用默认尺寸，自绘表面会随栏位呈圆形。", style: .footnote, color: .secondaryLabel)])
        card([DemoStyle.label("标记与分享 · 单项宽度", style: .headline), navGroupWidthPicker,
              DemoStyle.label("动作顺序", style: .subheadline), navOrderPicker,
              DemoStyle.label("组内净距", style: .subheadline), navSpacingPicker])
        syncPickers()
        updateStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        syncPickers()
        updateStatus()
    }

    /// Rebuilds the page configuration after any change.
    func apply() {
        if showsCustomTitle { updateTitleButton() }
        (navigationController as? BoneNavigationController)?.barPresentation = presentation
        refreshScreenConfiguration()
        syncPickers()
        updateStatus()
    }

    func reset() {
        titleSize = nil
        colorIndex = 0
        showsSubtitle = true
        usesLargeTitle = false
        buttonSize = nil
        presentationIndex = 0
        materialIndex = 0
        iconIndex = 0
        sidebarIndex = Self.initialSidebarIndex(ProcessInfo.processInfo.arguments)
        showsCustomTitle = false
        selectedTitle = "全部来源"
        navButtons = NavButtonSettings()
        navButtonTapCount = 0
        message = nil
        apply()
    }

    @discardableResult
    func openDetail() -> FormDemoController {
        let detail = FormDemoController()
        detail.pageTitle = "导航与输入"
        navigationController?.pushViewController(detail, animated: true)
        return detail
    }

    // MARK: - Test hooks (internal, used by the demo integration tests)

    func setTitleSizeForTesting(_ size: CGFloat, colorIndex: Int) {
        titleSize = size
        self.colorIndex = colorIndex
        apply()
    }

    func setPresentationIndexForTesting(_ index: Int) {
        presentationIndex = index
        apply()
    }

    func note(_ text: String) {
        message = "已触发：\(text)"
        updateStatus()
    }

    private func updateTitleButton() {
        guard titleButton.configuration?.title != selectedTitle else { return }
        titleButton.configuration?.title = selectedTitle
        titleButton.accessibilityLabel = selectedTitle
    }

    private func syncPickers() {
        sizePicker.selectedSegmentIndex = titleSize.flatMap { sizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        colorPicker.selectedSegmentIndex = colorIndex
        subtitlePicker.selectedSegmentIndex = showsSubtitle ? 1 : 0
        largeTitlePicker.selectedSegmentIndex = usesLargeTitle ? 1 : 0
        buttonSizePicker.selectedSegmentIndex = buttonSize.flatMap { buttonSizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        presentationPicker.selectedSegmentIndex = presentationIndex
        materialPicker.selectedSegmentIndex = materialIndex
        iconPicker.selectedSegmentIndex = iconIndex
        sidebarPicker.selectedSegmentIndex = sidebarIndex
        customTitlePicker.selectedSegmentIndex = showsCustomTitle ? 1 : 0
        for (picker, _, key) in navButtonPickers { picker.selectedSegmentIndex = navButtons[keyPath: key] }
        let custom = navButtons.mode == 1
        for picker in [navSizePicker, navVerticalPicker, navEffectPicker, navGroupWidthPicker] { picker.isEnabled = custom }
        for picker in [navOrderPicker, navSpacingPicker] { picker.isEnabled = custom && navButtons.groupWidth != 0 }
        iconPicker.isEnabled = !custom
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let size = titleSize.map { "\(Int($0)) pt" } ?? "系统"
        let buttons = buttonSize.map { "\(Int($0)) pt" } ?? "系统"
        let subtitle = showsSubtitle ? "开" : "关"
        let large = usesLargeTitle ? "开" : "关"
        let text = "标题：\(size) / \(colorNames[colorIndex])\n按钮：\(buttons)\n图标：\(iconNames[iconIndex]) / 侧栏：\(sidebarNames[sidebarIndex])\n副标题：\(subtitle) / 大标题：\(large)\n形态：\(presentationNames[presentationIndex])\n材质：\(materialNames[materialIndex])"
        let titleMode = showsCustomTitle ? "\n自定义标题：\(selectedTitle)" : ""
        let count = navButtons.mode == 1 ? "\nNavButton 点击：\(navButtonTapCount) 次" : ""
        let full = text + titleMode + count + (message.map { "\n" + $0 } ?? "")
        if status.text != full { status.text = full }
    }
}
