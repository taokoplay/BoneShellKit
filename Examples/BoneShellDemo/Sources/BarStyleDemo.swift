import UIKit
import BoneShellKit

@MainActor
enum BarStyleDemoIcons {
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

@MainActor
final class BarStyleDemoController: DemoStackController {
    private(set) var navigationFontSize: CGFloat?
    private(set) var navigationColorIndex = 0
    private(set) var tabFontSize: CGFloat?
    private(set) var tabColorIndex = 0
    private(set) var iconMode = 0
    private var navigationScalesWithDynamicType = true
    private var tabScalesWithDynamicType = true
    private var iconMessage: String?
    private let statusLabel = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    private let navigationFontPicker = UISegmentedControl(items: ["系统", "16", "20", "24"])
    private let navigationColorPicker = UISegmentedControl(items: ["系统", "蓝色", "橙色"])
    private let tabFontPicker = UISegmentedControl(items: ["系统", "10", "12", "14"])
    private let tabColorPicker = UISegmentedControl(items: ["系统", "灰 / 蓝", "蓝 / 橙"])
    private let iconPicker = UISegmentedControl(items: ["SF 图标", "资源图片", "彩色图片"])
    private let navigationSizes: [CGFloat] = [16, 20, 24]
    private let tabSizes: [CGFloat] = [10, 12, 14]
    private let navigationColorNames = ["系统", "蓝色", "橙色"]
    private let tabColorNames = ["系统", "灰 / 蓝", "蓝 / 橙"]
    private let iconNames = ["SF 图标", "资源图片", "彩色图片"]
    private let originalTabs = [
        (id: "examples", title: "示例", symbol: "square.grid.2x2"),
        (id: "materials", title: "材质", symbol: "circle.lefthalf.filled"),
        (id: "about", title: "关于", symbol: "info.circle")
    ]

    private var navigationStyle: ShellNavigationStyle {
        let color: UIColor? = [nil, UIColor.systemBlue, UIColor.systemOrange][navigationColorIndex]
        func text(_ size: CGFloat?, weight: UIFont.Weight) -> ShellTextStyle {
            ShellTextStyle(font: size.map { .systemFont(ofSize: $0, weight: weight) }, color: color,
                           scalesWithDynamicType: navigationScalesWithDynamicType)
        }
        return ShellNavigationStyle(
            title: text(navigationFontSize, weight: .semibold),
            largeTitle: text(navigationFontSize.map { $0 + 10 }, weight: .bold),
            subtitle: text(navigationFontSize.map { max(11, $0 - 6) }, weight: .regular),
            buttons: text(navigationFontSize, weight: .semibold)
        )
    }

    private var tabStyle: ShellTabBarStyle {
        let normal: UIColor? = [nil, UIColor.secondaryLabel, UIColor.systemBlue][tabColorIndex]
        let selected: UIColor? = [nil, UIColor.systemBlue, UIColor.systemOrange][tabColorIndex]
        return ShellTabBarStyle(
            normal: ShellTextStyle(font: tabFontSize.map { .systemFont(ofSize: $0) }, color: normal,
                                   scalesWithDynamicType: tabScalesWithDynamicType),
            selected: ShellTextStyle(font: tabFontSize.map { .systemFont(ofSize: $0, weight: .semibold) },
                                     color: selected, scalesWithDynamicType: tabScalesWithDynamicType),
            normalIconColor: normal, selectedIconColor: selected
        )
    }

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "栏位字体与图标"
        screen.navigation.subtitle = "大小、颜色与选中图标"
        screen.navigation.style = navigationStyle
        screen.tabBarStyle = tabStyle
        screen.navigation.trailingActions = [
            NavigationAction(id: "bar-style.next", title: "详情", priority: 20) { [weak self] in
                self?.openDetail()
            }
        ]
    }

