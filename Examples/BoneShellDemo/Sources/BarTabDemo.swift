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
    private(set) var iconMode = 0
    private(set) var selectedIconMode: ShellTabSelectedIconMode = .automatic
    private(set) var presentationIndex = 0
    private(set) var accessoryIndex = 0
    private(set) var showsBackground = false
    private(set) var message: String?

    private let sizes: [CGFloat] = [10, 12, 14]
    private let presentations: [ShellBarPresentation] = [.automatic, .classic, .capsule]
    private let presentationNames = ["自动", "经典", "胶囊"]
    private let selectedIconModes: [ShellTabSelectedIconMode] = [.automatic, .selectedColor, .selectedImage]
    private let selectedIconNames = ["自动", "选中颜色", "选中图片"]
    private let colorNames = ["系统", "灰 / 蓝", "蓝 / 橙"]
    private let iconNames = ["SF 图标", "资源图片", "彩色图片"]
    private let accessoryNames = ["无", "左", "右", "左右"]
    private let originalTabs = [
        (id: "examples", title: "示例", symbol: "square.grid.2x2"),
        (id: "materials", title: "材质", symbol: "circle.lefthalf.filled"),
        (id: "about", title: "关于", symbol: "info.circle")
    ]

    private let sizePicker = UISegmentedControl(items: ["系统", "10", "12", "14"])
    private let colorPicker = UISegmentedControl(items: ["系统", "灰 / 蓝", "蓝 / 橙"])
    private let iconPicker = UISegmentedControl(items: ["SF 图标", "资源图片", "彩色图片"])
    private let selectedIconPicker = UISegmentedControl(items: ["自动", "选中颜色", "选中图片"])
    private let presentationPicker = UISegmentedControl(items: ["自动", "经典", "胶囊"])
    private let accessoryPicker = UISegmentedControl(items: ["无", "左", "右", "左右"])
    private let status = DemoStyle.label("", style: .footnote, color: .secondaryLabel)

    private var style: ShellTabBarStyle {
        let normal: UIColor? = [nil, UIColor.secondaryLabel, UIColor.systemBlue][tabColorIndex]
        let selected: UIColor? = [nil, UIColor.systemBlue, UIColor.systemOrange][tabColorIndex]
        return ShellTabBarStyle(
            normal: ShellTextStyle(font: tabFontSize.map { .systemFont(ofSize: $0) }, color: normal),
            selected: ShellTextStyle(font: tabFontSize.map { .systemFont(ofSize: $0, weight: .semibold) },
                                     color: selected),
            normalIconColor: normal, selectedIconColor: selected
        )
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
        intro("标签栏的全部设置", "字号与颜色、图标来源、选中时的显示方式、栏位形态、左右附加按钮和标签栏背景，都在这一页。")
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
        card([DemoStyle.label("标签字号", style: .headline), sizePicker,
              DemoStyle.label("普通 / 选中颜色", style: .subheadline), colorPicker])

        bind(iconPicker, id: "tabbar.icons") { [weak self] index in
            guard let self = self else { return }
            self.setIconMode(index)
        }
        bind(selectedIconPicker, id: "tabbar.selected-mode") { [weak self] index in
            guard let self = self else { return }
            self.setSelectedIconMode(self.selectedIconModes[min(index, 2)])
        }
        card([DemoStyle.label("标签图标", style: .headline), iconPicker,
              DemoStyle.label("选中时如何显示", style: .subheadline), selectedIconPicker,
              DemoStyle.label("选中颜色沿用普通图标轮廓；选中图片使用独立图片并保留原色。自动保持已有渲染方式。",
                              style: .footnote, color: .secondaryLabel)])

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
              DemoStyle.label("经典把按钮放进栏内两端；胶囊与原生栏把圆形按钮挂在栏位旁。",
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
        selectedIconMode = .automatic
        presentationIndex = 0
        accessoryIndex = 0
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
        return items
    }

    private func syncPickers() {
        sizePicker.selectedSegmentIndex = tabFontSize.flatMap { sizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        colorPicker.selectedSegmentIndex = tabColorIndex
        iconPicker.selectedSegmentIndex = iconMode
        selectedIconPicker.selectedSegmentIndex = selectedIconModes.firstIndex(of: selectedIconMode) ?? 0
        presentationPicker.selectedSegmentIndex = presentationIndex
        accessoryPicker.selectedSegmentIndex = accessoryIndex
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let size = tabFontSize.map { "\(Int($0)) pt" } ?? "系统"
        let presentationName = (tabBarController as? BoneTabBarController)
            .map { "\(presentationNames[presentationIndex]) → \(Self.name($0.resolvedBarPresentation))" }
            ?? presentationNames[presentationIndex]
        var text = "字号：\(size) / \(colorNames[tabColorIndex])\n图标：\(iconNames[iconMode])"
        text += "\n选中：\(selectedIconNames[selectedIconModes.firstIndex(of: selectedIconMode) ?? 0])"
        text += "\n形态：\(presentationName)\n附加按钮：\(accessoryNames[accessoryIndex])"
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
