/// The presentation of SDK-managed navigation and tab bars.
///
/// The value describes the requested appearance, not the OS version: an explicit
/// case keeps its appearance on every supported system, and `.automatic` picks one
/// from the current runtime's capabilities.
public enum ShellBarPresentation: String, CaseIterable, Sendable {
    /// iOS 26 and later use the native floating capsule; earlier systems use `.classic`.
    case automatic
    /// Flat navigation and edge-to-edge bottom tabs inspired by pre-iOS 26 UIKit.
    /// Always used, including on iOS 26 and later.
    case classic
    /// Floating capsule tab bar over the content.
    /// iOS 26 and later use the system capsule; earlier systems use the SDK capsule.
    case capsule
    /// UIKit's native presentation on every system, unchanged legacy behavior.
    case system

    /// Whether this runtime provides the native floating capsule tab bar.
    ///
    /// `capabilityOverride` exists so tests can measure the SDK capsule renderer used
    /// below iOS 26 without shipping an OS-version spoof in the app.
    public static var supportsNativeCapsule: Bool {
        if let override = capabilityOverride { return override }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static var capabilityOverride: Bool?

    /// Resolves the appearance this case shows on a runtime with the given capability.
    ///
    /// Explicit cases stay unchanged, so `.classic` remains classic on iOS 26 and
    /// `.capsule` keeps the capsule appearance below iOS 26.
    public func resolved(supportsNativeCapsule: Bool) -> ShellBarPresentation {
        guard self == .automatic else { return self }
        return supportsNativeCapsule ? .capsule : .classic
    }

    /// Resolves the appearance for the current runtime.
    public var resolvedForCurrentSystem: ShellBarPresentation {
        resolved(supportsNativeCapsule: Self.supportsNativeCapsule)
    }
}

/// Which renderer draws a container's bars.
enum ShellBarRendering: Equatable {
    /// The native UIKit bar stays in charge.
    case native
    /// `ShellClassicNavigationBar` / `ShellClassicTabBar`.
    case classic
    /// `ShellCapsuleTabBar`. Only used below iOS 26; newer systems use the native capsule.
    case capsule
    /// `ShellNativeDockBar`: a real `UITabBar` plus circular accessories in one row.
    /// Used on iOS 26+ when capsule presentation needs a button outside the system capsule.
    case dock

    /// The tab bar renderer for a resolved presentation.
    static func tabBar(_ presentation: ShellBarPresentation, supportsNativeCapsule: Bool) -> ShellBarRendering {
        switch presentation {
        case .classic:
            return .classic
        case .capsule:
            return supportsNativeCapsule ? .native : .capsule
        case .system:
            return .native
        case .automatic:
            return supportsNativeCapsule ? .native : .classic
        }
    }

    /// The navigation bar renderer for a resolved presentation.
    ///
    /// There is no self-drawn capsule navigation bar, so a capsule request below
    /// iOS 26 keeps the flat classic navigation instead of inventing a new bar.
    static func navigation(_ presentation: ShellBarPresentation, supportsNativeCapsule: Bool) -> ShellBarRendering {
        switch presentation {
        case .classic:
            return .classic
        case .capsule:
            return supportsNativeCapsule ? .native : .classic
        case .system:
            return .native
        case .automatic:
            return supportsNativeCapsule ? .native : .classic
        }
    }
}
