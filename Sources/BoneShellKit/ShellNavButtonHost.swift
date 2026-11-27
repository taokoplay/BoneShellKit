import UIKit

/// One visual button. The enclosing cluster supplies the axis, frame and any larger hit region.
@MainActor
final class ShellNavButtonHost: UIButton {
    private enum Source { case normal, vertical }
    private struct CustomContent {
        let revision: Int
        let view: UIView?
        let initialSize: CGSize
    }

    private(set) var isVertical = false
    private(set) var preferredVisualSize: CGSize = .zero
    private(set) var actionID = ""

    private var appearance = ShellNavButton()
    private var style = ShellNavButton.Style()
    private var textStyle = ShellTextStyle()
    private var actionTitle = ""
    private var icon: ShellNavigationIcon?
    private var lastActivationTime: CFTimeInterval = 0
    private var performAction: (() -> Void)?
    private let customSlot = UIView()
    private var customContent: [Source: CustomContent] = [:]
    private var insets = NSDirectionalEdgeInsets.zero
    private var iconBox = CGSize.zero
    private var titleFittingWidth: CGFloat = 0
    /// 按钮自身的材质表面；与栏位、胶囊、标签附件共用同一套绘制规则。
    private let surface = ShellGlassView(material: .solid)
    private var moduleVisualOffset: CGFloat = 0
    private var moduleVisualOffsetVertical = false
    // Keep invalid or unbounded input out of UIKit geometry, without imposing a 44 pt visual minimum.
    private static let extentLimit: CGFloat = 1024

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerCurve = .continuous
        backgroundColor = .clear
        isAccessibilityElement = true
        customSlot.isUserInteractionEnabled = false
        customSlot.accessibilityElementsHidden = true
        customSlot.clipsToBounds = true
        customSlot.isHidden = true
        surface.isUserInteractionEnabled = false
        surface.isHidden = true
        addSubview(surface)
        addSubview(customSlot)
        addTarget(self, action: #selector(activateAction), for: .primaryActionTriggered)
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(action: NavigationAction, textStyle: ShellTextStyle, perform: @escaping () -> Void) {
        if actionID != action.id { clearCustomContent() }
        actionID = action.id
        actionTitle = action.title
        icon = action.icon ?? (action.symbol.isEmpty ? nil : .systemSymbol(action.symbol))
        appearance = action.navButton ?? ShellNavButton()
        self.textStyle = textStyle
        performAction = perform
        accessibilityIdentifier = "action.\(action.id)"
        accessibilityLabel = action.title
        isAccessibilityElement = true
        isEnabled = action.isEnabled
        tintColor = textStyle.color
        render()
    }

    func setVertical(_ value: Bool) {
        guard isVertical != value else { return }
        isVertical = value
        if performAction != nil { render() }
    }

    func unmount() {
        performAction = nil
        removeFromSuperview()
        clearCustomContent()
        appearance = ShellNavButton()
        style = .init()
        textStyle = .init()
        actionID = ""
        actionTitle = ""
        icon = nil
        isVertical = false
        isEnabled = false
        isAccessibilityElement = false
        accessibilityIdentifier = nil
        accessibilityLabel = nil
        customSlot.isHidden = true
        setImage(nil, for: .normal)
        setTitle(nil, for: .normal)
        tintColor = nil
        updateMaterial(reduceTransparency: false)
        setPreferredSize(.zero)
        setNeedsLayout()
    }

    @objc private func activateAction() {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastActivationTime > 0.02 else { return }
        lastActivationTime = now
        performAction?()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // UIControl rechecks the location on touch-up; use exactly the target the cluster hit-tested.
        if let target = (superview as? ShellNavButtonCluster)?.touchRect(for: self) {
            return target.contains(point) || super.point(inside: point, with: event)
        }
        return super.point(inside: point, with: event)
        }

    override func accessibilityActivate() -> Bool {
        guard isEnabled, performAction != nil else { return false }
        sendActions(for: .primaryActionTriggered)
        return true
    }

    private func render() {
        style = appearance.resolvedStyle(isVertical: isVertical)
        let i = style.contentInsets ?? .zero
        insets = NSDirectionalEdgeInsets(top: Self.extent(i.top), leading: Self.extent(i.leading),
                                         bottom: Self.extent(i.bottom), trailing: Self.extent(i.trailing))
        let content = resolveCustomContent()
        let view = content?.view
        for old in customSlot.subviews where old !== view { old.removeFromSuperview() }
        customSlot.isHidden = view == nil
        if let view, view.superview == nil { customSlot.addSubview(view) }

        let usesStandard: Bool
        if case .custom = style.content { usesStandard = false } else { usesStandard = true }
        let image = usesStandard ? (style.icon ?? icon)?.resolve(traits: traitCollection) : nil
        setImage(image, for: .normal)
        setTitle(usesStandard && image == nil ? actionTitle : nil, for: .normal)
        let natural: CGSize
        if let view, let content {
            natural = measuredSize(of: view, fallback: content.initialSize)
        } else if !usesStandard {
            natural = .zero
        } else if let image {
            iconBox = Self.size(style.iconSize ?? .zero, fallback: Self.size(image.size, fallback: .zero))
            imageView?.contentMode = .scaleAspectFit
            natural = iconBox
        } else {
            let font = textStyle.resolvedFont(for: .body, traits: traitCollection)
                ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
            titleLabel?.font = font
            titleLabel?.textAlignment = .center
            titleLabel?.lineBreakMode = .byTruncatingTail
            updateTitleColor()
            let text = (actionTitle as NSString).size(withAttributes: [.font: font])
            natural = CGSize(width: ceil(text.width), height: ceil(font.lineHeight))
        }
        titleFittingWidth = usesStandard && image == nil ? natural.width + 1 : 0
        let fitted = Self.size(CGSize(width: natural.width + insets.leading + insets.trailing,
                                      height: natural.height + insets.top + insets.bottom),
                               fallback: CGSize(width: 1, height: 1))
        if case .preferred(let requested) = style.size {
            setPreferredSize(Self.size(requested, fallback: fitted))
        } else {
            setPreferredSize(fitted)
        }
        updateCustomState()
        transparencyChanged()
        setNeedsLayout()
    }

    private func resolveCustomContent() -> CustomContent? {
        for (source, entry) in customContent {
            let declaration = source == .normal ? appearance.normal.content : appearance.vertical?.content
            if case .custom(let revision, _)? = declaration, revision == entry.revision { continue }
            if entry.view?.superview === customSlot { entry.view?.removeFromSuperview() }
            customContent[source] = nil
        }
        guard case .custom(let revision, let makeView) = style.content else { return nil }
        let source: Source
        if isVertical, case .custom? = appearance.vertical?.content { source = .vertical } else { source = .normal }
        if customContent[source] == nil {
            let candidate = makeView()
            // Never steal another slot's view, or try to add a view to its own descendant.
            let available = candidate.superview == nil && candidate.window == nil && !isDescendant(of: candidate)
                && candidate !== self && !customContent.values.contains { $0.view === candidate }
            let initialSize = available ? fallbackSize(of: candidate) : .zero
            customContent[source] = CustomContent(revision: revision, view: available ? candidate : nil,
                                                  initialSize: initialSize)
        }
        guard let entry = customContent[source], let view = entry.view,
              view.superview === customSlot || (view.superview == nil && view.window == nil) else { return nil }
        return entry
    }

    private func clearCustomContent() {
        customSlot.subviews.forEach { $0.removeFromSuperview() }
        customContent.removeAll()
    }

    private static func extent(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
        value.isFinite && value > 0 ? min(value, extentLimit) : fallback
    }

    private static func size(_ value: CGSize, fallback: CGSize) -> CGSize {
        CGSize(width: extent(value.width, fallback: fallback.width), height: extent(value.height, fallback: fallback.height))
    }

    private func fallbackSize(of view: UIView) -> CGSize {
        // Capture the factory's geometry before the bar ever gives this view a compressed/stretched frame.
        let limit = CGSize(width: Self.extentLimit, height: Self.extentLimit)
        let initial = view.bounds.size
        let fitting = view.sizeThatFits(Self.size(initial, fallback: limit))
        return Self.size(initial, fallback: Self.size(fitting, fallback: CGSize(width: 24, height: 24)))
    }

    private func measuredSize(of view: UIView, fallback: CGSize) -> CGSize {
        let intrinsic = view.intrinsicContentSize
        // A frame-based leaf's default compressed fitting result may simply echo sizeThatFits.
        // Only ask Auto Layout to supplement the intrinsic dimensions for constraint-based content.
        let constrained = (view.constraints.isEmpty && view.subviews.isEmpty) ? .zero
            : view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return Self.size(intrinsic, fallback: Self.size(constrained, fallback: fallback))
    }

    private func setPreferredSize(_ size: CGSize) {
        guard preferredVisualSize != size else { return }
        preferredVisualSize = size
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        superview?.setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize { preferredVisualSize }
    func setModuleVisualOffset(_ offset: CGFloat, vertical: Bool) {
        moduleVisualOffset = offset.isFinite ? offset : 0
        moduleVisualOffsetVertical = vertical
        setNeedsLayout()
    }

    /// 按钮自己绘制表面时，表面随模块视觉偏移一起移动，图形始终与表面同心。
    private var paintsOwnSurface: Bool { !surface.isHidden }

    private func shiftedRect(_ rect: CGRect) -> CGRect {
        moduleVisualOffsetVertical
            ? rect.offsetBy(dx: 0, dy: moduleVisualOffset)
            : rect.offsetBy(dx: moduleVisualOffset, dy: 0)
    }

    private func shiftedVisualBounds(_ rect: CGRect) -> CGRect {
        shiftedRect(rect).intersection(bounds)
    }

    /// 绘制用的内容外框。
    ///
    /// 自绘表面时表面整体偏移，内容必须跟着走、且不能按槽位裁剪，否则会被压窄或与表面错位；
    /// 透明按钮没有表面可跟随，可见边界就是内容本身，因此保留原有的槽位内裁剪。
    private func offsetContent(_ rect: CGRect) -> CGRect {
        paintsOwnSurface ? shiftedRect(rect) : shiftedVisualBounds(rect)
    }

    /// 系统栏位条目自身的玻璃尺寸（横栏取高度，侧栏取宽度）；由 `ShellNavButtonCluster` 写入。
    ///
    /// 系统玻璃会比我们拿到的槽位更大：Duo 横栏 48 pt 对 44 pt 槽位，侧栏 48 pt 对 44 pt 槽位。
    /// 不跟着取同尺寸，同一个栏里就会出现两种宽/高的胶囊。
    var barItemCross: CGFloat = 0

    /// 表面在按钮坐标中的外框。
    ///
    /// 尺寸取实际布局到的 `bounds`（系统可能把请求宽度压小），位置跟随模块视觉偏移；
    /// 表面、图标和标题因此共用同一份几何，任一项都不会相对其他项错位。
    private var surfaceFrame: CGRect {
        var size = bounds.size
        if !moduleVisualOffsetVertical, barItemCross > size.height, size.height > 0 {
            size.height = barItemCross
        } else if moduleVisualOffsetVertical, barItemCross > size.width, size.width > 0 {
            size.width = barItemCross
        }
        let centered = CGRect(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2,
                              width: size.width, height: size.height)
        return shiftedRect(centered)
    }

    var moduleVisualBounds: CGRect {
        // 自带表面的按钮，可见边界就是表面本身而不是内部图形，否则间距归零会把图标挤出圆心。
        if paintsOwnSurface { return surfaceFrame }
        if !customSlot.isHidden, let view = customSlot.subviews.first {
            return shiftedVisualBounds(view.frame)
        }
        let content = contentRect(forBounds: bounds)
        if image(for: .normal) != nil { return imageRect(forContentRect: content) }
        if title(for: .normal) != nil { return titleRect(forContentRect: content) }
        return shiftedVisualBounds(content)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let proposal = Self.size(size, fallback: preferredVisualSize)
        return CGSize(width: min(proposal.width, preferredVisualSize.width), height: min(proposal.height, preferredVisualSize.height))
    }

    override func contentRect(forBounds bounds: CGRect) -> CGRect {
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var leading = insets.leading, trailing = insets.trailing
        if titleFittingWidth > 0, bounds.width < preferredVisualSize.width, leading + trailing > 0 {
            // Give up padding before truncating a short title in a compressed bar slot.
            let ratio = min(1, max(0, bounds.width - titleFittingWidth) / (leading + trailing))
            leading *= ratio
            trailing *= ratio
        }
        let left = min(bounds.width, rtl ? trailing : leading)
        let top = min(bounds.height, insets.top)
        return CGRect(x: bounds.minX + left, y: bounds.minY + top,
                      width: max(0, bounds.width - left - (rtl ? leading : trailing)),
                      height: max(0, bounds.height - top - insets.bottom))
    }

    override func imageRect(forContentRect rect: CGRect) -> CGRect {
        guard let image = image(for: .normal), image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(min(rect.width, iconBox.width) / image.size.width, min(rect.height, iconBox.height) / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return offsetContent(CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                    width: size.width, height: size.height))
    }

    override func titleRect(forContentRect rect: CGRect) -> CGRect { offsetContent(rect) }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UIKit 会在首次布局时才把 imageView、titleLabel 插到索引 0，表面必须保持在最底层，
        // 否则玻璃会盖住图标和文字。
        if let index = subviews.firstIndex(of: surface), index != 0 { sendSubviewToBack(surface) }
        let radius = min(bounds.width, bounds.height) / 2
        layer.cornerRadius = surface.isHidden ? 0 : radius
        surface.layer.cornerRadius = radius
        surface.layer.cornerCurve = .continuous
        surface.frame = surface.isHidden ? bounds : surfaceFrame
        surface.synchronizeCornerRadius()
        guard !customSlot.isHidden, let view = customSlot.subviews.first else { return }
        customSlot.frame = contentRect(forBounds: bounds)
        view.bounds.size = customSlot.bounds.size
        view.center = CGPoint(x: customSlot.bounds.midX + shiftedRect(.zero).minX,
                              y: customSlot.bounds.midY + shiftedRect(.zero).minY)
    }

    override var isEnabled: Bool { didSet { updateCustomState() } }
    override var isHighlighted: Bool { didSet { updateCustomState() } }

    private func updateCustomState() {
        let alpha: CGFloat = !isEnabled ? 0.4 : (isHighlighted ? 0.55 : 1)
        customSlot.alpha = alpha
        // 标准内容没有自定义视图时也要有按压反馈，与自定义内容保持一致的透明度变化。
        imageView?.alpha = alpha
        titleLabel?.alpha = alpha
    }

    private func updateTitleColor() {
        let color = textStyle.color ?? tintColor ?? .systemBlue
        setTitleColor(color, for: .normal)
        setTitleColor(color.withAlphaComponent(0.55), for: .highlighted)
        setTitleColor(.tertiaryLabel, for: .disabled)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        if performAction != nil { updateTitleColor() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if performAction != nil { render() }
    }

    @objc private func transparencyChanged() {
        updateMaterial(reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
    }

    /// 按显式输入刷新按钮表面。显式参数便于在不改变设备辅助功能设置的前提下做确定性测试。
    /// - Parameter reduceTransparency: 是否按“减少透明度”解析材质。
    func updateMaterial(reduceTransparency: Bool) {
        guard let requested = style.effect.material else {
            surface.isHidden = true
            clipsToBounds = true
            backgroundColor = .clear
            setNeedsLayout()
            return
        }
        let resolution = ShellMaterials.resolve(
            requested,
            supportsSystemGlass: ShellMaterials.supportsSystemGlass,
            reduceTransparency: reduceTransparency
        )
        surface.glassTintColor = style.tintColor
        surface.apply(resolution)
        surface.isHidden = false
        backgroundColor = .clear
        // 系统玻璃自己画出边缘高光，宿主不能再裁剪；回退材质继续用圆角遮罩。
        clipsToBounds = ShellMaterialRendering.clipsContent(resolution.resolved)
        setNeedsLayout()
    }
}
