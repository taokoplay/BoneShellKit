import UIKit
import BoneShellKit

@MainActor
enum TabBarDemoIcons {
    static func assetName(selected: Bool, bundle: Bundle = .main) -> String {
        let name = selected ? "BarStyle-Orbit-Selected" : "BarStyle-Orbit"
        let hasSubdirectory = [name, "\(name)@2x"].contains {
            bundle.url(forResource: $0, withExtension: "png", subdirectory: "Icons") != nil
        }
        return hasSubdirectory ? "Icons/\(name)" : name
    }

    static func image(selected: Bool, bundle: Bundle = .main) -> UIImage? {
        UIImage(named: assetName(selected: selected, bundle: bundle), in: bundle, compatibleWith: nil)
    }
}

/// Every tab-bar setting in one place: text, icons, selected rendering, presentation,
/// accessory buttons and the tab background.
@MainActor
final class TabBarDemoController: DemoStackController {
    private(set) var tabFontSize: CGFloat?
    private(set) var tabColorIndex = 0
    private(set) var labelDisplayMode: ShellTabLabelDisplayMode = .always
    private(set) var iconMode = 0
    private(set) var selectedIconMode: ShellTabSelectedIconMode = .automatic
    private(set) var presentationIndex = 0
    private(set) var accessoryIndex = 0
    private var showsAnimatedIcons = false
    private(set) var showsBackground = false
    private(set) var message: String?

    private let sizes: [CGFloat] = [10, 12, 14]
    private let presentations: [ShellBarPresentation] = [.automatic, .classic, .capsule, .system]
    private let presentationNames = ["自动", "经典", "胶囊", "系统"]
    private let selectedIconModes: [ShellTabSelectedIconMode] = [.automatic, .selectedColor, .selectedImage]
    private let selectedIconNames = ["自动", "选中颜色", "选中图片"]
    private let labelDisplayModes: [ShellTabLabelDisplayMode] = [.always, .never, .selectedOnly, .unselectedOnly]
    private let labelDisplayNames = ["始终显示", "始终隐藏", "仅选中", "仅未选中"]
    private let colorNames = ["系统", "灰 / 蓝", "蓝 / 橙"]
    private let iconNames = ["SF 图标", "资源图片", "彩色图片"]
    private let accessoryNames = ["无", "左", "右", "左右", "动态"]
    private let originalTabs = [
        (id: "examples", title: "示例", symbol: "square.grid.2x2"),
        (id: "materials", title: "材质", symbol: "circle.lefthalf.filled"),
        (id: "about", title: "关于", symbol: "info.circle")
    ]

    private let sizePicker = UISegmentedControl(items: ["系统", "10", "12", "14"])
    private let colorPicker = UISegmentedControl(items: ["系统", "灰 / 蓝", "蓝 / 橙"])
    private let labelPicker = UISegmentedControl(items: ["始终显示", "始终隐藏", "仅选中", "仅未选中"])
    private let iconPicker = UISegmentedControl(items: ["SF 图标", "资源图片", "彩色图片"])
    private let selectedIconPicker = UISegmentedControl(items: ["自动", "选中颜色", "选中图片"])
    private lazy var presentationPicker = UISegmentedControl(items: presentationNames)
    private lazy var accessoryPicker = UISegmentedControl(items: accessoryNames)
    private let animatedIconsSwitch = UISwitch()
    private let status = DemoStyle.label("", style: .footnote, color: .secondaryLabel)

    private var style: ShellTabBarStyle {
        let normal: UIColor? = [nil, UIColor.secondaryLabel, UIColor.systemBlue][tabColorIndex]
        let selected: UIColor? = [nil, UIColor.systemBlue, UIColor.systemOrange][tabColorIndex]
        var style = ShellTabBarStyle(
            normal: ShellTextStyle(font: tabFontSize.map { .systemFont(ofSize: $0) }, color: normal),
            selected: ShellTextStyle(font: tabFontSize.map { .systemFont(ofSize: $0, weight: .semibold) },
                                     color: selected),
            normalIconColor: normal, selectedIconColor: selected
        )
        style.labelDisplayMode = labelDisplayMode
        return style
    }

