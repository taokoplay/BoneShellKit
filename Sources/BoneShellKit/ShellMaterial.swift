import UIKit

public enum ShellMaterial: String, CaseIterable {
    case automatic
    case systemDefault
    case systemGlass
    case frostedGlass
    case solid
}

public struct ShellMaterialResolution {
    public let requested: ShellMaterial
    public let resolved: ShellMaterial
    public let reason: String?

    public init(
        requested: ShellMaterial = .automatic,
        resolved: ShellMaterial = .systemDefault,
        reason: String? = nil
    ) {
        self.requested = requested
        self.resolved = resolved
        self.reason = reason
    }
}

@MainActor
public enum ShellMaterials {
    /// Capability inputs are explicit so fallback rules can be tested on any OS.
    public static func resolve(
        _ requested: ShellMaterial,
        supportsSystemGlass: Bool,
        reduceTransparency: Bool
    ) -> ShellMaterialResolution {
        if reduceTransparency {
            return ShellMaterialResolution(
                requested: requested,
                resolved: .solid,
                reason: requested == .solid ? nil : "Reduce Transparency is enabled."
            )
        }
        switch requested {
        case .automatic:
            return ShellMaterialResolution(
                requested: requested,
                resolved: supportsSystemGlass ? .systemGlass : .systemDefault
            )
        case .systemGlass where !supportsSystemGlass:
            return ShellMaterialResolution(
                requested: requested,
                resolved: .frostedGlass,
                reason: "System glass requires iOS 26 or later; using frosted glass."
            )
        default:
            return ShellMaterialResolution(requested: requested, resolved: requested)
        }
    }

    static var supportsSystemGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    static func currentResolution(for material: ShellMaterial) -> ShellMaterialResolution {
        resolve(
            material,
            supportsSystemGlass: supportsSystemGlass,
            reduceTransparency: UIAccessibility.isReduceTransparencyEnabled
        )
    }
}
