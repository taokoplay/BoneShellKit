import UIKit

@MainActor
open class BoneNavigationController: UINavigationController {
    /// Nil inherits the containing tab controller; system is the standalone default.
    public var barPresentation: ShellBarPresentation? {
        didSet { refreshCurrentBackground() }
    }
    /// The navigation appearance this container shows after resolving `.automatic`.
    ///
    /// There is no self-drawn capsule navigation bar, so below iOS 26 a capsule
    /// request keeps the flat classic navigation instead of inventing a new bar.
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

    @available(iOS 27.1, *)
    open override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        resolvedBarPresentation == .classic ? .disabled : .automatic
    }

    @available(iOS 27.1, *)
    open override var childForPreferredVerticalBarBehavior: UIViewController? {
        resolvedBarPresentation == .classic ? nil : topViewController
    }


    internal var shellUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
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

    public var backgroundConfiguration: ShellBackgroundConfiguration? {
        didSet { refreshCurrentBackground() }
    }
    public var backgroundView: ShellBackgroundView? { backgroundHost?.view }
    private var backgroundHost: ShellBarBackgroundHost?
    private var legacySnapshot: ShellNavigationBackgroundSnapshot?
    private var shellIsVisible = false

    public override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        navigationBar.prefersLargeTitles = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        navigationBar.prefersLargeTitles = true
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shellIsVisible = false
        refreshCurrentBackground()
    }
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shellIsVisible = true
        refreshCurrentBackground()
    }
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shellIsVisible = false
        backgroundView?.setPlaybackActive(false)
        shellUnifiedBackgroundHost?.pause()
    }
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutClassicNavigationBar()
        backgroundHost?.layout(in: backgroundNavigationSurface)
        shellUnifiedBackgroundHost?.layout()
    }
    open override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        prepareBackgrounds(for: viewController)
        backgroundView?.setPlaybackActive(false)
        super.pushViewController(viewController, animated: animated)
        refreshAfterTransition()
    }
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

    open override var childForStatusBarStyle: UIViewController? { topViewController }
    open override var childForStatusBarHidden: UIViewController? { topViewController }
    open override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
}

@MainActor
public struct ShellTab {
    public let id: String
    public let item: ShellTabItemConfiguration
    public let root: UIViewController
    public var title: String { item.title }
    /// Kept for source compatibility; custom images have no SF Symbol name.
    public var symbol: String {
        if case .systemSymbol(let name)? = item.icon { return name }
        return ""
    }

    public init(id: String, title: String, symbol: String,
                selectedIconMode: ShellTabSelectedIconMode = .automatic,
                labelDisplayMode: ShellTabLabelDisplayMode? = nil, root: UIViewController) {
        self.init(id: id, title: title, icon: .systemSymbol(symbol), selectedIconMode: selectedIconMode,
                  labelDisplayMode: labelDisplayMode, root: root)
    }

    public init(id: String, title: String, icon: ShellTabIcon, selectedIcon: ShellTabIcon? = nil,
                selectedIconMode: ShellTabSelectedIconMode = .automatic,
                labelDisplayMode: ShellTabLabelDisplayMode? = nil, root: UIViewController) {
        self.init(id: id, item: ShellTabItemConfiguration(title: title, icon: icon, selectedIcon: selectedIcon,
                                                        selectedIconMode: selectedIconMode, labelDisplayMode: labelDisplayMode), root: root)
    }

    public init(id: String, item: ShellTabItemConfiguration, root: UIViewController) {
        self.id = id
        self.item = item
        self.root = root
    }
}

@MainActor
open class BoneTabBarController: UITabBarController {
    public var barPresentation: ShellBarPresentation = .system {
        didSet {
            refreshCurrentBackground()
            for navigation in viewControllers?.compactMap({ $0 as? BoneNavigationController }) ?? [] {
                navigation.refreshBarPresentation()
            }
        }
    }
    /// The resolved presentation, including an SDK bar when UIKit cannot host a custom slot.
    public var resolvedBarPresentation: ShellBarPresentation {
        let nativeCapsule = ShellBarPresentation.supportsNativeCapsule
        let presentation = (ShellBarBackgroundHost.topScreen(in: selectedViewController)?.screenConfiguration.barPresentation
            ?? barPresentation).resolved(supportsNativeCapsule: nativeCapsule)
        guard presentation == .system else { return presentation }
        let needsCustomAccessoryHost = !ShellTabBarAccessoryHosting.supportsSystemSlot
            && tabBarAccessories.contains { $0.customContent != nil }
        if hasCustomTabItems || needsCustomAccessoryHost { return nativeCapsule ? .capsule : .classic }
        return presentation
    }

    var tabBarRendering: ShellBarRendering {
        let presentation = resolvedBarPresentation
        let base = ShellBarRendering.tabBar(presentation, supportsNativeCapsule: ShellBarPresentation.supportsNativeCapsule)
        guard base == .native, presentation == .capsule else { return base }
        if hasCustomTabItems { return .capsule }
        return tabBarAccessories.isEmpty ? .native : .dock
    }
    /// Floating surfaces overlay the primary scroll viewport; their safe-area contribution
    /// becomes scrollable padding instead of an opaque strip below a clipped viewport.
    internal var floatsAboveScrollContent: Bool {
        let floating = resolvedBarPresentation == .capsule
            || (resolvedBarPresentation == .system && ShellBarPresentation.supportsNativeCapsule)
        guard floating,
              ShellBarBackgroundHost.topScreen(in: selectedViewController)?.hidesBottomBarWhenPushed != true else { return false }
        if tabBarRendering == .native {
            if #available(iOS 18.0, *) { return !isTabBarHidden }
            return !tabBar.isHidden
        }
        return !originalTabBarHidden
    }

