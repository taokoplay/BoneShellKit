import UIKit
import BoneShellKit

@MainActor
final class DemoCatalogController: DemoStackController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "BoneShellKit"
        screen.navigation.usesLargeTitle = true
    }
    override func buildDemo() {
        intro("页面骨架，交给系统适配", "0.4 验证版 · 栏位字体、图标与多媒体背景。")
        let scenes: [(String, String, String, String, () -> UIViewController)] = [
            ("导航与多按钮", "优先级、更多菜单与导航外观", "rectangle.topthird.inset.filled", "navigation", { NavigationDemoController() }),
            ("背景与切页", "图片、动图、MP4、HTML 与缓存", "photo.on.rectangle.angled", "backgrounds", { BackgroundDemoController() }),
            ("栏位字体与图标", "字号、颜色与普通 / 选中图标", "textformat.size", "bar-style", { BarStyleDemoController() }),
            ("窗口与安全区", "实时查看当前窗口与内容区域", "arrow.up.left.and.arrow.down.right", "adaptive", { AdaptiveDemoController() }),
            ("表单与键盘", "输入、保存与键盘避让", "keyboard", "form", { FormDemoController() }),
            ("标签状态保留", "输入文字，切换标签后再回来", "square.stack.3d.up", "state", { let page = FormDemoController(); page.pageTitle = "标签状态保留"; return page }),
            ("返回与弹出页面", "原生返回、详情与 sheet", "arrow.left.arrow.right", "transitions", { TransitionDemoController() }),
            ("玻璃材质对照", "原生玻璃、仿玻璃与实色", "circle.lefthalf.filled", "material", { MaterialDemoController() })
        ]
        for (title, detail, symbol, id, make) in scenes {
            stack.addArrangedSubview(DemoRow(title: title, detail: detail, symbol: symbol, id: "scene.\(id)") { [weak self] in
                self?.navigationController?.pushViewController(make(), animated: true)
            })
        }
        stack.addArrangedSubview(DemoRow(title: "列表与详情分栏", detail: "宽窗口展开，紧凑窗口保留详情", symbol: "sidebar.left", id: "scene.split") { [weak self] in
            let split = DemoSplitFactory.make()
            split.modalPresentationStyle = .fullScreen
            self?.present(split, animated: true)
        })
        stack.addArrangedSubview(DemoStyle.label("所有示例仅使用本地演示数据，不读取手机中的个人资料。", style: .footnote, color: .secondaryLabel))
    }
}

