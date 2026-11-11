import UIKit

/// Nil font/color values preserve the corresponding UIKit value.
@MainActor
public struct ShellTextStyle {
    public var font: UIFont?
    public var color: UIColor?
    public var scalesWithDynamicType: Bool

    public init(font: UIFont? = nil, color: UIColor? = nil, scalesWithDynamicType: Bool = true) {
        self.font = font
        self.color = color
        self.scalesWithDynamicType = scalesWithDynamicType
    }

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

@MainActor
public struct ShellNavigationStyle {
    public var title: ShellTextStyle
    public var largeTitle: ShellTextStyle
    public var subtitle: ShellTextStyle
    public var buttons: ShellTextStyle

    public init(title: ShellTextStyle? = nil, largeTitle: ShellTextStyle? = nil, subtitle: ShellTextStyle? = nil, buttons: ShellTextStyle? = nil) {
        self.title = title ?? ShellTextStyle()
        self.largeTitle = largeTitle ?? ShellTextStyle()
        self.subtitle = subtitle ?? ShellTextStyle()
        self.buttons = buttons ?? ShellTextStyle()
    }

    var isEmpty: Bool { title.isEmpty && largeTitle.isEmpty && subtitle.isEmpty && buttons.isEmpty }
}

@MainActor
public struct ShellTabBarStyle {
    public var normal: ShellTextStyle
    public var selected: ShellTextStyle
    public var normalIconColor: UIColor?
    public var selectedIconColor: UIColor?

    public init(normal: ShellTextStyle? = nil, selected: ShellTextStyle? = nil, normalIconColor: UIColor? = nil, selectedIconColor: UIColor? = nil) {
        self.normal = normal ?? ShellTextStyle()
        self.selected = selected ?? ShellTextStyle()
        self.normalIconColor = normalIconColor
        self.selectedIconColor = selectedIconColor
    }

    var isEmpty: Bool { normal.isEmpty && selected.isEmpty && normalIconColor == nil && selectedIconColor == nil }
}

@MainActor
public enum ShellTabIcon {
    case systemSymbol(String)
    case asset(String, bundle: Bundle)
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

@MainActor
public struct ShellTabItemConfiguration {
    public var title: String
    public var icon: ShellTabIcon?
    public var selectedIcon: ShellTabIcon?
    public var selectedIconMode: ShellTabSelectedIconMode

    public init(title: String, icon: ShellTabIcon? = nil, selectedIcon: ShellTabIcon? = nil, selectedIconMode: ShellTabSelectedIconMode = .automatic) {
        self.title = title
        self.icon = icon
        self.selectedIcon = selectedIcon
        self.selectedIconMode = selectedIconMode
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
