import UIKit

/// 附加在标签栏上的操作按钮，不会成为可选中的标签目的地。
///
/// 经典栏会把操作放在栏内；胶囊栏会把圆形操作放在可见胶囊旁边。iOS 26 及以上的
/// 原生呈现使用系统附加操作区域，更早系统使用 SDK 的兼容实现或原生标签项拦截。
public struct ShellTabBarAccessory {
    /// 附加操作在标签栏中的位置。
    public enum Position: Equatable, Sendable {
        /// 放在标签栏左侧或前侧。
        case leading
        /// 放在标签栏右侧或后侧。
        case trailing
    }

    /// 附加操作的稳定标识，用于刷新时识别同一操作。
    public let id: String
    /// 标准图标；使用自定义内容时可以为空。
    public var icon: ShellTabIcon?
    /// 经典栏中显示在图标下方的可选标题。
    public var title: String?
    /// 附加操作在标签栏中的位置。
    public var position: Position
    /// 当前操作是否允许触发。
    public var isEnabled: Bool
    /// 无障碍元素使用的描述文本；为空时由标题回退。
    public var accessibilityLabel: String?
    /// 操作被触发时执行的回调。
    public var handler: () -> Void

    /// 替换操作的全部视觉内容；SDK 仍负责占位区域和点击行为。
    public var customContent: ShellTabBarCustomContent?

    struct Signature: Equatable {
        enum Icon: Equatable {
            case symbol(String)
            case asset(String, URL)
            case image(ObjectIdentifier)
        }

        let id: String
        let icon: Icon?
        let position: Position
        let title: String?
        let isEnabled: Bool
        let accessibilityLabel: String?
        let contentRevision: Int?
    }

    var signature: Signature {
        let iconKey: Signature.Icon?
        switch icon {
        case .systemSymbol(let name)?: iconKey = .symbol(name)
        case .asset(let name, let bundle)?: iconKey = .asset(name, bundle.bundleURL)
        case .image(let image)?: iconKey = .image(ObjectIdentifier(image))
        case nil: iconKey = nil
        }
        return Signature(id: id, icon: iconKey, position: position, title: title,
                         isEnabled: isEnabled, accessibilityLabel: accessibilityLabel, contentRevision: customContent?.revision)
    }

    /// 创建使用标准图标的标签栏附加操作。
    /// - Parameters:
    ///   - id: 附加操作的稳定标识。
    ///   - icon: 要显示的标签图标。
    ///   - title: 可选的标题；经典栏会显示该标题。
    ///   - position: 操作在标签栏中的位置。
    ///   - isEnabled: 是否允许触发操作。
    ///   - accessibilityLabel: 无障碍描述文本；为空时回退为标题。
    ///   - handler: 操作触发回调。
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

