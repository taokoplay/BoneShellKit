import UIKit

@MainActor
open class BoneNavigationController: UINavigationController {
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
        backgroundHost?.layout(in: navigationBar)
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
        if enabled, backgroundHost == nil {
            backgroundHost = ShellBarBackgroundHost(bar: navigationBar, container: view, priority: 20, extendsToStatusArea: true)
            backgroundHost?.view.accessibilityIdentifier = "shell.background.navigation"
        }
        backgroundHost?.layout(in: navigationBar)
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

    public init(id: String, title: String, symbol: String, root: UIViewController) {
        self.init(id: id, title: title, icon: .systemSymbol(symbol), root: root)
    }

    public init(id: String, title: String, icon: ShellTabIcon, selectedIcon: ShellTabIcon? = nil, root: UIViewController) {
        self.id = id
        self.item = ShellTabItemConfiguration(title: title, icon: icon, selectedIcon: selectedIcon)
        self.root = root
    }
}

@MainActor
open class BoneTabBarController: UITabBarController {
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
        if style.normalIconColor != nil || style.selectedIconColor != nil {
            item.image = coloredIcon(normal, color: style.normalIconColor ?? tabBar.unselectedItemTintColor)
            item.selectedImage = coloredIcon(selected ?? normal, color: style.selectedIconColor ?? tabBar.tintColor)
        } else {
            item.image = normal
            item.selectedImage = selected
        }
    }

    private func coloredIcon(_ image: UIImage?, color: UIColor?) -> UIImage? {
        guard let image = image, image.renderingMode != .alwaysOriginal, let color = color,
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
        backgroundHost?.layout(in: tabBar)
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
        if enabled && backgroundHost == nil {
            backgroundHost = ShellBarBackgroundHost(bar: tabBar, container: view, priority: 10)
            backgroundHost?.view.accessibilityIdentifier = "shell.background.tabs"
        }
        backgroundHost?.layout(in: tabBar)
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
