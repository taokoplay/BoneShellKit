import UIKit

/// 一个有序的导航模块。模块可以是独立按钮，也可以是不可拆分的按钮组。
@MainActor
public enum NavigationModule {
    /// 独立按钮模块；按钮不属于任何按钮组。
    case button(NavigationAction)
    /// 按钮组模块；组内动作按数组顺序呈现并作为一个布局单元。
    case group(NavigationButtonGroup)

    var actions: [NavigationAction] {
        switch self {
        case .button(let action): return [action]
        case .group(let group): return group.actions
        }
    }
}

/// 一组按声明顺序呈现的导航按钮。
///
/// 组是导航布局、溢出和 iPhone Duo 位置计算中的一个原子模块。组内按钮
/// 仍然保留各自的标题、图标、无障碍标识和点击回调。
@MainActor
public struct NavigationButtonGroup {
    /// 组的稳定标识，用于刷新时识别同一组。
    public var id: String
    /// 组内动作，顺序决定按钮的视觉和菜单顺序。
    public var actions: [NavigationAction]
    /// 组内按钮视觉外框之间的间距。
    public var itemSpacing: CGFloat
    /// 组表面材质。组内按钮的按钮级材质会自动被忽略。
    public var material: ShellMaterial

    /// 创建一个有序按钮组。
    /// - Parameters:
    ///   - id: 组的稳定标识。
    ///   - actions: 组内动作，至少应包含一个动作。
    ///   - itemSpacing: 组内相邻按钮外框之间的间距，单位为点。
    ///   - material: 组表面材质；组内按钮自身的 effect 会被 SDK 忽略。
    public init(
        id: String,
        actions: [NavigationAction],
        itemSpacing: CGFloat = 8,
        material: ShellMaterial = .automatic
    ) {
        self.id = id
        self.actions = actions
        self.itemSpacing = itemSpacing.isFinite ? max(0, itemSpacing) : 0
        self.material = material
    }
}

public extension NavigationAction {
    /// 将独立动作声明为一个导航模块。
    var asNavigationModule: NavigationModule { .button(self) }
}
