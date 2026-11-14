import UIKit

/// An extra action button attached to the tab bar. It never becomes a selected tab.
///
/// Classic bars place actions inside the bar. Capsule bars place circular actions beside
/// the visible capsule, using a standalone native tab bar on iOS 26 and later and the SDK
/// renderer on older systems. Explicit system presentation uses UIKit's accessory slot
/// on iOS 26 and later, or intercepted native tab items below iOS 26.
public struct ShellTabBarAccessory {
    public enum Position: Sendable {
        case leading
        case trailing
    }

    public let id: String
    /// Icon. `.systemSymbol` is rendered as a template and tinted with the tab bar style.
    public var icon: ShellTabIcon
    /// Optional caption under the icon in self-drawn bars.
    public var title: String?
    public var position: Position
    public var isEnabled: Bool
    public var accessibilityLabel: String?
    public var handler: () -> Void

    /// Cheap identity used to skip redundant bar rebuilds.
    var signature: String {
        let iconKey: String
        switch icon {
        case .systemSymbol(let name): iconKey = "symbol:\(name)"
        case .asset(let name, let bundle): iconKey = "asset:\(bundle.bundleURL.absoluteString):\(name)"
        case .image(let image): iconKey = "image:\(UInt(bitPattern: ObjectIdentifier(image).hashValue))"
        }
        return "\(id)|\(position == .leading ? "L" : "R")|\(title ?? "")|\(isEnabled)|\(accessibilityLabel ?? "")|\(iconKey)"
    }

    public init(
        id: String,
        icon: ShellTabIcon,
        title: String? = nil,
        position: Position,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.position = position
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.handler = handler
    }
}

/// Renderer-facing accessory resolved for the current traits.
@MainActor
struct ShellBarAccessoryItem {
    let id: String
    let title: String?
    let image: UIImage?
    let isEnabled: Bool
    let accessibilityLabel: String?
    let handler: () -> Void

    init(_ accessory: ShellTabBarAccessory, traits: UITraitCollection) {
        id = accessory.id
        title = accessory.title
        image = accessory.icon.resolve(traits: traits)
        isEnabled = accessory.isEnabled
        accessibilityLabel = accessory.accessibilityLabel
        handler = accessory.handler
    }
}

/// Chooses how a native bar hosts accessory buttons.
///
/// Explicit system presentation uses `UITabAccessory` on iOS 26 and later, and native tab
/// items with intercepted selection on older systems. `slotOverride` lets tests exercise
/// the legacy item path on a newer runtime.
enum ShellTabBarAccessoryHosting {
    static var slotOverride: Bool?

