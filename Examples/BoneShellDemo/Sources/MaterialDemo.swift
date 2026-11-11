import UIKit
import BoneShellKit

@MainActor
final class MaterialDemoController: DemoStackController {
    private let surface = ShellGlassView()
    private let status = DemoStyle.label("", style: .footnote, color: .secondaryLabel)
    private let feedback = DemoStyle.label("点按表面的按钮", style: .caption1, color: .secondaryLabel)
    private let modes: [ShellMaterial] = [.automatic, .systemGlass, .frostedGlass, .solid]
    private var tapCount = 0
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "材质对照"
        screen.navigation.usesLargeTitle = true
    }
    override func buildDemo() {
        intro("同一个表面，不同材质", "切换下面的选项。原生玻璃仅在支持的系统启用；不支持时展示实际降级结果。")
        let picker = UISegmentedControl(items: ["自动", "原生玻璃", "仿玻璃", "实色"])
        picker.selectedSegmentIndex = 0
        picker.accessibilityIdentifier = "material.picker"
        picker.addAction(UIAction { [weak self, weak picker] _ in
            guard let self = self, let picker = picker else { return }
            self.surface.material = self.modes[picker.selectedSegmentIndex]
            self.updateStatus()
        }, for: .valueChanged)
        stack.addArrangedSubview(picker)
        let preview = MaterialBackdrop()
        preview.layer.cornerRadius = 26
        preview.clipsToBounds = true
        preview.heightAnchor.constraint(equalToConstant: 250).isActive = true
        preview.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 20),
            surface.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -20),
            surface.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
            surface.heightAnchor.constraint(equalToConstant: 190)
        ])
        let action = UIButton(type: .system)
        var config = UIButton.Configuration.tinted()
        config.title = "点按试试"
        config.image = UIImage(systemName: "hand.tap")
        config.imagePadding = 8
        action.configuration = config
        action.accessibilityIdentifier = "material.press"
        action.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.tapCount += 1
            self.feedback.text = "已点按 \(self.tapCount) 次"
        }, for: .touchUpInside)
        feedback.accessibilityIdentifier = "material.feedback"
        let content = UIStackView(arrangedSubviews: [DemoStyle.label("BoneShellKit", style: .headline), DemoStyle.label("清晰的内容，适应系统的表面。", style: .subheadline), action, feedback])
        content.axis = .vertical
        content.spacing = 8
        surface.contentView.addSubview(content)
        DemoStyle.pin(content, in: surface.contentView, inset: 18)
        stack.addArrangedSubview(preview)
        status.accessibilityIdentifier = "material.status"
        card([DemoStyle.label("实际解析结果", style: .headline), status])
        stack.addArrangedSubview(DemoStyle.label("减少透明度等系统辅助设置也会参与解析。此页切换 SDK 自有表面，不修改系统菜单、键盘等其他界面。", style: .footnote, color: .secondaryLabel))
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatus), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        updateStatus()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStatus()
    }
    @objc private func updateStatus() {
        surface.refreshMaterial()
        let result = surface.resolution
        status.text = "请求：\(DemoStyle.materialName(result.requested))\n实际：\(DemoStyle.materialName(result.resolved))\n\(result.reason ?? "当前环境支持，已按配置应用")"
    }
}

@MainActor
private final class MaterialBackdrop: UIView {
    private let gradient = CAGradientLayer()
    private let orb = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [UIColor(red: 0.64, green: 0.84, blue: 0.73, alpha: 1).cgColor, UIColor(red: 0.43, green: 0.65, blue: 0.83, alpha: 1).cgColor, UIColor(red: 0.88, green: 0.73, blue: 0.50, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
        orb.fillColor = UIColor.white.withAlphaComponent(0.4).cgColor
        layer.addSublayer(orb)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        orb.path = UIBezierPath(ovalIn: CGRect(x: bounds.width * 0.6, y: -60, width: 190, height: 190)).cgPath
        CATransaction.commit()
    }
}
