import UIKit

@MainActor
/// 一个标签目的地及其根页面配置。
public struct ShellTab {
    /// 标签目的地的稳定标识。
    public let id: String
    /// 标签栏使用的完整项配置。
    public let item: ShellTabItemConfiguration
    /// 标签目的地的根页面控制器。
    public let root: UIViewController
    /// 标签目的地的语义标题。
    public var title: String { item.title }
    /// 为保留源码兼容而提供；自定义图片没有 SF Symbol 名称时返回空字符串。
    public var symbol: String {
        if case .systemSymbol(let name)? = item.icon { return name }
        return ""
    }

    /// 使用 SF Symbol 创建标签目的地。
    /// - Parameters:
    ///   - id: 标签目的地的稳定标识。
    ///   - title: 标签目的地的语义标题。
    ///   - symbol: SF Symbol 名称。
    ///   - selectedIconMode: 选中状态下选择图标和颜色的方式。
    ///   - labelDisplayMode: 标签标题显示策略；为空时继承标签栏样式。
    ///   - root: 标签目的地的根页面控制器。
    public init(id: String, title: String, symbol: String,
                selectedIconMode: ShellTabSelectedIconMode = .automatic,
                labelDisplayMode: ShellTabLabelDisplayMode? = nil, root: UIViewController) {
        self.init(id: id, title: title, icon: .systemSymbol(symbol), selectedIconMode: selectedIconMode,
                  labelDisplayMode: labelDisplayMode, root: root)
    }

    /// 使用自定义图标创建标签目的地。
    /// - Parameters:
    ///   - id: 标签目的地的稳定标识。
    ///   - title: 标签目的地的语义标题。
    ///   - icon: 未选中状态使用的图标。
    ///   - selectedIcon: 选中状态使用的图标。
    ///   - selectedIconMode: 选中状态下选择图标和颜色的方式。
    ///   - labelDisplayMode: 标签标题显示策略；为空时继承标签栏样式。
    ///   - root: 标签目的地的根页面控制器。
    public init(id: String, title: String, icon: ShellTabIcon, selectedIcon: ShellTabIcon? = nil,
                selectedIconMode: ShellTabSelectedIconMode = .automatic,
                labelDisplayMode: ShellTabLabelDisplayMode? = nil, root: UIViewController) {
        self.init(id: id, item: ShellTabItemConfiguration(title: title, icon: icon, selectedIcon: selectedIcon,
                                                        selectedIconMode: selectedIconMode, labelDisplayMode: labelDisplayMode), root: root)
    }

    /// 使用完整标签项配置创建标签目的地。
    /// - Parameters:
    ///   - id: 标签目的地的稳定标识。
    ///   - item: 标签栏使用的完整项配置。
    ///   - root: 标签目的地的根页面控制器。
    public init(id: String, item: ShellTabItemConfiguration, root: UIViewController) {
        self.id = id
        self.item = item
        self.root = root
    }
}
