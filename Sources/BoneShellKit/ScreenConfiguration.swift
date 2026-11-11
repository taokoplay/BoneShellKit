import UIKit

@MainActor
public struct NavigationAction {
    public var id: String
    public var title: String
    public var symbol: String
    public var priority: Int
    public var isEnabled: Bool
    public var handler: () -> Void

    public init(
        id: String,
        title: String,
        symbol: String = "",
        priority: Int = 0,
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.priority = priority
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

@MainActor
public struct NavigationConfiguration {
    public var title: String = ""
    public var subtitle: String? = nil
    public var usesLargeTitle: Bool = false
    public var leadingActions: [NavigationAction] = []
    public var trailingActions: [NavigationAction] = []
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
    public var content: ShellContentPlacement = .safeArea
    public var avoidsKeyboard: Bool = false
    public var background: ShellBackgroundConfiguration? = nil
    public var backgroundComposition: ShellBackgroundComposition = .independent
    public var tabBarBackground: ShellBackgroundConfiguration? = nil
    public var tabBarStyle: ShellTabBarStyle? = nil

    public init() {}
}

@MainActor
public struct ShellActionLayout {
    /// First occurrence wins for duplicate IDs. Priority affects selection, not display order.
    public static func visibleIDs(actions: [NavigationAction], maximumVisible: Int) -> [String] {
        guard maximumVisible > 0 else { return [] }
        let unique = uniqueActions(actions)
        let selected = unique.enumerated().sorted {
            if $0.element.priority == $1.element.priority { return $0.offset < $1.offset }
            return $0.element.priority > $1.element.priority
        }.prefix(maximumVisible)
        let selectedIDs = Set(selected.map { $0.element.id })
        return unique.filter { selectedIDs.contains($0.id) }.map(\.id)
    }

    static func visibleIDs(actions: [NavigationAction], availableWidth: CGFloat, width: (NavigationAction) -> CGFloat) -> [String] {
        let unique = uniqueActions(actions)
        let ordered = unique.enumerated().sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
        }
        var remaining = max(0, availableWidth)
        var selected = Set<String>()
        for (_, action) in ordered {
            let needed = max(44, width(action))
            if needed <= remaining {
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
}
