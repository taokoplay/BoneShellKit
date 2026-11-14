import UIKit

/// Fades page content at a fixed viewport edge while leaving sibling glass bars untouched.
@MainActor
final class ShellScrollBottomFade {
    private let mask = CAGradientLayer()
    private weak var host: UIView?

    init() {
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        // A smooth opacity falloff without painting a colour over the page or its glass.
        mask.colors = [1, 1, 0.84, 0.5, 0.16, 0].map {
            UIColor.black.withAlphaComponent(CGFloat($0)).cgColor
        }
    }

    func update(in view: UIView, height: CGFloat) {
        if host !== view {
            remove()
            host = view
        }
        guard height.isFinite, height > 0, view.bounds.height > 0, view.bounds.width > 0 else {
            remove()
            return
        }
        // Respect a custom mask owned by the host app, including one assigned after ours.
        guard view.layer.mask == nil || view.layer.mask === mask else { return }
        let fraction = min(height, view.bounds.height) / view.bounds.height
        let start = 1 - fraction
        let locations = [0, start, start + fraction * 0.25,
                         start + fraction * 0.5, start + fraction * 0.75, 1]
            .map { NSNumber(value: Double($0)) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if view.layer.mask !== mask { view.layer.mask = mask }
        if mask.frame != view.bounds { mask.frame = view.bounds }
        if mask.locations != locations { mask.locations = locations }
        CATransaction.commit()
    }

    func remove() {
        if let host = host, host.layer.mask === mask { host.layer.mask = nil }
        host = nil
    }
}