    /// 创建使用自定义视觉内容的标签栏附加操作。
    /// - Parameters:
    ///   - id: 附加操作的稳定标识。
    ///   - customContent: 替换标准图标和标题的自定义内容。
    ///   - position: 操作在标签栏中的位置。
    ///   - isEnabled: 是否允许触发操作。
    ///   - accessibilityLabel: 无障碍描述文本。
    ///   - handler: 操作触发回调。
    public init(id: String, customContent: ShellTabBarCustomContent, position: Position, isEnabled: Bool = true,
                accessibilityLabel: String, handler: @escaping () -> Void) {
        self.id = id
        self.customContent = customContent
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
    let customContent: ShellTabBarCustomContent?

    init(_ accessory: ShellTabBarAccessory, traits: UITraitCollection) {
        id = accessory.id
        title = accessory.title
        image = accessory.customContent == nil ? accessory.icon?.resolve(traits: traits) : nil
        isEnabled = accessory.isEnabled
        accessibilityLabel = accessory.accessibilityLabel
        handler = accessory.handler
        customContent = accessory.customContent
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
        guard #available(iOS 26.0, *) else { return false }
        return slotOverride ?? true
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
    private var customHost: ShellTabBarCustomContentHost?
    private let captionLabel = UILabel()
    private(set) var accessoryID: String?
    private var handler: (() -> Void)?
    private var usesBarSurface = false
    private var showsCaption = false
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
        iconView.isUserInteractionEnabled = false
        addSubview(iconView)
        captionLabel.isUserInteractionEnabled = false
        addSubview(captionLabel)
        addTarget(self, action: #selector(trigger), for: .touchUpInside)
    }

    /// Whether the current item shows a caption.
    var captionVisible: Bool { showsCaption }

    /// `compact` forces the icon-only circle even when a title exists.
    func update(item: ShellBarAccessoryItem, tint: UIColor, font: UIFont, compact: Bool,
                material: ShellMaterial = .systemDefault, captionBelow: Bool = false) {
        accessoryID = item.id
        handler = item.handler
        if let content = item.customContent {
            let host = customHost ?? ShellTabBarCustomContentHost()
            if customHost == nil {
                addSubview(host)
                customHost = host
            }
            host.update(content, owner: item.id)
        } else if let host = customHost {
            host.unmount()
            host.removeFromSuperview()
            customHost = nil
        }
        self.captionBelow = captionBelow
        self.material = material
        showsCaption = customHost == nil && !compact && (item.title?.isEmpty == false)
        backdrop.isHidden = usesBarSurface || customHost != nil
        iconView.isHidden = customHost != nil
        captionLabel.isHidden = !showsCaption
        let image = item.image
        iconView.image = image.map { $0.renderingMode == .alwaysOriginal ? $0 : $0.withRenderingMode(.alwaysTemplate) }
        iconView.tintColor = tint
        captionLabel.text = showsCaption ? item.title : nil
        captionLabel.font = font
        captionLabel.textColor = tint
        isEnabled = item.isEnabled
        updateButtonAlpha()
        accessibilityLabel = item.accessibilityLabel ?? item.title ?? "附加操作"
        accessibilityTraits = item.isEnabled ? .button : [.button, .notEnabled]
        accessibilityIdentifier = item.id
        refreshContentVisibility()
        refreshBackdrop()
        setNeedsLayout()
    }

    var controllerIsVisible = false {
        didSet { if oldValue != controllerIsVisible { refreshContentVisibility() } }
    }
    var resolvedContentMode: ShellTabBarCustomContent.Mode { customHost?.mode ?? .standard }

    /// Match by ID rather than array index so moving or adding a sibling cannot
    /// accidentally move its running animation to a different action.
    static func reconcile(_ previous: [ShellTabAccessoryButton], with items: [ShellBarAccessoryItem]) -> [ShellTabAccessoryButton] {
        var available = previous
        let buttons = items.map { item in
            guard let index = available.firstIndex(where: { $0.accessoryID == item.id }) else {
                return ShellTabAccessoryButton(frame: .zero)
            }
            return available.remove(at: index)
        }
        for button in available { button.unmount() }
        return buttons
    }

    func unmount() {
        customHost?.unmount()
        handler = nil
        accessoryID = nil
        removeFromSuperview()
    }

    func refreshContentVisibility() {
        customHost?.updateState(isSelected: false, isEnabled: isEnabled, isHighlighted: isHighlighted,
                                hostIsVisible: controllerIsVisible)
    }

    override var isHidden: Bool {
        didSet { if oldValue != isHidden { refreshContentVisibility() } }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshContentVisibility()
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
        self.usesBarSurface = usesBarSurface
        backdrop.isHidden = usesBarSurface || customHost != nil
        if usesBarSurface {
            castsCompatibilityShadow = false
            layer.shadowOpacity = 0
        }
        setNeedsLayout()
    }

    /// Mirrors the bar's own elevation so accessories sit at the same depth.
    func applyShadow(_ enabled: Bool) {
        castsCompatibilityShadow = enabled && customHost == nil
        ShellCapsuleElevation.apply(to: layer, enabled: castsCompatibilityShadow)
        setNeedsLayout()
    }

    /// Blur style currently used, exposed for diagnostics and tests.
    var blurStyle: UIBlurEffect.Style? { backdrop.blurStyle }
    /// Whether the button paints its own surface (false inside a full-width bar).
    var hasOwnBackdrop: Bool { !backdrop.isHidden }

    @objc private func trigger() {
        guard isEnabled else { return }
        handler?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let customHost {
            clipsToBounds = false
            customHost.frame = bounds
            customHost.layoutIfNeeded()
            return
        }
        backdrop.frame = bounds
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
        // 系统玻璃自己画出圆角轮廓和边缘高光，裁剪会把它们切掉；回退材质仍需圆角遮罩。
        let resolved = material == .solid || UIAccessibility.isReduceTransparencyEnabled ? .solid : material
        clipsToBounds = ShellMaterialRendering.clipsContent(resolved) && !castsCompatibilityShadow
        backdrop.layer.cornerRadius = bounds.height / 2
        backdrop.layer.cornerCurve = .continuous
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        if !showsCaption {
            captionLabel.frame = .zero
            layoutIcon(in: centeredSquare(in: bounds), standardCenterY: bounds.midY, standardSide: Self.barIconSide)
        } else if captionBelow {
            // Keep the classic caption baseline independent of content sizing.
            let titleHeight = min(ceil(captionLabel.font.lineHeight), bounds.height)
            let total = Self.barIconSide + 2 + titleHeight
            let top = bounds.minY + max(0, (bounds.height - total) / 2)
            let captionY = min(top + Self.barIconSide + 2, bounds.maxY - titleHeight)
            captionLabel.textAlignment = .center
            captionLabel.frame = CGRect(x: bounds.minX, y: captionY, width: bounds.width, height: titleHeight)
            let iconArea = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                                  height: max(0, captionY - bounds.minY - 2))
            layoutIcon(in: centeredSquare(in: iconArea), standardCenterY: top + Self.barIconSide / 2,
                       standardSide: Self.barIconSide)
        } else {
            let iconSide = Self.iconSide
            let titleWidth = min(ceil(captionLabel.intrinsicContentSize.width),
                                 max(0, bounds.width - iconSide - Self.contentGap - Self.horizontalPadding * 2))
            let start = bounds.midX - (iconSide + Self.contentGap + titleWidth) / 2
            let area = CGRect(x: start, y: bounds.midY - iconSide / 2, width: iconSide, height: iconSide)
                .intersection(bounds)
            layoutIcon(in: area.isNull ? .zero : area, standardCenterY: bounds.midY, standardSide: iconSide)
            captionLabel.textAlignment = .left
            captionLabel.frame = CGRect(x: start + iconSide + Self.contentGap,
                                        y: bounds.midY - captionLabel.font.lineHeight / 2,
                                        width: titleWidth, height: ceil(captionLabel.font.lineHeight))
        }
        refreshContentVisibility()
    }

    private func centeredSquare(in area: CGRect) -> CGRect {
        let side = min(area.width, area.height)
        return CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side)
    }

    private func layoutIcon(in area: CGRect, standardCenterY: CGFloat, standardSide: CGFloat) {
        let side = min(standardSide, area.width, area.height)
        let y = min(max(area.minY, standardCenterY - side / 2), area.maxY - side)
        iconView.frame = CGRect(x: area.midX - side / 2, y: y, width: side, height: side)
    }

    private func updateButtonAlpha() {
        alpha = customHost != nil ? 1 : (isEnabled ? (isHighlighted ? 0.5 : 1) : 0.4)
    }

    override var isHighlighted: Bool {
        didSet {
            updateButtonAlpha()
            refreshContentVisibility()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshBackdrop()
    }
}
