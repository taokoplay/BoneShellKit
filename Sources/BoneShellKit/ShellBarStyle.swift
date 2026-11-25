import UIKit

/// 导航栏和标签栏文字的字体、颜色及动态字体设置。
/// `nil` 会保留对应 UIKit 样式的值。
@MainActor
public struct ShellTextStyle {
    /// 覆盖 UIKit 使用的字体；为空时继承系统字体。
    public var font: UIFont?
    /// 覆盖 UIKit 使用的文字颜色；为空时继承系统颜色。
    public var color: UIColor?
    /// 是否根据动态字体设置缩放指定字体。
    public var scalesWithDynamicType: Bool

    /// 创建文字样式。
    /// - Parameters:
    ///   - font: 要使用的字体；为空时继承系统字体。
    ///   - color: 要使用的颜色；为空时继承系统颜色。
    ///   - scalesWithDynamicType: 是否根据动态字体设置缩放字体。
    public init(font: UIFont? = nil, color: UIColor? = nil, scalesWithDynamicType: Bool = true) {
        self.font = font
        self.color = color
        self.scalesWithDynamicType = scalesWithDynamicType
    }

    /// 按字号和字重创建文字样式。
    /// - Parameters:
    ///   - size: 字体点数，必须为有限正数。
    ///   - weight: 字体字重。
    ///   - color: 要使用的颜色；为空时继承系统颜色。
    ///   - scalesWithDynamicType: 是否根据动态字体设置缩放字体。
    public init(size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor? = nil, scalesWithDynamicType: Bool = true) {
        precondition(size.isFinite && size > 0, "Font size must be finite and positive.")
        self.init(font: .systemFont(ofSize: size, weight: weight), color: color, scalesWithDynamicType: scalesWithDynamicType)
    }

    var isEmpty: Bool { font == nil && color == nil }

    func resolvedFont(for role: UIFont.TextStyle, traits: UITraitCollection) -> UIFont? {
        guard let font = font else { return nil }
        return scalesWithDynamicType
            ? UIFontMetrics(forTextStyle: role).scaledFont(for: font, compatibleWith: traits) : font
    }

    func attributes(merging original: [NSAttributedString.Key: Any], role: UIFont.TextStyle, traits: UITraitCollection) -> [NSAttributedString.Key: Any] {
        var result = original
        if let font = resolvedFont(for: role, traits: traits) { result[.font] = font }
        if let color = color { result[.foregroundColor] = color }
        return result
    }
}

/// 导航栏标题、副标题、大标题和按钮的文字样式集合。
@MainActor
public struct ShellNavigationStyle {
    /// 普通导航标题的文字样式。
    public var title: ShellTextStyle
    /// 大标题布局的文字样式。
    public var largeTitle: ShellTextStyle
    /// 副标题的文字样式。
    public var subtitle: ShellTextStyle
    /// 导航按钮文字的样式。
    public var buttons: ShellTextStyle

    /// 创建导航栏样式。
    /// - Parameters:
    ///   - title: 普通标题样式；为空时使用默认样式。
    ///   - largeTitle: 大标题样式；为空时使用默认样式。
    ///   - subtitle: 副标题样式；为空时使用默认样式。
    ///   - buttons: 按钮文字样式；为空时使用默认样式。
    public init(title: ShellTextStyle? = nil, largeTitle: ShellTextStyle? = nil, subtitle: ShellTextStyle? = nil, buttons: ShellTextStyle? = nil) {
        self.title = title ?? ShellTextStyle()
        self.largeTitle = largeTitle ?? ShellTextStyle()
        self.subtitle = subtitle ?? ShellTextStyle()
        self.buttons = buttons ?? ShellTextStyle()
    }

    var isEmpty: Bool { title.isEmpty && largeTitle.isEmpty && subtitle.isEmpty && buttons.isEmpty }
}

/// 标签栏文字、图标和标签标题显示方式的样式集合。
@MainActor
public struct ShellTabBarStyle {
    /// 未选中标签的文字样式。
    public var normal: ShellTextStyle
    /// 选中标签的文字样式。
    public var selected: ShellTextStyle
    /// 未选中标签的图标颜色；为空时继承 UIKit 颜色。
    public var normalIconColor: UIColor?
    /// 选中标签的图标颜色；为空时继承 UIKit 颜色。
    public var selectedIconColor: UIColor?
    /// 没有单项覆盖时使用的默认标题显示策略。
    public var labelDisplayMode: ShellTabLabelDisplayMode

    /// 创建标签栏样式。
    /// - Parameters:
    ///   - normal: 未选中标签的文字样式；为空时使用默认样式。
    ///   - selected: 选中标签的文字样式；为空时使用默认样式。
    ///   - normalIconColor: 未选中图标颜色；为空时继承 UIKit 颜色。
    ///   - selectedIconColor: 选中图标颜色；为空时继承 UIKit 颜色。
    ///   - labelDisplayMode: 没有单项覆盖时使用的标题显示策略。
    public init(normal: ShellTextStyle? = nil, selected: ShellTextStyle? = nil, normalIconColor: UIColor? = nil, selectedIconColor: UIColor? = nil, labelDisplayMode: ShellTabLabelDisplayMode = .always) {
        self.normal = normal ?? ShellTextStyle()
        self.selected = selected ?? ShellTextStyle()
        self.normalIconColor = normalIconColor
        self.selectedIconColor = selectedIconColor
        self.labelDisplayMode = labelDisplayMode
    }

    var isEmpty: Bool {
        normal.isEmpty && selected.isEmpty && normalIconColor == nil
            && selectedIconColor == nil && labelDisplayMode == .always
    }
}

