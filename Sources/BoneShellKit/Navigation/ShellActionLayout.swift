import UIKit

/// 计算兼容导航布局中可直接显示的动作 ID。
@MainActor
public struct ShellActionLayout {
    /// 按稳定 ID 去重，并优先选择必须显示的动作。
    /// - Parameters:
    ///   - actions: 要参与筛选的动作。
    ///   - maximumVisible: 最多保留的动作数量。
    /// - Returns: 按原始声明顺序返回可直接显示的动作 ID。
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
