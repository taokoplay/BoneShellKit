import UIKit

/// 页面内容相对于 Shell 栏位的放置方式。
public enum ShellContentPlacement: Equatable {
    /// 内容位于安全区内，避开由栏位占用的区域。
    case safeArea
    /// 内容延伸到栏位下方，由页面自行处理遮挡关系。
    case underBars
}

/// 页面背景与导航、标签栏背景之间的组合方式。
public enum ShellBackgroundComposition: Equatable {
    /// 页面和各个栏位分别使用自己的背景画布。
    case independent
    /// 页面与原生栏位共用 `ScreenConfiguration.background` 的完整画布。
    case unified
}

/// 一个页面的导航、内容、背景和标签栏配置。
@MainActor
public struct ScreenConfiguration {
    /// 当前页面的完整导航配置。
    public var navigation = NavigationConfiguration()
    /// 页面栏位呈现模式；为空时继承容器模式。
    public var barPresentation: ShellBarPresentation? = nil
    /// 内容位于安全区内；注册主滚动视图后，浮动标签栏下方会自动保留可滚动内边距。
    public var content: ShellContentPlacement = .safeArea
    /// 浮动标签栏下方主滚动内容的渐隐高度；设为 0 可关闭，单位为点。
    public var floatingTabBarFadeHeight: CGFloat = 80
    /// 是否让内容底部避开键盘。
    public var avoidsKeyboard: Bool = false
    /// 页面背景；为空时清除页面背景。
    public var background: ShellBackgroundConfiguration? = nil
    /// 页面背景是否与导航栏、标签栏共享同一画布。
    public var backgroundComposition: ShellBackgroundComposition = .independent
    /// 当前页面的标签栏背景覆盖；为空时继承容器配置。
    public var tabBarBackground: ShellBackgroundConfiguration? = nil
    /// 当前页面的标签栏样式覆盖；为空时继承容器配置。
    public var tabBarStyle: ShellTabBarStyle? = nil

    /// 创建默认页面配置。
    public init() {}
}
