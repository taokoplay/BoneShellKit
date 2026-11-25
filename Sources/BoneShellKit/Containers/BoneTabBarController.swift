import UIKit

@MainActor
/// 管理多个 Shell 标签目的地及其标签栏呈现、背景和附加操作。
open class BoneTabBarController: UITabBarController {
    /// 请求的标签栏呈现模式；页面配置可以覆盖该值。
    public var barPresentation: ShellBarPresentation = .system {
        didSet {
            refreshCurrentBackground()
            for navigation in viewControllers?.compactMap({ $0 as? BoneNavigationController }) ?? [] {
                navigation.refreshBarPresentation()
            }
        }
    }
    /// 当前容器解析出的标签栏呈现模式，包括自定义内容无法由 UIKit 原生承载时的回退。
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
    /// 浮动栏覆盖主滚动视图时，是否应将占用区域转化为可滚动内边距。
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

    /// SDK 绘制的经典标签栏视图；当前呈现模式不是经典栏时为空。
    public var classicTabBarView: UIView? { resolvedBarPresentation == .classic ? classicTabBar : nil }
    /// SDK 绘制的胶囊标签栏视图，用于兼容系统和自定义目的地图标。
    public var capsuleTabBarView: UIView? { tabBarRendering == .capsule ? capsuleTabBar : nil }
    /// iOS 26 及以上胶囊呈现承载附加操作时使用的 Dock 行。
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

    /// iOS 27.1+ 的竖向系统栏行为；经典栏位会关闭系统竖向迁移。
    @available(iOS 27.1, *)
    open override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        resolvedBarPresentation == .classic ? .disabled : .automatic
    }

    /// iOS 27.1+ 负责竖向栏行为的子控制器；经典栏位不交给子控制器迁移。
    @available(iOS 27.1, *)
    open override var childForPreferredVerticalBarBehavior: UIViewController? {
        resolvedBarPresentation == .classic ? nil : selectedViewController
    }


    internal var shellUnifiedBackgroundHost: ShellUnifiedBackgroundHost?
    /// 当前标签栏容器使用的统一背景视图；没有已应用配置时为空。
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

    /// 附加在标签栏上的操作按钮，不会成为可选中的标签目的地。
    ///
    /// 经典栏将操作放在栏内，胶囊栏将圆形操作放在胶囊旁边；原生系统栏根据系统版本
    /// 使用系统附加操作区域或兼容标签项承载这些操作。
    public var tabBarAccessories: [ShellTabBarAccessory] = [] {
        didSet {
            // Identical visuals keep in-flight touch targets. Their handlers resolve the
            // latest accessory by ID, so callback-only updates need no layout refresh.
            guard oldValue.map(\.signature) != tabBarAccessories.map(\.signature) else { return }
            refreshBarPresentation()
        }
    }
    /// 当前栏位渲染器是否支持显示标签栏附加操作。
    public var supportsTabBarAccessories: Bool { true }

    /// 当前宿主解析出的附加操作内容模式，即使栏位暂时隐藏也会返回结果。
    /// - Parameter id: 要查询的附加操作稳定标识。
    /// - Returns: 当前内容模式；操作尚未挂载或不存在时返回 nil。
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

    /// 使用系统附加操作区域时承载附加按钮的视图。
    public private(set) var nativeTabAccessoryView: UIView?
    @available(iOS 26.0, *)
    private var systemBottomAccessory: UITabAccessory? {
        get { bottomAccessory }
        set { bottomAccessory = newValue }
    }
    /// 兼容渲染器承载的前侧附加按钮。
    public private(set) var leadingAccessoryButtons: [UIView] = []
    /// 兼容渲染器承载的后侧附加按钮。
    public private(set) var trailingAccessoryButtons: [UIView] = []
    private var accessoryButtons: [ShellTabAccessoryButton] = []
    /// Legacy accessory tab items keyed by their placeholder controllers.
    private var accessoryControllers: [UIViewController: String] = [:]
    private var accessoryAction: [UIViewController: () -> Void] = [:]
    private weak var forwardedTabDelegate: UITabBarControllerDelegate?

    /// 标签栏文字、图标和标题显示方式的样式。
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

    /// 返回指定 ID 对应的标签项配置。
    /// - Parameter id: 标签目的地的稳定标识。
    /// - Returns: 当前配置；控制器不存在或已从标签栏移除时返回 nil。
    public func tabItemConfiguration(for id: String) -> ShellTabItemConfiguration? {
        guard let record = tabRecords[id], let controller = record.controller,
              viewControllers?.contains(where: { $0 === controller }) == true else { return nil }
        return record.configuration
    }

    /// 返回标签目的地实际使用的自定义内容模式。
    /// - Parameter id: 标签目的地的稳定标识。
    /// - Returns: 当前内容模式；没有实时占位区域时返回 nil 或 `.unavailable`。
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

    /// 更新已有标签项，而不重建其控制器或导航栈。
    /// - Parameters:
    ///   - id: 要更新的标签目的地稳定标识。
    ///   - configuration: 新的标签项配置。
    /// - Returns: 找到并更新标签项时返回 true，否则返回 false。
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

    /// 特征环境变化后重新应用标签图标、样式和背景。
    /// - Parameter previousTraitCollection: 变化前的特征环境。
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        for record in tabRecords.values {
            if let controller = record.controller { applyTabItem(record.configuration, to: controller.tabBarItem) }
        }
        refreshCurrentBackground()
    }

    /// 标签栏背景配置；为空时不显示独立标签栏背景。
    public var backgroundConfiguration: ShellBackgroundConfiguration? {
        didSet { refreshCurrentBackground() }
    }
    /// 当前标签栏使用的背景视图；没有背景配置时为空。
    public var backgroundView: ShellBackgroundView? { backgroundHost?.view }
    private var backgroundHost: ShellBarBackgroundHost?
    private var originalStandard: UITabBarAppearance?
    private var originalEdge: UITabBarAppearance?
    private var shellIsVisible = false

    /// 当前选中的标签索引发生变化时刷新标签栏背景。
    open override var selectedIndex: Int { didSet { refreshCurrentBackground() } }
    /// 当前选中的标签控制器发生变化时刷新标签栏背景。
    open override var selectedViewController: UIViewController? { didSet { refreshCurrentBackground() } }

    /// 标签栏控制器即将显示时应用当前背景。
    /// - Parameter animated: 标签栏出现是否带有动画。
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shellIsVisible = false
        refreshCurrentBackground()
    }

    /// 标签栏控制器完成显示后恢复背景播放。
    /// - Parameter animated: 标签栏出现是否带有动画。
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shellIsVisible = true
        refreshCurrentBackground()
    }

    /// 标签栏控制器即将隐藏时暂停自绘栏和背景播放。
    /// - Parameter animated: 标签栏消失是否带有动画。
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

    /// 标签栏控制器布局完成后同步自绘栏和背景位置。
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

    /// 创建包含指定标签目的地的标签栏控制器。
    /// - Parameter tabs: 标签目的地列表；每个标签的 ID 必须唯一。
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

    /// 从归档恢复标签栏控制器。
    /// - Parameter coder: 用于解码控制器的归档对象。
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    private static func stableTag(for id: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Int(hash & 0x7fffffff)
    }
}

