import UIKit

/// Shell 栏位和控件可使用的背景材质。
public enum ShellMaterial: String, CaseIterable {
    /// 根据系统能力自动选择最合适的材质。
    case automatic
    /// 使用系统提供的默认材质。
    case systemDefault
    /// 使用 iOS 26 及以上的系统液态玻璃；旧系统回退为磨砂玻璃。
    case systemGlass
    /// 使用兼容旧系统的磨砂玻璃效果。
    case frostedGlass
    /// 使用普通不透明颜色绘制，不产生透明或模糊效果。
    case solid
}

/// 材质请求及其运行时解析结果。
public struct ShellMaterialResolution {
    /// 调用方请求的材质。
    public let requested: ShellMaterial
    /// 当前环境实际采用的材质。
    public let resolved: ShellMaterial
    /// 材质回退或调整的原因；没有原因时为空。
    public let reason: String?

    /// 创建一次材质解析结果。
    /// - Parameters:
    ///   - requested: 调用方请求的材质。
    ///   - resolved: 当前环境实际采用的材质。
    ///   - reason: 发生回退时的说明；没有回退时为空。
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

/// 材质解析工具，负责统一处理系统能力和辅助功能回退。
@MainActor
public enum ShellMaterials {
    /// 将请求的材质按系统能力和辅助功能设置解析为实际材质。
    /// - Parameters:
    ///   - requested: 调用方请求的材质。
    ///   - supportsSystemGlass: 当前运行环境是否支持系统液态玻璃。
    ///   - reduceTransparency: 用户是否开启了减少透明度。
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

/// 材质在宿主视图上的绘制约束。
@MainActor
enum ShellMaterialRendering {
    /// 系统玻璃会绘制到视图 bounds 之外形成边缘高光与投影；套一层宿主裁剪会切掉这部分。
    /// 只有回退材质需要宿主用圆角遮罩裁出边缘。
    /// - Parameter resolved: 已经过能力与辅助功能解析的材质。
    static func clipsContent(_ resolved: ShellMaterial) -> Bool {
        if #available(iOS 26.0, *) { return resolved != .systemGlass }
        return true
    }
}
