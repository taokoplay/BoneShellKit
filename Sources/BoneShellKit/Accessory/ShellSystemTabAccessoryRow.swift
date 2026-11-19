import UIKit

/// Retains the UIKit accessory slot and the controls it contains across style refreshes.
@available(iOS 26.0, *)
@MainActor
final class ShellSystemTabAccessoryRow: UIStackView {
    private(set) var buttons: [ShellTabAccessoryButton] = []
    var controllerIsVisible = false {
        didSet { if oldValue != controllerIsVisible { refreshContentVisibility() } }
    }

    func observeAccessoryEnvironment() {
        registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { (row: Self, _) in
            row.refreshContentVisibility()
        }
    }

    func update(items: [ShellBarAccessoryItem], tint: UIColor, font: UIFont) {
        buttons = ShellTabAccessoryButton.reconcile(buttons, with: items)
        for (button, item) in zip(buttons, items) {
            button.update(item: item, tint: tint, font: font, compact: true, material: .automatic)
            if button.superview !== self { button.heightAnchor.constraint(equalToConstant: 44).isActive = true }
        }
        shellArrange(buttons)
        refreshContentVisibility()
    }

    func discardAccessories() {
        for button in buttons { button.unmount() }
        buttons = []
    }

    func refreshContentVisibility() {
        let active = controllerIsVisible && traitCollection[UITraitTabAccessoryEnvironment.self] != .none
        for button in buttons {
            button.controllerIsVisible = active
            button.refreshContentVisibility()
        }
    }

    override var isHidden: Bool {
        didSet { if oldValue != isHidden { refreshContentVisibility() } }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshContentVisibility()
    }
}

extension UIStackView {
    /// Reorder arranged views without detaching survivors and restarting their content.
    func shellArrange(_ desired: [UIView]) {
        for view in arrangedSubviews where !desired.contains(where: { $0 === view }) {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, view) in desired.enumerated() {
            if arrangedSubviews.indices.contains(index), arrangedSubviews[index] === view { continue }
            if view.superview === self { removeArrangedSubview(view) }
            insertArrangedSubview(view, at: index)
        }
    }
}
