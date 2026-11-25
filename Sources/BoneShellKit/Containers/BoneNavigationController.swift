import UIKit

@MainActor
/// 管理导航栈、经典导航栏、系统导航栏和页面背景的 Shell 导航控制器。
open class BoneNavigationController: UINavigationController {
    /// 请求的导航栏呈现模式；为空时继承外层标签栏容器，独立导航控制器默认为系统模式。
    public var barPresentation: ShellBarPresentation? {
        didSet { refreshCurrentBackground() }
    }
    /// 当前导航容器解析出的实际导航栏呈现模式。
    ///
    /// SDK 没有自绘胶囊导航栏，因此 iOS 26 以下的胶囊请求会回退为经典导航栏。
    public var resolvedBarPresentation: ShellBarPresentation {
        let requested = ShellBarBackgroundHost.topScreen(in: topViewController)?.screenConfiguration.barPresentation
            ?? barPresentation ?? (tabBarController as? BoneTabBarController)?.barPresentation ?? .system
        switch ShellBarRendering.navigation(requested, supportsNativeCapsule: ShellBarPresentation.supportsNativeCapsule) {
        case .classic: return .classic
        case .capsule: return .capsule
        case .dock: return .capsule
        case .native: return .system
        }
    }
    /// SDK 绘制的经典导航栏视图；当前呈现模式不是经典栏时为空。
    public var classicNavigationBarView: UIView? {
        resolvedBarPresentation == .classic ? classicNavigationBar : nil
    }
    private var classicNavigationBar: ShellClassicNavigationBar?
    private var originalNavigationBarAlpha: CGFloat?
    private var originalNavigationBarAccessibilityHidden = false
    private var layingOutClassicNavigationBar = false
    @MainActor private final class ClassicNavigationInset {
        weak var controller: UIViewController?
        var contribution: CGFloat = 0
        init(_ controller: UIViewController) { self.controller = controller }
        func restore() {
            guard let controller = controller, contribution != 0 else { return }
            var insets = controller.additionalSafeAreaInsets
            insets.top -= contribution
            contribution = 0
            controller.additionalSafeAreaInsets = insets
        }
    }
    private var classicNavigationInsets: [ObjectIdentifier: ClassicNavigationInset] = [:]
    private var updatingBarPresentation = false
    private var backgroundNavigationSurface: UIView {
        if resolvedBarPresentation == .classic, let bar = classicNavigationBar { return bar }
        return navigationBar
    }

    internal func refreshBarPresentation() {
        guard isViewLoaded, !updatingBarPresentation else { return }
        updatingBarPresentation = true
        defer { updatingBarPresentation = false }
        if resolvedBarPresentation == .classic {
            if originalNavigationBarAlpha == nil {
                originalNavigationBarAlpha = navigationBar.alpha
                originalNavigationBarAccessibilityHidden = navigationBar.accessibilityElementsHidden
            }
            if classicNavigationBar == nil {
                let bar = ShellClassicNavigationBar()
                bar.onBack = { [weak self] in self?.popViewController(animated: true) }
                classicNavigationBar = bar
            }
            navigationBar.alpha = 0
            navigationBar.accessibilityElementsHidden = true
            let page = ShellBarBackgroundHost.topScreen(in: topViewController)
            let configuration = page?.screenConfiguration.navigation
            let background = configuration?.background ?? backgroundConfiguration
            let media = page?.usesUnifiedBackground == true || (background.map { !$0.source.isEmpty } ?? false)
            let item = topViewController?.navigationItem
            classicNavigationBar?.tintColor = navigationBar.tintColor
            classicNavigationBar?.update(title: configuration?.title ?? item?.title ?? topViewController?.title ?? "",
                subtitle: configuration?.subtitle, largeTitle: configuration?.usesLargeTitle ?? false,
                showsBack: viewControllers.count > 1 && item?.hidesBackButton != true,
                leadingItems: item?.leftBarButtonItems ?? [], trailingItems: item?.rightBarButtonItems ?? [],
                style: configuration?.style ?? navigationStyle, material: configuration?.material ?? .automatic,
                showsMediaBackground: media, customTitleView: page?.customTitleForClassicBar())
            layoutClassicNavigationBar()
        } else {
            if let alpha = originalNavigationBarAlpha {
                navigationBar.alpha = alpha
                navigationBar.accessibilityElementsHidden = originalNavigationBarAccessibilityHidden
                originalNavigationBarAlpha = nil
            }
            classicNavigationBar?.isHidden = true
            classicNavigationBar?.clearCustomTitleView()
            classicNavigationBar?.detachCustomActions()
            classicNavigationBar?.removeFromSuperview()
            for inset in classicNavigationInsets.values { inset.restore() }
            classicNavigationInsets.removeAll()
            ShellBarBackgroundHost.topScreen(in: topViewController)?.installNativeCustomTitle()
        }
        if #available(iOS 27.1, *) { setNeedsUpdateOfVerticalBarConfiguration() }
    }

