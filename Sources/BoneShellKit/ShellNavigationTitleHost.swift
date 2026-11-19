import UIKit

/// Sizes a page-owned view for the inline title without taking over its touches or accessibility.
@MainActor
final class ShellNavigationTitleHost: UIView {
    let content: UIView
    private let initialWidth: CGFloat
    private(set) var preferredWidth: CGFloat = 44
    var maximumWidth = UIView.layoutFittingExpandedSize.width {
        didSet { if maximumWidth != oldValue { invalidateIntrinsicContentSize() } }
    }

    init(content: UIView) {
        self.content = content
        initialWidth = content.bounds.width
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(content)
        updatePreferredWidth()
        bounds.size = intrinsicContentSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updatePreferredWidth() {
        let intrinsic = content.intrinsicContentSize.width
        let width: CGFloat
        if intrinsic.isFinite, intrinsic > 0 {
            width = intrinsic
        } else {
            let constrained = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            if constrained.isFinite, constrained > 0 {
                width = constrained
            } else if initialWidth.isFinite, initialWidth > 0 {
                width = initialWidth
            } else {
                width = content.sizeThatFits(CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44)).width
            }
        }
        let preferred = max(44, width.isFinite ? ceil(width) : 44)
        guard preferredWidth != preferred else { return }
        preferredWidth = preferred
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: min(maximumWidth, preferredWidth), height: 44)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let preferred = intrinsicContentSize
        let width = size.width > 0 ? min(preferred.width, size.width) : preferred.width
        let height = size.height > 0 ? min(preferred.height, size.height) : preferred.height
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if content.bounds.size != bounds.size { content.bounds.size = bounds.size }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if content.center != center { content.center = center }
    }
}
