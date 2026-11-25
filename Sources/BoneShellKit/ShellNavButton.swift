import UIKit

/// 导航动作的自定义按钮外观；动作标识、标题和回调仍由 NavigationAction 管理。
public struct ShellNavButton {
    /// 按钮视觉外框尺寸策略。
    public enum Size: Equatable {
        /// 继承默认尺寸。
        case inherited
        /// 根据内容拟合尺寸。
        case fitting
        /// 理想视觉尺寸，不能替代最小触控区域。
        /// 指定理想视觉尺寸，单位为点。
        case preferred(CGSize)
    }

    /// 按钮自身背景材质效果。
    public enum Effect: Equatable {
        /// 继承容器或 SDK 默认效果。
        case inherited
        /// 透明按钮背景。
        case none
        /// 使用系统模糊背景。
        case blur
        /// iOS 26 及以上使用系统液态玻璃，旧系统回退为模糊。
        case liquidGlass
    }

    /// 按钮内容来源。
    public enum Content {
        /// 继承标准内容。
        case inherited
        /// 使用动作的图标；图标不可用时显示标题。
        case standard
        /// 提供未挂载的自定义视图，并由按钮统一管理交互。
        case custom(revision: Int, makeView: @MainActor () -> UIView)
    }

    /// 一个导航按钮的尺寸、图标、内边距、材质和内容样式。
    public struct Style {
        /// 视觉外框尺寸。
        public var size: Size
        /// 图标宽度和高度的绘制区域；为空时继承动作图标尺寸。
        /// 图标绘制区域尺寸，单位为点。
        public var iconSize: CGSize?
        /// 当前轴向使用的图标；为空时继承动作图标。
        public var icon: ShellNavigationIcon?
        /// 内容内边距；为空时使用默认内边距。
        public var contentInsets: NSDirectionalEdgeInsets?
        /// 按钮自身的背景效果。
        public var effect: Effect
        /// 标准内容或自定义内容。
        public var content: Content

        /// 创建一套按钮视觉样式。
        /// - Parameters:
        ///   - size: 视觉外框尺寸策略。
        ///   - iconSize: 图标绘制区域尺寸。
        ///   - icon: 该轴向使用的图标。
        ///   - contentInsets: 内容内边距。
        ///   - effect: 按钮背景效果。
        ///   - content: 标准内容或自定义内容。
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

    /// 横栏使用的按钮样式。
    public var normal: Style
    /// 仅在实际侧边栏承载时使用；保留该名称以兼容旧调用。
    public var vertical: Style?
    /// iPhone Duo 侧边栏样式的明确别名。
    public var iPhoneDuo: Style? {
        get { vertical }
        set { vertical = newValue }
    }

    /// 创建横栏和 iPhone Duo 侧边栏两套按钮样式。
    /// - Parameters:
    ///   - normal: 横栏样式。
    ///   - vertical: 兼容旧名称的侧边栏样式。
    ///   - iPhoneDuo: iPhone Duo 侧边栏样式；传入后优先于 `vertical`。
    public init(
        normal: Style = .init(),
        vertical: Style? = nil,
        iPhoneDuo: Style? = nil
    ) {
        self.normal = normal
        self.vertical = iPhoneDuo ?? vertical
    }

    /// 根据当前是否处于 iPhone Duo 侧边栏解析最终样式。
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
