import UIKit

/// A navigation action's visual appearance. Its identifier, title and action still belong to NavigationAction.
public struct ShellNavButton {
    public enum Size: Equatable {
        case inherited
        case fitting
        /// Ideal visual size, not a minimum hit target. The bar may offer less space.
        case preferred(CGSize)
    }

    public enum Effect: Equatable {
        case inherited
        case none
        case blur
        /// Uses system glass on iOS 26 and later; otherwise uses blur.
        case liquidGlass
    }

    public enum Content {
        case inherited
        /// Displays the action's image, or its title if the image is unavailable.
        case standard
        /// Return an unattached view. Change revision to replace it. The button owns all interaction.
        case custom(revision: Int, makeView: @MainActor () -> UIView)
    }

    public struct Style {
        public var size: Size
        /// Point-size box for aspect-fit drawing; nil inherits, defaulting to the resolved action image.
        public var iconSize: CGSize?
        /// Axis-specific icon. Nil inherits the action's `NavigationAction.icon` / `symbol`.
        public var icon: ShellNavigationIcon?
        /// Nil inherits. Normal defaults to 4 pt above/below and 8 pt on each side.
        public var contentInsets: NSDirectionalEdgeInsets?
        public var effect: Effect
        public var content: Content

        public init(size: Size = .inherited, iconSize: CGSize? = nil,
                    icon: ShellNavigationIcon? = nil,
                    contentInsets: NSDirectionalEdgeInsets? = nil, effect: Effect = .inherited,
                    content: Content = .inherited) {
            self.size = size
            self.iconSize = iconSize
            self.icon = icon
            self.contentInsets = contentInsets
            self.effect = effect
            self.content = content
        }
    }

    public var normal: Style
    /// Only used in an actual sidebar. Each unspecified field independently inherits from normal.
    public var vertical: Style?

    public init(normal: Style = .init(), vertical: Style? = nil) {
        self.normal = normal
        self.vertical = vertical
    }

    // Unspecified normal values are fitting, the original icon, 4/8 pt insets, no material and standard content.
    func resolvedStyle(isVertical: Bool) -> Style {
        var result = normal
        if isVertical, let vertical {
            if vertical.size != .inherited { result.size = vertical.size }
            if vertical.icon != nil { result.icon = vertical.icon }
            result.iconSize = vertical.iconSize ?? result.iconSize
            result.contentInsets = vertical.contentInsets ?? result.contentInsets
            if vertical.effect != .inherited { result.effect = vertical.effect }
            switch vertical.content {
            case .inherited: break
            case .standard, .custom: result.content = vertical.content
            }
        }
        if result.size == .inherited { result.size = .fitting }
        if result.contentInsets == nil {
            result.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        }
        if result.effect == .inherited { result.effect = .none }
        if case .inherited = result.content { result.content = .standard }
        return result
    }
}

public enum ShellNavButtonLayout: Equatable {
    /// Each item keeps the platform's bar-item spacing.
    case individual
    /// Clear distance in points between adjacent compatible button visuals.
    case grouped(spacing: CGFloat)
}