    public var classicTabBarView: UIView? { resolvedBarPresentation == .classic ? classicTabBar : nil }
    /// The SDK-rendered capsule, used for compatibility and live destination icons.
    public var capsuleTabBarView: UIView? { tabBarRendering == .capsule ? capsuleTabBar : nil }
    /// The dock row, present when capsule presentation hosts accessories on iOS 26+.
    public var dockBarView: UIView? { tabBarRendering == .dock ? dockBar : nil }
    private var dockBar: ShellNativeDockBar?
    private var classicTabBar: ShellClassicTabBar?
    private var capsuleTabBar: ShellCapsuleTabBar?
    private var originalTabBarAlpha: CGFloat?
    private var originalTabBarAccessibilityHidden = false
    private var originalTabBarHidden = false
    private var selfDrawnBottomContribution: CGFloat = 0
    private var updatingBarPresentation = false
    private var layingOutSelfDrawnBar = false
    private var backgroundTabSurface: UIView {
        switch tabBarRendering {
        case .classic: return classicTabBar ?? tabBar
        case .capsule: return capsuleTabBar ?? tabBar
        case .dock: return dockBar ?? tabBar
        case .native: return tabBar
        }
    }
    private lazy var selfDrawnMoreItem: UITabBarItem = {
        let item = UITabBarItem(title: "更多", image: UIImage(systemName: "ellipsis"), selectedImage: nil)
        item.accessibilityIdentifier = "tab.more"
        return item
    }()

    private var selfDrawnItems: [UITabBarItem] {
        let items = (viewControllers ?? []).filter { accessoryControllers[$0] == nil }.compactMap(\.tabBarItem)
        return items.count > 5 ? Array(items.prefix(4)) + [selfDrawnMoreItem] : items
    }

    private var hasCustomTabItems: Bool {
        tabRecords.values.contains { $0.configuration.customContent != nil }
            && !tabCustomContents(for: selfDrawnItems).isEmpty
    }

    private func tabCustomContents(for items: [UITabBarItem]) -> [ObjectIdentifier: ShellTabBarCustomContent] {
        let visible = Set(items.map(ObjectIdentifier.init))
        return tabRecords.values.reduce(into: [:]) { result, record in
            guard let content = record.configuration.customContent, let item = record.controller?.tabBarItem else { return }
            let identity = ObjectIdentifier(item)
            if visible.contains(identity) { result[identity] = content }
        }
    }

    internal func refreshBarPresentation() {
        guard isViewLoaded, !updatingBarPresentation else { return }
        updatingBarPresentation = true
        defer { updatingBarPresentation = false }
        updateTabLabelPresentation()
        if tabBarRendering == .native {
            restoreNativeTabBar()
            removeAccessoryButtons()
            updateNativeAccessories()
        } else {
            removeNativeAccessories()
            showSelfDrawnTabBar()
        }
        (selectedViewController as? BoneNavigationController)?.refreshBarPresentation()
        ShellBarBackgroundHost.topScreen(in: selectedViewController)?.refreshContentLayoutForBars()
        if #available(iOS 27.1, *) { setNeedsUpdateOfVerticalBarConfiguration() }
    }

    private func accessoryItems(_ position: ShellTabBarAccessory.Position) -> [ShellBarAccessoryItem] {
        accessoryItems().filter { $0.0 == position }.map { $0.1 }
    }

