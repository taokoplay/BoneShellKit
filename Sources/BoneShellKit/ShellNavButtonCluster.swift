import UIKit

/// In classic mode the hidden UIKit navigation bar must not also own the custom view.
@MainActor
final class ShellNavigationBarItem: UIBarButtonItem {
    weak var classicSlot: ShellNavButtonCluster?
}

/// 同侧的连续区段。旧版宽度预算和原生菜单均以同一份分组为准。
@MainActor
struct ShellNavButtonRun {
    let first: NavigationAction
    private(set) var others: [NavigationAction] = []
    let groupID: String?
    let groupMaterial: ShellMaterial?
    let itemSpacing: CGFloat
    let moduleSpacingAfter: CGFloat
    var actions: [NavigationAction] { [first] + others }

    init(
        first: NavigationAction,
        groupID: String? = nil,
        groupMaterial: ShellMaterial? = nil,
        itemSpacing: CGFloat = 0,
        moduleSpacingAfter: CGFloat = 0
    ) {
        self.first = first
        self.groupID = groupID
        self.groupMaterial = groupMaterial
        self.itemSpacing = itemSpacing.isFinite ? max(0, itemSpacing) : 0
        self.moduleSpacingAfter = moduleSpacingAfter.isFinite ? max(0, moduleSpacingAfter) : 0
    }

    private init(
        actions: [NavigationAction],
        groupID: String,
        groupMaterial: ShellMaterial,
        itemSpacing: CGFloat,
        moduleSpacingAfter: CGFloat
    ) {
        precondition(!actions.isEmpty, "Navigation button groups must contain at least one action.")
        self.init(first: actions[0], groupID: groupID, groupMaterial: groupMaterial,
                  itemSpacing: itemSpacing, moduleSpacingAfter: moduleSpacingAfter)
        self.others = Array(actions.dropFirst())
    }


    static func collect(_ modules: [NavigationModule], moduleSpacing: CGFloat) -> [Self] {
        let spacing = moduleSpacing.isFinite ? max(0, moduleSpacing) : 0
        var runs: [Self] = []
        for (index, module) in modules.enumerated() {
            let after = index == modules.count - 1 ? 0 : spacing
            switch module {
            case .button(let action):
                runs.append(Self(first: action, moduleSpacingAfter: after))
            case .group(let group):
                guard !group.actions.isEmpty else { continue }
                runs.append(Self(
                    actions: group.actions,
                    groupID: group.id,
                    groupMaterial: group.material,
                    itemSpacing: group.itemSpacing,
                    moduleSpacingAfter: after
                ))
            }
        }
        return runs
    }
}