@MainActor
final class NavigationDemoController: DemoStackController {
    private var actionCount = 3
    private var eventCount = 0
    private var classic = false
    private let eventLabel = DemoStyle.label("点击导航操作，查看结果", style: .headline)
    private let layoutLabel = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    private let countLabel = DemoStyle.label("右侧操作：3 个")
    private let stepper = UIStepper()
    private let actionNames = ["新增", "收藏", "分享", "筛选", "排序", "刷新", "归档", "帮助"]
    private let symbols = ["plus", "star", "square.and.arrow.up", "line.3.horizontal.decrease", "arrow.up.arrow.down", "arrow.clockwise", "archivebox", "questionmark.circle"]

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "导航与多按钮"
        screen.navigation.subtitle = "按优先级保留主要操作"
        screen.navigation.material = classic ? .solid : .automatic
        screen.navigation.leadingActions = [NavigationAction(id: "leading", title: "标记", symbol: "pin", handler: { [weak self] in self?.record("标记") })]
        screen.navigation.trailingActions = (0..<actionCount).map { index in
            NavigationAction(id: "nav.\(index)", title: actionNames[index], symbol: symbols[index], priority: index == 0 ? 20 : 0, handler: { [weak self] in
                guard let self = self else { return }
                self.record(self.actionNames[index])
            })
        }
    }
    override func buildDemo() {
        intro("多操作，自动分配空间", "增加右侧操作数量。空间不足时，次要操作进入更多菜单；系统返回按钮仍然保留。")
        eventLabel.accessibilityIdentifier = "navigation.event"
        layoutLabel.accessibilityIdentifier = "navigation.layout"
        card([eventLabel, layoutLabel])
        stepper.minimumValue = 0
        stepper.maximumValue = 8
        stepper.value = Double(actionCount)
        stepper.accessibilityIdentifier = "navigation.count"
        stepper.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.actionCount = Int(self.stepper.value)
            self.updateActions()
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [countLabel, stepper])
        row.alignment = .center
        row.spacing = 12
        card([row])
        button("增加一个操作", symbol: "plus.circle", id: "navigation.add-action") { [weak self] in
            guard let self = self else { return }
            self.actionCount = min(8, self.actionCount + 1)
            self.stepper.value = Double(self.actionCount)
            self.updateActions()
        }
        button("切换导航背景", symbol: "paintbrush", id: "navigation.material") { [weak self] in
            guard let self = self else { return }
            self.classic.toggle()
            self.refreshScreenConfiguration()
        }
        button("打开详情页面", symbol: "arrow.right", id: "navigation.detail") { [weak self] in
            self?.navigationController?.pushViewController(FormDemoController(), animated: true)
        }
        stack.addArrangedSubview(DemoStyle.label("导航背景切换使用公开 Appearance API。严格统一的自定义经典栏位仍在后续规划中。", style: .footnote, color: .secondaryLabel))
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let value = "可见：\(visibleActionIDs.count) · 更多：\(overflowActionIDs.count)"
        if layoutLabel.text != value { layoutLabel.text = value }
    }
    private func updateActions() {
        countLabel.text = "右侧操作：\(actionCount) 个"
        refreshScreenConfiguration()
        view.setNeedsLayout()
    }
    private func record(_ name: String) {
        eventCount += 1
        eventLabel.text = "已触发 \(eventCount) 次：\(name)"
    }
}

@MainActor
class FormDemoController: DemoStackController {
    var pageTitle = "表单与键盘"
    var showsCloseButton = false
    let input = UITextField()
    let notes = UITextView()
    private let status = DemoStyle.label("尚未保存", style: .footnote, color: .secondaryLabel)
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = pageTitle
        screen.avoidsKeyboard = true
        screen.navigation.trailingActions = [NavigationAction(id: "save", title: "保存", symbol: "checkmark", priority: 20, handler: { [weak self] in
            guard let self = self else { return }
            self.view.endEditing(true)
            self.status.text = "已保存：\(self.input.text ?? "")"
        })]
        if showsCloseButton {
            screen.navigation.leadingActions = [NavigationAction(id: "close", title: "关闭", symbol: "xmark", handler: { [weak self] in self?.dismiss(animated: true) })]
        }
    }
    override func buildDemo() {
        intro("内容留在原来的页面", "输入一段文字，切换底部标签，再回到“示例”。导航栈和输入内容应保持。")
        input.placeholder = "输入一段测试文字"
        input.borderStyle = .roundedRect
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.autocorrectionType = .no
        input.accessibilityIdentifier = "state.input"
        input.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        notes.font = .preferredFont(forTextStyle: .body)
        notes.adjustsFontForContentSizeCategory = true
        notes.text = "这里也可以输入多行文字。"
        notes.backgroundColor = .tertiarySystemGroupedBackground
        notes.layer.cornerRadius = 12
        notes.accessibilityIdentifier = "state.notes"
        notes.heightAnchor.constraint(equalToConstant: 160).isActive = true
        status.accessibilityIdentifier = "form.status"
        card([DemoStyle.label("测试内容", style: .headline), input, notes, status])
        button("收起键盘", symbol: "keyboard.chevron.compact.down", id: "form.dismiss-keyboard") { [weak self] in self?.view.endEditing(true) }
        for index in 1...3 {
            card([DemoStyle.label("内容区域 \(index)", style: .headline), DemoStyle.label("滚动页面时，内容由 SDK 提供的布局区域承载。打开键盘后，检查当前输入和操作是否仍可访问。", style: .subheadline, color: .secondaryLabel)])
        }
    }
}