/// 标签栏和导航栏使用的图标来源。
@MainActor
public enum ShellTabIcon {
    /// 使用指定名称的 SF Symbol。
    case systemSymbol(String)
    /// 从指定资源包加载图片资源。
    case asset(String, bundle: Bundle)
    /// 直接使用 UIImage。
    case image(UIImage)

    func resolve(traits: UITraitCollection) -> UIImage? {
        switch self {
        case .systemSymbol(let name): return UIImage(systemName: name)
        case .asset(let name, let bundle):
            guard let image = UIImage(named: name, in: bundle, compatibleWith: traits) else { return nil }
            // Plain bundle PNGs are tab glyphs by default. Respect explicit asset-catalog modes.
            return image.renderingMode == .automatic ? image.withRenderingMode(.alwaysTemplate) : image
        case .image(let image): return image
        }
    }
}

/// 一个标签目的地的标题、图标和自定义内容配置。
@MainActor
public struct ShellTabItemConfiguration {
    /// 标签目的地的语义标题。
    public var title: String
    /// 未选中时使用的图标。
    public var icon: ShellTabIcon?
    /// 选中时使用的图标；为空时按 `selectedIconMode` 回退。
    public var selectedIcon: ShellTabIcon?
    /// 选中状态下选择图标和颜色的方式。
    public var selectedIconMode: ShellTabSelectedIconMode
    /// 单项标题显示策略；为空时继承标签栏样式。标题仍会用于无障碍。
    public var labelDisplayMode: ShellTabLabelDisplayMode?
    /// 替换整个视觉标签项；标题仍用于无障碍和溢出列表。
    public var customContent: ShellTabBarCustomContent?

    /// 创建标准标签项配置。
    /// - Parameters:
    ///   - title: 标签目的地的语义标题。
    ///   - icon: 未选中时使用的图标。
    ///   - selectedIcon: 选中时使用的图标。
    ///   - selectedIconMode: 选中时选择图标和颜色的方式。
    ///   - labelDisplayMode: 单项标题显示策略；为空时继承标签栏样式。
    public init(title: String, icon: ShellTabIcon? = nil, selectedIcon: ShellTabIcon? = nil, selectedIconMode: ShellTabSelectedIconMode = .automatic, labelDisplayMode: ShellTabLabelDisplayMode? = nil) {
        self.title = title
        self.icon = icon
        self.selectedIcon = selectedIcon
        self.selectedIconMode = selectedIconMode
        self.labelDisplayMode = labelDisplayMode
    }

    /// 创建使用自定义内容的标签项配置。
    /// - Parameters:
    ///   - title: 标签目的地的语义标题。
    ///   - customContent: 替换标准图标和标题的自定义内容。
    public init(title: String, customContent: ShellTabBarCustomContent) {
        self.init(title: title)
        self.customContent = customContent
    }
}

@MainActor
enum ShellBarStyling {
    static func navigationAppearance(base: UINavigationBarAppearance?, fallback: UINavigationBarAppearance?, scrollEdge: Bool, style: ShellNavigationStyle, material: ShellMaterial, mediaBackground: Bool, traits: UITraitCollection) -> UINavigationBarAppearance? {
        let customMaterial = material == .solid || material == .frostedGlass
        guard mediaBackground || customMaterial || !style.isEmpty else { return nil }
        let appearance = (base ?? fallback)?.copy() ?? UINavigationBarAppearance()
        if mediaBackground {
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
        } else if material == .solid {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .systemBackground
        } else if material == .frostedGlass {
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            appearance.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.20)
        } else if scrollEdge && base == nil {
            // UIKit derives a transparent edge appearance when none was supplied.
            appearance.configureWithTransparentBackground()
        }
        appearance.titleTextAttributes = style.title.attributes(merging: appearance.titleTextAttributes, role: .headline, traits: traits)
        appearance.largeTitleTextAttributes = style.largeTitle.attributes(merging: appearance.largeTitleTextAttributes, role: .largeTitle, traits: traits)
        if #available(iOS 26.0, *) {
            appearance.subtitleTextAttributes = style.subtitle.attributes(merging: appearance.subtitleTextAttributes, role: .caption1, traits: traits)
            appearance.largeSubtitleTextAttributes = style.subtitle.attributes(merging: appearance.largeSubtitleTextAttributes, role: .caption1, traits: traits)
            apply(style.buttons, to: appearance.prominentButtonAppearance, traits: traits)
        } else {
            apply(style.buttons, to: appearance.doneButtonAppearance, traits: traits)
        }
        apply(style.buttons, to: appearance.buttonAppearance, traits: traits)
        apply(style.buttons, to: appearance.backButtonAppearance, traits: traits)
        return appearance
    }

    static func apply(_ style: ShellTextStyle, to appearance: UIBarButtonItemAppearance, traits: UITraitCollection) {
        for state in [appearance.normal, appearance.highlighted, appearance.focused] {
            state.titleTextAttributes = style.attributes(merging: state.titleTextAttributes, role: .body, traits: traits)
        }
        // Keep UIKit's disabled color while applying the same font.
        if let font = style.resolvedFont(for: .body, traits: traits) {
            var attributes = appearance.disabled.titleTextAttributes
            attributes[.font] = font
            appearance.disabled.titleTextAttributes = attributes
        }
    }

    static func apply(_ style: ShellTabBarStyle, to appearance: UITabBarAppearance, traits: UITraitCollection) {
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = style.normal.attributes(merging: layout.normal.titleTextAttributes, role: .caption2, traits: traits)
            layout.selected.titleTextAttributes = style.selected.attributes(merging: layout.selected.titleTextAttributes, role: .caption2, traits: traits)
            if let color = style.normalIconColor { layout.normal.iconColor = color }
            if let color = style.selectedIconColor { layout.selected.iconColor = color }
        }
    }
}
