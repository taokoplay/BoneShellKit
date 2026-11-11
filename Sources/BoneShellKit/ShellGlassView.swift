import UIKit

@MainActor
public final class ShellGlassView: UIView {
    public var material: ShellMaterial {
        didSet { refreshMaterial() }
    }
    public var contentView: UIView { effectView.contentView }
    public private(set) var resolution: ShellMaterialResolution

    private let effectView = UIVisualEffectView(effect: nil)

    public init(material: ShellMaterial = .automatic) {
        self.material = material
        self.resolution = ShellMaterials.currentResolution(for: material)
        super.init(frame: .zero)
        setUp()
    }

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

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) != false
            || previousTraitCollection?.displayScale != traitCollection.displayScale {
            refreshMaterial()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshMaterial()
    }

    @objc private func accessibilitySettingsChanged() { refreshMaterial() }
}
