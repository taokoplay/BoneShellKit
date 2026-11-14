import UIKit

/// Floating capsule tab bar drawn by the SDK when the system has no native capsule.
///
/// The bar floats above the content instead of spanning edge to edge, keeps the
/// home-indicator area clear, and reports how much vertical space the container
/// must reserve so content is never hidden behind it.
@MainActor
final class ShellCapsuleTabBar: UIView {
    var onSelect: ((Int) -> Void)?

    /// Height of the capsule itself, excluding `bottomGap` and the safe area.
    private(set) var contentHeight: CGFloat = 56
    /// Home-indicator safe area the capsule floats above.
    var bottomInset: CGFloat = 0 {
        didSet {
            guard abs(bottomInset - oldValue) > 0.1 else { return }
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    /// Vertical space the container must keep clear, measured above the safe area.
    var occupiedHeight: CGFloat { contentHeight + Self.bottomGap }

    static let horizontalMargin: CGFloat = 12
    static let bottomGap: CGFloat = 8
    static let minimumContentHeight: CGFloat = 52
    private static let innerPadding: CGFloat = 6

    private struct Model {
        let items: [UITabBarItem]
        let selectedIndex: Int
        let style: ShellTabBarStyle
        let material: ShellMaterial
        let showsMediaBackground: Bool
    }

    /// Material style of the capsule surface, for diagnostics and consistency tests.
    var backdropBlurStyle: UIBlurEffect.Style? { backdrop.blurStyle }
    private let backdrop = ShellCapsuleBackdrop()
    private var buttons: [ShellClassicTabButton] = []
    private var model: Model?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func update(items: [UITabBarItem], selectedIndex: Int, style: ShellTabBarStyle,
                material: ShellMaterial, showsMediaBackground: Bool) {
        model = Model(items: items, selectedIndex: selectedIndex, style: style,
                      material: material, showsMediaBackground: showsMediaBackground)
        applyModel()
    }

    private func configureView() {
        isAccessibilityElement = false
        backgroundColor = .clear
        ShellCapsuleElevation.apply(to: layer)
        addSubview(backdrop)
    }

    private func applyModel() {
        guard let model = model else { return }
        let style = model.style
        let normalFont = style.normal.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        let selectedFont = style.selected.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        let newHeight = max(Self.minimumContentHeight,
                            ceil(25 + 2 + max(normalFont.lineHeight, selectedFont.lineHeight) + 16))
        if abs(contentHeight - newHeight) > 0.1 {
            contentHeight = newHeight
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
        while buttons.count > model.items.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < model.items.count {
            let index = buttons.count
            let button = ShellClassicTabButton(frame: .zero)
            button.showsSelectionPill = true
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            buttons.append(button)
            addSubview(button)
        }
        let pillColor = (tintColor ?? .systemBlue).withAlphaComponent(0.16)
        for (index, item) in model.items.enumerated() {
            let selected = index == model.selectedIndex
            let role = selected ? style.selected : style.normal
            let color = role.color ?? (selected ? (tintColor ?? .systemBlue) : .secondaryLabel)
            let iconColor = (selected ? style.selectedIconColor : style.normalIconColor)
                ?? (selected ? (tintColor ?? .systemBlue) : .secondaryLabel)
            buttons[index].selectionPillColor = pillColor
            buttons[index].update(item: item, selected: selected,
                                  font: selected ? selectedFont : normalFont,
                                  color: color, iconColor: iconColor)
        }
        backdrop.update(material: model.material, showsMediaBackground: model.showsMediaBackground)
        accessibilityElements = buttons
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: occupiedHeight + max(0, bottomInset))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        backdrop.layer.cornerRadius = min(bounds.height, bounds.width) / 2
        backdrop.layer.cornerCurve = .continuous
        layer.shadowPath = UIBezierPath(roundedRect: bounds,
                                        cornerRadius: min(bounds.height, bounds.width) / 2).cgPath
        guard !buttons.isEmpty else { return }
        let height = max(0, bounds.height - max(0, bottomInset))
        let inner = bounds.insetBy(dx: Self.innerPadding, dy: 0)
        let count = buttons.count
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, button) in buttons.enumerated() {
            let visualIndex = isRTL ? count - 1 - index : index
            let left = inner.width * CGFloat(visualIndex) / CGFloat(count)
            let right = inner.width * CGFloat(visualIndex + 1) / CGFloat(count)
            button.frame = CGRect(x: inner.minX + left, y: bounds.minY,
                                  width: right - left, height: height)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) != false {
            layer.shadowColor = UIColor.black.cgColor
        }
        applyModel()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyModel()
    }
}

/// Capsule surface: a rounded material that stays legible over photos and video.
@MainActor
final class ShellCapsuleBackdrop: UIView {
    /// Blur style in use, tracked because `UIBlurEffect.style` is not readable.
    private(set) var blurStyle: UIBlurEffect.Style?
    private let effectView = UIVisualEffectView(effect: nil)
    private let highlight = UIView()
    private var material: ShellMaterial = .automatic
    private var showsMediaBackground = false
    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = false
        if #available(iOS 26.0, *) {
            // Give UIKit the real contour so glass edges and the system shadow follow it.
            effectView.cornerConfiguration = .capsule()
        }
        highlight.isUserInteractionEnabled = false
        highlight.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor.white.withAlphaComponent(0.35)
        }
        addSubview(effectView)
        addSubview(highlight)
        NotificationCenter.default.addObserver(self, selector: #selector(reduceTransparencyDidChange),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                                               object: nil)
        refreshAppearance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(material: ShellMaterial, showsMediaBackground: Bool) {
        self.material = material
        self.showsMediaBackground = showsMediaBackground
        refreshAppearance()
    }

    private func refreshAppearance() {
        let reduce = UIAccessibility.isReduceTransparencyEnabled
        let solid = material == .solid || reduce
        backgroundColor = solid ? .secondarySystemBackground : .clear
        highlight.isHidden = !solid || showsMediaBackground
        let wantsGlass = material == .systemGlass && !reduce
        // A native glass effect draws beyond its surface to form the system shadow.
        // Only fallback blur/solid surfaces need an outer clipping mask.
        if #available(iOS 26.0, *) { clipsToBounds = !wantsGlass }
        else { clipsToBounds = true }
        if solid {
            effectView.effect = nil
            blurStyle = nil
        } else if wantsGlass, #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = false
            effectView.effect = glass
        } else if effectView.effect == nil || wantsGlass {
            // `.systemDefault` means the classic bar's material; the capsule uses chrome.
            let style: UIBlurEffect.Style = material == .systemDefault ? .systemMaterial : .systemChromeMaterial
            if blurStyle != style {
                effectView.effect = UIBlurEffect(style: style)
                blurStyle = style
            }
        }
        // A media background keeps the capsule translucent so the canvas stays visible.
        effectView.alpha = showsMediaBackground ? 0.85 : 1
        setNeedsLayout()
    }

    @objc private func reduceTransparencyDidChange() {
        refreshAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        let pixel = 1 / max(1, window?.screen.scale ?? traitCollection.displayScale)
        highlight.frame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: pixel * 2)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshAppearance()
    }
}

/// Shared elevation for the compatibility capsule and its accessory circles.
@MainActor
enum ShellCapsuleElevation {
    static func apply(to layer: CALayer, enabled: Bool = true) {
        layer.shadowColor = enabled ? UIColor.black.cgColor : nil
        layer.shadowOpacity = enabled ? 0.12 : 0
        layer.shadowRadius = enabled ? 12 : 0
        layer.shadowOffset = enabled ? CGSize(width: 0, height: 4) : .zero
    }
}