// MARK: - Accessory selection interception

extension BoneTabBarController: UITabBarControllerDelegate {
    /// 拦截附加操作的选择，将其作为按钮执行并保持当前标签。
    /// - Parameters:
    ///   - tabBarController: 触发选择的标签栏控制器。
    ///   - viewController: 被请求选择的控制器。
    /// - Returns: 是否允许 UIKit 切换到该控制器。
    public func tabBarController(_ tabBarController: UITabBarController,
                                 shouldSelect viewController: UIViewController) -> Bool {
        if let action = accessoryAction[viewController] {
            action()
            return false
        }
        return forwardedTabDelegate?.tabBarController?(tabBarController, shouldSelect: viewController) ?? true
    }

    /// 将普通标签选择事件转发给宿主代理。
    /// - Parameters:
    ///   - tabBarController: 触发选择的标签栏控制器。
    ///   - viewController: 已经选中的控制器。
    public func tabBarController(_ tabBarController: UITabBarController,
                                 didSelect viewController: UIViewController) {
        forwardedTabDelegate?.tabBarController?(tabBarController, didSelect: viewController)
    }

    /// 将标签切换动画控制器请求转发给宿主代理。
    /// - Parameters:
    ///   - tabBarController: 触发切换的标签栏控制器。
    ///   - fromVC: 切换前的控制器。
    ///   - toVC: 切换后的控制器。
    /// - Returns: 宿主提供的动画控制器；没有时返回 nil。
    public func tabBarController(_ tabBarController: UITabBarController,
                                 animationControllerForTransitionFrom fromVC: UIViewController,
                                 to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        forwardedTabDelegate?.tabBarController?(tabBarController,
                                                animationControllerForTransitionFrom: fromVC, to: toVC)
    }
}
