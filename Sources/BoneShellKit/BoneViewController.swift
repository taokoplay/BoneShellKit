import UIKit

@MainActor
open class BoneViewController: UIViewController {
    public let contentView = UIView()
    public let backgroundView = ShellBackgroundView()
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

    @available(iOS 27.1, *)
    open override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        resolvedBarPresentation == .classic ? .disabled : .automatic
    }

    public var usesUnifiedBackground: Bool {
        screenConfiguration.backgroundComposition == .unified && (screenConfiguration.background.map { !$0.source.isEmpty } ?? false)
    }
    /// The shared full-container surface in unified mode; the page surface otherwise.
    public var activeBackgroundView: ShellBackgroundView {
        usesUnifiedBackground ? existingUnifiedBackgroundHost?.view ?? backgroundView : backgroundView
    }
    private var standaloneUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
    private weak var displayedUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
    private var isShellVisible = false
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

    public init() { super.init(nibName: nil, bundle: nil) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    open func configureScreen(_ screen: inout ScreenConfiguration) {}
    open func buildContent(in contentView: UIView) {}

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

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isShellVisible = false
        applyNavigationConfiguration()
        refreshContentLayoutForBars()
        updateShellBackgrounds(playbackActive: false)
        lastActionLayoutKey = nil
        updateNavigationActions()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isShellVisible = true
        updateShellBackgrounds(playbackActive: true)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isShellVisible = false
        backgroundView.setPlaybackActive(false)
        (navigationController as? BoneNavigationController)?.backgroundView?.setPlaybackActive(false)
        (tabBarController as? BoneTabBarController)?.backgroundView?.setPlaybackActive(false)
        if navigationController == nil && tabBarController == nil { standaloneUnifiedBackgroundHost?.pause() }
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        displayedUnifiedBackgroundHost?.finishDisplaying(self)
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLegacyKeyboardAvoidance()
        updateNavigationActions()
        standaloneUnifiedBackgroundHost?.layout()
        updateBottomContentFade()
    }

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

    /// Re-evaluates page declarations without rebuilding business content or its scroll view.
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
        let allActions = ShellActionLayout.uniqueActions(
            configuration.leadingActions + configuration.trailingActions
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
        let leadingIDs = Set(configuration.leadingActions.map(\.id))
        let leading = allActions.filter {
            $0.role == .cancellation || ($0.role == .normal && leadingIDs.contains($0.id))
        }
        let trailing = allActions.filter { action in !leading.contains { $0.id == action.id } }
        let leadingRuns = ShellNavButtonRun.collect(leading, layout: configuration.navButtonLayout)
        let trailingRuns = ShellNavButtonRun.collect(trailing, layout: configuration.navButtonLayout)
        prepareNavButtons(leadingRuns + trailingRuns, layout: configuration.navButtonLayout)
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
        let sideBudget = max(0, (usableWidth - titleBudget - 24) / 2)
        let backWidth = backTitle.map {
            min(128, max(44, ($0 as NSString).size(
                withAttributes: [.font: buttonFont]
            ).width + 28))
        } ?? 0
        // A run occupies one slot including its measured gaps; never split it when pruning.
        let leftHeads = leadingRuns.map(\.first), rightHeads = trailingRuns.map(\.first)
        let leadingVisible = Set(ShellActionLayout.visibleIDs(actions: leftHeads,
            availableWidth: max(0, sideBudget - backWidth), width: navigationActionWidth))
        var trailingVisible = Set(ShellActionLayout.visibleIDs(actions: rightHeads,
            availableWidth: sideBudget, width: navigationActionWidth))
        if leadingVisible.count + trailingVisible.count < leadingRuns.count + trailingRuns.count {
            trailingVisible = Set(ShellActionLayout.visibleIDs(actions: rightHeads,
                availableWidth: max(0, sideBudget - 44), width: navigationActionWidth))
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

    private func prepareNavButtons(_ runs: [ShellNavButtonRun], layout: ShellNavButtonLayout) {
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
        let spacing: CGFloat
        switch layout { case .individual: spacing = 0; case .grouped(let gap): spacing = gap }
        let textStyle = effectiveNavigationStyle.buttons
        let classic = resolvedBarPresentation == .classic
        for run in runs where run.first.navButton != nil {
            let head = actionState(for: run.first)
            let cluster = head.cluster ?? ShellNavButtonCluster()
            cluster.navigationBar = navigationController?.navigationBar
            head.cluster = cluster
            if classic, head.item.customView === cluster { head.item.customView = nil }
            if !classic, cluster.superview is ShellClassicNavigationBar { cluster.removeFromSuperview() }
            head.item.classicSlot = classic ? cluster : nil
            let buttons = run.actions.map { action -> ShellNavButtonHost in
                let state = actionState(for: action)
                let button = state.button ?? ShellNavButtonHost(frame: .zero)
                state.button = button
                button.update(action: action, textStyle: textStyle) { [weak state] in
                    guard let state, state.action.isEnabled else { return }
                    if state.action.navButton != nil { state.invokeNavButton() } else { state.action.handler() }
                }
                return button
            }
            cluster.update(buttons: buttons, spacing: spacing,
                           tracksNativePlacement: usesSystemNavigationActionLayout && run.first.axisBehavior != .horizontalOnly)
            cluster.isUserInteractionEnabled = true
            }
    }

    private func makeBarButton(for run: ShellNavButtonRun, material: ShellMaterial) -> UIBarButtonItem {
        let action = run.first
        let state = actionState(for: action)
        state.action = action
        let item = state.item
        // 菜单中的 UIAction 在旧系统上不可变；配置刷新时替换表示，保留 item 身份。
        item.primaryAction = run.others.isEmpty ? makeMenuAction(action) : nil
        item.title = action.title
        item.image = action.resolvedImage(traits: traitCollection)
        item.style = action.role == .confirmation ? .done : .plain
        item.width = usesSystemNavigationActionLayout ? 0 : navigationActionWidth(action)
        item.isEnabled = run.others.isEmpty ? action.isEnabled : run.actions.contains { $0.isEnabled }
        if #available(iOS 27.0, *) {
            item.menuRepresentation = run.others.isEmpty ? makeMenuAction(action)
                : UIMenu(options: .displayInline, children: run.actions.map(makeMenuAction))
        } else if !run.others.isEmpty, #available(iOS 16.0, *) {
            item.menuRepresentation = UIMenu(options: .displayInline, children: run.actions.map(makeMenuAction))
        } else if action.navButton == nil, #available(iOS 16.0, *) {
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
            switch action.axisBehavior {
            case .automatic: item.axisBehavior = .automatic
            case .horizontalOnly: item.axisBehavior = .horizontalOnly
            case .verticalPreferred: item.axisBehavior = .verticalPreferred
            }
        }
        item.accessibilityLabel = action.title
        item.accessibilityIdentifier = "action.\(action.id)"
        configureSharedBackground(for: item, material: material)
        if let cluster = state.cluster {
            if resolvedBarPresentation != .classic {
                if run.others.isEmpty, !usesSystemNavigationActionLayout, let button = cluster.buttons.first {
                    button.removeFromSuperview()
                    item.customView = button
                } else if item.customView !== cluster {
                    item.customView = cluster
                }
            }
            if #available(iOS 26.0, *) { item.hidesSharedBackground = true }
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
            if let group = state.group { return group }
            let group = UIBarButtonItemGroup.fixedGroup(representativeItem: nil, items: [item])
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
        if navigationItem.leadingItemGroups != leadingGroups { navigationItem.leadingItemGroups = leadingGroups }
        if navigationItem.trailingItemGroups != trailingGroups { navigationItem.trailingItemGroups = trailingGroups }
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
