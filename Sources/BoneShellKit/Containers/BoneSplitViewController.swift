import UIKit

@MainActor
/// 将主列和详情列组织为可折叠的 Shell 分栏控制器。
open class BoneSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    /// 创建包含主列和详情列的分栏控制器。
    /// - Parameters:
    ///   - primary: 主列页面控制器。
    ///   - detail: 详情列页面控制器。
    public init(primary: UIViewController, detail: UIViewController) {
        super.init(style: .doubleColumn)
        preferredDisplayMode = .oneBesideSecondary
        setViewController(Self.navigationContainer(for: primary), for: .primary)
        setViewController(Self.navigationContainer(for: detail), for: .secondary)
        delegate = self
    }

    /// 从归档恢复分栏控制器。
    /// - Parameter coder: 用于解码控制器的归档对象。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    /// 指定折叠到顶部列时保留的列。
    /// - Parameters:
    ///   - svc: 发生折叠的分栏控制器。
    ///   - proposedTopColumn: UIKit 提议的顶部列。
    /// - Returns: 折叠后要保留为顶部列的列。
    open func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        .secondary
    }

    private static func navigationContainer(for controller: UIViewController) -> UIViewController {
        controller as? UINavigationController
            ?? BoneNavigationController(rootViewController: controller)
    }
}
