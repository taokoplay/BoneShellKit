import UIKit

/// 导航与标签共用 SF Symbol、资源图片及 UIImage 的解析规则。
/// 导航动作使用的图标类型别名，复用标签栏图标解析规则。
public typealias ShellNavigationIcon = ShellTabIcon

/// 导航动作的语义角色。
public enum ShellNavigationActionRole: String, CaseIterable, Sendable {
    /// 普通动作，保留模块声明的位置。
    case normal
    /// 关闭、取消等操作，放在前侧并保留原生返回按钮。
    case cancellation
    /// 完成、保存等操作；原生布局固定首个确认操作，其余仍可溢出。
    case confirmation
}

/// 导航动作在横向栏和 iPhone Duo 侧边栏之间的放置策略。
public enum ShellNavigationActionAxisBehavior: String, CaseIterable, Sendable {
    /// 由系统根据动作内容和设备环境选择横向栏或侧边栏。
    case automatic
    /// 只允许横向导航栏；用于关闭 iPhone Duo 的默认侧边栏迁移。
    case horizontalOnly
    /// 横向和侧边栏都支持；有侧边栏时优先放入侧边栏。
    case verticalPreferred
}

/// 导航动作是否允许在空间不足时进入溢出区域。
public enum ShellNavigationActionVisibility: String, CaseIterable, Sendable {
    /// 由系统和兼容布局根据空间与优先级决定是否进入溢出菜单。
    case automatic
    /// 空间不足时仍要求动作保留在导航栏结构中。
    case always
}

/// 一个可放入导航栏或导航按钮组的用户操作。
@MainActor
public struct NavigationAction {
    /// 动作的稳定标识，用于刷新、复用和无障碍标识。
    public var id: String
    /// 动作标题，也用于菜单和无障碍名称。
    public var title: String
    /// SF Symbol 名称；为空时不使用符号图标。
    public var symbol: String
    /// 空间不足时用于保留动作的优先级，不改变声明顺序。
    public var priority: Int
    /// 是否允许兼容宽度布局按空间和优先级将动作移入溢出菜单。
    public var visibility: ShellNavigationActionVisibility
    /// 是否允许用户触发动作。
    public var isEnabled: Bool
    /// 非 nil 时覆盖 `symbol`；图片不可用时回退为文字。
    public var icon: ShellNavigationIcon?
    /// 可选的整项外观。未提供时保留系统或经典导航原有按钮。
    public var navButton: ShellNavButton? = nil
    /// 动作角色，决定取消、普通或确认语义。
    public var role: ShellNavigationActionRole
    /// 动作在横向导航栏和 iPhone Duo 侧边栏之间的放置偏好。
    public var axisBehavior: ShellNavigationActionAxisBehavior
    /// 动作触发时执行的回调。
    public var handler: () -> Void

    /// 创建使用 SF Symbol 或文字回退的导航动作。
    /// - Parameters:
    ///   - id: 动作的稳定标识。
    ///   - title: 动作标题、菜单标题和无障碍名称。
    ///   - symbol: 可选的 SF Symbol 名称。
    ///   - priority: 空间不足时的保留优先级。
    ///   - visibility: 是否允许动作进入溢出菜单。
    ///   - isEnabled: 是否允许触发动作。
    ///   - role: 动作角色。
    ///   - axisBehavior: 横向和侧边栏的放置偏好。
    ///   - handler: 动作触发回调。
    public init(
        id: String,
        title: String,
        symbol: String = "",
        priority: Int = 0,
        visibility: ShellNavigationActionVisibility = .automatic,
        isEnabled: Bool = true,
        role: ShellNavigationActionRole = .normal,
        axisBehavior: ShellNavigationActionAxisBehavior = .automatic,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.priority = priority
        self.visibility = visibility
        self.isEnabled = isEnabled
        self.icon = nil
        self.role = role
        self.axisBehavior = axisBehavior
        self.handler = handler
    }

    /// 创建使用自定义图片或系统符号的导航动作。
    /// - Parameters:
    ///   - id: 动作的稳定标识。
    ///   - title: 动作标题、菜单标题和无障碍名称。
    ///   - icon: 自定义导航图标；解析失败时回退为标题。
    ///   - priority: 空间不足时的保留优先级。
    ///   - visibility: 是否允许动作进入溢出菜单。
    ///   - isEnabled: 是否允许触发动作。
    ///   - role: 动作角色。
    ///   - axisBehavior: 横向和侧边栏的放置偏好。
    ///   - handler: 动作触发回调。
    public init(
        id: String,
        title: String,
        icon: ShellNavigationIcon?,
        priority: Int = 0,
        visibility: ShellNavigationActionVisibility = .automatic,
        isEnabled: Bool = true,
        role: ShellNavigationActionRole = .normal,
        axisBehavior: ShellNavigationActionAxisBehavior = .automatic,
        handler: @escaping () -> Void
    ) {
        self.init(id: id, title: title, priority: priority, visibility: visibility, isEnabled: isEnabled,
                  role: role, axisBehavior: axisBehavior, handler: handler)
        self.icon = icon
    }

    /// 创建带自定义按钮外观的导航动作。
    /// - Parameters:
    ///   - id: 动作的稳定标识。
    ///   - title: 动作标题、菜单标题和无障碍名称。
    ///   - navButton: 横栏与 iPhone Duo 样式及自定义内容。
    ///   - icon: 自定义导航图标；解析失败时回退为标题。
    ///   - priority: 空间不足时的保留优先级。
    ///   - visibility: 是否允许动作进入溢出菜单。
    ///   - isEnabled: 是否允许触发动作。
    ///   - role: 动作角色。
    ///   - axisBehavior: 横向和侧边栏的放置偏好。
    ///   - handler: 动作触发回调。
    public init(
        id: String,
        title: String,
        navButton: ShellNavButton,
        icon: ShellNavigationIcon? = nil,
        priority: Int = 0,
        visibility: ShellNavigationActionVisibility = .automatic,
        isEnabled: Bool = true,
        role: ShellNavigationActionRole = .normal,
        axisBehavior: ShellNavigationActionAxisBehavior = .verticalPreferred,
        handler: @escaping () -> Void
    ) {
        self.init(id: id, title: title, icon: icon, priority: priority, visibility: visibility,
                  isEnabled: isEnabled, role: role, axisBehavior: axisBehavior, handler: handler)
        self.navButton = navButton
    }

    func resolvedImage(traits: UITraitCollection) -> UIImage? {
        if let icon = icon { return icon.resolve(traits: traits) }
        return symbol.isEmpty ? nil : UIImage(systemName: symbol)
    }
}
