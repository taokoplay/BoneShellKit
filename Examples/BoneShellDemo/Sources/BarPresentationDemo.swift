import UIKit
import BoneShellKit

@MainActor
final class BarPresentationDemoController: DemoStackController {
    private let picker = UISegmentedControl(items: ["系统", "经典"])
    private let status = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    private var showsBackground = false

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "栏位类型"
        screen.navigation.subtitle = "系统与经典"
        if showsBackground {
            screen.backgroundComposition = .unified
            screen.background = DemoBackgroundAssets.configuration(0)
        }
        screen.navigation.trailingActions = [NavigationAction(id: "presentation.next", title: "详情", symbol: "arrow.right", priority: 20, handler: { [weak self] in self?.openDetail() })]
    }

    override func buildDemo() {
        intro("经典风格，平直栏位", "经典类型参考 iOS 26 以前的导航和底部标签：全宽栏位、普通按钮，没有悬浮胶囊。系统类型跟随当前系统。")
        picker.accessibilityIdentifier = "presentation.picker"
        picker.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.selectPresentation(self.picker.selectedSegmentIndex == 1 ? .classic : .system)
        }, for: .valueChanged)
        card([DemoStyle.label("导航与标签类型", style: .headline), picker])
        status.accessibilityIdentifier = "presentation.status"
        card([status])
        button("显示或关闭整体背景", symbol: "photo", id: "presentation.background") { [weak self] in
            guard let self = self else { return }
            self.showsBackground.toggle()
            self.refreshScreenConfiguration()
            self.updateStatus()
        }
        button("打开输入详情", symbol: "arrow.right", id: "presentation.detail") { [weak self] in self?.openDetail() }
        button("恢复系统类型", symbol: "arrow.uturn.backward", id: "presentation.reset") { [weak self] in self?.selectPresentation(.system) }
        card([DemoStyle.label("继续使用已有配置", style: .headline), DemoStyle.label("字号、颜色、普通与选中图标仍可设置。整体背景保持一幅画面，切换标签或栏位类型不重建页面内容。", style: .subheadline, color: .secondaryLabel)])
        stack.addArrangedSubview(DemoStyle.label("类型只控制 SDK 的导航和标签栏。系统菜单、键盘、Sheet 及材质对照中的内容仍按真实系统和各自配置呈现。", style: .footnote, color: .secondaryLabel))
        syncPicker()
        updateStatus()
    }

    func selectPresentation(_ presentation: ShellBarPresentation) {
        if let tabs = tabBarController as? BoneTabBarController { tabs.barPresentation = presentation }
        else { (navigationController as? BoneNavigationController)?.barPresentation = presentation }
        syncPicker()
        updateStatus()
    }

    @discardableResult
    func openDetail() -> BarPresentationDetailController {
        let detail = BarPresentationDetailController()
        detail.pageTitle = "类型与输入"
        if showsBackground { detail.sharedBackground = DemoBackgroundAssets.configuration(0) }
        navigationController?.pushViewController(detail, animated: true)
        return detail
    }

    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); syncPicker(); updateStatus() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updateStatus() }

    private func syncPicker() {
        let presentation = (tabBarController as? BoneTabBarController)?.resolvedBarPresentation ?? resolvedBarPresentation
        picker.selectedSegmentIndex = presentation == .classic ? 1 : 0
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let navigation = (navigationController as? BoneNavigationController)?.resolvedBarPresentation ?? resolvedBarPresentation
        let tabs = (tabBarController as? BoneTabBarController)?.resolvedBarPresentation ?? resolvedBarPresentation
        let text = "导航：\(navigation == .classic ? "经典" : "系统")\n标签：\(tabs == .classic ? "经典" : "系统")\n背景：\(showsBackground ? "整体画布" : "默认")"
        let backgroundStatus = showsBackground ? "\n整体：\(activeBackgroundView.status.sourceKind) / \(activeBackgroundView.status.phase.rawValue)" : ""
        if showsBackground { activeBackgroundView.onStatusChange = { [weak self] _ in self?.updateStatus() } }
        let fullText = text + backgroundStatus
        if status.text != fullText { status.text = fullText }
    }
}

@MainActor
final class BarPresentationDetailController: FormDemoController {
    var sharedBackground: ShellBackgroundConfiguration?
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        super.configureScreen(&screen)
        if let sharedBackground = sharedBackground {
            screen.backgroundComposition = .unified
            screen.background = sharedBackground
        }
        screen.navigation.trailingActions.append(NavigationAction(id: "presentation.toggle", title: "切换类型", symbol: "rectangle.3.group", priority: 10, handler: { [weak self] in
            guard let self = self else { return }
            if let tabs = self.tabBarController as? BoneTabBarController {
                tabs.barPresentation = tabs.resolvedBarPresentation == .classic ? .system : .classic
            } else if let navigation = self.navigationController as? BoneNavigationController {
                navigation.barPresentation = navigation.resolvedBarPresentation == .classic ? .system : .classic
            }
        }))
    }
}