    private func hideNativeTabBar() {
        if originalTabBarAlpha == nil {
            originalTabBarAlpha = tabBar.alpha
            originalTabBarAccessibilityHidden = tabBar.accessibilityElementsHidden
            if #available(iOS 18.0, *) { originalTabBarHidden = isTabBarHidden }
            else { originalTabBarHidden = tabBar.isHidden }
        }
        if #available(iOS 18.0, *) {
            if !isTabBarHidden { setTabBarHidden(true, animated: false) }
        }
        tabBar.alpha = 0
        tabBar.accessibilityElementsHidden = true
    }

    private func restoreNativeTabBar() {
        if let alpha = originalTabBarAlpha {
            if #available(iOS 18.0, *) { setTabBarHidden(originalTabBarHidden, animated: false) }
            tabBar.alpha = alpha
            tabBar.accessibilityElementsHidden = originalTabBarAccessibilityHidden
            originalTabBarAlpha = nil
        }
        updateSelfDrawnBottomContribution(0)
        removeInactiveSelfDrawnBars(keeping: .native)
    }

    private func removeInactiveSelfDrawnBars(keeping rendering: ShellBarRendering) {
        let bars: [(ShellBarRendering, UIView?)] = [
            (.classic, classicTabBar), (.capsule, capsuleTabBar), (.dock, dockBar)
        ]
        for (kind, bar) in bars where kind != rendering {
            bar?.isHidden = true
            bar?.removeFromSuperview()
            switch kind {
            case .dock: dockBar?.discardAccessories()
            case .classic: classicTabBar?.discardItems()
            case .capsule: capsuleTabBar?.discardItems()
            case .native: break
            }
        }
    }

    private func showSelfDrawnTabBar() {
        hideNativeTabBar()
        removeInactiveSelfDrawnBars(keeping: tabBarRendering)
        let page = ShellBarBackgroundHost.topScreen(in: selectedViewController)
        let background = page?.screenConfiguration.tabBarBackground ?? backgroundConfiguration
        let media = page?.usesUnifiedBackground == true || (background.map { !$0.source.isEmpty } ?? false)
        let items = selfDrawnItems
        let selection = (viewControllers?.count ?? 0) > 5 ? min(selectedIndex, 4) : selectedIndex
        let style = currentTabBarStyle
        let labelModes = tabLabelModes(for: items, style: style)
        switch tabBarRendering {
        case .dock:
            // The dock draws its own circles, so the container must not keep a second copy.
            removeAccessoryButtons()
            if dockBar == nil {
                let bar = ShellNativeDockBar()
                bar.onSelect = { [weak self] index in
                    self?.selectSelfDrawnTab(at: index, source: self?.dockBar)
                }
                bar.onGeometryChange = { [weak self] in self?.layoutSelfDrawnTabBar() }
                dockBar = bar
            }
            guard let bar = dockBar else { return }
            bar.tabBar.tintColor = tabBar.tintColor
            bar.tabBar.unselectedItemTintColor = tabBar.unselectedItemTintColor
            if bar.tabBar.standardAppearance != tabBar.standardAppearance {
                bar.tabBar.standardAppearance = tabBar.standardAppearance
            }
            if bar.tabBar.scrollEdgeAppearance != tabBar.scrollEdgeAppearance {
                bar.tabBar.scrollEdgeAppearance = tabBar.scrollEdgeAppearance
            }
            bar.controllerIsVisible = shellIsVisible
            bar.update(items: items, selected: selection,
                       leading: accessoryItems(.leading), trailing: accessoryItems(.trailing),
                       labelDisplayModes: labelModes, style: style)
            if bar.superview !== view { view.addSubview(bar) }
        case .classic:
            syncAccessoryButtons()
            if classicTabBar == nil {
                let bar = ShellClassicTabBar()
                bar.accessibilityIdentifier = "shell.classic.tabs"
                bar.onSelect = { [weak self] index in self?.selectSelfDrawnTab(at: index, source: self?.classicTabBar) }
                classicTabBar = bar
            }
            guard let bar = classicTabBar else { return }
            bar.tintColor = tabBar.tintColor
            bar.controllerIsVisible = shellIsVisible
            bar.update(items: items, selectedIndex: selection, labelDisplayModes: labelModes, style: style,
                       material: .systemDefault, showsMediaBackground: media, customContents: tabCustomContents(for: items))
            if bar.superview !== view { view.addSubview(bar) }
        case .capsule:
            syncAccessoryButtons()
            if capsuleTabBar == nil {
                let bar = ShellCapsuleTabBar()
                bar.accessibilityIdentifier = "shell.capsule.tabs"
                bar.onSelect = { [weak self] index in self?.selectSelfDrawnTab(at: index, source: self?.capsuleTabBar) }
                capsuleTabBar = bar
            }
            guard let bar = capsuleTabBar else { return }
            bar.tintColor = tabBar.tintColor
            bar.controllerIsVisible = shellIsVisible
            bar.update(items: items, selectedIndex: selection, labelDisplayModes: labelModes, style: style,
                       material: capsuleMaterial, showsMediaBackground: media, customContents: tabCustomContents(for: items))
            if bar.superview !== view { view.addSubview(bar) }
        case .native:
            return
        }
        layoutSelfDrawnTabBar()
    }

    private func layoutSelfDrawnTabBar() {
        guard !layingOutSelfDrawnBar else { return }
        let rendering = tabBarRendering
        guard rendering != .native else {
            updateSelfDrawnBottomContribution(0)
            return
        }
        layingOutSelfDrawnBar = true
        defer { layingOutSelfDrawnBar = false }
        let top = (selectedViewController as? UINavigationController)?.topViewController ?? selectedViewController
        let hidden = top?.hidesBottomBarWhenPushed == true || originalTabBarHidden
        let bottom = view.window?.safeAreaInsets.bottom ?? max(0, view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
        var occupied: CGFloat = 0
        let zones = accessoryZones()
        if rendering == .classic, let bar = classicTabBar {
            bar.bottomInset = bottom
            // Classic keeps its edge-to-edge surface; accessory slots are as wide as a tab slot.
            let totalSlots = max(1, bar.itemCount + zones.leadingCount + zones.trailingCount)
            let slot = view.bounds.width / CGFloat(totalSlots)
            bar.itemInsets = (CGFloat(zones.leadingCount) * slot, CGFloat(zones.trailingCount) * slot)
            let frame = CGRect(x: view.bounds.minX,
                               y: view.bounds.maxY - bar.contentHeight - bottom,
                               width: view.bounds.width,
                               height: bar.contentHeight + bottom)
            if bar.frame != frame { bar.frame = frame }
            bar.isHidden = hidden
            layoutAccessoryButtons(zones: zones,
                                   barFrame: CGRect(x: frame.minX, y: frame.minY,
                                                    width: frame.width, height: bar.contentHeight),
                                   hidden: hidden, insideBar: true, fixedWidth: slot)
            view.bringSubviewToFront(bar)
            // Buttons live inside the bar's surface, so they must stay above it.
            accessoryButtons.forEach { view.bringSubviewToFront($0) }
            occupied = bar.contentHeight
        } else if rendering == .dock, let bar = dockBar {
            // The row follows the actual capsule surface height. Its child keeps UIKit's full
            // fitted bar height, including transparent bottom padding.
            let margin = Self.dockHorizontalMargin
            let available = min(max(0, view.bounds.width - margin * 2), ShellNativeDockBar.maximumWidth)
            // Match the system capsule's screen-bottom spacing, rather than adding a second
            // gap above the safe area. The host measures UIKit's own transparent padding.
            let bottomPadding = bar.nativeBottomPadding ?? bottom
            let frame = CGRect(x: view.bounds.midX - available / 2,
                               y: view.bounds.maxY - bottomPadding - bar.rowHeight,
                               width: available, height: bar.rowHeight)
            if bar.frame != frame { bar.frame = frame }
            bar.isHidden = hidden
            view.bringSubviewToFront(bar)
            occupied = hidden ? 0 : max(0, bar.rowHeight + bottomPadding - bottom)
        } else if let bar = capsuleTabBar {
            let margin = ShellCapsuleTabBar.horizontalMargin
            // The capsule floats above the safe area, so it owns no inset of its own.
            bar.bottomInset = 0
            let frame = CGRect(x: view.bounds.minX + margin + zones.leading,
                               y: view.bounds.maxY - bottom - ShellCapsuleTabBar.bottomGap - bar.contentHeight,
                               width: max(0, view.bounds.width - margin * 2 - zones.leading - zones.trailing),
                               height: bar.contentHeight)
            if bar.frame != frame { bar.frame = frame }
            bar.isHidden = hidden
            layoutAccessoryButtons(zones: zones, barFrame: frame, hidden: hidden)
            view.bringSubviewToFront(bar)
            occupied = bar.occupiedHeight
        }
        let contribution: CGFloat
        if #available(iOS 18.0, *) { contribution = hidden ? 0 : occupied }
        else { contribution = hidden ? 0 : max(0, occupied - 49) }
        updateSelfDrawnBottomContribution(contribution)
    }

    // MARK: - Native accessory hosting

    /// Installs the accessory on a native bar: system slot on iOS 26+, tab items below.
    private func updateNativeAccessories() {
        guard isViewLoaded else { return }
        if ShellTabBarAccessoryHosting.supportsSystemSlot {
            removeAccessoryTabItems()
            installSystemAccessorySlot()
        } else {
            clearSystemAccessorySlot()
            installAccessoryTabItems()
        }
    }

    private func removeNativeAccessories() {
        clearSystemAccessorySlot()
        removeAccessoryTabItems()
    }

    /// iOS 26 and later: the system accessory slot hosts custom buttons.
    private func installSystemAccessorySlot() {
        guard #available(iOS 26.0, *) else {
            nativeTabAccessoryView = nil
            return
        }
        guard !tabBarAccessories.isEmpty else {
            clearSystemAccessorySlot()
            return
        }
        let row: ShellSystemTabAccessoryRow
        if let existing = nativeTabAccessoryView as? ShellSystemTabAccessoryRow {
            row = existing
        } else {
            row = ShellSystemTabAccessoryRow()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.alignment = .fill
            row.isLayoutMarginsRelativeArrangement = true
            row.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            row.accessibilityIdentifier = "shell.tabs.accessories"
            row.observeAccessoryEnvironment()
            nativeTabAccessoryView = row
        }
        let style = currentTabBarStyle
        let tint = style.normal.color ?? (tabBar.tintColor ?? .systemBlue)
        let font = style.normal.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        row.controllerIsVisible = shellIsVisible
        row.update(items: accessoryItems().map { $0.1 }, tint: tint, font: font)
        if systemBottomAccessory?.contentView !== row {
            row.frame = CGRect(x: 0, y: 0, width: max(160, view.bounds.width - 24), height: 50)
            systemBottomAccessory = UITabAccessory(contentView: row)
        }
    }

    private func clearSystemAccessorySlot() {
        if #available(iOS 26.0, *) {
            (nativeTabAccessoryView as? ShellSystemTabAccessoryRow)?.discardAccessories()
            if systemBottomAccessory != nil { systemBottomAccessory = nil }
        }
        nativeTabAccessoryView?.removeFromSuperview()
        nativeTabAccessoryView = nil
    }

    /// Below iOS 26: accessory buttons are real tab items, arranged by UIKit in order.
    private func installAccessoryTabItems() {
        guard !tabBarAccessories.isEmpty else {
            removeAccessoryTabItems()
            return
        }
        guard let controllers = viewControllers else { return }
        let plain = controllers.filter { accessoryControllers[$0] == nil }
        guard !plain.isEmpty else { return }
        let keep = selectedViewController.flatMap { plain.contains($0) ? $0 : nil } ?? plain[0]
        accessoryControllers.removeAll()
        accessoryAction.removeAll()
        var arranged: [UIViewController] = []
        let leading = tabBarAccessories.filter { $0.position == .leading }
        let trailing = tabBarAccessories.filter { $0.position == .trailing }
        arranged += leading.map(makeAccessoryController)
        arranged += plain
        arranged += trailing.map(makeAccessoryController)
        guard arranged.count != controllers.count || !controllers.elementsEqual(arranged, by: ===) else { return }
        viewControllers = arranged
        selectedViewController = keep
        installSelfAsDelegate()
    }

    private func makeAccessoryController(_ accessory: ShellTabBarAccessory) -> UIViewController {
        let controller = UIViewController()
        let image = accessory.icon?.resolve(traits: traitCollection)
        let tabItem = UITabBarItem(title: accessory.title,
                                   image: image.map { $0.renderingMode == .alwaysOriginal ? $0 : $0.withRenderingMode(.alwaysTemplate) },
                                   selectedImage: nil)
        tabItem.accessibilityIdentifier = accessory.id
        tabItem.accessibilityLabel = accessory.accessibilityLabel ?? accessory.title
        tabItem.isEnabled = accessory.isEnabled
        controller.tabBarItem = tabItem
        accessoryControllers[controller] = accessory.id
        accessoryAction[controller] = accessoryHandler(for: accessory.id)
        return controller
    }

    private func removeAccessoryTabItems() {
        guard !accessoryControllers.isEmpty else { return }
        let plain = (viewControllers ?? []).filter { accessoryControllers[$0] == nil }
        let keep = selectedViewController.flatMap { plain.contains($0) ? $0 : nil } ?? plain.first
        accessoryControllers.removeAll()
        accessoryAction.removeAll()
        if !plain.isEmpty {
            viewControllers = plain
            if let keep = keep { selectedViewController = keep }
        }
        uninstallSelfAsDelegate()
    }

    private func installSelfAsDelegate() {
        guard super.delegate !== self else { return }
        forwardedTabDelegate = super.delegate
        super.delegate = self
    }

    private func uninstallSelfAsDelegate() {
        guard super.delegate === self else { return }
        super.delegate = forwardedTabDelegate
        forwardedTabDelegate = nil
    }

    /// Dock geometry mirrors the system capsule insets.
    static let dockHorizontalMargin: CGFloat = ShellNativeDockBar.sideMargin


    /// Space reserved beside the bar for accessory buttons, excluding the outer margin.
    private struct AccessoryZones {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        var size: CGFloat = 0
        var leadingCount = 0
        var trailingCount = 0
        static let margin: CGFloat = 12
        static let gap: CGFloat = 8
        var isEmpty: Bool { leadingCount == 0 && trailingCount == 0 }
    }

    private func accessoryZones() -> AccessoryZones {
        var zones = AccessoryZones()
        zones.size = accessorySize
        let leading = leadingAccessoryButtons.compactMap { $0 as? ShellTabAccessoryButton }
        let trailing = trailingAccessoryButtons.compactMap { $0 as? ShellTabAccessoryButton }
        zones.leadingCount = leading.count
        zones.trailingCount = trailing.count
        zones.leading = leading.reduce(0) { $0 + width(of: $1) + AccessoryZones.gap }
        zones.trailing = trailing.reduce(0) { $0 + width(of: $1) + AccessoryZones.gap }
        return zones
    }

    /// Accessory buttons are circles without a title and pills with one.
    private func width(of button: ShellTabAccessoryButton) -> CGFloat {
        button.preferredWidth(height: accessorySize)
    }

    private var accessorySize: CGFloat {
        max(44, capsuleTabBar?.contentHeight ?? classicTabBar?.contentHeight ?? 52)
    }

    private func accessoryItems() -> [(ShellTabBarAccessory.Position, ShellBarAccessoryItem)] {
        tabBarAccessories.map { accessory in
            var resolved = accessory
            resolved.handler = accessoryHandler(for: accessory.id)
            return (resolved.position, ShellBarAccessoryItem(resolved, traits: traitCollection))
        }
    }

    /// Resolve at invocation time so cached controls never retain stale business callbacks.
    private func accessoryHandler(for id: String) -> () -> Void {
        { [weak self] in
            guard let accessory = self?.tabBarAccessories.first(where: { $0.id == id }),
                  accessory.isEnabled else { return }
            accessory.handler()
        }
    }

    private var capsuleMaterial: ShellMaterial {
        ShellBarPresentation.supportsNativeCapsule ? .systemGlass : .automatic
    }

    private func syncAccessoryButtons() {
        let items = accessoryItems()
        let style = currentTabBarStyle
        let rendering = tabBarRendering
        // Inside the classic bar the accessory must read exactly like an unselected tab item.
        let tint = rendering == .classic
            ? (style.normal.color ?? .secondaryLabel)
            : (style.normal.color ?? (tabBar.tintColor ?? .systemBlue))
        let font = style.normal.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        accessoryButtons = ShellTabAccessoryButton.reconcile(accessoryButtons, with: items.map { $0.1 })
        // Same material and elevation as the bar being drawn, so the row reads as one control.
        let material: ShellMaterial = rendering == .capsule ? capsuleMaterial : .systemDefault
        // Beside a floating capsule only the glyph fits; inside the classic bar a caption does.
        let compact = rendering == .capsule
        let captionBelow = rendering == .classic
        for (button, entry) in zip(accessoryButtons, items) {
            button.controllerIsVisible = shellIsVisible
            button.update(item: entry.1, tint: tint, font: font, compact: compact,
                          material: material, captionBelow: captionBelow)
            // The compatibility capsule and its circles share one elevation profile.
            button.applyShadow(rendering == .capsule && material != .systemGlass)
            if button.superview !== view {
                button.isHidden = true // The first layout will place and reveal it.
                view.addSubview(button)
            }
        }
        leadingAccessoryButtons = items.indices.compactMap { items[$0].0 == .leading ? accessoryButtons[$0] : nil }
        trailingAccessoryButtons = items.indices.compactMap { items[$0].0 == .trailing ? accessoryButtons[$0] : nil }
    }

    private func removeAccessoryButtons() {
        accessoryButtons.forEach { $0.unmount() }
        accessoryButtons.removeAll()
        leadingAccessoryButtons = []
        trailingAccessoryButtons = []
    }

    private func layoutAccessoryButtons(zones: AccessoryZones, barFrame: CGRect, hidden: Bool,
                                        insideBar: Bool = false, fixedWidth: CGFloat? = nil) {
        guard !zones.isEmpty else {
            // Never mutate the hierarchy from layout: just hide until the next refresh.
            accessoryButtons.forEach { $0.isHidden = true }
            return
        }
        let gap = AccessoryZones.gap
        let margin = AccessoryZones.margin
        let height = min(zones.size, barFrame.height)
        let leading = leadingAccessoryButtons.compactMap { $0 as? ShellTabAccessoryButton }
        let trailing = trailingAccessoryButtons.compactMap { $0 as? ShellTabAccessoryButton }
        for button in accessoryButtons {
            // Inside a bar the button reuses the bar surface; beside a capsule it keeps its own.
            button.useBarSurface(insideBar)
        }
        var x = insideBar ? barFrame.minX : view.bounds.minX + margin
        for button in leading {
            let width = fixedWidth ?? width(of: button)
            button.frame = CGRect(x: x, y: barFrame.midY - height / 2, width: width, height: height)
            button.isHidden = hidden
            x += width + (insideBar ? 0 : gap)
        }
        var rightEdge = insideBar ? barFrame.maxX : view.bounds.maxX - margin
        for button in trailing.reversed() {
            let width = fixedWidth ?? width(of: button)
            rightEdge -= width
            button.frame = CGRect(x: rightEdge, y: barFrame.midY - height / 2, width: width, height: height)
            button.isHidden = hidden
            if !insideBar { rightEdge -= gap }
        }
        accessoryButtons.forEach { view.bringSubviewToFront($0) }
    }

    private func updateSelfDrawnBottomContribution(_ value: CGFloat) {
        guard abs(value - selfDrawnBottomContribution) > 0.1 else { return }
        var insets = additionalSafeAreaInsets
        insets.bottom += value - selfDrawnBottomContribution
        selfDrawnBottomContribution = value
        additionalSafeAreaInsets = insets
    }

    private func selectSelfDrawnTab(at index: Int, source: UIView?) {
        guard let controllers = viewControllers else { return }
        if controllers.count > 5 && index == 4 {
            let menu = UIAlertController(title: "更多标签", message: nil, preferredStyle: .actionSheet)
            for (offset, controller) in controllers.dropFirst(4).enumerated() {
                let target = offset + 4
                menu.addAction(UIAlertAction(title: controller.tabBarItem.title, style: .default) { [weak self] _ in
                    self?.selectedIndex = target
                })
            }
            menu.addAction(UIAlertAction(title: "取消", style: .cancel))
            menu.popoverPresentationController?.sourceView = source
            if let bar = source {
                menu.popoverPresentationController?.sourceRect = CGRect(x: bar.bounds.width * 0.8, y: 0,
                                                                        width: max(1, bar.bounds.width * 0.2),
                                                                        height: bar.bounds.height)
            }
            present(menu, animated: true)
        } else if controllers.indices.contains(index), controllers[index].tabBarItem.isEnabled {
            selectedIndex = index
        }
    }

    @available(iOS 27.1, *)
    open override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        resolvedBarPresentation == .classic ? .disabled : .automatic
    }

    @available(iOS 27.1, *)
    open override var childForPreferredVerticalBarBehavior: UIViewController? {
        resolvedBarPresentation == .classic ? nil : selectedViewController
    }


    internal var shellUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
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

    /// Extra action buttons attached to the tab bar. They never become selected tabs.
    ///
    /// Classic bars host actions inside the bar; capsule bars draw circles beside the
    /// capsule. Explicit system presentation uses a native accessory slot on iOS 26+
    /// and intercepted tab items on earlier systems.
    public var tabBarAccessories: [ShellTabBarAccessory] = [] {
        didSet {
            // Identical visuals keep in-flight touch targets. Their handlers resolve the
            // latest accessory by ID, so callback-only updates need no layout refresh.
            guard oldValue.map(\.signature) != tabBarAccessories.map(\.signature) else { return }
            refreshBarPresentation()
        }
    }
    /// Whether the current renderer can display accessories.
    ///
    /// Native capsule docks and compatibility renderers host their own controls. Explicit
    /// system presentation uses intercepted tab items below iOS 26 and a system slot on 26+.
    public var supportsTabBarAccessories: Bool { true }

    /// The content resolved by the current host, even if its bar is temporarily hidden.
    /// Returns nil when the accessory does not have a mounted representation yet.
    public func tabBarAccessoryContentMode(for id: String) -> ShellTabBarCustomContent.Mode? {
        guard isViewLoaded else { return nil }
        switch tabBarRendering {
        case .dock:
            return dockBar?.contentMode(for: id)
        case .classic, .capsule:
            return accessoryButtons.first { $0.accessoryID == id }?.resolvedContentMode
        case .native:
            if #available(iOS 26.0, *), let row = nativeTabAccessoryView as? ShellSystemTabAccessoryRow {
                return row.buttons.first { $0.accessoryID == id }?.resolvedContentMode
            }
            return accessoryControllers.values.contains(id) ? .standard : nil
        }
    }

    /// The system-hosted accessory view, present only for native bars using the slot.
    public private(set) var nativeTabAccessoryView: UIView?
    @available(iOS 26.0, *)
    private var systemBottomAccessory: UITabAccessory? {
        get { bottomAccessory }
        set { bottomAccessory = newValue }
    }
    /// Controls hosted by compatibility renderers; use dockBarView or nativeTabAccessoryView for native hosts.
    public private(set) var leadingAccessoryButtons: [UIView] = []
    public private(set) var trailingAccessoryButtons: [UIView] = []
    private var accessoryButtons: [ShellTabAccessoryButton] = []
    /// Legacy accessory tab items keyed by their placeholder controllers.
    private var accessoryControllers: [UIViewController: String] = [:]
    private var accessoryAction: [UIViewController: () -> Void] = [:]
    private weak var forwardedTabDelegate: UITabBarControllerDelegate?

    public var tabBarStyle = ShellTabBarStyle() {
        didSet { refreshCurrentBackground() }
    }
    @MainActor private final class TabRecord {
        weak var controller: UIViewController?
        var configuration: ShellTabItemConfiguration
        var generatedAccessibilityLabel: String?
        init(controller: UIViewController, configuration: ShellTabItemConfiguration) {
            self.controller = controller
            self.configuration = configuration
        }
    }
    private var tabRecords: [String: TabRecord] = [:]
    private weak var nativeMoreLabelItem: UITabBarItem?
    private var nativeMoreSemanticTitle: String?
    private var generatedMoreAccessibilityLabel: String?
    private var originalSelectedTint: UIColor?
    private var originalNormalTint: UIColor?
    private var overridesSelectedTint = false
    private var overridesNormalTint = false

    public func tabItemConfiguration(for id: String) -> ShellTabItemConfiguration? {
        guard let record = tabRecords[id], let controller = record.controller,
              viewControllers?.contains(where: { $0 === controller }) == true else { return nil }
        return record.configuration
    }

    /// The destination's actual layout mode. An overflow-only custom item has no live slot.
    public func tabItemContentMode(for id: String) -> ShellTabBarCustomContent.Mode? {
        guard isViewLoaded, let configuration = tabItemConfiguration(for: id),
              let item = tabRecords[id]?.controller?.tabBarItem else { return nil }
        guard configuration.customContent != nil else { return .standard }
        switch tabBarRendering {
        case .classic: return classicTabBar?.contentMode(for: item) ?? .unavailable
        case .capsule: return capsuleTabBar?.contentMode(for: item) ?? .unavailable
        case .native, .dock: return .unavailable
        }
    }

    /// Updates the existing native item without rebuilding its controller or navigation stack.
    @discardableResult
    public func updateTabItem(id: String, configuration: ShellTabItemConfiguration) -> Bool {
        guard let record = tabRecords[id], let controller = record.controller,
              viewControllers?.contains(where: { $0 === controller }) == true else { return false }
        record.configuration = configuration
        applyTabItem(configuration, to: controller.tabBarItem)
        refreshBarPresentation()
        return true
    }

    private var currentTabBarStyle: ShellTabBarStyle {
        let page = ShellBarBackgroundHost.topScreen(in: selectedViewController)
        return page?.screenConfiguration.tabBarStyle ?? tabBarStyle
    }

    private func tabLabelModes(for items: [UITabBarItem], style: ShellTabBarStyle) -> [ShellTabLabelDisplayMode] {
        var modes: [ObjectIdentifier: ShellTabLabelDisplayMode] = [:]
        for record in tabRecords.values {
            guard let controller = record.controller else { continue }
            modes[ObjectIdentifier(controller.tabBarItem)] = record.configuration.labelDisplayMode ?? style.labelDisplayMode
        }
        return items.map { modes[ObjectIdentifier($0)] ?? style.labelDisplayMode }
    }

    private func updateTabLabelPresentation() {
        let style = currentTabBarStyle
        let usesNativeItems = tabBarRendering == .native
        let moreItem: UITabBarItem? = (viewControllers?.count ?? 0) > 5
            ? moreNavigationController.tabBarItem : nil
        let hasNativeMore = usesNativeItems && moreItem.map { more in
            tabBar.items?.contains(where: { $0 === more }) == true
        } == true
        let visibleItems = Set((tabBar.items ?? []).map(ObjectIdentifier.init))
        for record in tabRecords.values {
            guard let controller = record.controller,
                  viewControllers?.contains(where: { $0 === controller }) == true else { continue }
            let item = controller.tabBarItem!
            let mode = record.configuration.labelDisplayMode ?? style.labelDisplayMode
            // UIKit also uses overflow items' titles in the More destination list.
            let isOverflow = hasNativeMore && !visibleItems.contains(ObjectIdentifier(item))
            let showsTitle = !usesNativeItems || isOverflow
                || mode.isVisible(isSelected: controller === selectedViewController)
            let title = showsTitle ? record.configuration.title : nil
            if item.title != title { item.title = title }
            if mode == .always {
                if let generated = record.generatedAccessibilityLabel, item.accessibilityLabel == generated {
                    item.accessibilityLabel = nil
                }
                record.generatedAccessibilityLabel = nil
            } else if item.accessibilityLabel == nil || item.accessibilityLabel == record.generatedAccessibilityLabel {
                item.accessibilityLabel = record.configuration.title
                record.generatedAccessibilityLabel = record.configuration.title
            }
        }
        if let item = moreItem {
            if nativeMoreLabelItem !== item {
                nativeMoreLabelItem = item
                nativeMoreSemanticTitle = item.title
                generatedMoreAccessibilityLabel = nil
            } else if let title = item.title, title != nativeMoreSemanticTitle {
                nativeMoreSemanticTitle = title
            }
            let mode = hasNativeMore ? style.labelDisplayMode : .always
            let title = mode.isVisible(isSelected: tabBar.selectedItem === item) ? nativeMoreSemanticTitle : nil
            if item.title != title { item.title = title }
            if mode == .always {
                if let generated = generatedMoreAccessibilityLabel, item.accessibilityLabel == generated {
                    item.accessibilityLabel = nil
                }
                generatedMoreAccessibilityLabel = nil
            } else if item.accessibilityLabel == nil || item.accessibilityLabel == generatedMoreAccessibilityLabel {
                item.accessibilityLabel = nativeMoreSemanticTitle
                generatedMoreAccessibilityLabel = nativeMoreSemanticTitle
            }
        }
    }

    private func applyTabItem(_ configuration: ShellTabItemConfiguration, to item: UITabBarItem, style: ShellTabBarStyle? = nil) {
        item.title = configuration.title
        if configuration.customContent != nil {
            item.image = nil
            item.selectedImage = nil
            return
        }
        let style = style ?? currentTabBarStyle
        let normal = configuration.icon?.resolve(traits: traitCollection)
        let selected = configuration.selectedIcon?.resolve(traits: traitCollection)
        let hasIconColors = style.normalIconColor != nil || style.selectedIconColor != nil
        item.image = hasIconColors ? coloredIcon(normal, color: style.normalIconColor ?? tabBar.unselectedItemTintColor) : normal
        switch configuration.selectedIconMode {
        case .automatic:
            item.selectedImage = hasIconColors ? coloredIcon(selected ?? normal, color: style.selectedIconColor ?? tabBar.tintColor) : selected
        case .selectedColor:
            let color = style.selectedIconColor ?? style.selected.color
                ?? (isViewLoaded ? tabBar.tintColor : nil) ?? .systemBlue
            // Use the normal artwork explicitly: UIKit must not substitute a filled symbol.
            item.selectedImage = coloredIcon(normal ?? selected, color: color, force: true)
        case .selectedImage:
            // Detach from template/symbol metadata so the selected artwork keeps its own pixels.
            item.selectedImage = originalIcon(selected ?? normal)
        }
    }

    private func coloredIcon(_ image: UIImage?, color: UIColor?, force: Bool = false) -> UIImage? {
        guard let image = image, (force || image.renderingMode != .alwaysOriginal), let color = color,
              image.size.width > 0, image.size.height > 0 else { return image }
        let resolved = color.resolvedColor(with: traitCollection)
        let source = image.isSymbolImage
            ? image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 25)) ?? image : image
        // Some native tab presentations ignore the unselected template tint. Bake
        // configured colors into a standalone raster without the bundle asset metadata.
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(source.scale, traitCollection.displayScale)
        format.preferredRange = .standard
        format.opaque = false
        let mask = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            source.draw(at: .zero)
        }
        return UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            resolved.setFill()
            UIRectFill(CGRect(origin: .zero, size: source.size))
            mask.draw(at: .zero, blendMode: .destinationIn, alpha: 1)
        }.withRenderingMode(.alwaysOriginal)
    }

    private func originalIcon(_ image: UIImage?) -> UIImage? {
        guard let image = image, image.size.width > 0, image.size.height > 0 else { return image }
        let source = image.isSymbolImage
            ? image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 25)) ?? image : image
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(source.scale, traitCollection.displayScale)
        format.preferredRange = .standard
        format.opaque = false
        return UIGraphicsImageRenderer(size: source.size, format: format).image { _ in
            source.withRenderingMode(.alwaysOriginal).draw(at: .zero)
        }.withRenderingMode(.alwaysOriginal)
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        for record in tabRecords.values {
            if let controller = record.controller { applyTabItem(record.configuration, to: controller.tabBarItem) }
        }
        refreshCurrentBackground()
    }

    public var backgroundConfiguration: ShellBackgroundConfiguration? {
        didSet { refreshCurrentBackground() }
    }
    public var backgroundView: ShellBackgroundView? { backgroundHost?.view }
    private var backgroundHost: ShellBarBackgroundHost?
    private var originalStandard: UITabBarAppearance?
    private var originalEdge: UITabBarAppearance?
    private var shellIsVisible = false

    open override var selectedIndex: Int { didSet { refreshCurrentBackground() } }
    open override var selectedViewController: UIViewController? { didSet { refreshCurrentBackground() } }
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shellIsVisible = false
        refreshCurrentBackground()
    }
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shellIsVisible = true
        refreshCurrentBackground()
    }
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shellIsVisible = false
        classicTabBar?.controllerIsVisible = false
        capsuleTabBar?.controllerIsVisible = false
        for button in accessoryButtons { button.controllerIsVisible = false }
        dockBar?.controllerIsVisible = false
        if #available(iOS 26.0, *) {
            (nativeTabAccessoryView as? ShellSystemTabAccessoryRow)?.controllerIsVisible = false
        }
        backgroundView?.setPlaybackActive(false)
        shellUnifiedBackgroundHost?.pause()
    }
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutSelfDrawnTabBar()
        backgroundHost?.layout(in: backgroundTabSurface)
        shellUnifiedBackgroundHost?.layout()
    }
    private func refreshCurrentBackground() {
        guard isViewLoaded else { return }
        let page = ShellBarBackgroundHost.topScreen(in: selectedViewController)
        if page == nil || (page?.isViewLoaded == true && page?.usesUnifiedBackground == false) {
            shellUnifiedBackgroundHost?.deactivate()
        }
        let unified = page?.isViewLoaded == true ? page?.usesUnifiedBackground == true : shellUnifiedBackgroundHost?.view.configuration != nil
        applyShellBackground(page?.isViewLoaded == true ? page?.screenConfiguration.tabBarBackground : nil,
            playbackActive: shellIsVisible, style: page?.isViewLoaded == true ? page?.screenConfiguration.tabBarStyle : nil,
            unifiedBackground: unified)
    }
    internal func applyShellBackground(_ override: ShellBackgroundConfiguration?, playbackActive: Bool, style overrideStyle: ShellTabBarStyle? = nil, unifiedBackground: Bool = false) {
        guard isViewLoaded else { return }
        let configuration = override ?? backgroundConfiguration
        let enabled = !unifiedBackground && (configuration.map { !$0.source.isEmpty } ?? false)
        let style = overrideStyle ?? tabBarStyle
        if enabled || unifiedBackground || !style.isEmpty {
            if originalStandard == nil {
                originalStandard = tabBar.standardAppearance.copy()
                originalEdge = tabBar.scrollEdgeAppearance?.copy()
            }
            let standard = originalStandard!.copy()
            let edge = (originalEdge ?? originalStandard!).copy()
            for appearance in [standard, edge] {
                if enabled || unifiedBackground { appearance.configureWithTransparentBackground() }
                ShellBarStyling.apply(style, to: appearance, traits: traitCollection)
            }
            if !enabled && !unifiedBackground && originalEdge == nil {
                edge.configureWithTransparentBackground()
                ShellBarStyling.apply(style, to: edge, traits: traitCollection)
            }
            tabBar.standardAppearance = standard
            tabBar.scrollEdgeAppearance = edge
        } else if let original = originalStandard {
            tabBar.standardAppearance = original
            tabBar.scrollEdgeAppearance = originalEdge
            originalStandard = nil
            originalEdge = nil
        }
        if let color = style.selectedIconColor {
            if !overridesSelectedTint { originalSelectedTint = tabBar.tintColor; overridesSelectedTint = true }
            tabBar.tintColor = color
        } else if overridesSelectedTint {
            tabBar.tintColor = originalSelectedTint
            originalSelectedTint = nil
            overridesSelectedTint = false
        }
        if let color = style.normalIconColor {
            if !overridesNormalTint { originalNormalTint = tabBar.unselectedItemTintColor; overridesNormalTint = true }
            tabBar.unselectedItemTintColor = color
        } else if overridesNormalTint {
            tabBar.unselectedItemTintColor = originalNormalTint
            originalNormalTint = nil
            overridesNormalTint = false
        }
        for record in tabRecords.values {
            if let controller = record.controller { applyTabItem(record.configuration, to: controller.tabBarItem, style: style) }
        }
        refreshBarPresentation()
        if enabled && backgroundHost == nil {
            backgroundHost = ShellBarBackgroundHost(bar: tabBar, container: view, priority: 10)
            backgroundHost?.view.accessibilityIdentifier = "shell.background.tabs"
        }
        backgroundHost?.layout(in: backgroundTabSurface)
        backgroundHost?.view.apply(enabled ? configuration : nil)
        backgroundHost?.view.setPlaybackActive(playbackActive && enabled)
    }

    public init(tabs: [ShellTab]) {
        precondition(Set(tabs.map(\.id)).count == tabs.count, "ShellTab IDs must be unique.")
        super.init(nibName: nil, bundle: nil)
        var usedTags = Set<Int>()
        viewControllers = tabs.map { tab in
            let controller = tab.root as? UINavigationController
                ?? BoneNavigationController(rootViewController: tab.root)
            let item = UITabBarItem(title: tab.title, image: nil, selectedImage: nil)
            applyTabItem(tab.item, to: item)
            tabRecords[tab.id] = TabRecord(controller: controller, configuration: tab.item)
            // Deterministic across launches and tab order changes (unlike Swift's hashValue).
            var tag = Self.stableTag(for: tab.id)
            while !usedTags.insert(tag).inserted { tag = (tag + 1) & 0x7fffffff }
            item.tag = tag
            item.accessibilityIdentifier = "tab.\(tab.id)"
            controller.tabBarItem = item
            return controller
        }
    }

    public required init?(coder: NSCoder) { super.init(coder: coder) }

    private static func stableTag(for id: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash & 0x7fffffff)
    }
}

