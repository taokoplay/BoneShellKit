import UIKit

/// 可承载内容的材质背景视图，统一处理系统玻璃、磨砂玻璃和不透明回退。
@MainActor
public final class ShellGlassView: UIView {
    /// 请求使用的背景材质；修改后会立即刷新视图。
    public var material: ShellMaterial {
        didSet { refreshMaterial() }
    }
    /// 玻璃效果视图内部的内容容器。
    public var contentView: UIView { effectView.contentView }
    /// 当前材质经过系统能力解析后的结果，只读。
    public private(set) var resolution: ShellMaterialResolution

    private let effectView = UIVisualEffectView(effect: nil)

    /// 创建使用指定材质的玻璃视图。
    /// - Parameter material: 请求使用的背景材质。
    public init(material: ShellMaterial = .automatic) {
        self.material = material
        self.resolution = ShellMaterials.currentResolution(for: material)
        super.init(frame: .zero)
        setUp()
    }

    /// 从归档恢复玻璃视图。
    /// - Parameter coder: 用于解码视图的归档对象。
    public required init?(coder: NSCoder) {
        material = .automatic
        resolution = ShellMaterials.currentResolution(for: .automatic)
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        refreshMaterial()
    }

    /// 按当前材质和辅助功能设置刷新背景效果及解析结果。
    public func refreshMaterial() {
        resolution = ShellMaterials.currentResolution(for: material)
        backgroundColor = .clear
        effectView.backgroundColor = .clear
        contentView.backgroundColor = .clear
        layer.borderWidth = 0
        layer.borderColor = nil

        switch resolution.resolved {
        case .solid:
            effectView.effect = nil
            effectView.backgroundColor = .secondarySystemBackground
            contentView.backgroundColor = .secondarySystemBackground
        case .systemGlass:
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect(style: .regular)
                glass.isInteractive = true
                effectView.effect = glass
            } else {
                // The capability resolver excludes this branch on old systems.
                effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
        case .frostedGlass:
            effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            contentView.backgroundColor = traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.04)
                : UIColor.white.withAlphaComponent(0.16)
            layer.borderWidth = 1 / max(1, traitCollection.displayScale)
            layer.borderColor = (traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.24)
                : UIColor.black.withAlphaComponent(0.12)).cgColor
        case .systemDefault, .automatic:
            effectView.effect = UIBlurEffect(style: .systemMaterial)
        }
    }

    /// 特征环境变化时重新解析材质。
    /// - Parameter previousTraitCollection: 变化前的特征环境。
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) != false
            || previousTraitCollection?.displayScale != traitCollection.displayScale {
            refreshMaterial()
        }
    }

    /// 视图从窗口移除时重新解析当前材质。
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshMaterial()
    }

    @objc private func accessibilitySettingsChanged() { refreshMaterial() }
}
