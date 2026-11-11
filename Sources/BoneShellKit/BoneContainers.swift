import UIKit

@MainActor
open class BoneNavigationController: UINavigationController {
    /// Nil inherits the containing tab controller; system is the standalone default.
    public var barPresentation: ShellBarPresentation? {
        didSet { refreshCurrentBackground() }
    }
    public var resolvedBarPresentation: ShellBarPresentation {
        ShellBarBackgroundHost.topScreen(in: topViewController)?.screenConfiguration.barPresentation
            ?? barPresentation ?? (tabBarController as? BoneTabBarController)?.barPresentation ?? .system
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
                showsMediaBackground: media)
            layoutClassicNavigationBar()
        } else {
            if let alpha = originalNavigationBarAlpha {
                navigationBar.alpha = alpha
                navigationBar.accessibilityElementsHidden = originalNavigationBarAccessibilityHidden
                originalNavigationBarAlpha = nil
            }
            classicNavigationBar?.isHidden = true
            classicNavigationBar?.removeFromSuperview()
            for inset in classicNavigationInsets.values { inset.restore() }
            classicNavigationInsets.removeAll()
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
        if let page = topViewController, page.isViewLoaded {
            classicNavigationInsets = classicNavigationInsets.filter { $0.value.controller != nil }
            let id = ObjectIdentifier(page)
            let inset = classicNavigationInsets[id] ?? ClassicNavigationInset(page)
            classicNavigationInsets[id] = inset
            let headerBottom = bar.convert(bar.bounds, to: page.view).maxY - page.view.bounds.minY
            let parentSafeTop = view.convert(CGPoint(x: view.bounds.minX,
                y: view.bounds.minY + view.safeAreaInsets.top), to: page.view).y - page.view.bounds.minY
            let desired: CGFloat = bar.isHidden ? 0 : max(0, headerBottom - max(0, parentSafeTop))
            if abs(desired - inset.contribution) > 0.1 {
                var safe = page.additionalSafeAreaInsets
                safe.top += desired - inset.contribution
                inset.contribution = desired
                page.additionalSafeAreaInsets = safe
            }
        }
        parent.bringSubviewToFront(bar)
    }

    @available(iOS 27.1, *)
    open override var childForPreferredVerticalBarBehavior: UIViewController? { topViewController }


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
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.refreshCurrentBackground() }
        } else {
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

    public init(id: String, title: String, symbol: String, selectedIconMode: ShellTabSelectedIconMode = .automatic, root: UIViewController) {
        self.init(id: id, title: title, icon: .systemSymbol(symbol), selectedIconMode: selectedIconMode, root: root)
    }

    public init(id: String, title: String, icon: ShellTabIcon, selectedIcon: ShellTabIcon? = nil, selectedIconMode: ShellTabSelectedIconMode = .automatic, root: UIViewController) {
        self.id = id
        self.item = ShellTabItemConfiguration(title: title, icon: icon, selectedIcon: selectedIcon, selectedIconMode: selectedIconMode)
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
    public var resolvedBarPresentation: ShellBarPresentation {
        ShellBarBackgroundHost.topScreen(in: selectedViewController)?.screenConfiguration.barPresentation ?? barPresentation
    }
    public var classicTabBarView: UIView? { resolvedBarPresentation == .classic ? classicTabBar : nil }
    private var classicTabBar: ShellClassicTabBar?
    private var originalTabBarAlpha: CGFloat?
    private var originalTabBarAccessibilityHidden = false
    private var originalTabBarHidden = false
    private var classicBottomContribution: CGFloat = 0
    private var updatingBarPresentation = false
    private var layingOutClassicBar = false
    private var backgroundTabSurface: UIView {
        if resolvedBarPresentation == .classic, let bar = classicTabBar { return bar }
        return tabBar
    }
    private lazy var classicMoreItem: UITabBarItem = {
        let item = UITabBarItem(title: "更多", image: UIImage(systemName: "ellipsis"), selectedImage: nil)
        item.accessibilityIdentifier = "tab.more"
        return item
    }()

    internal func refreshBarPresentation() {
        guard isViewLoaded, !updatingBarPresentation else { return }
        updatingBarPresentation = true
        defer { updatingBarPresentation = false }
        if resolvedBarPresentation == .classic {
            if originalTabBarAlpha == nil {
                originalTabBarAlpha = tabBar.alpha
                originalTabBarAccessibilityHidden = tabBar.accessibilityElementsHidden
                if #available(iOS 18.0, *) { originalTabBarHidden = isTabBarHidden }
                else { originalTabBarHidden = tabBar.isHidden }
            }
            if classicTabBar == nil {
                let bar = ShellClassicTabBar()
                bar.accessibilityIdentifier = "shell.classic.tabs"
                bar.onSelect = { [weak self] index in self?.selectClassicTab(at: index) }
                classicTabBar = bar
            }
            if #available(iOS 18.0, *) {
                if !isTabBarHidden { setTabBarHidden(true, animated: false) }
            }
            tabBar.alpha = 0
            tabBar.accessibilityElementsHidden = true
            let page = ShellBarBackgroundHost.topScreen(in: selectedViewController)
            let background = page?.screenConfiguration.tabBarBackground ?? backgroundConfiguration
            let media = page?.usesUnifiedBackground == true || (background.map { !$0.source.isEmpty } ?? false)
            let allItems = viewControllers?.compactMap(\.tabBarItem) ?? []
            let items = allItems.count > 5 ? Array(allItems.prefix(4)) + [classicMoreItem] : allItems
            let selection = allItems.count > 5 ? min(selectedIndex, 4) : selectedIndex
            classicTabBar?.tintColor = tabBar.tintColor
            classicTabBar?.update(items: items, selectedIndex: selection, style: currentTabBarStyle,
                material: .systemDefault, showsMediaBackground: media)
            if let bar = classicTabBar, bar.superview !== view { view.addSubview(bar) }
            layoutClassicTabBar()
        } else {
            if let alpha = originalTabBarAlpha {
                if #available(iOS 18.0, *) { setTabBarHidden(originalTabBarHidden, animated: false) }
                tabBar.alpha = alpha
                tabBar.accessibilityElementsHidden = originalTabBarAccessibilityHidden
                originalTabBarAlpha = nil
            }
            updateClassicBottomContribution(0)
            classicTabBar?.isHidden = true
            classicTabBar?.removeFromSuperview()
        }
        (selectedViewController as? BoneNavigationController)?.refreshBarPresentation()
        if #available(iOS 27.1, *) { setNeedsUpdateOfVerticalBarConfiguration() }
    }

    private func layoutClassicTabBar() {
        guard resolvedBarPresentation == .classic, let bar = classicTabBar, !layingOutClassicBar else { return }
        layingOutClassicBar = true
        defer { layingOutClassicBar = false }
        let top = (selectedViewController as? UINavigationController)?.topViewController ?? selectedViewController
        let hidden = top?.hidesBottomBarWhenPushed == true || originalTabBarHidden
        let bottom = view.window?.safeAreaInsets.bottom ?? max(0, view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
        bar.bottomInset = bottom
        let frame = CGRect(x: view.bounds.minX, y: view.bounds.maxY - bar.contentHeight - bottom,
                           width: view.bounds.width, height: bar.contentHeight + bottom)
        if bar.frame != frame { bar.frame = frame }
        bar.isHidden = hidden
        view.bringSubviewToFront(bar)
        let contribution: CGFloat
        if #available(iOS 18.0, *) { contribution = hidden ? 0 : bar.contentHeight }
        else { contribution = hidden ? 0 : max(0, bar.contentHeight - 49) }
        updateClassicBottomContribution(contribution)
    }

    private func updateClassicBottomContribution(_ value: CGFloat) {
        guard abs(value - classicBottomContribution) > 0.1 else { return }
        var insets = additionalSafeAreaInsets
        insets.bottom += value - classicBottomContribution
        classicBottomContribution = value
        additionalSafeAreaInsets = insets
    }

    private func selectClassicTab(at index: Int) {
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
            menu.popoverPresentationController?.sourceView = classicTabBar
            if let bar = classicTabBar { menu.popoverPresentationController?.sourceRect = CGRect(x: bar.bounds.width * 0.8, y: 0, width: bar.bounds.width * 0.2, height: bar.contentHeight) }
            present(menu, animated: true)
        } else if controllers.indices.contains(index), controllers[index].tabBarItem.isEnabled {
            selectedIndex = index
        }
    }

    @available(iOS 27.1, *)
    open override var childForPreferredVerticalBarBehavior: UIViewController? { selectedViewController }


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

    public var tabBarStyle = ShellTabBarStyle() {
        didSet { refreshCurrentBackground() }
    }
    @MainActor private final class TabRecord {
        weak var controller: UIViewController?
        var configuration: ShellTabItemConfiguration
        init(controller: UIViewController, configuration: ShellTabItemConfiguration) {
            self.controller = controller
            self.configuration = configuration
        }
    }
    private var tabRecords: [String: TabRecord] = [:]
    private var originalSelectedTint: UIColor?
    private var originalNormalTint: UIColor?
    private var overridesSelectedTint = false
    private var overridesNormalTint = false

    public func tabItemConfiguration(for id: String) -> ShellTabItemConfiguration? {
        guard let record = tabRecords[id], let controller = record.controller,
              viewControllers?.contains(where: { $0 === controller }) == true else { return nil }
        return record.configuration
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

    private func applyTabItem(_ configuration: ShellTabItemConfiguration, to item: UITabBarItem, style: ShellTabBarStyle? = nil) {
        let style = style ?? currentTabBarStyle
        let normal = configuration.icon?.resolve(traits: traitCollection)
        let selected = configuration.selectedIcon?.resolve(traits: traitCollection)
        item.title = configuration.title
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
        backgroundView?.setPlaybackActive(false)
        shellUnifiedBackgroundHost?.pause()
    }
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutClassicTabBar()
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
