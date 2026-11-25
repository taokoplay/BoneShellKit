/// 标签选中时选择和渲染图标的方式。
public enum ShellTabSelectedIconMode: String, CaseIterable, Sendable {
    /// 保留现有的选中图标和渲染模式行为。
    case automatic
    /// 保留普通图标，并应用当前选中颜色。
    case selectedColor
    /// 保留选中图标的原始颜色和透明度；没有选中图标时回退为普通图标。
    case selectedImage
}
