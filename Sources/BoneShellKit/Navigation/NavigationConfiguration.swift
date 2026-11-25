import UIKit

/// 当前页面导航栏的标题、模块、材质和背景配置。
@MainActor
public struct NavigationConfiguration {
    /// 导航栏普通标题，也用于系统返回按钮的语义。
    public var title: String = ""
    /// 导航栏副标题；为空时不显示。
    public var subtitle: String? = nil
    /// 替换内联文字标题的完整可交互视图。刷新配置时应复用同一个未挂载视图。
    /// 自定义标题后普通标题、副标题和大标题不再显示；`title` 仍保留用于返回语义。
    public var titleView: UIView? = nil
    /// 是否请求 UIKit 的大标题布局。
    public var usesLargeTitle: Bool = false
    /// 按声明顺序排列的前侧导航模块。
    public var leadingModules: [NavigationModule] = []
    /// 按声明顺序排列的后侧导航模块。
    public var trailingModules: [NavigationModule] = []
    /// 相邻模块之间的期望间距；系统原生栏可能根据可用空间调整该值。
    public var moduleSpacing: CGFloat = 8
    /// 导航栏背景材质。
    public var material: ShellMaterial = .automatic
    /// 导航栏媒体或颜色背景；为空时继承容器背景。
    public var background: ShellBackgroundConfiguration? = nil
    /// 导航栏字体和颜色样式；为空时继承导航容器样式。
    public var style: ShellNavigationStyle? = nil

    /// 创建默认导航配置。
    public init() {}
}
