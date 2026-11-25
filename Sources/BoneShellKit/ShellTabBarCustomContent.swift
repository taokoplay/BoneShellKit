import UIKit

/// 替换标签或附加操作的全部视觉内容；SDK 仍负责占位区域和点击行为。
public struct ShellTabBarCustomContent {
    /// 自定义内容当前的挂载模式。
    public enum Mode: Equatable, Sendable {
        /// 使用 SDK 的标准标签内容。
        case standard
        /// 使用工厂创建的自定义视图。
        case customView
        /// 没有可见内容，或工厂返回的视图已被其他层级占用。
        case unavailable
    }

    /// 传递给自定义内容视图的当前状态。
    public struct State: Equatable, Sendable {
        /// 自定义内容挂载区域当前是否可见。
        public let isVisible: Bool
        /// 附加操作始终为 false，因为附加操作是动作而不是目的地。
        public let isSelected: Bool
        /// 当前内容是否允许交互。
        public let isEnabled: Bool
        /// 当前内容是否处于高亮状态。
        public let isHighlighted: Bool
    }

    /// 修改此版本号即可替换已挂载的视图，而无需替换按钮本身。
    public var revision: Int
    /// 创建新的未挂载视图。SDK 会将其布局到整个标签项区域。
    public var makeView: @MainActor () -> UIView

    /// 创建标签栏自定义内容配置。
    /// - Parameters:
    ///   - revision: 内容版本号；版本变化会使 SDK 重新创建视图。
    ///   - makeView: 创建未挂载 UIView 的工厂闭包。
    public init(revision: Int = 0, makeView: @escaping @MainActor () -> UIView) {
        self.revision = revision
        self.makeView = makeView
    }
}

/// 为自定义标签内容提供可选的状态更新回调。
@MainActor
public protocol ShellTabBarContentUpdating: AnyObject {
    /// 自定义视图的可见性、选中、启用和高亮状态发生变化时调用。
    /// - Parameter state: 当前内容状态。
    func tabBarContentDidChange(_ state: ShellTabBarCustomContent.State)
}

@MainActor
final class ShellTabBarCustomContentHost: UIView {
    private struct Key: Equatable {
        let owner: AnyHashable
        let revision: Int
    }

    private var key: Key?
    private var pendingFactory: (@MainActor () -> UIView)?
    private var content: UIView?
    private var lastState: ShellTabBarCustomContent.State?
    private var hostIsVisible = false
    private var selected = false
    private var enabled = true
    private var highlighted = false

    var mode: ShellTabBarCustomContent.Mode {
        guard key != nil else { return .standard }
        return content == nil ? .unavailable : .customView
    }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ configuration: ShellTabBarCustomContent, owner: AnyHashable) {
        let newKey = Key(owner: owner, revision: configuration.revision)
        guard newKey != key else { return }
        unmount()
        key = newKey
        pendingFactory = configuration.makeView
        mountIfNeeded()
    }

    private func mountIfNeeded() {
        // UIKit can load an initial bar before the caller supplies its presentation.
        guard window != nil, let makeView = pendingFactory else { return }
        pendingFactory = nil
        let view = makeView()
        guard view.superview == nil, view.window == nil, view !== self, !isDescendant(of: view) else { return }
        view.bounds.size = .zero
        content = view
        addSubview(view)
        setNeedsLayout()
    }

    func unmount() {
        deliverState(isVisible: false)
        content?.removeFromSuperview()
        content = nil
        key = nil
        pendingFactory = nil
        lastState = nil
    }

    func updateState(isSelected: Bool, isEnabled: Bool, isHighlighted: Bool, hostIsVisible: Bool) {
        selected = isSelected
        enabled = isEnabled
        highlighted = isHighlighted
        self.hostIsVisible = hostIsVisible
        refreshVisibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let content {
            if content.bounds.size != bounds.size { content.bounds.size = bounds.size }
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if content.center != center { content.center = center }
        }
        refreshVisibility()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        mountIfNeeded()
        refreshVisibility()
    }

    private func refreshVisibility() {
        guard let content else { return }
        guard hostIsVisible, window != nil, !content.bounds.isEmpty else {
            deliverState(isVisible: false)
            return
        }
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0 {
                deliverState(isVisible: false)
                return
            }
            ancestor = view.superview
        }
        deliverState(isVisible: true)
    }

    private func deliverState(isVisible: Bool) {
        guard let view = content as? any ShellTabBarContentUpdating else { return }
        let state = ShellTabBarCustomContent.State(isVisible: isVisible, isSelected: selected,
                                                  isEnabled: enabled, isHighlighted: highlighted)
        guard lastState != state else { return }
        lastState = state
        view.tabBarContentDidChange(state)
    }
}
