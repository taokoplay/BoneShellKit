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
    private enum Material { case none, blur, glass, solid }

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
    private var material = Material.none
    private var materialView: UIVisualEffectView?
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
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    }

    override func titleRect(forContentRect rect: CGRect) -> CGRect { rect }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = material == .none ? 0 : min(bounds.width, bounds.height) / 2
        materialView?.frame = bounds
        guard !customSlot.isHidden, let view = customSlot.subviews.first else { return }
        customSlot.frame = contentRect(forBounds: bounds)
        view.bounds.size = customSlot.bounds.size
        view.center = CGPoint(x: customSlot.bounds.midX, y: customSlot.bounds.midY)
    }

    override var isEnabled: Bool { didSet { updateCustomState() } }
    override var isHighlighted: Bool { didSet { updateCustomState() } }

    private func updateCustomState() {
        customSlot.alpha = !isEnabled ? 0.4 : (isHighlighted ? 0.55 : 1)
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

    // Explicit input also allows deterministic testing without changing the device's accessibility settings.
    func updateMaterial(reduceTransparency: Bool) {
        let next: Material
        if style.effect == .none || style.effect == .inherited { next = .none }
        else if reduceTransparency { next = .solid }
        else if style.effect == .liquidGlass, #available(iOS 26.0, *) { next = .glass }
        else { next = .blur }
        guard next != material else { return }
        material = next
        backgroundColor = next == .solid ? .secondarySystemBackground : .clear
        if next == .blur || next == .glass {
            let view = materialView ?? UIVisualEffectView(effect: nil)
            if materialView == nil {
                view.isUserInteractionEnabled = false
                view.accessibilityElementsHidden = true
                if #available(iOS 26.0, *) { view.cornerConfiguration = .capsule() }
                insertSubview(view, at: 0)
                materialView = view
            }
            if next == .glass, #available(iOS 26.0, *) { view.effect = UIGlassEffect(style: .regular) }
            else { view.effect = UIBlurEffect(style: .systemMaterial) }
        } else {
            materialView?.removeFromSuperview()
            materialView = nil
        }
        setNeedsLayout()
    }
}
