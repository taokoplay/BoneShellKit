import UIKit

/// 可承载内容的材质背景视图，统一处理系统玻璃、磨砂玻璃和不透明回退。
///
/// 栏位和控件共用的系统玻璃表面都由此视图绘制：系统玻璃不裁剪溢出层，
/// 以便保留边缘高光；回退材质继续用圆角遮罩裁出边缘。
@MainActor
public final class ShellGlassView: UIView {
    /// 请求使用的背景材质；修改后会立即刷新视图。
    public var material: ShellMaterial {
        get { storedMaterial }
        set {
            storedMaterial = newValue
            refreshMaterial()
        }
    }
    /// 叠加在玻璃或磨砂表面的可选着色，与导航栏 `backgroundColor` 使用同一语义。
    /// 系统玻璃使用 `UIGlassEffect.tintColor`；回退磨砂把它作为叠加色。
    public var glassTintColor: UIColor? {
        didSet { refreshMaterial() }
    }
    /// 玻璃效果视图内部的内容容器。
    public var contentView: UIView { effectView.contentView }
    /// 当前材质经过系统能力解析后的结果，只读。
    public private(set) var resolution: ShellMaterialResolution

    private var storedMaterial: ShellMaterial
    private let effectView = UIVisualEffectView(effect: nil)

    /// 创建使用指定材质的玻璃视图。
    /// - Parameter material: 请求使用的背景材质。
    public init(material: ShellMaterial = .automatic) {
        self.storedMaterial = material
        self.resolution = ShellMaterials.currentResolution(for: material)
        super.init(frame: .zero)
        setUp()
    }

    /// 从归档恢复玻璃视图。
    /// - Parameter coder: 用于解码视图的归档对象。
    public required init?(coder: NSCoder) {
        storedMaterial = .automatic
        resolution = ShellMaterials.currentResolution(for: .automatic)
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
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
        apply(ShellMaterials.currentResolution(for: material))
    }

    /// 用已经解析好的材质刷新绘制，不再重复咨询辅助功能设置。
    /// - Parameter resolution: 材质请求及其解析结果；SDK 内部与确定性测试使用。
    func apply(_ resolution: ShellMaterialResolution) {
        storedMaterial = resolution.requested
        self.resolution = resolution
        backgroundColor = .clear
        effectView.backgroundColor = .clear
        contentView.backgroundColor = .clear
        layer.borderWidth = 0
        layer.borderColor = nil
        // 系统玻璃自己画出圆角轮廓和边缘高光，宿主再裁剪会把高光切掉。
        clipsToBounds = ShellMaterialRendering.clipsContent(resolution.resolved)

        switch resolution.resolved {
        case .solid:
            effectView.effect = nil
            effectView.backgroundColor = .secondarySystemBackground
            contentView.backgroundColor = .secondarySystemBackground
        case .systemGlass:
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect(style: .regular)
                // 材质层不参与命中测试：按压形态由承载控件自己反馈，避免开启一个
                // 永远收不到触摸的交互玻璃。系统栏按钮的形态由 UIKit 负责。
                glass.isInteractive = false
                glass.tintColor = glassTintColor
                effectView.effect = glass
            } else {
                // The capability resolver excludes this branch on old systems.
                effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
        case .frostedGlass:
            effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            contentView.backgroundColor = glassTintColor ?? (traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.04)
                : UIColor.white.withAlphaComponent(0.16))

            layer.borderWidth = 1 / max(1, traitCollection.displayScale)
            layer.borderColor = (traitCollection.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.24)
                : UIColor.black.withAlphaComponent(0.12)).cgColor
        case .systemDefault, .automatic:
            effectView.effect = UIBlurEffect(style: .systemMaterial)
        }
    }

    /// 同步外层材质视图与内部系统效果层的圆角裁剪。
    public override func layoutSubviews() {
        super.layoutSubviews()
        synchronizeCornerRadius()
    }

    func synchronizeCornerRadius() {
        let radius = layer.cornerRadius
        let clips = ShellMaterialRendering.clipsContent(resolution.resolved)
        effectView.layer.cornerRadius = radius
        effectView.layer.cornerCurve = .continuous
        effectView.layer.masksToBounds = clips
        if #available(iOS 26.0, *), !clips {
            // 取消裁剪后由效果层自己按同一半径画出轮廓。
            effectView.cornerConfiguration = .uniformCorners(radius: .fixed(radius))
        }
        // 业务内容始终限制在圆角内，避免超出栏位表面。
        effectView.contentView.layer.cornerRadius = radius
        effectView.contentView.layer.cornerCurve = .continuous
        effectView.contentView.layer.masksToBounds = true
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