    private var presentation: ShellBarPresentation { presentations[presentationIndex] }

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "标签栏"
        screen.navigation.subtitle = "文字、图标、形态与附加按钮"
        screen.tabBarStyle = style
        if showsBackground {
            screen.backgroundComposition = .unified
            screen.background = DemoBackgroundAssets.configuration(0)
        }
    }

    override func buildDemo() {
        intro("标签栏的全部设置", "文字显示、字号与颜色、图标来源、选中时的显示方式、栏位形态、左右附加按钮和标签栏背景，都在这一页。")
        status.accessibilityIdentifier = "tabbar.status"
        card([status])
        button("恢复系统标签外观", symbol: "arrow.counterclockwise", id: "tabbar.reset") { [weak self] in
            self?.reset()
        }

        bind(sizePicker, id: "tabbar.size") { [weak self] index in
            guard let self = self else { return }
            self.tabFontSize = index == 0 ? nil : self.sizes[index - 1]
            self.apply()
        }
        bind(colorPicker, id: "tabbar.colors") { [weak self] index in
            guard let self = self else { return }
            self.tabColorIndex = index
            self.apply()
        }
        bind(labelPicker, id: "tabbar.labels") { [weak self] index in
            guard let self = self else { return }
            self.labelDisplayMode = self.labelDisplayModes[index]
            self.apply()
        }
        card([DemoStyle.label("标签字号", style: .headline), sizePicker,
              DemoStyle.label("普通 / 选中颜色", style: .subheadline), colorPicker,
              DemoStyle.label("标签文字显示", style: .subheadline), labelPicker])

        bind(iconPicker, id: "tabbar.icons") { [weak self] index in
            guard let self = self else { return }
            self.setIconMode(index)
        }
        bind(selectedIconPicker, id: "tabbar.selected-mode") { [weak self] index in
            guard let self = self else { return }
            self.setSelectedIconMode(self.selectedIconModes[min(index, 2)])
        }
        animatedIconsSwitch.accessibilityIdentifier = "tabbar.animated-icons"
        animatedIconsSwitch.accessibilityLabel = "自定义标签视图"
        animatedIconsSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.showsAnimatedIcons = self.animatedIconsSwitch.isOn
            _ = self.setIconMode(self.iconMode)
        }, for: .valueChanged)
        let motionRow = UIStackView(arrangedSubviews: [DemoStyle.label("自定义标签视图", style: .subheadline), animatedIconsSwitch])
        motionRow.alignment = .center
        motionRow.spacing = 8
        card([DemoStyle.label("标签图标", style: .headline), iconPicker,
              DemoStyle.label("选中时如何显示", style: .subheadline), selectedIconPicker,
              DemoStyle.label("选中颜色沿用普通图标轮廓；选中图片使用独立图片并保留原色。自动保持已有渲染方式。",
                              style: .footnote, color: .secondaryLabel), motionRow])

        bind(presentationPicker, id: "tabbar.presentation") { [weak self] index in
            guard let self = self else { return }
            self.presentationIndex = index
            self.apply()
        }
        bind(accessoryPicker, id: "tabbar.accessories") { [weak self] index in
            guard let self = self else { return }
            self.accessoryIndex = index
            self.apply()
        }
        card([DemoStyle.label("栏位形态", style: .headline), presentationPicker,
              DemoStyle.label("左右附加按钮", style: .subheadline), accessoryPicker,
              DemoStyle.label("经典栏使用栏内两端；胶囊使用外侧槽位。动态选项由自定义视图绘制整个按钮内容。",
                              style: .footnote, color: .secondaryLabel)])

        button("标签栏背景：默认 / 整体画布", symbol: "photo", id: "tabbar.background") { [weak self] in
            guard let self = self else { return }
            self.showsBackground.toggle()
            self.apply()
        }
        syncPickers()
        updateStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        syncPickers()
        updateStatus()
    }

    /// Applies style, presentation and accessories to the live tab controller.
    func apply() {
        guard let tabs = tabBarController as? BoneTabBarController else { return }
        tabs.barPresentation = presentation
        tabs.tabBarAccessories = accessories()
        tabs.tabBarStyle.labelDisplayMode = labelDisplayMode
        refreshScreenConfiguration()
        syncPickers()
        updateStatus()
    }

    @discardableResult
    func setIconMode(_ index: Int) -> Bool {
        iconMode = index
        guard let tabs = tabBarController as? BoneTabBarController else { return false }
        var updated = false
        for tab in originalTabs where tabs.tabItemConfiguration(for: tab.id) != nil {
            if showsAnimatedIcons {
                let content = ShellTabBarCustomContent {
                    DemoTabContentView(symbol: tab.symbol, title: tab.id == "materials" ? nil : tab.title,
                                       isAction: false)
                }
                updated = tabs.updateTabItem(id: tab.id, configuration: .init(title: tab.title, customContent: content)) || updated
                continue
            }
            var configuration: ShellTabItemConfiguration
            switch index {
            case 1:
                configuration = ShellTabItemConfiguration(
                    title: tab.title,
                    icon: .asset(TabBarDemoIcons.assetName(selected: false), bundle: .main),
                    selectedIcon: .asset(TabBarDemoIcons.assetName(selected: true), bundle: .main)
                )
            case 2:
                let normal = TabBarDemoIcons.image(selected: false)?.withRenderingMode(.alwaysOriginal)
                let selected = TabBarDemoIcons.image(selected: true)?.withRenderingMode(.alwaysOriginal)
                configuration = ShellTabItemConfiguration(
                    title: tab.title,
                    icon: normal.map { .image($0) } ?? .systemSymbol(tab.symbol),
                    selectedIcon: selected.map { .image($0) }
                )
            default:
                configuration = ShellTabItemConfiguration(title: tab.title, icon: .systemSymbol(tab.symbol))
            }
            configuration.selectedIconMode = selectedIconMode
            updated = tabs.updateTabItem(id: tab.id, configuration: configuration) || updated
        }
        guard updated else { return false }
        updateStatus()
        return true
    }

    @discardableResult
    func setSelectedIconMode(_ mode: ShellTabSelectedIconMode) -> Bool {
        guard let tabs = tabBarController as? BoneTabBarController else { return false }
        var updated = false
        for tab in originalTabs {
            guard var item = tabs.tabItemConfiguration(for: tab.id) else { continue }
            item.selectedIconMode = mode
            updated = tabs.updateTabItem(id: tab.id, configuration: item) || updated
        }
        guard updated else { return false }
        selectedIconMode = mode
        syncPickers()
        updateStatus()
        return true
    }

    func reset() {
        tabFontSize = nil
        tabColorIndex = 0
        labelDisplayMode = .always
        selectedIconMode = .automatic
        presentationIndex = 0
        accessoryIndex = 0
        showsAnimatedIcons = false
        showsBackground = false
        message = nil
        _ = setIconMode(0)
        apply()
    }

    // MARK: - Test hooks (internal, used by the demo integration tests)

    func setPresentationIndexForTesting(_ index: Int) {
        presentationIndex = index
        apply()
    }

    func setAccessoryIndexForTesting(_ index: Int) {
        accessoryIndex = index
        apply()
    }

    func setLabelDisplayModeForTesting(_ mode: ShellTabLabelDisplayMode) {
        labelDisplayMode = mode
        apply()
    }

    func note(_ text: String) {
        message = "已触发：\(text)"
        updateStatus()
    }

    /// Accessory buttons for the current picker value.
    func accessories() -> [ShellTabBarAccessory] {
        var items: [ShellTabBarAccessory] = []
        if accessoryIndex == 1 || accessoryIndex == 3 {
            items.append(ShellTabBarAccessory(
                id: "accessory.compose", icon: .systemSymbol("square.and.pencil"),
                title: "写", position: .leading, accessibilityLabel: "新建"
            ) { [weak self] in self?.note("新建") })
        }
        if accessoryIndex == 2 || accessoryIndex == 3 {
            items.append(ShellTabBarAccessory(
                id: "accessory.search", icon: .systemSymbol("magnifyingglass"),
                title: "搜索", position: .trailing, accessibilityLabel: "搜索"
            ) { [weak self] in self?.note("搜索") })
        }
        if accessoryIndex == 4 {
            items.append(Self.makeAnimatedAccessory { [weak self] in self?.note("动态入口") })
        }
        return items
    }

    static func makeAnimatedAccessory(handler: @escaping () -> Void) -> ShellTabBarAccessory {
        ShellTabBarAccessory(id: "accessory.pulse", customContent: ShellTabBarCustomContent {
            DemoTabContentView(symbol: "waveform", title: nil, isAction: true)
        }, position: .trailing, accessibilityLabel: "动态入口", handler: handler)
    }

    private func syncPickers() {
        sizePicker.selectedSegmentIndex = tabFontSize.flatMap { sizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        colorPicker.selectedSegmentIndex = tabColorIndex
        labelPicker.selectedSegmentIndex = labelDisplayModes.firstIndex(of: labelDisplayMode) ?? 0
        iconPicker.selectedSegmentIndex = iconMode
        selectedIconPicker.selectedSegmentIndex = selectedIconModes.firstIndex(of: selectedIconMode) ?? 0
        presentationPicker.selectedSegmentIndex = presentationIndex
        accessoryPicker.selectedSegmentIndex = accessoryIndex
        animatedIconsSwitch.isOn = showsAnimatedIcons
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let size = tabFontSize.map { "\(Int($0)) pt" } ?? "系统"
        let presentationName = (tabBarController as? BoneTabBarController)
            .map { "\(presentationNames[presentationIndex]) → \(Self.name($0.resolvedBarPresentation))" }
            ?? presentationNames[presentationIndex]
        var text = "字号：\(size) / \(colorNames[tabColorIndex])\n图标：\(iconNames[iconMode])"
        text += "\n文字：\(labelDisplayNames[labelDisplayModes.firstIndex(of: labelDisplayMode) ?? 0])"
        text += "\n选中：\(selectedIconNames[selectedIconModes.firstIndex(of: selectedIconMode) ?? 0])"
        text += "\n形态：\(presentationName)\n附加按钮：\(accessoryNames[accessoryIndex])"
        if let tabs = tabBarController as? BoneTabBarController {
            let custom = tabs.tabItemContentMode(for: "examples") == .customView
            text += custom ? "\n普通标签：自定义视图" : "\n普通标签：标准图标"
        }
        text += "\n背景：\(showsBackground ? "整体画布" : "默认")"
        let full = message.map { text + "\n" + $0 } ?? text
        if status.text != full { status.text = full }
    }

    private static func name(_ presentation: ShellBarPresentation) -> String {
        switch presentation {
        case .automatic: return "自动"
        case .classic: return "经典"
        case .capsule: return "胶囊"
        case .system: return "系统"
        }
    }
}

