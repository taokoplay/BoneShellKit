import UIKit

/// Floating row with circular actions beside one standalone UIKit tab bar.
@MainActor
final class ShellNativeDockBar: UIView {
    var onSelect: ((Int) -> Void)?
    var onGeometryChange: (() -> Void)?

    var controllerIsVisible = false {
        didSet {
            guard oldValue != controllerIsVisible else { return }
            for button in leadingButtons + trailingButtons { button.controllerIsVisible = controllerIsVisible }
        }
    }
    private(set) var rowHeight: CGFloat = 56
    /// Transparent padding below UIKit's visible platter, measured after native layout.
    private(set) var nativeBottomPadding: CGFloat?
    /// Space between visible surfaces, excluding UIKit's transparent bar margins.
    static let gap: CGFloat = 12
    static let sideMargin: CGFloat = 18
    static let maximumWidth: CGFloat = 440

    private(set) var tabBar = UITabBar()
    private let tabHost: ShellDockTabHost
    private let row = UIStackView()
    private var lastLayoutWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 56
    private var measuredBottomPadding: CGFloat = 0
    private var geometryUpdateScheduled = false
    private var leadingButtons: [ShellTabAccessoryButton] = []
    private var trailingButtons: [ShellTabAccessoryButton] = []
    private struct ItemMetrics: Equatable {
        let title: String?
        let imageSize: CGSize
        let normalFont: UIFont?
        let selectedFont: UIFont?
        let labelMode: ShellTabLabelDisplayMode
    }
    private var itemMetrics: [ItemMetrics] = []
    private var itemCopies: [ObjectIdentifier: UITabBarItem] = [:]