    override func buildDemo() {
        intro("栏位也有自己的风格", "调整后直接观察顶部标题、文字按钮与底部标签。打开详情，输入文字，再切换标签试试。")
        statusLabel.accessibilityIdentifier = "bar-style.status"
        card([statusLabel])
        button("恢复系统样式", symbol: "arrow.counterclockwise", id: "bar-style.reset") { [weak self] in
            self?.resetStyles()
        }
        bind(navigationFontPicker, id: "bar-style.nav-font") { [weak self] index in
            guard let self = self else { return }
            self.setNavigationFontSize(index == 0 ? nil : self.navigationSizes[index - 1])
        }
        bind(navigationColorPicker, id: "bar-style.nav-color") { [weak self] in self?.setNavigationColor($0) }
        card([DemoStyle.label("导航字号", style: .headline), navigationFontPicker,
              DemoStyle.label("标题与按钮颜色", style: .subheadline), navigationColorPicker])
        bind(tabFontPicker, id: "bar-style.tab-font") { [weak self] index in
            guard let self = self else { return }
            self.setTabFontSize(index == 0 ? nil : self.tabSizes[index - 1])
        }
        bind(tabColorPicker, id: "bar-style.tab-colors") { [weak self] in self?.setTabColors($0) }
        card([DemoStyle.label("标签字号", style: .headline), tabFontPicker,
              DemoStyle.label("普通 / 选中颜色", style: .subheadline), tabColorPicker])
        bind(iconPicker, id: "bar-style.icons") { [weak self] in self?.setIconMode($0) }
        card([DemoStyle.label("标签图标", style: .headline), iconPicker,
              DemoStyle.label("资源图片随标签着色；彩色图片保留青绿与橙色。图片选中时使用实心图案。", style: .footnote, color: .secondaryLabel)])
        button("打开输入详情", symbol: "arrow.right.circle", id: "bar-style.detail") { [weak self] in
            self?.openDetail()
        }
        updateControls()
    }

    func setNavigationFontSize(_ size: CGFloat?, scalesWithDynamicType: Bool = true) {
        guard size == nil || navigationSizes.contains(size!) else { return }
        navigationFontSize = size
        navigationScalesWithDynamicType = scalesWithDynamicType
        applyStyles()
    }

    func setNavigationColor(_ index: Int) {
        guard navigationColorNames.indices.contains(index) else { return }
        navigationColorIndex = index
        applyStyles()
    }

    func setTabFontSize(_ size: CGFloat?, scalesWithDynamicType: Bool = true) {
        guard size == nil || tabSizes.contains(size!) else { return }
        tabFontSize = size
        tabScalesWithDynamicType = scalesWithDynamicType
        applyStyles()
    }

    func setTabColors(_ index: Int) {
        guard tabColorNames.indices.contains(index) else { return }
        tabColorIndex = index
        applyStyles()
    }

    @discardableResult
    func setIconMode(_ index: Int) -> Bool {
        guard iconNames.indices.contains(index) else { return false }
        guard let tabs = tabBarController as? BoneTabBarController else { return false }
        let normal = BarStyleDemoIcons.image(selected: false)
        let selected = BarStyleDemoIcons.image(selected: true)
        guard index == 0 || (normal != nil && selected != nil) else {
            iconMessage = "图片暂时不可用"
            updateControls()
            return false
        }
        var updated = false
        for tab in originalTabs where tabs.tabItemConfiguration(for: tab.id) != nil {
            let configuration: ShellTabItemConfiguration
            switch index {
            case 1:
                configuration = ShellTabItemConfiguration(
                    title: tab.title, icon: .asset(BarStyleDemoIcons.assetName(selected: false), bundle: .main),
                    selectedIcon: .asset(BarStyleDemoIcons.assetName(selected: true), bundle: .main))
            case 2:
                configuration = ShellTabItemConfiguration(
                    title: tab.title, icon: .image(normal!.withRenderingMode(.alwaysOriginal)),
                    selectedIcon: .image(selected!.withRenderingMode(.alwaysOriginal)))
            default:
                configuration = ShellTabItemConfiguration(title: tab.title, icon: .systemSymbol(tab.symbol))
            }
            updated = tabs.updateTabItem(id: tab.id, configuration: configuration) || updated
        }
        guard updated else { return false }
        iconMode = index
        iconMessage = nil
        updateControls()
        return true
    }

