/// 控制标签目的地的文字标题显示方式，不改变其语义标题。
public enum ShellTabLabelDisplayMode: String, CaseIterable, Sendable {
    /// 无论是否选中都显示文字标题；UIKit 原生布局仍可能压缩显示方式。
    case always
    /// 无论是否选中都只显示图标。
    case never
    /// 仅在目的地选中时显示文字标题。
    case selectedOnly
    /// 仅在目的地未选中时显示文字标题。
    case unselectedOnly

    /// 根据标签当前是否选中，判断是否显示文字标题。
    /// - Parameter isSelected: 标签当前是否处于选中状态。
    /// - Returns: 按显示策略计算出的可见性。
    public func isVisible(isSelected: Bool) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .selectedOnly: return isSelected
        case .unselectedOnly: return !isSelected
        }
    }
}