    private final class SelectionProxy: NSObject, UITabBarDelegate {
        var onSelect: ((Int) -> Void)?
        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            // Updating captions can rebuild UIKit's representations. Let its selection
            // event finish before refreshing the destination's style and content.
            DispatchQueue.main.async { [weak self, weak tabBar, weak item] in
                guard let tabBar = tabBar, let item = item, tabBar.selectedItem === item,
                      let index = tabBar.items?.firstIndex(where: { $0 === item }) else { return }
                self?.onSelect?(index)
            }
        }
    }
    private let proxy = SelectionProxy()

    override init(frame: CGRect = .zero) {
        tabHost = ShellDockTabHost(tabBar: tabBar)
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        tabHost = ShellDockTabHost(tabBar: tabBar)
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isAccessibilityElement = false
        backgroundColor = .clear
        accessibilityIdentifier = "shell.dock.row"
        tabHost.onCapsuleLayout = { [weak self] frame, bottomPadding in
            self?.scheduleGeometryUpdate(height: frame.height, bottomPadding: bottomPadding)
        }
        tabBar.delegate = proxy
        proxy.onSelect = { [weak self] index in self?.onSelect?(index) }
        tabBar.itemPositioning = .fill
        tabBar.accessibilityIdentifier = "shell.dock.tabs"
        row.axis = .horizontal
        row.spacing = Self.gap
        row.alignment = .fill
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let preferredWidth = row.widthAnchor.constraint(equalTo: widthAnchor)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            preferredWidth,
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(items: [UITabBarItem], selected: Int,
                leading: [ShellBarAccessoryItem], trailing: [ShellBarAccessoryItem],
                labelDisplayModes: [ShellTabLabelDisplayMode] = [], style: ShellTabBarStyle) {
        let sources = items
        let modes = sources.indices.map {
            labelDisplayModes.indices.contains($0) ? labelDisplayModes[$0] : style.labelDisplayMode
        }
        let items = dockItems(from: sources, selected: selected, labelModes: modes)
        let previousItems = tabBar.items ?? []
        let itemsChanged = previousItems.count != items.count
            || zip(previousItems, items).contains { $0.0 !== $0.1 }
        let metrics = sources.enumerated().map { index, item in
            ItemMetrics(title: item.title, imageSize: item.image?.size ?? .zero,
                        normalFont: style.normal.resolvedFont(for: .caption2, traits: traitCollection),
                        selectedFont: style.selected.resolvedFont(for: .caption2, traits: traitCollection),
                        labelMode: modes[index])
        }
        let accessoriesChanged = leading.map(\.id) != leadingButtons.compactMap(\.accessibilityIdentifier)
            || trailing.map(\.id) != trailingButtons.compactMap(\.accessibilityIdentifier)
            || tabHost.superview !== row
        // Selection callbacks also refresh page appearance. Reassigning the same items or
        // rebuilding their row during that callback interrupts UIKit's next touch sequence.
        if itemsChanged { tabBar.items = items }
        if items.indices.contains(selected), tabBar.selectedItem !== items[selected] {
            tabBar.selectedItem = items[selected]
        }
        if itemsChanged || accessoriesChanged || metrics != itemMetrics {
            tabHost.invalidateCapsuleSize()
            itemMetrics = metrics
        }
        let tint = style.normal.color ?? (tabBar.tintColor ?? .systemBlue)
        let font = style.normal.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        if accessoriesChanged {
            let buttons = ShellTabAccessoryButton.reconcile(leadingButtons + trailingButtons, with: leading + trailing)
            leadingButtons = Array(buttons.prefix(leading.count))
            trailingButtons = Array(buttons.dropFirst(leading.count))
            row.shellArrange(leadingButtons.map(circle) + [tabHost] + trailingButtons.map(circle))
            accessibilityElements = leadingButtons + [tabBar] + trailingButtons
        }
        for (button, item) in zip(leadingButtons + trailingButtons, leading + trailing) {
            button.controllerIsVisible = controllerIsVisible
            button.update(item: item, tint: tint, font: font, compact: true, material: .systemGlass)
        }
        tabHost.setNeedsLayout()
        setNeedsLayout()
    }

    /// Keep UIKit's view representations separate from the hidden container bar.
    private func dockItems(from sources: [UITabBarItem], selected: Int,
                           labelModes: [ShellTabLabelDisplayMode]) -> [UITabBarItem] {
        let identities = Set(sources.map { ObjectIdentifier($0) })
        itemCopies = itemCopies.filter { identities.contains($0.key) }
        return sources.enumerated().map { index, source in
            let id = ObjectIdentifier(source)
            let item = itemCopies[id] ?? UITabBarItem()
            itemCopies[id] = item
            let title = labelModes[index].isVisible(isSelected: index == selected) ? source.title : nil
            if item.title != title { item.title = title }
            item.image = source.image
            item.selectedImage = source.selectedImage
            item.imageInsets = source.imageInsets
            item.titlePositionAdjustment = source.titlePositionAdjustment
            item.landscapeImagePhone = source.landscapeImagePhone
            item.landscapeImagePhoneInsets = source.landscapeImagePhoneInsets
            item.badgeValue = source.badgeValue
            item.badgeColor = source.badgeColor
            item.isEnabled = source.isEnabled
            item.tag = source.tag
            item.accessibilityIdentifier = source.accessibilityIdentifier
            item.accessibilityLabel = source.accessibilityLabel ?? source.title
            item.accessibilityHint = source.accessibilityHint
            item.accessibilityValue = source.accessibilityValue
            for state: UIControl.State in [.normal, .selected, .disabled, .focused] {
                let attributes = source.titleTextAttributes(for: state)
                if !NSDictionary(dictionary: item.titleTextAttributes(for: state) ?? [:]).isEqual(to: attributes ?? [:]) {
                    item.setTitleTextAttributes(attributes, for: state)
                }
                item.setBadgeTextAttributes(source.badgeTextAttributes(for: state), for: state)
            }
            return item
        }
    }

    func contentMode(for id: String) -> ShellTabBarCustomContent.Mode? {
        (leadingButtons + trailingButtons).first { $0.accessoryID == id }?.resolvedContentMode
    }

    func discardAccessories() {
        guard !leadingButtons.isEmpty || !trailingButtons.isEmpty else { return }
        for button in leadingButtons + trailingButtons { button.unmount() }
        leadingButtons = []
        trailingButtons = []
        row.shellArrange([tabHost])
        accessibilityElements = [tabBar]
    }

    override var isHidden: Bool {
        didSet {
            guard oldValue != isHidden else { return }
            for button in leadingButtons + trailingButtons { button.refreshContentVisibility() }
        }
    }

    private func circle(_ button: ShellTabAccessoryButton) -> UIView {
        if let holder = button.superview, holder.superview === row { return holder }
        let holder = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(button)
        NSLayoutConstraint.activate([
            holder.widthAnchor.constraint(equalTo: holder.heightAnchor),
            button.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            button.topAnchor.constraint(equalTo: holder.topAnchor),
            button.bottomAnchor.constraint(equalTo: holder.bottomAnchor)
        ])
        return holder
    }

    private func scheduleGeometryUpdate(height: CGFloat, bottomPadding: CGFloat) {
        guard height.isFinite, height > 0, bottomPadding.isFinite else { return }
        measuredHeight = max(44, height)
        measuredBottomPadding = max(0, bottomPadding)
        let changed = abs(measuredHeight - rowHeight) > 0.5 || nativeBottomPadding == nil
            || abs(measuredBottomPadding - (nativeBottomPadding ?? 0)) > 0.5
        guard changed, !geometryUpdateScheduled else { return }
        geometryUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.geometryUpdateScheduled = false
            let heightChanged = abs(self.measuredHeight - self.rowHeight) > 0.5
            let paddingChanged = self.nativeBottomPadding == nil
                || abs(self.measuredBottomPadding - (self.nativeBottomPadding ?? 0)) > 0.5
            guard heightChanged || paddingChanged else { return }
            self.rowHeight = self.measuredHeight
            self.nativeBottomPadding = self.measuredBottomPadding
            if heightChanged { self.tabHost.invalidateCapsuleSize() }
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
            // The child's layout has finished. Updating the container here cannot re-enter it.
            self.onGeometryChange?()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: rowHeight)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // The floating row has no full-width hit surface. Gestures in the transparent gaps
        // belong to the scroll view underneath, while glass controls keep their own targets.
        return hit === self || hit === row ? nil : hit
    }

    override func layoutSubviews() {
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            tabHost.invalidateCapsuleSize()
        }
        super.layoutSubviews()
    }
}

