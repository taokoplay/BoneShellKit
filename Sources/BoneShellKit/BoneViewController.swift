import UIKit

/// Shell 页面控制器基类，负责页面配置、内容容器、背景和导航动作。
@MainActor
open class BoneViewController: UIViewController {
    /// 业务内容应添加到此容器；SDK 会负责其栏位边界和键盘布局。
    public let contentView = UIView()
    /// 页面独立背景视图；在统一背景模式下由容器背景替代显示。
    public let backgroundView = ShellBackgroundView()
    /// 当前页面实际采用的栏位呈现模式。
    public var resolvedBarPresentation: ShellBarPresentation {
        if let navigation = navigationController as? BoneNavigationController {
            return navigation.resolvedBarPresentation
        }
        if let tabs = tabBarController as? BoneTabBarController {
            return tabs.resolvedBarPresentation
        }
        return (screenConfiguration.barPresentation ?? .system)
            .resolved(supportsNativeCapsule: ShellBarPresentation.supportsNativeCapsule)
    }

    /// iOS 27.1+ 的竖向系统栏行为；经典栏位会关闭系统竖向迁移。
    @available(iOS 27.1, *)
    open override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        resolvedBarPresentation == .classic ? .disabled : .automatic
    }

    /// 页面是否正在使用贯穿页面和栏位的统一背景。
    public var usesUnifiedBackground: Bool {
        screenConfiguration.backgroundComposition == .unified && (screenConfiguration.background.map { !$0.source.isEmpty } ?? false)
    }
    /// 当前页面正在显示的背景视图；统一背景模式返回容器共享背景。
    public var activeBackgroundView: ShellBackgroundView {
        usesUnifiedBackground ? existingUnifiedBackgroundHost?.view ?? backgroundView : backgroundView
    }
    private var standaloneUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
    private weak var displayedUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
    private var isShellVisible = false
    /// 页面当前生效的完整配置，只读反映最近一次刷新结果。
    public private(set) var screenConfiguration = ScreenConfiguration()
    /// iOS 27+ 的原生导航使用系统分组、优先级与溢出，不预先按横向宽度裁剪。
    public var usesSystemNavigationActionLayout: Bool {
        if #available(iOS 27.0, *), navigationController != nil {
            return resolvedBarPresentation != .classic
        }
        return false
    }
    /// SDK 直接提交到栏位的动作 ID；系统布局下是候选项，不代表实际可见性。
    public private(set) var visibleActionIDs: [String] = []
    /// SDK 预先放入更多菜单的动作 ID；系统管理的溢出不包含在此数组中。
    public private(set) var overflowActionIDs: [String] = []

    private var hasBuiltContent = false
    private var contentConstraints: [NSLayoutConstraint] = []
    private var keyboardBottomConstraint: NSLayoutConstraint?
    private weak var primaryScrollView: UIScrollView?
    private var lastActionLayoutKey: ActionLayoutKey?
    private var scrollsUnderFloatingTabBar = false
    private var normalizingModuleSpacing = false

    private var moduleSpacingNormalizationScheduled = false
    private var originalBottomEdgeEffectHidden: Bool?
    private let bottomContentFade = ShellScrollBottomFade()
    private var subtitleTitleView: ShellSubtitleTitleView?
    private var customNavigationTitle: ShellNavigationTitleHost?

    @MainActor private final class NavigationActionState {
        var action: NavigationAction
        let item = ShellNavigationBarItem()
        var button: ShellNavButtonHost?
        var cluster: ShellNavButtonCluster?
        var group: UIBarButtonItemGroup?
        var lastNavButtonInvocation: CFTimeInterval = 0
        func invokeNavButton() {
            let now = CACurrentMediaTime()
            guard now - lastNavButtonInvocation > 0.5 else { return }
            lastNavButtonInvocation = now
            action.handler()
        }
        init(_ action: NavigationAction) { self.action = action }
    }
    private var navigationActionStates: [String: NavigationActionState] = [:]
    private var appliedSystemActionLayout = false
    private var pinnedSystemActionGroup: UIBarButtonItemGroup?
    private var pinnedSystemActionIDs = Set<String>()

    /// 创建没有 storyboard 的 Shell 页面控制器。
    public init() { super.init(nibName: nil, bundle: nil) }
    /// 从 storyboard 或归档恢复 Shell 页面控制器。
    /// - Parameter coder: 用于解码页面控制器的归档对象。
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    /// 声明页面的导航、栏位、背景和内容配置。
    /// - Parameter screen: SDK 每次刷新时重新生成的页面配置。
    open func configureScreen(_ screen: inout ScreenConfiguration) {}
    /// 在 SDK 内容容器中创建业务视图。
    /// - Parameter contentView: 由 SDK 管理边界的内容容器。
    open func buildContent(in contentView: UIView) {}

    /// 加载页面基础视图、初始配置和背景容器。
    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        backgroundView.playbackPriority = 30
        backgroundView.accessibilityIdentifier = "shell.background.page"
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(backgroundView, belowSubview: contentView)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        refreshScreenConfiguration()
        if !hasBuiltContent {
            buildContent(in: contentView)
            hasBuiltContent = true
        }
        updateShellBackgrounds(playbackActive: false)
    }

    /// 页面即将显示时应用导航、布局和背景配置。
    /// - Parameter animated: 页面出现是否带有动画。
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isShellVisible = false
        applyNavigationConfiguration()
        refreshContentLayoutForBars()
        updateShellBackgrounds(playbackActive: false)
        lastActionLayoutKey = nil
        updateNavigationActions()
    }

    /// 页面完成显示后恢复可见状态并开始背景播放。
    /// - Parameter animated: 页面出现是否带有动画。
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isShellVisible = true
        // A navigation pop can finish after viewWillAppear and let the outgoing
        // page's bar state win one last layout pass. Re-submit this page's actions
        // after the controller is actually visible.
        lastActionLayoutKey = nil
        updateNavigationActions()
        updateShellBackgrounds(playbackActive: true)
        restoreNativeCustomTitleIfNeeded()
    }

    /// 页面即将隐藏时暂停页面及容器背景播放。
    /// - Parameter animated: 页面消失是否带有动画。
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isShellVisible = false
        backgroundView.setPlaybackActive(false)
        (navigationController as? BoneNavigationController)?.backgroundView?.setPlaybackActive(false)
        (tabBarController as? BoneTabBarController)?.backgroundView?.setPlaybackActive(false)
        if navigationController == nil && tabBarController == nil { standaloneUnifiedBackgroundHost?.pause() }
    }

    /// 页面完成隐藏后结束统一背景的显示记录。
    /// - Parameter animated: 页面消失是否带有动画。
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayedUnifiedBackgroundHost?.finishDisplaying(self)
    }

    /// 页面子视图布局完成后同步键盘、导航动作和背景位置。
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLegacyKeyboardAvoidance()
        updateNavigationActions()
        normalizeNavigationModuleSpacing()
        scheduleNavigationModuleSpacingNormalization()
        standaloneUnifiedBackgroundHost?.layout()
        updateBottomContentFade()
    }
    private func scheduleNavigationModuleSpacingNormalization() {
        guard !moduleSpacingNormalizationScheduled else { return }
        moduleSpacingNormalizationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.moduleSpacingNormalizationScheduled = false
            self.normalizeNavigationModuleSpacing()
        }
    }


    /// 按模块可见边界重新对齐系统、兼容和经典栏位，消除 UIKit 与按钮内边距插入的额外间距。
    private func normalizeNavigationModuleSpacing() {
        guard !normalizingModuleSpacing else { return }
        let bar: UIView?
        if resolvedBarPresentation == .classic {
            bar = (navigationController as? BoneNavigationController)?.classicNavigationBarView
        } else {
            bar = navigationController?.navigationBar
        }
        guard let bar else { return }
        let spacing = screenConfiguration.navigation.moduleSpacing
        guard spacing.isFinite else { return }
        let leading = navigationModuleClusters(leading: true)
        let trailing = navigationModuleClusters(leading: false)
        guard leading.count > 1 || trailing.count > 1 else { return }

        normalizingModuleSpacing = true
        defer { normalizingModuleSpacing = false }
        bar.layoutIfNeeded()
        let value = max(0, spacing)
        normalizeModuleClusterFrames(leading, spacing: value, in: bar)
        normalizeModuleClusterFrames(trailing, spacing: value, in: bar)
    }

    private func navigationModuleClusters(leading: Bool) -> [ShellNavButtonCluster] {
        if #available(iOS 27.0, *), usesSystemNavigationActionLayout {
            var groups = leading ? navigationItem.leadingItemGroups : navigationItem.trailingItemGroups
            if !leading, let pinned = navigationItem.pinnedTrailingGroup { groups.append(pinned) }
            return groups.flatMap { group in
                group.barButtonItems.compactMap { $0.customView as? ShellNavButtonCluster }
            }
        }
        let items = leading ? (navigationItem.leftBarButtonItems ?? []) : (navigationItem.rightBarButtonItems ?? [])
        return items.compactMap { $0.customView as? ShellNavButtonCluster }
    }

    private func normalizeModuleClusterFrames(
        _ clusters: [ShellNavButtonCluster],
        spacing: CGFloat,
        in bar: UIView
    ) {
        // 只考虑真正落在栏内的模块：进入溢出菜单的模块仍留在 item group 里，但可能被移出
        // 栏位或压成零尺寸。算进来会按一个幽灵位置求偏移，把可见模块整体推走
        //（「完成」被推到返回键上、文字越出按钮边界）。
        let visible = clusters.filter { $0.isVisibleInBar(bar) }
        guard visible.count > 1 else { return }
        let vertical = visible.contains { $0.isVertical }
        visible.forEach { $0.setModuleVisualOffset(0) }
        bar.layoutIfNeeded()
        func frame(for cluster: ShellNavButtonCluster) -> CGRect {
            cluster.convert(cluster.moduleVisualBounds, to: bar)
        }
        func start(_ frame: CGRect) -> CGFloat { vertical ? frame.minY : frame.minX }
        func end(_ frame: CGRect) -> CGFloat { vertical ? frame.maxY : frame.maxX }
        let ordered = visible.sorted { start(frame(for: $0)) < start(frame(for: $1)) }
        let frames = ordered.map { frame(for: $0) }
        let widths = frames.map { end($0) - start($0) }
        let span = end(frames[frames.count - 1]) - start(frames[0])
        // 系统栏位给每个 item 的触控补偿会把它撑到超过 44 pt，可见边界之间因此多出空隙。
        // 校正只调整模块内部间距，剩余量在两侧均分；若把它全部推给后继模块，偏移会逐级累积，
        // 末位模块的胶囊会整体越出自身槽位（「完成」看起来贴到按钮边上）。
        let desired = widths.reduce(0, +) + spacing * CGFloat(ordered.count - 1)
        var cursor = start(frames[0]) + (span - desired) / 2
        for (index, cluster) in ordered.enumerated() {
            let delta = cursor - start(frames[index])
            // 超过一个模块宽度量级的偏移只可能来自错误的参考位置，直接跳过，
            // 避免把模块推出栏位。
            if abs(delta) > 0.01, abs(delta) <= widths[index] + spacing {
                cluster.setModuleVisualOffset(delta)
            }
            cursor += widths[index] + spacing
        }
        bar.layoutIfNeeded()
    }

    /// 安全区变化后重新计算栏位和页面内容布局。
    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard isViewLoaded else { return }
        if let navigation = navigationController as? BoneNavigationController,
           navigation.resolvedBarPresentation == .classic {
            navigation.refreshBarPresentation()
        }
        updateNavigationActions()
        refreshContentLayoutForBars()
    }

    /// 特征环境变化后按需要重新应用导航样式和动作布局。
    /// - Parameter previousTraitCollection: 变化前的特征环境。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        // Menu presentation can change unrelated traits. Replacing its source item in
        // response dismisses the native menu before the user can choose an action.
        let needsRestyling = previousTraitCollection.map { previous in
            previous.hasDifferentColorAppearance(comparedTo: traitCollection)
                || previous.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
                || previous.legibilityWeight != traitCollection.legibilityWeight
                || previous.layoutDirection != traitCollection.layoutDirection
                || previous.displayScale != traitCollection.displayScale
                || (!usesSystemNavigationActionLayout && (
                    previous.horizontalSizeClass != traitCollection.horizontalSizeClass
                    || previous.verticalSizeClass != traitCollection.verticalSizeClass))
                || previous.userInterfaceIdiom != traitCollection.userInterfaceIdiom
        } ?? true
        if needsRestyling {
            applyNavigationConfiguration()
            lastActionLayoutKey = nil
        }
        updateNavigationActions()
    }

    /// 重新执行页面声明，并更新导航、背景和布局，不重建业务内容或其滚动视图。
    public func refreshScreenConfiguration() {
        var configuration = ScreenConfiguration()
        configureScreen(&configuration)
        screenConfiguration = configuration
        guard isViewLoaded else { return }
        updateContentLayout()
        applyNavigationConfiguration()
        updateShellBackgrounds(playbackActive: isShellVisible)
        lastActionLayoutKey = nil
        updateNavigationActions()
        view.setNeedsLayout()
    }

    /// 注册页面主要滚动视图，使 SDK 能处理浮动标签栏和底部安全区。
    /// - Parameter scrollView: 页面承担主要滚动内容的滚动视图。
    public func registerPrimaryScrollView(_ scrollView: UIScrollView) {
        if #available(iOS 26.0, *), let hidden = originalBottomEdgeEffectHidden {
            primaryScrollView?.bottomEdgeEffect.isHidden = hidden
        }
        originalBottomEdgeEffectHidden = nil
        primaryScrollView = scrollView
        if isViewLoaded { updateContentLayout() }
    }

    internal func prepareBackgroundAssets(pageSize: CGSize, navigationSize: CGSize, tabSize: CGSize, scale: CGFloat, traits: UITraitCollection) {
        var configuration = ScreenConfiguration()
        configureScreen(&configuration)
        if let value = configuration.background {
            ShellBackgroundCache.prefetch(value, targetSize: pageSize, scale: scale, traits: traits)
        }
        if configuration.backgroundComposition == .unified { return }
        if let value = configuration.navigation.background ?? (navigationController as? BoneNavigationController)?.backgroundConfiguration {
            ShellBackgroundCache.prefetch(value, targetSize: navigationSize, scale: scale, traits: traits)
        }
        if let value = configuration.tabBarBackground ?? (tabBarController as? BoneTabBarController)?.backgroundConfiguration {
            ShellBackgroundCache.prefetch(value, targetSize: tabSize, scale: scale, traits: traits)
        }
    }

    internal func refreshShellBarBackgrounds(playbackActive: Bool) {
        guard isViewLoaded else { return }
        applyNavigationConfiguration()
        lastActionLayoutKey = nil
        updateNavigationActions()
        updateShellBackgrounds(playbackActive: playbackActive && isShellVisible)
    }

    private var sharedTabContainer: BoneTabBarController? {
        guard let tabs = tabBarController as? BoneTabBarController,
              tabs.selectedViewController === navigationController || tabs.selectedViewController === self else { return nil }
        return tabs
    }

    private var existingUnifiedBackgroundHost: ShellUnifiedBackgroundHost? {
        if let tabs = sharedTabContainer { return tabs.shellUnifiedBackgroundHost }
        if let navigation = navigationController as? BoneNavigationController { return navigation.shellUnifiedBackgroundHost }
        return standaloneUnifiedBackgroundHost
    }

    private func ensureUnifiedBackgroundHost() -> ShellUnifiedBackgroundHost {
        if let tabs = sharedTabContainer { return tabs.ensureUnifiedBackgroundHost() }
        if let navigation = navigationController as? BoneNavigationController { return navigation.ensureUnifiedBackgroundHost() }
        if let host = standaloneUnifiedBackgroundHost { return host }
        let host = ShellUnifiedBackgroundHost(container: self)
        standaloneUnifiedBackgroundHost = host
        return host
    }

    private var canPresentShellBackground: Bool {
        if let navigation = navigationController, navigation.topViewController !== self { return false }
        if let tabs = tabBarController,
           ShellBarBackgroundHost.topScreen(in: tabs.selectedViewController) !== self { return false }
        return true
    }

    private func updateShellBackgrounds(playbackActive: Bool) {
        guard hasBuiltContent, canPresentShellBackground else { return }
        let unified = usesUnifiedBackground
        if unified, let configuration = screenConfiguration.background {
            let host = ensureUnifiedBackgroundHost()
            if let previous = displayedUnifiedBackgroundHost, previous !== host { previous.finishDisplaying(self) }
            backgroundView.apply(nil)
            displayedUnifiedBackgroundHost = host
            host.activate(for: self, configuration: configuration, playbackActive: playbackActive)
        } else {
            existingUnifiedBackgroundHost?.deactivate()
            standaloneUnifiedBackgroundHost?.deactivate()
            displayedUnifiedBackgroundHost = nil
            backgroundView.apply(screenConfiguration.background)
            backgroundView.setPlaybackActive(playbackActive)
        }
        (navigationController as? BoneNavigationController)?.applyShellBackground(screenConfiguration.navigation.background,
            playbackActive: playbackActive, unifiedBackground: unified)
        (tabBarController as? BoneTabBarController)?.applyShellBackground(screenConfiguration.tabBarBackground,
            playbackActive: playbackActive, style: screenConfiguration.tabBarStyle, unifiedBackground: unified)
    }

    private var shouldScrollUnderFloatingTabBar: Bool {
        primaryScrollView != nil && !hidesBottomBarWhenPushed
            && (tabBarController as? BoneTabBarController)?.floatsAboveScrollContent == true
    }

    /// A presentation switch changes the viewport, not the scroll view or business content.
    internal func refreshContentLayoutForBars() {
        guard isViewLoaded, scrollsUnderFloatingTabBar != shouldScrollUnderFloatingTabBar else { return }
        updateContentLayout()
    }

    private func updateContentLayout() {
        keyboardBottomConstraint?.isActive = false
        NSLayoutConstraint.deactivate(contentConstraints)
        keyboardBottomConstraint = nil
        scrollsUnderFloatingTabBar = shouldScrollUnderFloatingTabBar
        let boundary = screenConfiguration.content == .safeArea
            ? view.safeAreaLayoutGuide : nil
        let top = boundary?.topAnchor ?? view.topAnchor
        let leading = boundary?.leadingAnchor ?? view.leadingAnchor
        let trailing = boundary?.trailingAnchor ?? view.trailingAnchor
        let bottom = scrollsUnderFloatingTabBar ? view.bottomAnchor : (boundary?.bottomAnchor ?? view.bottomAnchor)
        let preferredBottom = contentView.bottomAnchor.constraint(equalTo: bottom)
        preferredBottom.priority = .defaultHigh
        contentConstraints = [
            contentView.topAnchor.constraint(equalTo: top),
            contentView.leadingAnchor.constraint(equalTo: leading),
            contentView.trailingAnchor.constraint(equalTo: trailing),
            contentView.bottomAnchor.constraint(lessThanOrEqualTo: bottom),
            preferredBottom
        ]
        if screenConfiguration.avoidsKeyboard {
            let guide = view.keyboardLayoutGuide
            guide.followsUndockedKeyboard = false
            if #available(iOS 17.0, *) {
                guide.usesBottomSafeArea = screenConfiguration.content == .safeArea && !scrollsUnderFloatingTabBar
            }
            let limit = contentView.bottomAnchor.constraint(lessThanOrEqualTo: guide.topAnchor)
            keyboardBottomConstraint = limit
            if #available(iOS 17.0, *) {
                contentConstraints.append(limit)
            } else if screenConfiguration.content == .safeArea && !scrollsUnderFloatingTabBar {
                contentConstraints.append(limit)
            }
        }
        NSLayoutConstraint.activate(contentConstraints)
        updateLegacyKeyboardAvoidance()
        updateScrollViewPolicy()
    }

    private func updateLegacyKeyboardAvoidance() {
        if #available(iOS 17.0, *) { return }
        guard screenConfiguration.content == .underBars || scrollsUnderFloatingTabBar,
              let constraint = keyboardBottomConstraint else { return }
        // iOS 15–16 tie the hidden keyboard guide to the safe bottom. Only constrain
        // under-bar content to that guide while it actually obscures the view.
        let safeBottom = view.bounds.maxY - view.safeAreaInsets.bottom
        let obscuresContent = view.keyboardLayoutGuide.layoutFrame.minY < safeBottom - 0.5
        if constraint.isActive != obscuresContent { constraint.isActive = obscuresContent }
    }

    private func updateScrollViewPolicy() {
        guard let scrollView = primaryScrollView else { return }
        if scrollsUnderFloatingTabBar {
            // Extend the viewport; let UIKit add safe-area padding to the content so its last
            // row and scroll indicator can still clear the glass without clipping the list.
            scrollView.contentInsetAdjustmentBehavior = .always
        } else {
            scrollView.contentInsetAdjustmentBehavior = screenConfiguration.content == .safeArea
                ? .never : .automatic
        }
        if isViewLoaded { setContentScrollView(scrollView, for: .all) }
        if #available(iOS 26.0, *) {
            if scrollsUnderFloatingTabBar {
                if originalBottomEdgeEffectHidden == nil {
                    originalBottomEdgeEffectHidden = scrollView.bottomEdgeEffect.isHidden
                }
                scrollView.bottomEdgeEffect.isHidden = true
            } else if let hidden = originalBottomEdgeEffectHidden {
                scrollView.bottomEdgeEffect.isHidden = hidden
                originalBottomEdgeEffectHidden = nil
            }
        }
        updateBottomContentFade()
    }

    private func updateBottomContentFade() {
        // A keyboard-shortened viewport must not fade its controls above the keyboard.
        let reachesPageBottom = contentView.frame.maxY >= view.bounds.maxY - 0.5
        let height = scrollsUnderFloatingTabBar && reachesPageBottom
            ? screenConfiguration.floatingTabBarFadeHeight : 0
        bottomContentFade.update(in: contentView, height: height)
    }

    private var effectiveNavigationStyle: ShellNavigationStyle {
        screenConfiguration.navigation.style
            ?? (navigationController as? BoneNavigationController)?.navigationStyle
            ?? ShellNavigationStyle()
    }

    private func applyNavigationConfiguration() {
        let configuration = screenConfiguration.navigation
        let style = effectiveNavigationStyle
        navigationItem.title = configuration.title
        if customNavigationTitle?.content !== configuration.titleView {
            if let previous = customNavigationTitle {
                if navigationItem.titleView === previous { navigationItem.titleView = nil }
                if previous.content.superview === previous { previous.content.removeFromSuperview() }
            }
            customNavigationTitle = nil
            if let view = configuration.titleView, view.superview == nil, view.window == nil {
                customNavigationTitle = ShellNavigationTitleHost(content: view)
            }
        }
        let usesLargeTitle = customNavigationTitle == nil && configuration.usesLargeTitle
        navigationItem.largeTitleDisplayMode = usesLargeTitle ? .always : .never
        navigationItem.leftItemsSupplementBackButton = true
        if usesLargeTitle { navigationController?.navigationBar.prefersLargeTitles = true }
        if let customNavigationTitle {
            customNavigationTitle.updatePreferredWidth()
            subtitleTitleView = nil
            if #available(iOS 26.0, *) { navigationItem.subtitle = nil }
            if (navigationController as? BoneNavigationController)?.resolvedBarPresentation == .classic {
                _ = customTitleForClassicBar()
            } else {
                installNativeCustomTitle()
            }
        } else if #available(iOS 26.0, *) {
            navigationItem.titleView = nil
            subtitleTitleView = nil
            navigationItem.subtitle = configuration.subtitle
        } else if let subtitle = configuration.subtitle, !subtitle.isEmpty {
            let titleView = ShellSubtitleTitleView(title: configuration.title, subtitle: subtitle, style: style, traits: traitCollection)
            subtitleTitleView = titleView
            navigationItem.titleView = titleView
        } else {
            subtitleTitleView = nil
            navigationItem.titleView = nil
        }
        let material = ShellMaterials.currentResolution(for: configuration.material).resolved
        let bar = navigationController?.navigationBar
        let background = configuration.background ?? (navigationController as? BoneNavigationController)?.backgroundConfiguration
        let hasMedia = usesUnifiedBackground || (background.map { !$0.source.isEmpty } ?? false)
        func appearance(_ base: UINavigationBarAppearance?, scrollEdge: Bool = false) -> UINavigationBarAppearance? {
            ShellBarStyling.navigationAppearance(base: base, fallback: bar?.standardAppearance,
                scrollEdge: scrollEdge, style: style, material: material,
                mediaBackground: hasMedia, traits: traitCollection)
        }
        // Per-item attributes follow native navigation transitions and pop restoration.
        navigationItem.standardAppearance = appearance(bar?.standardAppearance)
        navigationItem.scrollEdgeAppearance = appearance(bar?.scrollEdgeAppearance, scrollEdge: true)
        navigationItem.compactAppearance = appearance(bar?.compactAppearance)
        navigationItem.compactScrollEdgeAppearance = appearance(bar?.compactScrollEdgeAppearance, scrollEdge: true)
        if let navigation = navigationController as? BoneNavigationController, navigation.topViewController === self {
            navigation.applyShellButtonTint(style.buttons.color)
        }
    }

    internal func customTitleForClassicBar() -> ShellNavigationTitleHost? {
        guard let host = customNavigationTitle else { return nil }
        if navigationItem.titleView === host { navigationItem.titleView = nil }
        return host
    }

    internal func installNativeCustomTitle() {
        guard let host = customNavigationTitle, !(host.superview is ShellClassicNavigationBar),
              navigationItem.titleView !== host else { return }
        navigationItem.titleView = host
    }

    /// 页面显示完成后恢复脱离窗口的原生导航标题。
    private func restoreNativeCustomTitleIfNeeded() {
        guard let host = customNavigationTitle, resolvedBarPresentation != .classic,
              let navigation = navigationController, navigation.topViewController === self,
              !navigation.isNavigationBarHidden, !navigation.navigationBar.isHidden,
              let window = navigation.navigationBar.window, viewIfLoaded?.window === window,
              host.window !== window else { return }

        // 转场可能移除标题宿主却保留 titleView 引用，先清空引用再提交才能重新挂载。
        if navigationItem.titleView === host { navigationItem.titleView = nil }
        installNativeCustomTitle()
    }

    private func updateNavigationActions() {
        let configuration = screenConfiguration.navigation
        let backTitle = systemBackTitle()
        let style = effectiveNavigationStyle
        let titleFont = style.title.resolvedFont(for: .headline, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        let subtitleFont = style.subtitle.resolvedFont(for: .caption1, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        let buttonFont = style.buttons.resolvedFont(for: .body, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let systemLayout = usesSystemNavigationActionLayout
        let key = ActionLayoutKey(
            width: view.bounds.width,
            leftInset: view.safeAreaInsets.left,
            rightInset: view.safeAreaInsets.right,
            backTitle: backTitle,
            textSize: titleFont.pointSize,
            systemLayout: systemLayout
        )
        // 原生布局只在声明或样式刷新时更新，尺寸变化由 UIKit 处理，保留菜单来源。
        if systemLayout && lastActionLayoutKey?.systemLayout == true {
            subtitleTitleView?.maximumWidth = max(44, (key.width - key.leftInset - key.rightInset) * 0.45)
            return
        }
        guard key != lastActionLayoutKey else { return }
        lastActionLayoutKey = key
        let leadingModules = configuration.leadingModules
        let trailingModules = configuration.trailingModules
        let allActions = ShellActionLayout.uniqueActions(
            (leadingModules + trailingModules).flatMap(\.actions)
        )
        let activeIDs = Set(allActions.map(\.id))
        for (id, state) in navigationActionStates where !activeIDs.contains(id) {
            state.button?.unmount()
            state.button?.removeFromSuperview()
            state.item.customView = nil
            state.item.classicSlot = nil
        }
        navigationActionStates = navigationActionStates.filter { activeIDs.contains($0.key) }
        for action in allActions { actionState(for: action).action = action }

        let leadingRuns = ShellNavButtonRun.collect(leadingModules, moduleSpacing: configuration.moduleSpacing)
        let trailingRuns = ShellNavButtonRun.collect(trailingModules, moduleSpacing: configuration.moduleSpacing)
        prepareNavButtons(leadingRuns + trailingRuns)
        let material = ShellMaterials.currentResolution(for: configuration.material).resolved
        if #available(iOS 27.0, *), systemLayout {
            customNavigationTitle?.maximumWidth = UIView.layoutFittingExpandedSize.width
            subtitleTitleView?.maximumWidth = max(44, (key.width - key.leftInset - key.rightInset) * 0.45)
            applySystemNavigationActions(leading: leadingRuns, trailing: trailingRuns, material: material)
            visibleActionIDs = allActions.map(\.id)
            overflowActionIDs = []
            return
        }
        clearSystemNavigationActions()

        let usableWidth = max(0, key.width - key.leftInset - key.rightInset - 32)
        let titleWidth = customNavigationTitle?.preferredWidth ?? max(
            (configuration.title as NSString).size(withAttributes: [.font: titleFont]).width,
            ((configuration.subtitle ?? "") as NSString).size(withAttributes: [.font: subtitleFont]).width
        )
        let preferredTitleBudget = min(max(88, titleWidth), usableWidth * 0.45)
        // Shorten the title before displacing a primary trailing action. When other
        // actions overflow, reserve both its touch target and the menu's target.
        let primaryWidth = trailingRuns.map(\.first).filter { $0.priority > 0 || $0.role == .confirmation }.map(navigationActionWidth).max()
        let primaryReserve: CGFloat = primaryWidth.map { $0 + (allActions.count > 1 ? 44 : 0) } ?? 0
        let titleBudget = min(preferredTitleBudget, max(44, usableWidth - 24 - primaryReserve * 2))
        subtitleTitleView?.maximumWidth = titleBudget
        customNavigationTitle?.maximumWidth = max(44, titleBudget)
        let backWidth = backTitle.map {
            min(128, max(44, ($0 as NSString).size(
                withAttributes: [.font: buttonFont]
            ).width + 28))
        } ?? 0
        // Give an empty side's share to the side that actually owns actions.
        let sideSpace = max(0, usableWidth - titleBudget - 24)
        let leadingSideBudget = trailingRuns.isEmpty ? sideSpace : sideSpace / 2
        let trailingSideBudget = leadingRuns.isEmpty ? sideSpace : sideSpace / 2
        // A run occupies one slot including its measured gaps; never split it when pruning.
        let leftHeads = leadingRuns.map(\.first), rightHeads = trailingRuns.map(\.first)
        let leadingVisible = Set(ShellActionLayout.visibleIDs(actions: leftHeads,
            availableWidth: max(0, leadingSideBudget - backWidth), width: navigationActionWidth))
        var trailingVisible = Set(ShellActionLayout.visibleIDs(actions: rightHeads,
            availableWidth: trailingSideBudget, width: navigationActionWidth))
        if leadingVisible.count + trailingVisible.count < leadingRuns.count + trailingRuns.count {
            trailingVisible = Set(ShellActionLayout.visibleIDs(actions: rightHeads,
                availableWidth: max(0, trailingSideBudget - 44), width: navigationActionWidth))
        }
        let leftRuns = leadingRuns.filter { leadingVisible.contains($0.first.id) }
        let rightRuns = trailingRuns.filter { trailingVisible.contains($0.first.id) }
        let visible = Set((leftRuns + rightRuns).flatMap { $0.actions.map(\.id) })
        visibleActionIDs = allActions.filter { visible.contains($0.id) }.map(\.id)
        let overflow = allActions.filter { !visible.contains($0.id) }
        overflowActionIDs = overflow.map(\.id)
        let leftItems = leftRuns.map { makeBarButton(for: $0, material: material) }
        var rightItems = rightRuns.map { makeBarButton(for: $0, material: material) }
        if !overflow.isEmpty {
            let menu = UIMenu(children: overflow.map(makeMenuAction))
            let item = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
            item.title = "More Actions"
            item.width = 44
            item.accessibilityLabel = "More Actions"
            item.accessibilityIdentifier = "shell.overflow"
            configureSharedBackground(for: item, material: material)
            rightItems.append(item)
        }
        navigationItem.leftBarButtonItems = leftItems.isEmpty ? nil : leftItems
        // UIKit places the first right item at the outer edge; preserve visual input order.
        navigationItem.rightBarButtonItems = rightItems.isEmpty ? nil : Array(rightItems.reversed())
        (navigationController as? BoneNavigationController)?.refreshBarPresentation()
        if #available(iOS 27.1, *) { setNeedsUpdateOfVerticalBarConfiguration() }
    }

    private func systemBackTitle() -> String? {
        guard !navigationItem.hidesBackButton,
              let controllers = navigationController?.viewControllers,
              let index = controllers.firstIndex(where: { $0 === self }), index > 0 else { return nil }
        let previous = controllers[index - 1]
        if previous.navigationItem.backButtonDisplayMode == .minimal { return "" }
        return previous.navigationItem.backBarButtonItem?.title
            ?? previous.navigationItem.backButtonTitle
            ?? previous.navigationItem.title
            ?? previous.title
            ?? "Back"
    }

    private func makeMenuAction(_ action: NavigationAction) -> UIAction {
        let result = UIAction(
            title: action.title,
            image: action.resolvedImage(traits: traitCollection),
            identifier: UIAction.Identifier("action.\(action.id)"),
            attributes: action.isEnabled ? [] : [.disabled]
        ) { [weak state = actionState(for: action)] _ in
            guard let state = state, state.action.isEnabled else { return }
            state.action.handler()
        }
        result.accessibilityIdentifier = "action.\(action.id)"
        return result
    }

    private func prepareNavButtons(_ runs: [ShellNavButtonRun]) {
        let heads = Set(runs.compactMap { $0.first.navButton == nil ? nil : $0.first.id })
        for (id, state) in navigationActionStates {
            if state.action.navButton == nil, let old = state.button {
                old.unmount()
                old.removeFromSuperview()
                state.button = nil
            }
            if !heads.contains(id), state.cluster != nil {
                state.item.customView = nil
                state.item.classicSlot = nil
                state.cluster = nil
            }
        }

        let textStyle = effectiveNavigationStyle.buttons
        let classic = resolvedBarPresentation == .classic
        for run in runs where run.first.navButton != nil {
            let head = actionState(for: run.first)
            let cluster = head.cluster ?? ShellNavButtonCluster()
            cluster.navigationBar = navigationController?.navigationBar
            // 模块进入或离开侧栏时重新提交条目：横竖两种承载的布局方式不同。
            // 轴向变化后 UIKit 需要按新的横竖尺寸重新量测，否则竖排模块仍按其横排尺寸摆放。
            // 组不拆分：仍由同一个 cluster 整体竖排。
            cluster.onAxisChange = { [weak self] _ in
                guard let self else { return }
                self.lastActionLayoutKey = nil
                self.updateNavigationActions()
            }
            head.cluster = cluster
            if classic, head.item.customView === cluster { head.item.customView = nil }
            if !classic, cluster.superview is ShellClassicNavigationBar { cluster.removeFromSuperview() }
            head.item.classicSlot = classic ? cluster : nil
            let buttons = run.actions.map { action -> ShellNavButtonHost in
                let state = actionState(for: action)
                let button = state.button ?? ShellNavButtonHost(frame: .zero)
                state.button = button
                let displayAction = run.groupID == nil ? action : actionWithoutButtonMaterial(action)
                button.update(action: displayAction, textStyle: textStyle) { [weak state] in
                    guard let state, state.action.isEnabled else { return }
                    if state.action.navButton != nil { state.invokeNavButton() } else { state.action.handler() }
                }
                return button
            }
            cluster.update(
                buttons: buttons,
                spacing: run.itemSpacing,
                tracksNativePlacement: usesSystemNavigationActionLayout && run.sidebarBehavior != .disabled,
                groupMaterial: clusterMaterial(for: run),
                groupTintColor: run.groupTintColor,
                moduleSpacingAfter: classic ? run.moduleSpacingAfter : 0
            )
            cluster.isUserInteractionEnabled = true
        }
    }

    private func actionWithoutButtonMaterial(_ action: NavigationAction) -> NavigationAction {
        guard var navButton = action.navButton else { return action }
        var normal = navButton.normal
        normal.effect = .none
        navButton.normal = normal
        if var vertical = navButton.vertical {
            vertical.effect = .none
            navButton.vertical = vertical
        }
        var result = action
        result.navButton = navButton
        return result
    }

    private func clusterMaterial(for run: ShellNavButtonRun) -> ShellMaterial? {
        guard let material = run.groupMaterial else { return nil }
        return material
    }
    private func usesCustomGlass(_ action: NavigationAction) -> Bool {
        guard let button = action.navButton else { return false }
        return [button.normal, button.vertical].compactMap { $0?.effect.material }.contains {
            ShellMaterials.currentResolution(for: $0).resolved == .systemGlass
        }
    }

    private func makeBarButton(for run: ShellNavButtonRun, material: ShellMaterial) -> UIBarButtonItem {
        let action = run.first
        let state = actionState(for: action)
        state.action = action
        let item = state.item
        // 菜单中的 UIAction 在旧系统上不可变；配置刷新时替换表示，保留 item 身份。
        let usesCustomButton = action.navButton != nil
        item.primaryAction = usesCustomButton || !run.others.isEmpty ? nil : makeMenuAction(action)
        item.title = usesCustomButton ? nil : action.title
        item.image = usesCustomButton ? nil : action.resolvedImage(traits: traitCollection)
        item.style = action.role == .confirmation && !usesCustomButton ? .done : .plain
        item.width = usesSystemNavigationActionLayout ? 0 : navigationActionWidth(action)
        item.isEnabled = run.others.isEmpty ? action.isEnabled : run.actions.contains { $0.isEnabled }
        if #available(iOS 27.0, *) {
            item.menuRepresentation = run.others.isEmpty
                ? (usesCustomButton ? nil : makeMenuAction(action))
                : UIMenu(options: .displayInline, children: run.actions.map(makeMenuAction))
        } else if !run.others.isEmpty, #available(iOS 16.0, *) {
            item.menuRepresentation = UIMenu(options: .displayInline, children: run.actions.map(makeMenuAction))
        } else if !usesCustomButton, #available(iOS 16.0, *) {
            item.menuRepresentation = makeMenuAction(action)
        } else if #available(iOS 16.0, *) {
            item.menuRepresentation = nil
        }
        if #available(iOS 27.0, *) {
            item.visibilityPriority = action.visibility == .always
                ? UIBarButtonItemVisibilityPriority(rawValue: Int.max)
                : UIBarButtonItemVisibilityPriority(rawValue: action.priority)
        }
        if #available(iOS 27.1, *) {
            switch run.sidebarBehavior {
            case .system: item.axisBehavior = .automatic
            case .disabled: item.axisBehavior = .horizontalOnly
            case .preferred: item.axisBehavior = .verticalPreferred
            }
        }
        item.accessibilityLabel = action.title
        item.accessibilityIdentifier = "action.\(action.id)"
        if let groupMaterial = run.groupMaterial {
            let resolvedGroupMaterial = ShellMaterials.currentResolution(for: groupMaterial).resolved
            configureSharedBackground(for: item, material: resolvedGroupMaterial)
            if #available(iOS 26.0, *) {
                // The cluster renders one rounded group surface; avoid UIKit drawing a second shared surface.
                item.hidesSharedBackground = true
            }
        } else {
            configureSharedBackground(for: item, material: material)
            if #available(iOS 26.0, *), usesCustomGlass(action) {
                // An independent glass button owns its surface; do not stack UIKit's shared surface.
                item.hidesSharedBackground = true
            }
        }
        if let cluster = state.cluster {
            if resolvedBarPresentation != .classic {
                // Keep the cluster as the custom view even for one action. UIKit can
                // detach a bare child button during a navigation-bar relayout,
                // leaving its glass container visible with no content.
                if item.customView !== cluster { item.customView = cluster }
            }
        }
        return item
    }

    private func navigationActionWidth(_ action: NavigationAction) -> CGFloat {
        if let cluster = navigationActionStates[action.id]?.cluster { return cluster.intrinsicContentSize.width }
        guard action.resolvedImage(traits: traitCollection) == nil else { return 44 }
        let font = effectiveNavigationStyle.buttons.resolvedFont(for: .body, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        return max(44, ceil((action.title as NSString).size(withAttributes: [.font: font]).width) + 20)
    }

    private func actionState(for action: NavigationAction) -> NavigationActionState {
        if let state = navigationActionStates[action.id] { return state }
        let state = NavigationActionState(action)
        navigationActionStates[action.id] = state
        return state
    }

    @available(iOS 27.0, *)
    private func applySystemNavigationActions(leading: [ShellNavButtonRun], trailing: [ShellNavButtonRun], material: ShellMaterial) {
        for id in pinnedSystemActionIDs {
            navigationActionStates[id]?.group = nil
        }

        let confirmationID = trailing.first { $0.first.role == .confirmation }?.first.id
        let pinnedRuns = trailing.filter {
            $0.first.id == confirmationID || $0.first.visibility == .always
        }
        for id in pinnedRuns.flatMap({ $0.actions.map(\.id) }) {
            navigationActionStates[id]?.group = nil
        }
        pinnedSystemActionIDs = Set(pinnedRuns.flatMap { $0.actions.map(\.id) })

        func group(for run: ShellNavButtonRun) -> UIBarButtonItemGroup {
            let item = makeBarButton(for: run, material: material)
            let state = actionState(for: run.first)
            let group = state.group ?? UIBarButtonItemGroup.fixedGroup(representativeItem: nil, items: [item])
            // UIKit may detach or empty a group while a navigation pop is completing.
            // Reattach the current item before submitting the group again.
            group.barButtonItems = [item]
            group.alwaysAvailable = run.first.visibility == .automatic
            state.group = group
            return group
        }

        let leadingGroups = leading.map(group)
        let pinnedIDs = Set(pinnedRuns.map { $0.first.id })
        let trailingGroups = trailing.filter { !pinnedIDs.contains($0.first.id) }.map(group)
        let pinned: UIBarButtonItemGroup?
        if pinnedRuns.isEmpty {
            pinnedSystemActionGroup = nil
            pinned = nil
        } else {
            let items = pinnedRuns.map { makeBarButton(for: $0, material: material) }
            let group = pinnedSystemActionGroup ?? UIBarButtonItemGroup.fixedGroup(
                representativeItem: nil, items: items
            )
            group.barButtonItems = items
            group.alwaysAvailable = false
            pinnedSystemActionGroup = group
            pinned = group
        }

        if !appliedSystemActionLayout {
            navigationItem.leftBarButtonItems = nil
            navigationItem.rightBarButtonItems = nil
        }
        navigationItem.leadingItemGroups = leadingGroups
        navigationItem.trailingItemGroups = trailingGroups
        if navigationItem.pinnedTrailingGroup !== pinned { navigationItem.pinnedTrailingGroup = pinned }
        appliedSystemActionLayout = true
        (navigationController as? BoneNavigationController)?.refreshBarPresentation()
    }

    private func clearSystemNavigationActions() {
        guard appliedSystemActionLayout else { return }
        if #available(iOS 16.0, *) {
            navigationItem.leadingItemGroups = []
            navigationItem.trailingItemGroups = []
            navigationItem.pinnedTrailingGroup = nil
        }
        for state in navigationActionStates.values { state.group = nil }
        pinnedSystemActionGroup = nil
        pinnedSystemActionIDs.removeAll()
        appliedSystemActionLayout = false
    }

    private func configureSharedBackground(for item: UIBarButtonItem, material: ShellMaterial) {
        if #available(iOS 26.0, *) { item.hidesSharedBackground = material == .solid }
        let style = effectiveNavigationStyle.buttons
        item.tintColor = style.color
        for state: UIControl.State in [.normal, .highlighted, .focused] {
            item.setTitleTextAttributes(style.attributes(merging: [:], role: .body, traits: traitCollection), for: state)
        }
        let disabledAttributes = style.resolvedFont(for: .body, traits: traitCollection).map { [NSAttributedString.Key.font: $0] }
        item.setTitleTextAttributes(disabledAttributes, for: .disabled)
    }

    @objc private func accessibilitySettingsChanged() {
        applyNavigationConfiguration()
        lastActionLayoutKey = nil
        updateNavigationActions()
    }

    private struct ActionLayoutKey: Equatable {
        let width: CGFloat
        let leftInset: CGFloat
        let rightInset: CGFloat
        let backTitle: String?
        let textSize: CGFloat
        let systemLayout: Bool
    }
}

@MainActor
private final class ShellSubtitleTitleView: UIView {
    var maximumWidth: CGFloat = 240 {
        didSet {
            if oldValue != maximumWidth { invalidateIntrinsicContentSize() }
        }
    }
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    init(title: String, subtitle: String, style: ShellNavigationStyle, traits: UITraitCollection) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = style.title.resolvedFont(for: .headline, traits: traits)
            ?? .preferredFont(forTextStyle: .headline, compatibleWith: traits)
        titleLabel.textColor = style.title.color ?? .label
        titleLabel.adjustsFontForContentSizeCategory = style.title.scalesWithDynamicType
        subtitleLabel.text = subtitle
        subtitleLabel.font = style.subtitle.resolvedFont(for: .caption1, traits: traits)
            ?? .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        subtitleLabel.textColor = style.subtitle.color ?? .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = style.subtitle.scalesWithDynamicType
        for label in [titleLabel, subtitleLabel] {
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(subtitle)"
        accessibilityTraits = .header
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: min(maximumWidth, max(titleLabel.intrinsicContentSize.width, subtitleLabel.intrinsicContentSize.width)),
            height: titleLabel.intrinsicContentSize.height + subtitleLabel.intrinsicContentSize.height + 1
        )
    }
}
