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
    let groupTintColor: UIColor?
    let itemSpacing: CGFloat
    let moduleSpacingAfter: CGFloat
    /// 模块最终生效的侧栏策略；组声明优先于组内动作声明。
    let sidebarBehavior: ShellNavigationSidebarBehavior
    var actions: [NavigationAction] { [first] + others }

    init(
        first: NavigationAction,
        groupID: String? = nil,
        groupMaterial: ShellMaterial? = nil,
        groupTintColor: UIColor? = nil,
        itemSpacing: CGFloat = 0,
        moduleSpacingAfter: CGFloat = 0,
        sidebarBehavior: ShellNavigationSidebarBehavior? = nil
    ) {
        self.first = first
        self.groupID = groupID
        self.groupMaterial = groupMaterial
        self.groupTintColor = groupTintColor
        self.itemSpacing = itemSpacing.isFinite ? max(0, itemSpacing) : 0
        self.moduleSpacingAfter = moduleSpacingAfter.isFinite ? max(0, moduleSpacingAfter) : 0
        self.sidebarBehavior = sidebarBehavior ?? first.sidebarBehavior
    }

    private init(
        actions: [NavigationAction],
        groupID: String,
        groupMaterial: ShellMaterial,
        groupTintColor: UIColor?,
        itemSpacing: CGFloat,
        moduleSpacingAfter: CGFloat,
        sidebarBehavior: ShellNavigationSidebarBehavior
    ) {
        precondition(!actions.isEmpty, "Navigation button groups must contain at least one action.")
        self.first = actions[0]
        self.others = Array(actions.dropFirst())
        self.groupID = groupID
        self.groupMaterial = groupMaterial
        self.groupTintColor = groupTintColor
        self.itemSpacing = itemSpacing.isFinite ? max(0, itemSpacing) : 0
        self.moduleSpacingAfter = moduleSpacingAfter.isFinite ? max(0, moduleSpacingAfter) : 0
        self.sidebarBehavior = sidebarBehavior
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
                    groupTintColor: group.tintColor,
                    itemSpacing: group.itemSpacing,
                    moduleSpacingAfter: after,
                    sidebarBehavior: group.sidebarBehavior
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
    /// 组表面覆盖整个模块，任何材质都只画这一整块。
    ///
    /// 系统分组玻璃本身就是一整块连续表面（组内没有分隔线），因此不需要逐按钮的玻璃元素：
    /// 多个元素相接或重叠都会在接缝处产生凹陷或二次折射的暗带。
    private let groupSurface = ShellGlassView(material: .solid)
    weak var navigationBar: UINavigationBar?
    /// 自定义条目尺寸变化时，请宿主重新提交给 UIKit 量测。
    var onSizeChange: (() -> Void)?
    private var sizeChangeScheduled = false
    private var measuredDefaultCircleSide: CGFloat?
    /// 侧栏里系统按钮玻璃比槽位宽出的量（Duo 外屏实测：槽位 44 pt，返回键玻璃 47.7 pt）。
    ///
    /// 玻璃会画到槽位之外，因此我们绘制的表面按「槽位 + 该差值」取宽，才能与返回键等宽。
    /// 注意不要用无障碍 frame 判断：侧栏返回键的 AX frame 是 38（命中框），玻璃实际 48。
    private static let sidebarGlassExtra: CGFloat = 4
    /// 侧轨槽位宽度。用常量而不是运行时 bounds：几何一旦反过来依赖 bounds，布局会自我触发。
    private static let sidebarSlot: CGFloat = 44


    private(set) var isVertical = false

    /// 仅用于同模块测试：按给定轴向重新布局，不经过侧栏检测。
    func setVerticalForLayoutTesting(_ vertical: Bool) { applyAxis(vertical) }
    private var touchRects: [CGRect] = []

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        setUpSurfaces()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpSurfaces()
    }

    private func setUpSurfaces() {
        groupSurface.isUserInteractionEnabled = false
        groupSurface.isHidden = true
        insertSubview(groupSurface, at: 0)
    }

    func update(
        buttons: [ShellNavButtonHost],
        spacing: CGFloat,
        tracksNativePlacement: Bool,
        groupMaterial: ShellMaterial? = nil,
        groupTintColor: UIColor? = nil,
        moduleSpacingAfter: CGFloat = 0
    ) {
        for old in self.buttons where old.superview === self && !buttons.contains(old) { old.removeFromSuperview() }
        self.buttons = buttons
        self.spacing = spacing.isFinite ? max(0, spacing) : 0
        self.moduleSpacingAfter = moduleSpacingAfter.isFinite ? max(0, moduleSpacingAfter) : 0
        self.tracksNativePlacement = tracksNativePlacement
        self.groupMaterial = groupMaterial
        if let groupMaterial {
            groupSurface.glassTintColor = groupTintColor
            groupSurface.apply(ShellMaterials.currentResolution(for: groupMaterial))
            groupSurface.isHidden = buttons.isEmpty
        } else {
            groupSurface.isHidden = true
        }
        if !tracksNativePlacement { isVertical = false }
        for button in buttons {
            if button.superview !== self { addSubview(button) }
            button.setVertical(isVertical)
        }
        measuredDefaultCircleSide = defaultCircleSide
        isAccessibilityElement = false
        accessibilityElements = buttons
        invalidateIntrinsicContentSize()
        if bounds.isEmpty { bounds.size = intrinsicContentSize }
        setNeedsLayout()
    }
    /// 是否参与系统侧栏位置判断；仅用于同模块测试，不影响布局。
    var tracksNativeSidebarPlacement: Bool { tracksNativePlacement }

    /// 模块是否真的摆在给定栏位里。用于间距归一化排除已进入溢出菜单的模块。
    /// - Parameter bar: 承载模块的系统栏位视图。
    func isVisibleInBar(_ bar: UIView) -> Bool {
        guard !isHidden, alpha > 0.01, window != nil else { return false }
        // 溢出菜单里的模块可能仍挂在某个承载视图上，但已经不在栏位的可见范围内。
        guard let host = superview, host.window === bar.window else { return false }
        let barBounds = bar.convert(bar.bounds, to: nil)
        let mine = convert(bounds, to: nil)
        guard mine.width > 1, mine.height > 1 else { return false }
        let overlap = barBounds.intersection(mine)
        guard !overlap.isNull, overlap.width > 1 else { return false }
        // 只有一半以上落在栏内才算可见：被溢出菜单挤到边缘的模块不算。
        return overlap.width >= mine.width * 0.5
    }

    /// 系统栏位条目自身的可视高度。横栏里系统按钮的玻璃比自定义视图的槽位更高，
    /// 表面按它长高才能与返回键等高；侧栏用不到（轨道宽度固定 44 pt）。
    private var barItemCross: CGFloat {
        // 侧栏：玻璃宽度固定为槽位 + 4，不随运行时 bounds 变化，避免几何自我触发。
        if isVertical { return Self.sidebarSlot + Self.sidebarGlassExtra }
        guard let bar = navigationBar, bar.window != nil else { return 0 }
        // 横栏：系统条目的玻璃高度是栏高的一个固定内缩量：Duo 58 → 48，普通 iPhone 44 → 44。
        let inset: CGFloat = bar.bounds.height > 50 ? 10 : 0
        return max(0, bar.bounds.height - inset)
    }

    /// 使用系统条目的常规厚度，限制横栏测量上限以避开大标题展开的高度。
    private var defaultCircleSide: CGFloat? {
        guard buttons.contains(where: \.usesDefaultCircle) else { return nil }
        return min(sidebarItemSide, max(44, barItemCross))
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
        let circleSide = defaultCircleSide
        let sizes = buttons.map { button -> CGSize in
            let fitted = button.preferredVisualSize
            guard let circleSide, button.usesDefaultCircle else { return fitted }
            let diameter = max(circleSide, fitted.width, fitted.height)
            return CGSize(width: diameter, height: diameter)
        }
        let lengths = sizes.map { isVertical ? $0.height : $0.width }
        let cross = sizes.map { isVertical ? $0.width : $0.height }
        guard let first = lengths.first, let last = lengths.last else { return ([], [], 0, 0) }
        if lengths.count == 1 {
            let inset = max(0, (44 - first) / 2)
            return (lengths, cross, inset, inset)
        }
        return (lengths, cross, max(0, 44 - first - spacing / 2), max(0, 44 - last - spacing / 2))
    }

    /// 竖排且由组表面统一绘制时，每个按钮的边长：与组玻璃同宽。
    private var sidebarItemSide: CGFloat { Self.sidebarSlot + Self.sidebarGlassExtra }

    override var intrinsicContentSize: CGSize {
        // 竖排时组内按钮是与组同宽的正方形，长度只取决于按钮数量和组内净距，
        // 与按钮自己声明的尺寸无关（图标大小交给 `iconSize`）。
        if isVertical, !groupSurface.isHidden, !buttons.isEmpty {
            let side = sidebarItemSide
            let height = side * CGFloat(buttons.count)
                + spacing * CGFloat(max(0, buttons.count - 1))
                + moduleSpacingAfter
            return CGSize(width: side, height: height)
        }
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
        let circleSide = defaultCircleSide
        if measuredDefaultCircleSide != circleSide {
            // 导航栏挂载或改变高度后，原生承载可能仍持有上一次量测的尺寸。
            measuredDefaultCircleSide = circleSide
            invalidateIntrinsicContentSize()
            scheduleSizeChangeNotification()
        }
        // 竖排时长度由按钮数量和组内净距决定（两枚即 44×104），横排的 104×44 装不下。
        // 以自身中心为锚点按目标尺寸收敛，交给系统承载视图按新尺寸摆放。
        // 只收敛高度：宽度由栏位槽位决定，强行改宽会与系统量测互相触发。
        if isVertical {
            let target = intrinsicContentSize
            if abs(bounds.height - target.height) > 0.5 {
                frame = CGRect(x: frame.minX, y: frame.minY,
                               width: bounds.width, height: target.height)
            }
        }
        let groupLength = isVertical
            ? max(0, bounds.height - moduleSpacingAfter)
            : max(0, bounds.width - moduleSpacingAfter)
        // 组表面与系统按钮的玻璃同宽：侧栏按 barItemCross（槽位 + 4）居中，横栏铺满槽位。
        let glassWidth = isVertical ? sidebarItemSide : bounds.width
        let groupFrame = isVertical
            ? CGRect(x: bounds.midX - glassWidth / 2, y: bounds.minY,
                     width: glassWidth, height: groupLength)
            : CGRect(x: bounds.minX, y: bounds.minY, width: groupLength, height: bounds.height)
        // 模块间距归一化只做视觉校正：表面与其中内容一起平移，槽位（触控区）保持不动。
        // 组表面、组内图标、独立按钮的表面与图标因此遵循同一条规则。
        let shift = CGPoint(x: isVertical ? 0 : moduleVisualOffset, y: isVertical ? moduleVisualOffset : 0)
        let itemCross = barItemCross
        buttons.forEach {
            $0.barItemCross = itemCross
            $0.setModuleVisualOffset(moduleVisualOffset, vertical: isVertical)
        }
        groupSurface.frame = groupFrame.offsetBy(dx: shift.x, dy: shift.y)
        groupSurface.layer.cornerRadius = min(groupSurface.bounds.width, groupSurface.bounds.height) / 2
        groupSurface.layer.cornerCurve = .continuous
        groupSurface.synchronizeCornerRadius()
        let m = metrics
        guard !buttons.isEmpty else { touchRects = []; return }
        let available = isVertical
            ? max(0, bounds.height - moduleSpacingAfter)
            : max(0, bounds.width - moduleSpacingAfter)
        // 竖排且由组表面统一绘制时，每个按钮都是与组同宽的正方形：按钮自己的宽高不再决定
        // 外形，图标大小完全交给用户通过 `iconSize` / `contentInsets` 控制。
        // 独立按钮自带玻璃，保持自身声明尺寸（例如 44×72）。
        let squaresWithGroup = isVertical && !groupSurface.isHidden
        let verticalItemSide = isVertical ? glassWidth : 0
        let cross = isVertical ? bounds.width : bounds.height
        let pairs = CGFloat(buttons.count - 1)
        let gap = min(spacing, pairs > 0 ? available / pairs : 0)
        // 正方形按钮的边长与声明尺寸无关，总量必须按实际边长算，否则会多出居中偏移。
        let total = squaresWithGroup
            ? verticalItemSide * CGFloat(buttons.count)
            : m.lengths.reduce(0, +)
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
            let length = squaresWithGroup ? verticalItemSide : m.lengths[i] * scale
            let span = squaresWithGroup ? verticalItemSide : min(cross, m.cross[i])
            let slot = rect(p, length, span)
            if buttons[i].usesDefaultCircle {
                let side = min(length, span)
                buttons[i].frame = CGRect(x: slot.midX - side / 2, y: slot.midY - side / 2,
                                          width: side, height: side)
            } else {
                buttons[i].frame = slot
            }
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
        // 竖排时按钮与玻璃同宽、会比槽位宽出一点，命中区域必须覆盖到玻璃范围。
        let hitArea = touchRects.reduce(CGRect.null) { $0.union($1) }
        let allowed = bounds.contains(point) || (!hitArea.isNull && hitArea.contains(point))
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, allowed else { return nil }
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
        guard vertical != isVertical, tracksNativePlacement else { return }
        applyAxis(vertical)
    }

    /// 切换横竖排并立即按新轴向重新定尺寸。
    func applyAxis(_ vertical: Bool) {
        guard vertical != isVertical else { return }
        isVertical = vertical
        buttons.forEach { $0.setVertical(vertical) }
        invalidateIntrinsicContentSize()
        let target = intrinsicContentSize
        if isVertical, bounds.width > target.width + 0.5 {
            frame = CGRect(x: frame.midX - target.width / 2, y: frame.minY,
                           width: target.width, height: target.height)
        }
        superview?.setNeedsLayout()
        setNeedsLayout()
        scheduleSizeChangeNotification()
    }

    private func scheduleSizeChangeNotification() {
        guard onSizeChange != nil, !sizeChangeScheduled else { return }
        sizeChangeScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sizeChangeScheduled = false
            self.onSizeChange?()
        }
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
        // 用模块中心判断，而不是整块外框：比侧轨更宽的按钮组居中在槽位里时，外框会同时
        // 溢出两侧；若用 minX 判断，它就永远认不出自己在侧轨，也就永远不会触发拆分。
        return (window.safeAreaInsets.right > 0 && rect.midX >= safe.maxX - tolerance)
            || (window.safeAreaInsets.left > 0 && rect.midX <= safe.minX + tolerance)
    }
}
