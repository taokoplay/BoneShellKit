/// The presentation of SDK-managed navigation and tab bars, independent of OS version.
public enum ShellBarPresentation: String, CaseIterable, Sendable {
    /// UIKit's current native presentation (classic on older systems, glass where supported).
    case system
    /// Flat navigation and edge-to-edge bottom tabs inspired by pre-iOS 26 UIKit.
    case classic
}