@MainActor
final class AdaptiveDemoController: DemoStackController {
    private let values = DemoStyle.label("", style: .body)
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "窗口与安全区"
    }
    override func buildDemo() {
        intro("读取当前窗口，不缓存屏幕尺寸", "旋转设备或调整 iPad 窗口。以下数值来自当前页面，会随布局实时更新。")
        values.accessibilityIdentifier = "adaptive.values"
        card([values])
        card([DemoStyle.label("自适应原则", style: .headline), DemoStyle.label("交互内容位于安全区域；背景可以延伸。导航和标签使用系统容器，栏位位置交给系统根据当前环境处理。", style: .body)])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset = view.safeAreaInsets
        let widthClass = traitCollection.horizontalSizeClass == .regular ? "Regular" : "Compact"
        let text = "窗口  \(Int(view.bounds.width)) × \(Int(view.bounds.height)) pt\n内容  \(Int(contentView.bounds.width)) × \(Int(contentView.bounds.height)) pt\n安全区  上 \(Int(inset.top)) · 下 \(Int(inset.bottom))\n左右  \(Int(inset.left)) / \(Int(inset.right))\n宽度类别  \(widthClass)\n系统  iOS \(UIDevice.current.systemVersion)"
        if values.text != text { values.text = text }
    }
}

@MainActor
final class TransitionDemoController: DemoStackController {
    override func configureScreen(_ screen: inout ScreenConfiguration) { screen.navigation.title = "返回与弹出页面" }
    override func buildDemo() {
        intro("使用系统的导航行为", "进入详情后尝试边缘返回；弹出表单后，可以用关闭按钮或系统下拉手势返回。")
        button("Push 详情", symbol: "arrow.right", id: "transition.push") { [weak self] in self?.navigationController?.pushViewController(FormDemoController(), animated: true) }
        button("打开 Sheet", symbol: "rectangle.bottomhalf.inset.filled", id: "transition.sheet") { [weak self] in
            let page = FormDemoController()
            page.pageTitle = "弹出表单"
            page.showsCloseButton = true
            let navigation = BoneNavigationController(rootViewController: page)
            navigation.modalPresentationStyle = .pageSheet
            self?.present(navigation, animated: true)
        }
    }
}

@MainActor
final class AboutDemoController: DemoStackController {
    private let backgroundState = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateBackgroundState()
        DispatchQueue.main.async { [weak self] in self?.updateBackgroundState() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updateBackgroundState() }
    private func updateBackgroundState() {
        guard isViewLoaded else { return }
        let text = "动态背景运行：\(ShellBackgroundPlaybackBudget.activeCount(in: view.window?.windowScene))"
        if backgroundState.text != text { backgroundState.text = text }
    }
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "关于"
        screen.navigation.usesLargeTitle = true
    }
    override func buildDemo() {
        intro("BoneShellKit", "0.4.0 · 原生 UIKit SDK 与独立 Demo")
        backgroundState.accessibilityIdentifier = "about.backgrounds"
        card([backgroundState])
        card([DemoStyle.label("本版可体验", style: .headline), DemoStyle.label("原生导航与标签容器\n栏位字体、颜色与标签图标\n三处多媒体背景\n操作优先级与更多菜单\n安全区、表单与键盘\n列表详情分栏\n原生玻璃、仿玻璃与实色表面")])
        card([DemoStyle.label("兼容方式", style: .headline), DemoStyle.label("部署目标 iOS 15。原生玻璃使用 iOS 26 公开 API，旧版本采用公开模糊材质。系统版本与辅助功能设置决定实际效果。", style: .subheadline, color: .secondaryLabel)])
        card([DemoStyle.label("后续规划", style: .headline), DemoStyle.label("完整自定义栏位渲染器、更多页面 adapter，以及全部系统与设备矩阵的验收。当前安装包用于验证最小真实实现。", style: .subheadline, color: .secondaryLabel)])
    }
}
