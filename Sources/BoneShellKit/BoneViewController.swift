import UIKit

@MainActor
open class BoneViewController: UIViewController {
    public let contentView = UIView()
    public let backgroundView = ShellBackgroundView()
    public var resolvedBarPresentation: ShellBarPresentation {
        screenConfiguration.barPresentation
            ?? (navigationController as? BoneNavigationController)?.barPresentation
            ?? (tabBarController as? BoneTabBarController)?.barPresentation
            ?? .system
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
    public private(set) var visibleActionIDs: [String] = []
    public private(set) var overflowActionIDs: [String] = []

    private var hasBuiltContent = false
    private var contentConstraints: [NSLayoutConstraint] = []
    private var keyboardBottomConstraint: NSLayoutConstraint?
    private weak var primaryScrollView: UIScrollView?
    private var lastActionLayoutKey: ActionLayoutKey?
    private var subtitleTitleView: ShellSubtitleTitleView?

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
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard isViewLoaded else { return }
        updateNavigationActions()
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        applyNavigationConfiguration()
        lastActionLayoutKey = nil
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
        primaryScrollView = scrollView
        updateScrollViewPolicy()
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

    private func updateContentLayout() {
        keyboardBottomConstraint?.isActive = false
        NSLayoutConstraint.deactivate(contentConstraints)
        keyboardBottomConstraint = nil
        let boundary = screenConfiguration.content == .safeArea
            ? view.safeAreaLayoutGuide : nil
        let top = boundary?.topAnchor ?? view.topAnchor
        let leading = boundary?.leadingAnchor ?? view.leadingAnchor
        let trailing = boundary?.trailingAnchor ?? view.trailingAnchor
        let bottom = boundary?.bottomAnchor ?? view.bottomAnchor
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
                guide.usesBottomSafeArea = screenConfiguration.content == .safeArea
            }
            let limit = contentView.bottomAnchor.constraint(lessThanOrEqualTo: guide.topAnchor)
            keyboardBottomConstraint = limit
            if #available(iOS 17.0, *) {
                contentConstraints.append(limit)
            } else if screenConfiguration.content == .safeArea {
                contentConstraints.append(limit)
            }
        }
        NSLayoutConstraint.activate(contentConstraints)
        updateLegacyKeyboardAvoidance()
        updateScrollViewPolicy()
    }

    private func updateLegacyKeyboardAvoidance() {
        if #available(iOS 17.0, *) { return }
        guard screenConfiguration.content == .underBars,
              let constraint = keyboardBottomConstraint else { return }
        // iOS 15–16 tie the hidden keyboard guide to the safe bottom. Only constrain
        // under-bar content to that guide while it actually obscures the view.
        let safeBottom = view.bounds.maxY - view.safeAreaInsets.bottom
        let obscuresContent = view.keyboardLayoutGuide.layoutFrame.minY < safeBottom - 0.5
        if constraint.isActive != obscuresContent { constraint.isActive = obscuresContent }
    }

    private func updateScrollViewPolicy() {
        guard let scrollView = primaryScrollView else { return }
        scrollView.contentInsetAdjustmentBehavior = screenConfiguration.content == .safeArea
            ? .never : .automatic
        if isViewLoaded { setContentScrollView(scrollView, for: .all) }
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
        navigationItem.largeTitleDisplayMode = configuration.usesLargeTitle ? .always : .never
        navigationItem.leftItemsSupplementBackButton = true
        if configuration.usesLargeTitle { navigationController?.navigationBar.prefersLargeTitles = true }
        if #available(iOS 26.0, *) {
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
        let key = ActionLayoutKey(
            width: view.bounds.width,
            leftInset: view.safeAreaInsets.left,
            rightInset: view.safeAreaInsets.right,
            backTitle: backTitle,
            textSize: titleFont.pointSize
        )
        guard key != lastActionLayoutKey else { return }
        lastActionLayoutKey = key
        let allActions = ShellActionLayout.uniqueActions(
            configuration.leadingActions + configuration.trailingActions
        )
        let leadingIDs = Set(configuration.leadingActions.map(\.id))
        let leading = allActions.filter { leadingIDs.contains($0.id) }
        let trailing = allActions.filter { !leadingIDs.contains($0.id) }

        let usableWidth = max(0, key.width - key.leftInset - key.rightInset - 32)
        let titleWidth = max(
            (configuration.title as NSString).size(withAttributes: [.font: titleFont]).width,
            ((configuration.subtitle ?? "") as NSString).size(withAttributes: [.font: subtitleFont]).width
        )
        let preferredTitleBudget = min(max(88, titleWidth), usableWidth * 0.45)
        // Shorten the title before displacing a primary trailing action. When other
        // actions overflow, reserve both its touch target and the menu's target.
        let primaryWidth = trailing.filter { $0.priority > 0 }.map(navigationActionWidth).max()
        let primaryReserve: CGFloat = primaryWidth.map { $0 + (allActions.count > 1 ? 44 : 0) } ?? 0
        let titleBudget = min(preferredTitleBudget, max(44, usableWidth - 24 - primaryReserve * 2))
        subtitleTitleView?.maximumWidth = titleBudget
        let sideBudget = max(0, (usableWidth - titleBudget - 24) / 2)
        let backWidth = backTitle.map {
            min(128, max(44, ($0 as NSString).size(
                withAttributes: [.font: buttonFont]
            ).width + 28))
        } ?? 0
        // Measure text items with the actual font; icons keep native 44-point targets.
        let leadingVisible = ShellActionLayout.visibleIDs(actions: leading,
            availableWidth: max(0, sideBudget - backWidth), width: navigationActionWidth)
        var trailingVisible = ShellActionLayout.visibleIDs(actions: trailing,
            availableWidth: sideBudget, width: navigationActionWidth)
        if leadingVisible.count + trailingVisible.count < allActions.count {
            trailingVisible = ShellActionLayout.visibleIDs(actions: trailing,
                availableWidth: max(0, sideBudget - 44), width: navigationActionWidth)
        }
        let visible = Set(leadingVisible + trailingVisible)
        visibleActionIDs = allActions.filter { visible.contains($0.id) }.map(\.id)
        let overflow = allActions.filter { !visible.contains($0.id) }
        overflowActionIDs = overflow.map(\.id)
        let material = ShellMaterials.currentResolution(for: configuration.material).resolved
        let leftItems = leading.filter { visible.contains($0.id) }.map {
            makeBarButton(for: $0, material: material)
        }
        var rightItems = trailing.filter { visible.contains($0.id) }.map {
            makeBarButton(for: $0, material: material)
        }
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
            image: action.symbol.isEmpty ? nil : UIImage(systemName: action.symbol),
            identifier: UIAction.Identifier("action.\(action.id)"),
            attributes: action.isEnabled ? [] : [.disabled]
        ) { _ in
            if action.isEnabled { action.handler() }
        }
        result.accessibilityIdentifier = "action.\(action.id)"
        return result
    }

    private func makeBarButton(for action: NavigationAction, material: ShellMaterial) -> UIBarButtonItem {
        let item = UIBarButtonItem(primaryAction: makeMenuAction(action))
        item.width = navigationActionWidth(action)
        item.isEnabled = action.isEnabled
        item.accessibilityLabel = action.title
        item.accessibilityIdentifier = "action.\(action.id)"
        configureSharedBackground(for: item, material: material)
        return item
    }

    private func navigationActionWidth(_ action: NavigationAction) -> CGFloat {
        guard action.symbol.isEmpty else { return 44 }
        let font = effectiveNavigationStyle.buttons.resolvedFont(for: .body, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        return max(44, ceil((action.title as NSString).size(withAttributes: [.font: font]).width) + 20)
    }

    private func configureSharedBackground(for item: UIBarButtonItem, material: ShellMaterial) {
        if #available(iOS 26.0, *) { item.hidesSharedBackground = material == .solid }
        let style = effectiveNavigationStyle.buttons
        item.tintColor = style.color
        for state: UIControl.State in [.normal, .highlighted, .focused] {
            item.setTitleTextAttributes(style.attributes(merging: [:], role: .body, traits: traitCollection), for: state)
        }
        if let font = style.resolvedFont(for: .body, traits: traitCollection) {
            item.setTitleTextAttributes([.font: font], for: .disabled)
        }
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
