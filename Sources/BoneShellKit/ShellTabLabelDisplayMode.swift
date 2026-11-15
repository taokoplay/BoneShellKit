/// Controls the visual caption of a tab destination without changing its semantic title.
public enum ShellTabLabelDisplayMode: String, CaseIterable, Sendable {
    /// Show captions in both selection states. UIKit may still compact its native layout.
    case always
    /// Show icons only in both selection states.
    case never
    /// Show the caption only for the selected destination.
    case selectedOnly
    /// Show captions only for destinations that are not selected.
    case unselectedOnly

    public func isVisible(isSelected: Bool) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .selectedOnly: return isSelected
        case .unselectedOnly: return !isSelected
        }
    }
}
