import UIKit

/// 导航与标签共用 SF Symbol、资源图片及 UIImage 的解析规则。
public typealias ShellNavigationIcon = ShellTabIcon

public enum ShellNavigationActionRole: String, CaseIterable, Sendable {
    case normal
    /// 关闭、取消等操作，放在前侧并保留原生返回按钮。
    case cancellation
    /// 完成、保存等操作；原生布局固定首个确认操作，其余仍可溢出。
    case confirmation
}

public enum ShellNavigationActionAxisBehavior: String, CaseIterable, Sendable {
    case automatic
    case horizontalOnly
    case verticalPreferred
}
public enum ShellNavigationActionVisibility: String, CaseIterable, Sendable {
    case automatic
    /// Keeps the action in the navigation bar when layout space is constrained.
    case always
}

@MainActor
public struct NavigationAction {
    public var id: String
    public var title: String
    public var symbol: String
    public var priority: Int
    /// Controls whether width-based layout may move the action into overflow.
    public var visibility: ShellNavigationActionVisibility
    public var isEnabled: Bool
    /// 非 nil 时覆盖 symbol；图片不可用时回退为文字。
    public var icon: ShellNavigationIcon?
    /// 可选的整项外观。未提供时保留系统或经典导航原有按钮。
    public var navButton: ShellNavButton? = nil
    public var role: ShellNavigationActionRole
    public var axisBehavior: ShellNavigationActionAxisBehavior
    public var handler: () -> Void

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

@MainActor
public struct NavigationConfiguration {
    public var title: String = ""
    public var subtitle: String? = nil
    /// Replaces the inline title area. Return the same unattached UIKit view for this page
    /// on subsequent configuration refreshes. The title string remains available for Back.
    public var titleView: UIView? = nil
    public var usesLargeTitle: Bool = false
    public var leadingActions: [NavigationAction] = []
    public var trailingActions: [NavigationAction] = []
    /// `.grouped` 只控制相容自定义按钮的组内净距，返回和固定确认动作保持独立。
    public var navButtonLayout: ShellNavButtonLayout = .individual
    public var material: ShellMaterial = .automatic
    public var background: ShellBackgroundConfiguration? = nil
    /// Nil inherits the navigation container style; an empty style requests system defaults.
    public var style: ShellNavigationStyle? = nil

    public init() {}
}

public enum ShellContentPlacement: Equatable {
    case safeArea
    case underBars
}

public enum ShellBackgroundComposition: Equatable {
    case independent
    /// A single full-container surface uses screen.background behind page and native bars.
    case unified
}

@MainActor
public struct ScreenConfiguration {
    public var navigation = NavigationConfiguration()
    /// Nil inherits container defaults; a value changes both managed bars for this page.
    public var barPresentation: ShellBarPresentation? = nil
    /// Safe-area placement keeps fixed content clear of bars. A registered primary scroll view
    /// extends beneath a floating tab capsule, with safe-area padding applied to its scrollable
    /// content so the last item remains reachable.
    public var content: ShellContentPlacement = .safeArea
    /// Opacity fade at the screen bottom for primary scroll content beneath a floating tab bar.
    /// The glass controls are not faded. Set to zero to disable; the default is 80 points.
    public var floatingTabBarFadeHeight: CGFloat = 80
    public var avoidsKeyboard: Bool = false
    public var background: ShellBackgroundConfiguration? = nil
    public var backgroundComposition: ShellBackgroundComposition = .independent
    public var tabBarBackground: ShellBackgroundConfiguration? = nil
    public var tabBarStyle: ShellTabBarStyle? = nil

    public init() {}
}

@MainActor
public struct ShellActionLayout {
    /// First occurrence wins for duplicate IDs. Always-visible actions are selected before priority.
    public static func visibleIDs(actions: [NavigationAction], maximumVisible: Int) -> [String] {
        let unique = uniqueActions(actions)
        let required = unique.filter { $0.visibility == .always }
        guard maximumVisible > 0 else { return required.map(\.id) }

        let automaticCapacity = maximumVisible <= required.count ? 0 : maximumVisible - required.count
        let selectedAutomatic = orderedActions(unique)
            .filter { $0.action.visibility == .automatic }
            .prefix(automaticCapacity)
        var selectedIDs = Set(required.map(\.id))
        selectedIDs.formUnion(selectedAutomatic.map { $0.action.id })
        return unique.filter { selectedIDs.contains($0.id) }.map(\.id)
    }

    static func visibleIDs(actions: [NavigationAction], availableWidth: CGFloat, width: (NavigationAction) -> CGFloat) -> [String] {
        let unique = uniqueActions(actions)
        let ordered = orderedActions(unique)
        var remaining = max(0, availableWidth)
        var selected = Set<String>()
        for (_, action) in ordered {
            let needed = max(44, width(action))
            if action.visibility == .always || needed <= remaining {
                selected.insert(action.id)
                remaining -= needed
            }
        }
        return unique.filter { selected.contains($0.id) }.map(\.id)
    }

    static func uniqueActions(_ actions: [NavigationAction]) -> [NavigationAction] {
        var seen = Set<String>()
        return actions.filter { seen.insert($0.id).inserted }
    }

    private static func orderedActions(_ actions: [NavigationAction]) -> [(offset: Int, action: NavigationAction)] {
        let sorted = actions.enumerated().sorted {
            if $0.element.visibility != $1.element.visibility {
                return $0.element.visibility == .always
            }
            let firstConfirms = $0.element.role == .confirmation
            let secondConfirms = $1.element.role == .confirmation
            if firstConfirms != secondConfirms { return firstConfirms }
            if $0.element.priority == $1.element.priority { return $0.offset < $1.offset }
            return $0.element.priority > $1.element.priority
        }
        return sorted.map { (offset: $0.offset, action: $0.element) }
    }
}
