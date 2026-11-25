/// SDK 管理的导航栏和标签栏的呈现模式。
///
/// 该值描述请求的外观，而不是系统版本。显式模式在所有支持的系统上保持一致，
/// `.automatic` 会根据当前运行环境的能力选择呈现方式。
public enum ShellBarPresentation: String, CaseIterable, Sendable {
    /// iOS 26 及以上使用原生浮动胶囊；更早系统使用 `.classic`。
    case automatic
    /// 扁平导航栏和延伸到边缘的底部标签栏。
    /// 在 iOS 26 及以上也保持经典外观。
    case classic
    /// 悬浮在内容之上的胶囊标签栏。
    /// iOS 26 及以上使用系统胶囊；更早系统使用 SDK 胶囊。
    case capsule
    /// 在所有系统上使用 UIKit 原生栏位，保留系统默认行为。
    case system

    /// 当前运行环境是否提供原生浮动胶囊标签栏。
    ///
    /// 测试可以通过 `capabilityOverride` 使用旧系统的 SDK 胶囊渲染器，而无需伪造系统版本。
    public static var supportsNativeCapsule: Bool {
        if let override = capabilityOverride { return override }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static var capabilityOverride: Bool?

    /// 按给定的系统能力解析当前呈现模式。
    ///
    /// 显式指定的模式保持不变；只有 `.automatic` 会根据能力选择胶囊或经典栏。
    /// - Parameter supportsNativeCapsule: 当前运行环境是否支持原生浮动胶囊标签栏。
    public func resolved(supportsNativeCapsule: Bool) -> ShellBarPresentation {
        guard self == .automatic else { return self }
        return supportsNativeCapsule ? .capsule : .classic
    }

    /// 按当前运行环境解析自动呈现模式。
    public var resolvedForCurrentSystem: ShellBarPresentation {
        resolved(supportsNativeCapsule: Self.supportsNativeCapsule)
    }
}

/// 负责绘制容器栏位的内部渲染器。
enum ShellBarRendering: Equatable {
    /// 由 UIKit 原生栏位负责绘制。
    case native
    /// 使用 `ShellClassicNavigationBar` 或 `ShellClassicTabBar` 绘制。
    case classic
    /// 使用 `ShellCapsuleTabBar` 绘制；iOS 26 及以上使用原生胶囊。
    case capsule
    /// 使用 `ShellNativeDockBar` 绘制原生标签栏及同一行的圆形附加操作。
    case dock

    /// 根据已解析的呈现模式选择标签栏渲染器。
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

    /// 根据已解析的呈现模式选择导航栏渲染器。
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
