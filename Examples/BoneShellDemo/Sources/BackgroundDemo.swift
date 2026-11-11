import UIKit
import BoneShellKit

@MainActor
enum DemoBackgroundAssets {
    private static let overlayColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.58) : UIColor.white.withAlphaComponent(0.20)
    }
    static func url(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Backgrounds")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }
    static func configuration(_ index: Int) -> ShellBackgroundConfiguration {
        let poster = url("Background-Paper", "jpg").map(ShellBackgroundResource.file)
        let source: ShellBackgroundSource
        switch index {
        case 1: source = url("Background-Orbit", "gif").map { .animatedImage(.file($0)) } ?? .none
        case 2: source = url("Background-Drift", "mp4").map(ShellBackgroundSource.video) ?? .none
        case 3: source = url("Background-Aurora", "html").map(ShellBackgroundSource.htmlFile) ?? .none
        default: source = poster.map(ShellBackgroundSource.image) ?? .none
        }
        return ShellBackgroundConfiguration(source: source, poster: poster, overlayColor: overlayColor, fallbackColor: .systemGroupedBackground)
    }
    static func assign(_ configuration: ShellBackgroundConfiguration, scope: Int, screen: inout ScreenConfiguration) {
        screen.backgroundComposition = scope == 3 ? .unified : .independent
        screen.background = (scope == 0 || scope == 3 || scope == 4) ? configuration : nil
        screen.navigation.background = (scope == 1 || scope == 4) ? configuration : nil
        screen.tabBarBackground = (scope == 2 || scope == 4) ? configuration : nil
    }
    static func metrics(for page: BoneViewController) -> String {
        func describe(_ view: ShellBackgroundView?) -> String {
            guard let view = view, view.configuration != nil else { return "none / idle" }
            return "\(view.status.sourceKind) / \(view.status.phase.rawValue)"
        }
        let nav = page.navigationController as? BoneNavigationController
        let tabs = page.tabBarController as? BoneTabBarController
        let stats = ShellBackgroundCache.statistics
        let active = ShellBackgroundPlaybackBudget.activeCount(in: page.view.window?.windowScene)
        let playback = "播放：\(active)/\(ShellBackgroundPlaybackBudget.maximumActivePerScene)\n解码：\(stats.decodeCount) · 命中：\(stats.cacheHitCount)\n加载中：\(stats.inFlightCount)"
        if page.usesUnifiedBackground {
            let views: [ShellBackgroundView?] = [page.activeBackgroundView, page.backgroundView, nav?.backgroundView, tabs?.backgroundView, nav?.unifiedBackgroundView, tabs?.unifiedBackgroundView]
            let canvasCount = Set(views.compactMap { view -> ObjectIdentifier? in
                guard let view = view, view.configuration != nil else { return nil }
                return ObjectIdentifier(view)
            }).count
            return "模式：整体画布\n画布：\(canvasCount)\n整体：\(describe(page.activeBackgroundView))\n页面：共享画布\n导航：共享画布\n标签：共享画布\n\(playback)"
        }
        return "页面：\(describe(page.activeBackgroundView))\n导航：\(describe(nav?.backgroundView))\n标签：\(describe(tabs?.backgroundView))\n\(playback)"
    }
}