    private func layoutClassicNavigationBar() {
        guard resolvedBarPresentation == .classic, let bar = classicNavigationBar,
              let parent = navigationBar.superview, !layingOutClassicNavigationBar else { return }
        layingOutClassicNavigationBar = true
        defer { layingOutClassicNavigationBar = false }
        navigationBar.alpha = 0
        var frame = navigationBar.convert(navigationBar.bounds, to: parent)
        let containerFrame = navigationBar.convert(navigationBar.bounds, to: view)
        let top = max(0, min(view.safeAreaInsets.top, containerFrame.minY - view.bounds.minY))
        frame.origin.y -= top
        frame.size.height += top
        bar.topInset = top
        if bar.superview !== parent { parent.insertSubview(bar, aboveSubview: navigationBar) }
        if bar.frame != frame { bar.frame = frame }
        bar.isHidden = isNavigationBarHidden || navigationBar.isHidden
        if transitionCoordinator == nil { restoreRemovedClassicNavigationInsets() }
        if let page = topViewController, page.isViewLoaded {
            let id = ObjectIdentifier(page)
            let inset = classicNavigationInsets[id] ?? ClassicNavigationInset(page)
            classicNavigationInsets[id] = inset
            let headerBottom = bar.convert(bar.bounds, to: page.view).maxY - page.view.bounds.minY
            // 容器与页面的原生安全区可能不同；从页面实测值扣除本 SDK 的旧贡献。
            // 保留宿主自己的 additionalSafeAreaInsets，避免遮挡或重复预留栏位高度。
            let pageSafeTopWithoutContribution = page.view.safeAreaInsets.top - inset.contribution
            let desired: CGFloat = bar.isHidden ? 0 : max(0, headerBottom - max(0, pageSafeTopWithoutContribution))
            if abs(desired - inset.contribution) > 0.1 {
                var safe = page.additionalSafeAreaInsets
                safe.top += desired - inset.contribution
                inset.contribution = desired
                page.additionalSafeAreaInsets = safe
            }
        }
        parent.bringSubviewToFront(bar)
    }

    private func restoreRemovedClassicNavigationInsets() {
        let retained = Set(viewControllers.map { ObjectIdentifier($0) })
        for (id, inset) in classicNavigationInsets where !retained.contains(id) {
            inset.restore()
            classicNavigationInsets[id] = nil
        }
    }

