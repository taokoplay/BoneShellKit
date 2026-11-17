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
    private(set) var iconIndex = 0
    private(set) var axisIndex = 0
    private(set) var message: String?

    private let sizes: [CGFloat] = [16, 20, 24]
    private let buttonSizes: [CGFloat] = [15, 17, 19]
    private let colorNames = ["系统", "蓝", "橙"]
    private let presentationNames = ["跟随标签", "系统", "经典"]
    private let iconNames = ["符号", "本地图片", "UIImage"]
    private let axisNames = ["自动", "仅横向", "优先侧边"]
    private let axisBehaviors: [ShellNavigationActionAxisBehavior] = [.automatic, .horizontalOnly, .verticalPreferred]

    private let sizePicker = UISegmentedControl(items: ["系统", "16", "20", "24"])
    private let colorPicker = UISegmentedControl(items: ["系统", "蓝", "橙"])
    private let subtitlePicker = UISegmentedControl(items: ["关", "开"])
    private let largeTitlePicker = UISegmentedControl(items: ["关", "开"])
    private let buttonSizePicker = UISegmentedControl(items: ["系统", "15", "17", "19"])
    private let presentationPicker = UISegmentedControl(items: ["跟随标签", "系统", "经典"])
    private let iconPicker = UISegmentedControl(items: ["符号", "本地图片", "UIImage"])
    private let axisPicker = UISegmentedControl(items: ["自动", "仅横向", "优先侧边"])
    private let status = DemoStyle.label("", style: .footnote, color: .secondaryLabel)

    private var color: UIColor? { [nil, UIColor.systemBlue, UIColor.systemOrange][colorIndex] }

    private var style: ShellNavigationStyle {
        func text(_ size: CGFloat?, weight: UIFont.Weight) -> ShellTextStyle {
            ShellTextStyle(font: size.map { .systemFont(ofSize: $0, weight: weight) }, color: color)
        }
        return ShellNavigationStyle(
            title: text(titleSize, weight: .semibold),
            largeTitle: text(titleSize.map { $0 + 10 }, weight: .bold),
            subtitle: text(titleSize.map { max(11, $0 - 6) }, weight: .regular),
            buttons: text(buttonSize ?? titleSize, weight: .semibold)
        )
    }

    private var presentation: ShellBarPresentation? {
        [nil, .system, .classic][presentationIndex]
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
        screen.navigation.style = style
        screen.navigation.trailingActions = [
            NavigationAction(id: "nav.text", title: "完成", priority: 30, role: .confirmation) { [weak self] in
                self?.note("完成")
            },
            NavigationAction(id: "nav.detail", title: "详情", icon: detailIcon, priority: 20,
                             axisBehavior: axisBehaviors[axisIndex]) { [weak self] in
                self?.openDetail()
            }
        ]
        screen.navigation.leadingActions = [
            NavigationAction(id: "nav.mark", title: "标记", symbol: "bookmark", priority: 10) { [weak self] in
                self?.note("标记")
            }
        ]
    }

    override func buildDemo() {
        intro("导航栏的全部设置", "标题字号与颜色、副标题、大标题、按钮图标与方向，以及导航栏形态，都在这一页。")
        status.accessibilityIdentifier = "nav.status"
        card([status])
        button("恢复系统导航外观", symbol: "arrow.counterclockwise", id: "nav.reset") { [weak self] in
            self?.reset()
        }

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
        bind(axisPicker, id: "nav.axis") { [weak self] index in
            guard let self = self else { return }
            self.axisIndex = index
            self.apply()
        }
        card([DemoStyle.label("详情图标", style: .headline), iconPicker,
              DemoStyle.label("详情按钮方向", style: .subheadline), axisPicker,
              DemoStyle.label("切换“详情”的图标来源，UIImage 保留原色。方向选项在支持的系统上生效，实际位置由系统决定。", style: .footnote, color: .secondaryLabel)])

        bind(presentationPicker, id: "nav.presentation") { [weak self] index in
            guard let self = self else { return }
            self.presentationIndex = index
            self.apply()
        }
        card([DemoStyle.label("导航栏形态", style: .headline), presentationPicker,
              DemoStyle.label("“跟随标签”使用标签栏的形态；其它选项只作用于导航栏。", style: .footnote, color: .secondaryLabel)])

        button("打开输入详情", symbol: "arrow.right.circle", id: "nav.detail") { [weak self] in
            self?.openDetail()
        }
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
        iconIndex = 0
        axisIndex = 0
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

    private func syncPickers() {
        sizePicker.selectedSegmentIndex = titleSize.flatMap { sizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        colorPicker.selectedSegmentIndex = colorIndex
        subtitlePicker.selectedSegmentIndex = showsSubtitle ? 1 : 0
        largeTitlePicker.selectedSegmentIndex = usesLargeTitle ? 1 : 0
        buttonSizePicker.selectedSegmentIndex = buttonSize.flatMap { buttonSizes.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        presentationPicker.selectedSegmentIndex = presentationIndex
        iconPicker.selectedSegmentIndex = iconIndex
        axisPicker.selectedSegmentIndex = axisIndex
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let size = titleSize.map { "\(Int($0)) pt" } ?? "系统"
        let buttons = buttonSize.map { "\(Int($0)) pt" } ?? "跟随标题"
        let subtitle = showsSubtitle ? "开" : "关"
        let large = usesLargeTitle ? "开" : "关"
        let text = "标题：\(size) / \(colorNames[colorIndex])\n按钮：\(buttons)\n图标：\(iconNames[iconIndex]) / 方向：\(axisNames[axisIndex])\n副标题：\(subtitle) / 大标题：\(large)\n形态：\(presentationNames[presentationIndex])"
        let full = message.map { text + "\n" + $0 } ?? text
        if status.text != full { status.text = full }
    }
}