@MainActor
final class BackgroundDemoController: DemoStackController {
    private(set) var sourceIndex = 0
    private(set) var scopeIndex = 3
    private let metricsLabel = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    private let sourcePicker = UISegmentedControl(items: ["图片", "动图", "MP4", "HTML"])
    private var stressGeneration = 0

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "背景与切页"
        DemoBackgroundAssets.assign(DemoBackgroundAssets.configuration(sourceIndex), scope: scopeIndex, screen: &screen)
        screen.navigation.trailingActions = [NavigationAction(id: "background.next", title: "下一页", symbol: "arrow.right", priority: 20, handler: { [weak self] in self?.openDetail() })]
    }
    override func buildDemo() {
        intro("一幅背景，贯穿全屏", "默认「全部」让导航、页面和标签共享一幅连续背景；选择「分区」可让三个区域各自呈现。图片、动图、MP4 和 HTML 使用同一套配置，动态背景默认最多同时播放一个。")
        sourcePicker.selectedSegmentIndex = sourceIndex
        sourcePicker.accessibilityIdentifier = "background.source"
        sourcePicker.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.selectSource(self.sourcePicker.selectedSegmentIndex)
        }, for: .valueChanged)
        let scope = UISegmentedControl(items: ["页面", "导航", "标签", "全部", "分区"])
        scope.selectedSegmentIndex = scopeIndex
        scope.accessibilityIdentifier = "background.scope"
        scope.addAction(UIAction { [weak self, weak scope] _ in
            guard let self = self, let scope = scope else { return }
            self.selectScope(scope.selectedSegmentIndex)
        }, for: .valueChanged)
        let budget = UISegmentedControl(items: ["1 个", "2 个", "3 个"])
        budget.selectedSegmentIndex = max(0, min(2, ShellBackgroundPlaybackBudget.maximumActivePerScene - 1))
        budget.accessibilityIdentifier = "background.budget"
        budget.addAction(UIAction { [weak self, weak budget] _ in
            guard let budget = budget else { return }
            ShellBackgroundPlaybackBudget.maximumActivePerScene = budget.selectedSegmentIndex + 1
            self?.updateMetrics()
        }, for: .valueChanged)
        card([DemoStyle.label("背景类型", style: .headline), sourcePicker, DemoStyle.label("应用区域", style: .headline), scope, DemoStyle.label("同时运行的动态背景", style: .headline), budget])
        metricsLabel.accessibilityIdentifier = "background.status"
        card([DemoStyle.label("实时状态与缓存", style: .headline), metricsLabel])
        button("预加载后打开下一页", symbol: "arrow.right.circle", id: "background.detail") { [weak self] in self?.openDetail() }
        button("清缓存后打开下一页", symbol: "arrow.clockwise", id: "background.cold") { [weak self] in
            ShellBackgroundCache.removeAll()
            ShellBackgroundCache.resetStatistics()
            self?.openDetail()
        }
        button("连续切换 8 次", symbol: "bolt", id: "background.cycle") { [weak self] in self?.cycleSources() }
        stack.addArrangedSubview(DemoStyle.label("图片按目标像素解码；预加载不提前启动播放器或网页。离开页面即停止动态播放，HTML 在离屏后释放。减少动态效果或低电量时会采用静态表示。", style: .footnote, color: .secondaryLabel))
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        bindStatuses()
        updateMetrics()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMetrics()
    }
    override func viewWillDisappear(_ animated: Bool) {
        stressGeneration += 1
        super.viewWillDisappear(animated)
    }
    func selectSource(_ index: Int) {
        guard (0...3).contains(index) else { return }
        sourceIndex = index
        sourcePicker.selectedSegmentIndex = index
        refreshScreenConfiguration()
        bindStatuses()
        updateMetrics()
    }
    func selectScope(_ index: Int) {
        guard (0...4).contains(index) else { return }
        scopeIndex = index
        refreshScreenConfiguration()
        bindStatuses()
        updateMetrics()
    }
    private func bindStatuses() {
        let callback: (ShellBackgroundStatus) -> Void = { [weak self] _ in self?.updateMetrics() }
        activeBackgroundView.onStatusChange = callback
        if !usesUnifiedBackground {
            (navigationController as? BoneNavigationController)?.backgroundView?.onStatusChange = callback
            (tabBarController as? BoneTabBarController)?.backgroundView?.onStatusChange = callback
        }
    }
    private func updateMetrics() {
        guard isViewLoaded else { return }
        let text = DemoBackgroundAssets.metrics(for: self)
        if metricsLabel.text != text { metricsLabel.text = text }
    }
    private func openDetail() {
        let page = BackgroundDetailController()
        page.backgroundConfiguration = DemoBackgroundAssets.configuration(sourceIndex)
        page.backgroundScope = scopeIndex
        navigationController?.pushViewController(page, animated: true)
    }
    private func cycleSources() {
        stressGeneration += 1
        let generation = stressGeneration
        for (offset, index) in [1, 2, 3, 0, 2, 1, 3, 0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(offset) * 0.045) { [weak self] in
                guard let self = self, self.stressGeneration == generation else { return }
                self.selectSource(index)
            }
        }
    }
}

@MainActor
final class BackgroundDetailController: DemoStackController {
    var backgroundConfiguration = DemoBackgroundAssets.configuration(0)
    var backgroundScope = 3
    private let metricsLabel = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "背景详情"
        DemoBackgroundAssets.assign(backgroundConfiguration, scope: backgroundScope, screen: &screen)
    }
    override func buildDemo() {
        intro("同一资源，新的页面", "沿用前页的背景范围：「全部」共享整体画布，「分区」各自呈现。返回后恢复前页的配置与播放状态；图片和海报复用缓存。")
        metricsLabel.accessibilityIdentifier = "background.detail.status"
        card([metricsLabel])
        let input = UITextField()
        input.borderStyle = .roundedRect
        input.placeholder = "背景不截获输入与返回手势"
        input.accessibilityIdentifier = "background.detail.input"
        input.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        card([DemoStyle.label("交互内容", style: .headline), input])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let callback: (ShellBackgroundStatus) -> Void = { [weak self] _ in self?.updateMetrics() }
        activeBackgroundView.onStatusChange = callback
        if !usesUnifiedBackground {
            (navigationController as? BoneNavigationController)?.backgroundView?.onStatusChange = callback
            (tabBarController as? BoneTabBarController)?.backgroundView?.onStatusChange = callback
        }
        updateMetrics()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updateMetrics() }
    private func updateMetrics() {
        guard isViewLoaded else { return }
        let text = DemoBackgroundAssets.metrics(for: self)
        if metricsLabel.text != text { metricsLabel.text = text }
    }
}