/// The host represents the visible capsule, so stack spacing is actual surface spacing.
/// UIKit's transparent margins extend outside it and never take accessory taps.
@MainActor
final class ShellDockTabHost: UIView {
    private let tabBar: UITabBar
    private var naturalWidth: CGFloat?
    private var horizontalInsets = UIEdgeInsets.zero
    private var isLayingOut = false
    private var needsItemLayoutReset = true
    private(set) var capsuleFrame = CGRect.zero
    var onCapsuleLayout: ((CGRect, CGFloat) -> Void)?

    init(tabBar: UITabBar) {
        self.tabBar = tabBar
        super.init(frame: .zero)
        addSubview(tabBar)
        // This host owns the fitted frame, including intermediate stack proposals.
        autoresizesSubviews = false
        tabBar.autoresizingMask = []
        setContentHuggingPriority(UILayoutPriority(751), for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Page-content reservations must not feed back into the standalone bar's own safe area.
    override var safeAreaInsets: UIEdgeInsets {
        UIEdgeInsets(top: 0, left: 0, bottom: window?.safeAreaInsets.bottom ?? 0, right: 0)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: naturalWidth ?? UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    func invalidateCapsuleSize() {
        naturalWidth = nil
        horizontalInsets = .zero
        needsItemLayoutReset = true
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        var previousWidth: CGFloat?
        for _ in 0..<3 {
            let width = bounds.width + horizontalInsets.left + horizontalInsets.right
            let fitting = tabBar.sizeThatFits(CGSize(width: width, height: bounds.height))
            let frame = CGRect(x: -horizontalInsets.left, y: 0,
                               width: width, height: max(bounds.height, fitting.height))
            if tabBar.frame != frame { tabBar.frame = frame }
            // UIKit can cache compressed captions before the bar has a fitted frame.
            // Reset on geometry/font changes, preserving model, selection and accessibility IDs.
            if needsItemLayoutReset, tabBar.window != nil {
                needsItemLayoutReset = false
                let items = tabBar.items
                let identifiers = items?.map(\.accessibilityIdentifier) ?? []
                let selected = tabBar.selectedItem
                tabBar.items = nil
                tabBar.items = items
                for (item, identifier) in zip(items ?? [], identifiers) {
                    item.accessibilityIdentifier = identifier
                }
                tabBar.selectedItem = selected
            }
            tabBar.setNeedsLayout()
            tabBar.layoutIfNeeded()
            let visible = visibleCapsuleBounds()
            capsuleFrame = tabBar.convert(visible, to: self)
            // UIKit caps the width of a small destination set. Hug that surface instead of
            // repeatedly expanding transparent space around a capsule that cannot get wider.
            if let previous = previousWidth, abs(visible.width - previous) < 0.5,
               visible.width < bounds.width - 0.5 { break }
            previousWidth = visible.width
            let next = UIEdgeInsets(top: 0, left: max(0, visible.minX), bottom: 0,
                                    right: max(0, tabBar.bounds.width - visible.maxX))
            if abs(next.left - horizontalInsets.left) < 0.5,
               abs(next.right - horizontalInsets.right) < 0.5 { break }
            horizontalInsets = next
        }
        let preferred = min(bounds.width, capsuleFrame.width)
        if preferred > 0, naturalWidth == nil || abs((naturalWidth ?? 0) - preferred) > 0.5 {
            naturalWidth = preferred
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
        updateAccessibilityIdentifiers()
        onCapsuleLayout?(capsuleFrame, max(0, tabBar.frame.maxY - capsuleFrame.maxY))
    }

    /// UIKit does not always transfer item IDs to controls rebuilt after a fitted layout.
    /// Match public destination controls even when their visual captions are hidden.
    private func updateAccessibilityIdentifiers() {
        guard let items = tabBar.items, !items.isEmpty else { return }
        var groups: [ObjectIdentifier: [UIView]] = [:]
        func collect(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if view is UIControl, let parent = view.superview {
                groups[ObjectIdentifier(parent), default: []].append(view)
            }
            view.subviews.forEach(collect)
        }
        collect(tabBar)
        let rtl = tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
        for var controls in groups.values where controls.count == items.count {
            controls.sort { rtl ? $0.frame.maxX > $1.frame.maxX : $0.frame.minX < $1.frame.minX }
            for (control, item) in zip(controls, items) {
                control.accessibilityIdentifier = item.accessibilityIdentifier
                control.accessibilityLabel = item.accessibilityLabel ?? item.title
                control.accessibilityHint = item.accessibilityHint
                let isSelected = item === tabBar.selectedItem
                if let destination = control as? UIControl, destination.isSelected != isSelected {
                    destination.isSelected = isSelected
                }
                var traits = control.accessibilityTraits
                if isSelected { traits.insert(.selected) }
                else { traits.remove(.selected) }
                if control.accessibilityTraits != traits { control.accessibilityTraits = traits }
            }
        }
    }

    /// Read UIKit's final geometry without private class names, KVC or measurement frame writes.
    private func visibleCapsuleBounds() -> CGRect {
        let candidates = tabBar.subviews.filter {
            !$0.isHidden && $0.alpha > 0.01 && $0.bounds.width > 0 && $0.bounds.height > 0
                && $0.frame.width < tabBar.bounds.width - 0.5
                && abs($0.frame.midX - tabBar.bounds.midX) < 1
        }
        return candidates.max(by: { $0.frame.width < $1.frame.width })?.frame ?? tabBar.bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) && (capsuleFrame.isEmpty || capsuleFrame.contains(point))
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }
}
