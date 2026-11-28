import UIKit

/// 导航动作的自定义按钮外观；动作标识、标题和回调仍由 NavigationAction 管理。
public struct ShellNavButton {
    /// 按钮视觉外框尺寸策略。
    public enum Size: Equatable {
        /// 使用默认外框。使用默认内边距且自绘表面的独立标准图标按钮按栏位绘制圆形，其余内容按尺寸拟合。
        case inherited
        /// 根据内容拟合尺寸。
        case fitting
        /// 理想视觉尺寸，不能替代最小触控区域。
        /// 指定理想视觉尺寸，单位为点。
        case preferred(CGSize)
    }

    /// 按钮自身的背景表面。
    ///
    /// 这里只表达“请求什么表面”，由 `ShellMaterials` 与 `ShellGlassView` 决定实际绘制结果，
    /// 不再提供独立的玻璃名称；`ShellMaterial.systemGlass` 在旧系统同样回退为磨砂。
    public enum Effect: Equatable {
        /// 继承容器或 SDK 默认效果：不绘制按钮自身表面。
        case inherited
        /// 不绘制任何按钮表面。
        case none
        /// 请求一个 `ShellMaterial` 表面，解析与回退规则与导航栏材质完全一致。
        case material(ShellMaterial)

        /// 请求的材质；`.inherited` 与 `.none` 返回 nil。
        var material: ShellMaterial? {
            if case .material(let material) = self { return material }
            return nil
        }
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
        /// 按钮自身的背景表面。
        public var effect: Effect
        /// 叠加在按钮表面上的可选着色，与导航栏 `backgroundColor` 使用同一语义。
        public var tintColor: UIColor?
        /// 标准内容或自定义内容。
        public var content: Content

        /// 创建一套按钮视觉样式。
        /// - Parameters:
        ///   - size: 视觉外框尺寸策略。
        ///   - iconSize: 图标绘制区域尺寸。
        ///   - icon: 该轴向使用的图标。
        ///   - contentInsets: 内容内边距。
        ///   - effect: 按钮背景表面。
        ///   - tintColor: 叠加在表面上的着色。
        ///   - content: 标准内容或自定义内容。
        public init(size: Size = .inherited, iconSize: CGSize? = nil,
                    icon: ShellNavigationIcon? = nil,
                    contentInsets: NSDirectionalEdgeInsets? = nil, effect: Effect = .inherited,
                    tintColor: UIColor? = nil, content: Content = .inherited) {
            self.size = size
            self.iconSize = iconSize
            self.icon = icon
            self.contentInsets = contentInsets
            self.effect = effect
            self.tintColor = tintColor
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
            result.tintColor = vertical.tintColor ?? result.tintColor
            switch vertical.content {
            case .inherited: break
            case .standard, .custom: result.content = vertical.content
            }
        }
        // 保留继承尺寸和空内边距，由承载项结合实际图标和材质确定默认外形。
        if result.effect == .inherited { result.effect = .none }
        if result.effect == .none { result.tintColor = nil }
        if case .inherited = result.content { result.content = .standard }
        return result
    }
}