    @discardableResult
    func resetStyles() -> Bool {
        navigationFontSize = nil
        tabFontSize = nil
        navigationColorIndex = 0
        tabColorIndex = 0
        navigationScalesWithDynamicType = true
        tabScalesWithDynamicType = true
        let restoredIcons = setIconMode(0)
        applyStyles()
        return restoredIcons
    }

    @discardableResult
    func openDetail(animated: Bool = true) -> BarStyleDetailController {
        let page = BarStyleDetailController(navigationStyle: navigationStyle, tabStyle: tabStyle,
                                          iconMode: iconMode) { [weak self] in self?.setIconMode($0) ?? false }
        navigationItem.backButtonDisplayMode = .minimal
        navigationController?.pushViewController(page, animated: animated)
        return page
    }

    private func bind(_ picker: UISegmentedControl, id: String, action: @escaping (Int) -> Void) {
        picker.accessibilityIdentifier = id
        picker.addAction(UIAction { [weak picker] _ in
            guard let picker = picker else { return }
            action(picker.selectedSegmentIndex)
        }, for: .valueChanged)
    }

    private func applyStyles() {
        refreshScreenConfiguration()
        updateControls()
    }

    private func updateControls() {
        navigationFontPicker.selectedSegmentIndex = navigationFontSize.flatMap { navigationSizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        navigationColorPicker.selectedSegmentIndex = navigationColorIndex
        tabFontPicker.selectedSegmentIndex = tabFontSize.flatMap { tabSizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        tabColorPicker.selectedSegmentIndex = tabColorIndex
        iconPicker.selectedSegmentIndex = iconMode
        let navigationSize = navigationFontSize.map { "\(Int($0)) pt" } ?? "系统"
        let tabSize = tabFontSize.map { "\(Int($0)) pt" } ?? "系统"
        statusLabel.text = "导航：\(navigationSize) / \(navigationColorNames[navigationColorIndex])\n标签：\(tabSize) / \(tabColorNames[tabColorIndex])\n图标：\(iconMessage ?? iconNames[iconMode])"
    }
}

@MainActor
final class BarStyleDetailController: DemoStackController {
    let input = UITextField()
    private let navigationStyle: ShellNavigationStyle
    private let tabStyle: ShellTabBarStyle
    private var iconMode: Int
    private let changeIcons: (Int) -> Bool
    private let statusLabel = DemoStyle.label("", style: .footnote, color: .secondaryLabel)

    init(navigationStyle: ShellNavigationStyle, tabStyle: ShellTabBarStyle, iconMode: Int,
         changeIcons: @escaping (Int) -> Bool) {
        self.navigationStyle = navigationStyle
        self.tabStyle = tabStyle
        self.iconMode = iconMode
        self.changeIcons = changeIcons
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "输入与图标"
        screen.navigation.style = navigationStyle
        screen.tabBarStyle = tabStyle
        screen.avoidsKeyboard = true
        screen.navigation.trailingActions = [
            NavigationAction(id: "bar-style.done", title: "完成", priority: 20) { [weak self] in
                self?.view.endEditing(true)
            }
        ]
    }

    override func buildDemo() {
        intro("换图标，文字还在", "输入文字后切换图标，再去“关于”看看。回到“示例”时，应仍在这一页。")
        input.borderStyle = .roundedRect
        input.placeholder = "输入一段想保留的文字"
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.accessibilityIdentifier = "bar-style.detail.input"
        input.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        card([DemoStyle.label("保留输入", style: .headline), input])
        statusLabel.accessibilityIdentifier = "bar-style.detail.status"
        card([statusLabel])
        button("切换标签图标", symbol: "arrow.triangle.2.circlepath", id: "bar-style.detail.icons") { [weak self] in
            self?.toggleIcons()
        }
        updateStatus()
    }

    @discardableResult
    func toggleIcons() -> Bool {
        let next = iconMode == 2 ? 0 : 2
        guard changeIcons(next) else { return false }
        iconMode = next
        updateStatus()
        return true
    }

    private func updateStatus() {
        let name = ["SF 图标", "资源图片", "彩色图片"][iconMode]
        statusLabel.text = "图标：\(name) · 可切换标签检查输入"
    }
}