    static var supportsSystemSlot: Bool {
        if let override = slotOverride { return override }
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

/// Accessory button drawn outside the tab bar.
///
/// It carries its own material so it reads like part of the bar: a circle when it only
/// has an icon, and a pill with icon plus caption when a title is provided.
@MainActor
final class ShellTabAccessoryButton: UIButton {
    /// The capsule's own backdrop, reused so both surfaces composite identically.
    private let backdrop = ShellCapsuleBackdrop()
    /// Material of the bar this button belongs to, so both surfaces look the same.
    private var material: ShellMaterial = .systemDefault

    private let iconView = UIImageView()
    private let captionLabel = UILabel()
    private var item: ShellBarAccessoryItem?
    private var showsCaption = false
    private var compact = false
    /// Classic bar items stack icon over caption; the native slot lays them side by side.
    private var captionBelow = false
    private var castsCompatibilityShadow = false

    /// Gap between icon and caption inside a pill.
    private static let contentGap: CGFloat = 6
    private static let horizontalPadding: CGFloat = 14
    fileprivate static let iconSide: CGFloat = 22
    /// Same glyph size as a tab item so the row reads as one row.
    static let barIconSide: CGFloat = 25

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isAccessibilityElement = true
        backdrop.isUserInteractionEnabled = false
        backdrop.isAccessibilityElement = false
        backdrop.clipsToBounds = true
        iconView.isAccessibilityElement = false
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Self.barIconSide)
        captionLabel.isAccessibilityElement = false
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 1
        captionLabel.adjustsFontForContentSizeCategory = true
        addSubview(backdrop)
        for view in [iconView, captionLabel] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        addTarget(self, action: #selector(trigger), for: .touchUpInside)
    }

    /// Whether the current item shows a caption.
    var captionVisible: Bool { showsCaption }

    /// `compact` forces the icon-only circle even when a title exists.
    func update(item: ShellBarAccessoryItem, tint: UIColor, font: UIFont, compact: Bool,
                material: ShellMaterial = .systemDefault, captionBelow: Bool = false) {
        self.item = item
        self.compact = compact
        self.captionBelow = captionBelow
        self.material = material
        showsCaption = !compact && (item.title?.isEmpty == false)
        let image = item.image
        iconView.image = image.map { $0.renderingMode == .alwaysOriginal ? $0 : $0.withRenderingMode(.alwaysTemplate) }
        iconView.tintColor = tint
        captionLabel.text = showsCaption ? item.title : nil
        captionLabel.font = font
        captionLabel.textColor = tint
        isEnabled = item.isEnabled
        alpha = item.isEnabled ? 1 : 0.4
        accessibilityLabel = item.accessibilityLabel ?? item.title ?? "附加操作"
        accessibilityTraits = item.isEnabled ? .button : [.button, .notEnabled]
        accessibilityIdentifier = item.id
        refreshBackdrop()
        setNeedsLayout()
    }

    /// Width this button wants when the bar decides its geometry.
    ///
    /// The pill must fit icon + gap + caption + both paddings, otherwise the caption
    /// collapses into an ellipsis.
    func preferredWidth(height: CGFloat) -> CGFloat {
        guard showsCaption else { return height }
        let attributes: [NSAttributedString.Key: Any] = [.font: captionLabel.font ?? UIFont.systemFont(ofSize: 11)]
        let textWidth = ceil((captionLabel.text ?? "").size(withAttributes: attributes).width)
        let content = Self.iconSide + Self.contentGap + textWidth + Self.horizontalPadding * 2
        return max(height, ceil(content))
    }

    private func refreshBackdrop() {
        backdrop.update(material: material, showsMediaBackground: false)
    }

    /// Inside a full-width bar the button borrows the bar's surface instead of drawing one.
    func useBarSurface(_ usesBarSurface: Bool) {
        backdrop.isHidden = usesBarSurface
        if usesBarSurface {
            castsCompatibilityShadow = false
            layer.shadowOpacity = 0
        }
        setNeedsLayout()
    }

    /// Mirrors the bar's own elevation so accessories sit at the same depth.
    func applyShadow(_ enabled: Bool) {
        castsCompatibilityShadow = enabled
        ShellCapsuleElevation.apply(to: layer, enabled: enabled)
        setNeedsLayout()
    }

    /// Blur style currently used, exposed for diagnostics and tests.
    var blurStyle: UIBlurEffect.Style? { backdrop.blurStyle }
    /// Whether the button paints its own surface (false inside a full-width bar).
    var hasOwnBackdrop: Bool { !backdrop.isHidden }

    @objc private func trigger() {
        guard let item = item, item.isEnabled else { return }
        item.handler()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
        // Native glass owns its rounded contour and shadow. Clipping the button cuts that
        // shadow off; older blur surfaces still need a rounded mask.
        if #available(iOS 26.0, *) {
            clipsToBounds = (material != .systemGlass || UIAccessibility.isReduceTransparencyEnabled)
                && !castsCompatibilityShadow
        } else {
            clipsToBounds = !castsCompatibilityShadow
        }
        backdrop.layer.cornerRadius = bounds.height / 2
        backdrop.layer.cornerCurve = .continuous
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        if compact || !showsCaption {
            let iconSide = Self.barIconSide
            iconView.frame = CGRect(x: bounds.midX - iconSide / 2, y: bounds.midY - iconSide / 2,
                                    width: iconSide, height: iconSide)
            captionLabel.frame = .zero
            return
        }
        if captionBelow {
            // Mirror the tab item metrics: glyph on top, caption centred underneath.
            let titleHeight = min(ceil(captionLabel.font.lineHeight), max(0, bounds.height))
            let total = Self.barIconSide + 2 + titleHeight
            let top = bounds.minY + max(0, (bounds.height - total) / 2)
            iconView.frame = CGRect(x: bounds.midX - Self.barIconSide / 2, y: top,
                                    width: Self.barIconSide, height: Self.barIconSide)
            captionLabel.textAlignment = .center
            captionLabel.frame = CGRect(x: bounds.minX, y: iconView.frame.maxY + 2,
                                        width: bounds.width, height: titleHeight)
            return
        }
        let iconSide = Self.iconSide
        if showsCaption {
            let captionWidth = min(ceil(captionLabel.intrinsicContentSize.width),
                                   max(0, bounds.width - iconSide - Self.contentGap - Self.horizontalPadding * 2))
            let contentWidth = iconSide + Self.contentGap + captionWidth
            let start = bounds.midX - contentWidth / 2
            iconView.frame = CGRect(x: start, y: bounds.midY - iconSide / 2, width: iconSide, height: iconSide)
            captionLabel.textAlignment = .left
            captionLabel.frame = CGRect(x: iconView.frame.maxX + Self.contentGap,
                                        y: bounds.midY - captionLabel.font.lineHeight / 2,
                                        width: captionWidth, height: ceil(captionLabel.font.lineHeight))
        } else {
            iconView.frame = CGRect(x: bounds.midX - iconSide / 2, y: bounds.midY - iconSide / 2,
                                    width: iconSide, height: iconSide)
            captionLabel.frame = .zero
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isEnabled ? (isHighlighted ? 0.5 : 1) : 0.4 }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshBackdrop()
    }
}
