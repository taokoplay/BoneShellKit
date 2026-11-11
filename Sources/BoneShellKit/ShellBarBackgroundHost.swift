import UIKit

@MainActor
final class ShellBarBackgroundHost {
    let view = ShellBackgroundView()
    private weak var container: UIView?
    private let extendsToStatusArea: Bool

    init(bar: UIView, container: UIView, priority: Int, extendsToStatusArea: Bool = false) {
        self.container = container
        self.extendsToStatusArea = extendsToStatusArea
        view.playbackPriority = priority
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layout(in: bar)
    }

    func layout(in bar: UIView) {
        var top: CGFloat = 0
        if extendsToStatusArea, bar.bounds.width > bar.bounds.height, let container = container {
            let frame = bar.convert(bar.bounds, to: container)
            top = max(0, min(container.safeAreaInsets.top, frame.minY - container.bounds.minY))
        }
        guard let parent = bar.superview else { return }
        // A bar manages its own subviews. Keep media as its sibling so UIKit's
        // foreground content is never covered or reordered by our background.
        var frame = bar.convert(bar.bounds, to: parent)
        frame.origin.y -= top
        frame.size.height += top
        if view.superview !== parent { parent.insertSubview(view, belowSubview: bar) }
        if view.frame != frame { view.frame = frame }
        parent.insertSubview(view, belowSubview: bar)
        view.isHidden = bar.isHidden
    }

    static func navigationAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        return appearance
    }

    static func tabAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        return appearance
    }

    static func topScreen(in controller: UIViewController?) -> BoneViewController? {
        guard let controller = controller else { return nil }
        if let page = controller as? BoneViewController { return page }
        if let nav = controller as? UINavigationController { return topScreen(in: nav.topViewController) }
        if let tabs = controller as? UITabBarController { return topScreen(in: tabs.selectedViewController) }
        if let split = controller as? UISplitViewController { return topScreen(in: split.viewControllers.last) }
        return nil
    }
}

@MainActor
final class ShellNavigationBackgroundSnapshot {
    weak var controller: UIViewController?
    let standard: UINavigationBarAppearance?
    let edge: UINavigationBarAppearance?
    let compact: UINavigationBarAppearance?
    let compactEdge: UINavigationBarAppearance?
    init(controller: UIViewController) {
        self.controller = controller
        standard = controller.navigationItem.standardAppearance?.copy() as? UINavigationBarAppearance
        edge = controller.navigationItem.scrollEdgeAppearance?.copy() as? UINavigationBarAppearance
        compact = controller.navigationItem.compactAppearance?.copy() as? UINavigationBarAppearance
        compactEdge = controller.navigationItem.compactScrollEdgeAppearance?.copy() as? UINavigationBarAppearance
    }
    func restore() {
        controller?.navigationItem.standardAppearance = standard
        controller?.navigationItem.scrollEdgeAppearance = edge
        controller?.navigationItem.compactAppearance = compact
        controller?.navigationItem.compactScrollEdgeAppearance = compactEdge
    }
}
