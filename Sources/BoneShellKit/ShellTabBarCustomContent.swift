import UIKit

/// Replaces all visual content of a tab or accessory. The SDK owns the slot and its action.
public struct ShellTabBarCustomContent {
    public enum Mode: Equatable, Sendable {
        case standard
        case customView
        /// The item has no visible slot or the factory returned a view already in use.
        case unavailable
    }

    public struct State: Equatable, Sendable {
        public let isVisible: Bool
        /// Always false for accessories, which are actions rather than destinations.
        public let isSelected: Bool
        public let isEnabled: Bool
        public let isHighlighted: Bool
    }

    /// Change this to replace the mounted view without replacing the button.
    public var revision: Int
    /// Create a new, unattached view. The SDK lays it out in the entire item slot.
    public var makeView: @MainActor () -> UIView

    public init(revision: Int = 0, makeView: @escaping @MainActor () -> UIView) {
        self.revision = revision
        self.makeView = makeView
    }
}

/// Optional state updates for a custom view. Scene activity and Reduce Motion are host policies.
@MainActor
public protocol ShellTabBarContentUpdating: AnyObject {
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
