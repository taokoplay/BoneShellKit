import UIKit

/// Sizes a page-owned view for the inline title without taking over its touches or accessibility.
@MainActor
final class ShellNavigationTitleHost: UIView {
    let content: UIView
    private let initialWidth: CGFloat
    private let originalAutoresizingMaskTranslation: Bool
    private var requestedNativeSize: CGSize?
    private(set) var preferredWidth: CGFloat = 44
    var onPreferredWidthChange: ((ShellNavigationTitleHost) -> Void)?
    private var widthChangeScheduled = false
    var maximumWidth = UIView.layoutFittingExpandedSize.width {
        didSet { if maximumWidth != oldValue { invalidateIntrinsicContentSize() } }
    }

    init(content: UIView) {
        self.content = content
        initialWidth = content.bounds.width
        originalAutoresizingMaskTranslation = content.translatesAutoresizingMaskIntoConstraints
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        // 让 UIKit 按内容宽度求解，固有尺寸失效时标题宿主才会收到布局回调。
        let fittingWidth = content.widthAnchor.constraint(equalTo: widthAnchor)
        fittingWidth.priority = .fittingSizeLevel - 1
        let fittingHeight = content.heightAnchor.constraint(equalTo: heightAnchor)
        fittingHeight.priority = .fittingSizeLevel - 1
        NSLayoutConstraint.activate([
            fittingWidth,
            fittingHeight,
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updatePreferredWidth()
        bounds.size = intrinsicContentSize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func updatePreferredWidth() -> Bool {
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
        guard preferredWidth != preferred else { return false }
        preferredWidth = preferred
        invalidateIntrinsicContentSize()
        return true
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: min(maximumWidth, preferredWidth), height: 44)
    }

    func resetNativeSizeRequest() {
        requestedNativeSize = nil
    }

    func syncNativeSizeIfNeeded(in navigationBar: UINavigationBar) {
        let target = intrinsicContentSize
        // UIKit 可以压缩已提交的尺寸。只在目标变化或重新挂载时发起量测。
        guard requestedNativeSize != target else { return }
        requestedNativeSize = target
        if bounds.size != target { bounds.size = target }
        setNeedsLayout()
        navigationBar.setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let preferred = intrinsicContentSize
        let width = size.width > 0 ? min(preferred.width, size.width) : preferred.width
        let height = size.height > 0 ? min(preferred.height, size.height) : preferred.height
        return CGSize(width: width, height: height)
    }

    func detachContent() {
        guard content.superview === self else { return }
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = originalAutoresizingMaskTranslation
    }

    private func schedulePreferredWidthChange() {
        guard !widthChangeScheduled, onPreferredWidthChange != nil else { return }
        widthChangeScheduled = true
        // 宿主回调可能重新提交栏位条目，等当前布局完成再执行。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.widthChangeScheduled = false
            guard self.window != nil else { return }
            self.onPreferredWidthChange?(self)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard content.superview === self else { return }
        if updatePreferredWidth() { schedulePreferredWidthChange() }
        // 内容始终铺满栏位分配的实际区域，包括窄栏压缩和最小触控宽度。
        if content.bounds.size != bounds.size { content.bounds.size = bounds.size }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if content.center != center { content.center = center }
    }
}
