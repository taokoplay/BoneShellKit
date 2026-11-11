import UIKit
import BoneShellKit

@MainActor
enum DemoStyle {
    static let tint = UIColor(red: 0.12, green: 0.43, blue: 0.32, alpha: 1)

    static func label(_ text: String, style: UIFont.TextStyle = .body, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    static func pin(_ view: UIView, in parent: UIView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    static func materialName(_ material: ShellMaterial) -> String {
        switch material {
        case .automatic: return "自动"
        case .systemDefault: return "系统默认"
        case .systemGlass: return "原生玻璃"
        case .frostedGlass: return "仿玻璃"
        case .solid: return "实色"
        }
    }
}

@MainActor
class DemoStackController: BoneViewController {
    let scrollView = UIScrollView()
    let stack = UIStackView()

    override func buildContent(in contentView: UIView) {
        view.backgroundColor = .systemGroupedBackground
        contentView.addSubview(scrollView)
        DemoStyle.pin(scrollView, in: contentView)
        scrollView.keyboardDismissMode = .interactive
        scrollView.accessibilityIdentifier = "demo.scroll"
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        registerPrimaryScrollView(scrollView)
        buildDemo()
    }

    func buildDemo() {}

    func intro(_ title: String, _ body: String) {
        stack.addArrangedSubview(DemoStyle.label(title, style: .title2))
        stack.addArrangedSubview(DemoStyle.label(body, style: .subheadline, color: .secondaryLabel))
    }

    @discardableResult
    func card(_ views: [UIView]) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 20
        card.layer.cornerCurve = .continuous
        let body = UIStackView(arrangedSubviews: views)
        body.axis = .vertical
        body.spacing = 12
        card.addSubview(body)
        DemoStyle.pin(body, in: card, inset: 18)
        stack.addArrangedSubview(card)
        return card
    }

    @discardableResult
    func button(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 10
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = id
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        stack.addArrangedSubview(button)
        return button
    }
}

@MainActor
final class DemoRow: UIControl {
    init(title: String, detail: String, symbol: String, id: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = DemoStyle.tint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let labels = UIStackView(arrangedSubviews: [
            DemoStyle.label(title, style: .headline),
            DemoStyle.label(detail, style: .footnote, color: .secondaryLabel)
        ])
        labels.axis = .vertical
        labels.spacing = 4
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
        let row = UIStackView(arrangedSubviews: [icon, labels, chevron])
        row.spacing = 16
        row.alignment = .center
        row.isUserInteractionEnabled = false
        addSubview(row)
        DemoStyle.pin(row, in: self, inset: 18)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title
        accessibilityHint = detail
        accessibilityIdentifier = id
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.65 : 1 }
    }
}