/// One native bar item (or one classic slot), even when it contains multiple actions.
/// Only the child buttons are accessibility elements; the container never fires an action.
@MainActor
final class ShellNavButtonCluster: UIView {
    private(set) var buttons: [ShellNavButtonHost] = []
    private var spacing: CGFloat = 0
    private var moduleSpacingAfter: CGFloat = 0
    private var moduleVisualOffset: CGFloat = 0
    private var tracksNativePlacement = false
    private var groupMaterial: ShellMaterial?
    private let groupSurface = ShellGlassView(material: .solid)
    weak var navigationBar: UINavigationBar?
    private(set) var isVertical = false
    private var touchRects: [CGRect] = []

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        groupSurface.isUserInteractionEnabled = false
        groupSurface.isHidden = true
        insertSubview(groupSurface, at: 0)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        groupSurface.isUserInteractionEnabled = false
        groupSurface.isHidden = true
        insertSubview(groupSurface, at: 0)
    }

    func update(
        buttons: [ShellNavButtonHost],
        spacing: CGFloat,
        tracksNativePlacement: Bool,
        groupMaterial: ShellMaterial? = nil,
        moduleSpacingAfter: CGFloat = 0
    ) {
        for old in self.buttons where old.superview === self && !buttons.contains(old) { old.removeFromSuperview() }
        self.buttons = buttons
        self.spacing = spacing.isFinite ? max(0, spacing) : 0
        self.moduleSpacingAfter = moduleSpacingAfter.isFinite ? max(0, moduleSpacingAfter) : 0
        self.tracksNativePlacement = tracksNativePlacement
        self.groupMaterial = groupMaterial
        if let groupMaterial {
            groupSurface.material = ShellMaterials.currentResolution(for: groupMaterial).resolved
            groupSurface.isHidden = buttons.isEmpty
        } else {
            groupSurface.isHidden = true
        }
        if !tracksNativePlacement { isVertical = false }
        for button in buttons {
            if button.superview !== self { addSubview(button) }
            button.setVertical(isVertical)
        }
        isAccessibilityElement = false
        accessibilityElements = buttons
        invalidateIntrinsicContentSize()
        if bounds.isEmpty { bounds.size = intrinsicContentSize }
        setNeedsLayout()
    }
    func setModuleVisualOffset(_ offset: CGFloat) {
        let value = offset.isFinite ? offset : 0
        guard moduleVisualOffset != value else { return }
        moduleVisualOffset = value
        setNeedsLayout()
    }

    /// A small visual does not stretch to fill a 44 pt target. Neighbours divide their
    /// gap; free space at the two ends can complete the outermost targets.
    private var metrics: (lengths: [CGFloat], cross: [CGFloat], before: CGFloat, after: CGFloat) {
        let sizes = buttons.map(\.preferredVisualSize)
        let lengths = sizes.map { isVertical ? $0.height : $0.width }
        let cross = sizes.map { isVertical ? $0.width : $0.height }
        guard let first = lengths.first, let last = lengths.last else { return ([], [], 0, 0) }
        if lengths.count == 1 {
            let inset = max(0, (44 - first) / 2)
            return (lengths, cross, inset, inset)
        }
        return (lengths, cross, max(0, 44 - first - spacing / 2), max(0, 44 - last - spacing / 2))
    }

    override var intrinsicContentSize: CGSize {
        let m = metrics
        let length = m.before + m.lengths.reduce(0, +)
            + CGFloat(max(0, buttons.count - 1)) * spacing
            + m.after + moduleSpacingAfter
        let cross = max(44, m.cross.max() ?? 0)
        return isVertical ? CGSize(width: cross, height: length) : CGSize(width: length, height: cross)
    }
    var moduleVisualBounds: CGRect {
        if !groupSurface.isHidden { return groupSurface.frame }
        var result = CGRect.null
        for button in buttons {
            result = result.union(button.convert(button.moduleVisualBounds, to: self))
        }
        return result.isNull ? bounds : result
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        refreshPlacement()
        let groupLength = isVertical
            ? max(0, bounds.height - moduleSpacingAfter)
            : max(0, bounds.width - moduleSpacingAfter)
        let groupFrame = isVertical
            ? CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: groupLength)
            : CGRect(x: bounds.minX, y: bounds.minY, width: groupLength, height: bounds.height)
        buttons.forEach { $0.setModuleVisualOffset(groupSurface.isHidden ? moduleVisualOffset : 0, vertical: isVertical) }
        groupSurface.frame = groupFrame
        groupSurface.layer.cornerRadius = min(groupSurface.bounds.width, groupSurface.bounds.height) / 2
        groupSurface.layer.cornerCurve = .continuous
        groupSurface.layer.masksToBounds = true
        groupSurface.synchronizeCornerRadius()
        let m = metrics
        guard !buttons.isEmpty else { touchRects = []; return }
        let available = isVertical
            ? max(0, bounds.height - moduleSpacingAfter)
            : max(0, bounds.width - moduleSpacingAfter)
        let cross = isVertical ? bounds.width : bounds.height
        let pairs = CGFloat(buttons.count - 1)
        let gap = min(spacing, pairs > 0 ? available / pairs : 0)
        let total = m.lengths.reduce(0, +)
        let extra = max(0, available - total - gap * pairs)
        let padding = m.before + m.after
        let start = (max(0, extra - padding) / 2) + (padding > 0 ? min(1, extra / padding) * m.before : 0)
        let scale = total > 0 ? min(1, max(0, available - gap * pairs) / total) : 0
        let rtl = !isVertical && effectiveUserInterfaceLayoutDirection == .rightToLeft
        func rect(_ p: CGFloat, _ length: CGFloat, _ span: CGFloat) -> CGRect {
            let side = (cross - span) / 2
            if isVertical { return CGRect(x: bounds.minX + side, y: bounds.minY + p, width: span, height: length) }
            return CGRect(x: bounds.minX + (rtl ? available - p - length : p), y: bounds.minY + side, width: length, height: span)
        }
        var p = start
        touchRects = buttons.indices.map { i in
            let length = m.lengths[i] * scale
            let span = min(cross, m.cross[i])
            buttons[i].frame = rect(p, length, span)
            let need = max(0, 44 - length)
            let left = i == 0 ? min(p, max(need / 2, need - gap / 2)) : min(gap / 2, need / 2)
            let right = i == buttons.count - 1 ? min(max(0, available - p - length), need - left) : min(gap / 2, need - left)
            defer { p += length + gap }
            return rect(p - left, length + left + right, min(cross, max(44, span)))
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let p = intrinsicContentSize
        return CGSize(width: size.width > 0 ? min(size.width, p.width) : p.width,
                      height: size.height > 0 ? min(size.height, p.height) : p.height)
    }


    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        if let index = touchRects.firstIndex(where: { $0.contains(point) }), buttons.indices.contains(index) {
            return buttons[index].isEnabled ? buttons[index] : nil
        }
        if let button = buttons.first(where: { $0.isEnabled && $0.frame.contains(point) }) {
            return button
        }
        return nil
    }

    func touchRect(for button: ShellNavButtonHost) -> CGRect? {
        guard let index = buttons.firstIndex(of: button), touchRects.indices.contains(index) else { return nil }
        return convert(touchRects[index], to: button)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        schedulePlacementCheck()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        schedulePlacementCheck()
    }

    private var pendingPlacementCheck = false
    private func schedulePlacementCheck() {
        guard tracksNativePlacement, !pendingPlacementCheck else { return }
        pendingPlacementCheck = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingPlacementCheck = false
            self.refreshPlacement()
        }
    }

    private func refreshPlacement() {
        let vertical = isMountedInSideBar
        guard vertical != isVertical else { return }
        isVertical = vertical
        buttons.forEach { $0.setVertical(vertical) }
        invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
        setNeedsLayout()
    }

    /// The edge trait is only a capability hint. The same item in a horizontal bar can
    /// have that hint too. Require a mounted slot in the window's actual side exclusion.
    private var isMountedInSideBar: Bool {
        guard #available(iOS 27.1, *), tracksNativePlacement,
              traitCollection.verticalBarEdge != .unspecified, let window, !window.isHidden,
              let navigationBar, navigationBar.window === window, !isDescendant(of: navigationBar),
              !bounds.isEmpty else { return false }
        let rect = convert(bounds, to: window)
        let safe = window.safeAreaLayoutGuide.layoutFrame
        guard !safe.isEmpty, window.bounds.intersects(rect), rect.midY >= safe.minY, rect.midY <= safe.maxY else { return false }
        let tolerance = 1 / max(1, traitCollection.displayScale)
        return (window.safeAreaInsets.right > 0 && rect.minX >= safe.maxX - tolerance)
            || (window.safeAreaInsets.left > 0 && rect.maxX <= safe.minX + tolerance)
    }
}