/// The host supplies everything inside the slot, including any caption and selection treatment.
private final class DemoTabContentView: UIView, ShellTabBarContentUpdating {
    private let surface = UIView()
    private let glyph = UIImageView()
    private let caption = UILabel()
    private let isAction: Bool
    private var canPlay = false
    private let animationKey = "pulse"

    init(symbol: String, title: String?, isAction: Bool) {
        self.isAction = isAction
        super.init(frame: .zero)
        surface.layer.cornerCurve = .continuous
        glyph.image = UIImage(systemName: symbol)
        glyph.tintColor = .label
        glyph.contentMode = .scaleAspectFit
        caption.text = title
        caption.font = .preferredFont(forTextStyle: .caption2)
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.8
        caption.textAlignment = .center
        addSubview(surface)
        addSubview(glyph)
        addSubview(caption)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(updateMotion),
                           name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneActivityChanged(_:)), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(sceneActivityChanged(_:)), name: UIScene.willDeactivateNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let shortestSide = min(bounds.width, bounds.height)
        if isAction {
            let side = max(0, shortestSide - 6)
            surface.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        } else {
            surface.frame = bounds.insetBy(dx: 3, dy: 4)
        }
        surface.layer.cornerRadius = max(0, min(surface.bounds.width, surface.bounds.height) / 2)
        let titleHeight = caption.text == nil ? 0 : min(ceil(caption.font.lineHeight), bounds.height * 0.33)
        let glyphSide = max(0, min(isAction ? 29 : 24, shortestSide - 8, bounds.height - titleHeight - 6))
        let gap: CGFloat = titleHeight > 0 ? 2 : 0
        let top = bounds.midY - (glyphSide + gap + titleHeight) / 2
        glyph.frame = CGRect(x: bounds.midX - glyphSide / 2, y: top, width: glyphSide, height: glyphSide)
        caption.frame = CGRect(x: bounds.minX + 5, y: glyph.frame.maxY + gap,
                               width: max(0, bounds.width - 10), height: titleHeight)
    }

    func tabBarContentDidChange(_ state: ShellTabBarCustomContent.State) {
        canPlay = state.isVisible && state.isEnabled && (isAction || state.isSelected)
        surface.backgroundColor = UIColor.systemTeal.withAlphaComponent(state.isSelected || isAction ? 0.27 : 0.06)
        alpha = state.isEnabled ? (state.isHighlighted ? 0.65 : 1) : 0.4
        updateMotion()
    }

    @objc private func sceneActivityChanged(_ notification: Notification) {
        guard let scene = window?.windowScene, notification.object as? UIScene === scene else { return }
        if notification.name == UIScene.willDeactivateNotification {
            surface.layer.removeAnimation(forKey: animationKey)
        } else {
            updateMotion()
        }
    }

    @objc private func updateMotion() {
        guard canPlay, window?.windowScene?.activationState == .foregroundActive,
              !UIAccessibility.isReduceMotionEnabled else {
            surface.layer.removeAnimation(forKey: animationKey)
            return
        }
        guard surface.layer.animation(forKey: animationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.35
        animation.toValue = 1.0
        animation.duration = 1.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        surface.layer.add(animation, forKey: animationKey)
    }
}