    /// iOS 27.1+ 的竖向系统栏行为；经典栏位会关闭系统竖向迁移。
    @available(iOS 27.1, *)
    open override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        resolvedBarPresentation == .classic ? .disabled : .automatic
    }

    /// iOS 27.1+ 负责竖向栏行为的子控制器；经典栏位不交给子控制器迁移。
    @available(iOS 27.1, *)
    open override var childForPreferredVerticalBarBehavior: UIViewController? {
        resolvedBarPresentation == .classic ? nil : topViewController
    }


    internal var shellUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
    /// 当前导航容器使用的统一背景视图；没有已应用配置时为空。
    public var unifiedBackgroundView: ShellBackgroundView? {
        guard let host = shellUnifiedBackgroundHost, host.view.configuration != nil else { return nil }
        return host.view
    }
    internal func ensureUnifiedBackgroundHost() -> ShellUnifiedBackgroundHost {
        if let host = shellUnifiedBackgroundHost { return host }
        let host = ShellUnifiedBackgroundHost(container: self)
        shellUnifiedBackgroundHost = host
        return host
    }

    /// 导航栏标题和按钮的文字样式。
    public var navigationStyle = ShellNavigationStyle() {
        didSet { refreshCurrentBackground() }
    }
    private var originalButtonTint: UIColor?
    private var overridesButtonTint = false

    internal func applyShellButtonTint(_ color: UIColor?) {
        if let color = color {
            if !overridesButtonTint { originalButtonTint = navigationBar.tintColor; overridesButtonTint = true }
            navigationBar.tintColor = color
        } else if overridesButtonTint {
            navigationBar.tintColor = originalButtonTint
            originalButtonTint = nil
            overridesButtonTint = false
        }
    }
    /// 导航栏背景配置；为空时不显示独立导航栏背景。
    public var backgroundConfiguration: ShellBackgroundConfiguration? {
        didSet { refreshCurrentBackground() }
    }
    /// 当前导航栏使用的背景视图；没有背景配置时为空。
    public var backgroundView: ShellBackgroundView? { backgroundHost?.view }
    private var backgroundHost: ShellBarBackgroundHost?
    private var legacySnapshot: ShellNavigationBackgroundSnapshot?
    private var shellIsVisible = false

    /// 使用指定根控制器创建导航控制器。
    /// - Parameter rootViewController: 导航栈的根页面控制器。
    public override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        navigationBar.prefersLargeTitles = true
    }

    /// 从归档恢复导航控制器。
    /// - Parameter coder: 用于解码控制器的归档对象。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        navigationBar.prefersLargeTitles = true
    }

    /// 导航控制器即将显示时刷新栏位和背景。
    /// - Parameter animated: 导航控制器出现是否带有动画。
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shellIsVisible = false
        refreshCurrentBackground()
    }

    /// 导航控制器完成显示后恢复背景播放。
    /// - Parameter animated: 导航控制器出现是否带有动画。
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shellIsVisible = true
        refreshCurrentBackground()
    }

    /// 导航控制器即将隐藏时暂停背景播放。
    /// - Parameter animated: 导航控制器消失是否带有动画。
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shellIsVisible = false
        backgroundView?.setPlaybackActive(false)
        shellUnifiedBackgroundHost?.pause()
    }

    /// 导航控制器布局完成后同步经典导航栏和背景位置。
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutClassicNavigationBar()
        backgroundHost?.layout(in: backgroundNavigationSurface)
        shellUnifiedBackgroundHost?.layout()
    }

    /// 推入页面前预取其背景资源并刷新当前背景。
    /// - Parameters:
    ///   - viewController: 要推入导航栈的页面控制器。
    ///   - animated: 推入操作是否带有动画。
    open override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        prepareBackgrounds(for: viewController)
        backgroundView?.setPlaybackActive(false)
        super.pushViewController(viewController, animated: animated)
        refreshAfterTransition()
    }

    /// 弹出当前页面并在转换完成后刷新背景。
    /// - Parameter animated: 弹出操作是否带有动画。
    /// - Returns: 被弹出的页面控制器；没有可弹出页面时返回 nil。
    @discardableResult
    open override func popViewController(animated: Bool) -> UIViewController? {
        if viewControllers.count > 1 { prepareBackgrounds(for: viewControllers[viewControllers.count - 2]) }
        backgroundView?.setPlaybackActive(false)
        let result = super.popViewController(animated: animated)
        refreshAfterTransition()
        return result
    }
    private func prepareBackgrounds(for controller: UIViewController) {
        guard isViewLoaded, let page = ShellBarBackgroundHost.topScreen(in: controller) else { return }
        page.prepareBackgroundAssets(pageSize: tabBarController?.view.bounds.size ?? view.bounds.size, navigationSize: navigationBar.bounds.size, tabSize: tabBarController?.tabBar.bounds.size ?? .zero, scale: traitCollection.displayScale, traits: traitCollection)
    }
    private func refreshAfterTransition() {
        guard isViewLoaded else { return }
        if let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.restoreRemovedClassicNavigationInsets()
                self?.refreshCurrentBackground()
            }
        } else {
            restoreRemovedClassicNavigationInsets()
            refreshCurrentBackground()
        }
    }
    private func refreshCurrentBackground() {
        guard isViewLoaded else { return }
        if let page = ShellBarBackgroundHost.topScreen(in: topViewController), page.isViewLoaded {
            page.refreshShellBarBackgrounds(playbackActive: shellIsVisible)
        } else {
            if topViewController == nil || !(topViewController is BoneViewController) {
                shellUnifiedBackgroundHost?.deactivate()
                if let tabs = tabBarController as? BoneTabBarController, tabs.selectedViewController === self {
                    tabs.shellUnifiedBackgroundHost?.deactivate()
                }
            }
            applyShellBackground(nil, playbackActive: shellIsVisible)
            applyShellButtonTint(navigationStyle.buttons.color)
        }
    }
    internal func applyShellBackground(_ override: ShellBackgroundConfiguration?, playbackActive: Bool, unifiedBackground: Bool = false) {
        guard isViewLoaded else { return }
        let configuration = override ?? backgroundConfiguration
        let enabled = !unifiedBackground && (configuration.map { !$0.source.isEmpty } ?? false)
        refreshBarPresentation()
        if enabled, backgroundHost == nil {
            backgroundHost = ShellBarBackgroundHost(bar: navigationBar, container: view, priority: 20, extendsToStatusArea: true)
            backgroundHost?.view.accessibilityIdentifier = "shell.background.navigation"
        }
        backgroundHost?.layout(in: backgroundNavigationSurface)
        backgroundHost?.view.apply(enabled ? configuration : nil)
        backgroundHost?.view.setPlaybackActive(playbackActive && enabled)
        if !(topViewController is BoneViewController), let top = topViewController {
            if enabled {
                if legacySnapshot?.controller !== top {
                    legacySnapshot?.restore()
                    legacySnapshot = ShellNavigationBackgroundSnapshot(controller: top)
                }
                let appearance = ShellBarBackgroundHost.navigationAppearance()
                top.navigationItem.standardAppearance = appearance
                top.navigationItem.scrollEdgeAppearance = appearance
                top.navigationItem.compactAppearance = appearance
                top.navigationItem.compactScrollEdgeAppearance = appearance
            } else {
                legacySnapshot?.restore()
                legacySnapshot = nil
            }
        }
    }

    /// 页面状态栏样式由当前顶部控制器决定。
    open override var childForStatusBarStyle: UIViewController? { topViewController }
    /// 状态栏隐藏状态由当前顶部控制器决定。
    open override var childForStatusBarHidden: UIViewController? { topViewController }
    /// Home Indicator 自动隐藏状态由当前顶部控制器决定。
    open override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
}