@MainActor
open class BoneSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    public init(primary: UIViewController, detail: UIViewController) {
        super.init(style: .doubleColumn)
        preferredDisplayMode = .oneBesideSecondary
        setViewController(Self.navigationContainer(for: primary), for: .primary)
        setViewController(Self.navigationContainer(for: detail), for: .secondary)
        delegate = self
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    /// UIKit owns stacking and separation; retain the supplied detail when collapsing.
    open func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        .secondary
    }

    private static func navigationContainer(for controller: UIViewController) -> UIViewController {
        controller as? UINavigationController
            ?? BoneNavigationController(rootViewController: controller)
    }
}

// MARK: - Accessory selection interception

extension BoneTabBarController: UITabBarControllerDelegate {
    /// Accessory items behave like buttons: run the action and keep the current tab.
    public func tabBarController(_ tabBarController: UITabBarController,
                                 shouldSelect viewController: UIViewController) -> Bool {
        if let action = accessoryAction[viewController] {
            action()
            return false
        }
        return forwardedTabDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
    }

    public func tabBarController(_ tabBarController: UITabBarController,
                                 didSelect viewController: UIViewController) {
        forwardedTabDelegate?.tabBarController?(tabBarController, didSelect: viewController)
    }

    public func tabBarController(_ tabBarController: UITabBarController,
                                 animationControllerForTransitionFrom fromVC: UIViewController,
                                 to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        forwardedTabDelegate?.tabBarController?(tabBarController,
                                                animationControllerForTransitionFrom: fromVC, to: toVC)
    }
}
