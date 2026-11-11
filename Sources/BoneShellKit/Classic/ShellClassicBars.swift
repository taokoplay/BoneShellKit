import UIKit

@MainActor
final class ShellClassicNavigationBar: UIView {
    var onBack: (() -> Void)?
    var topInset: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    private struct Model {
        let title: String
        let subtitle: String?
        let largeTitle: Bool
        let showsBack: Bool
        let leadingItems: [UIBarButtonItem]
        let trailingItems: [UIBarButtonItem]
        let style: ShellNavigationStyle
        let material: ShellMaterial
        let showsMediaBackground: Bool
    }

    private let backdrop = ShellClassicBackdrop(separatorAtTop: false)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private var leadingButtons: [ShellClassicActionButton] = []
    private var trailingButtons: [ShellClassicActionButton] = []
    private var model: Model?
    private var titleFont = UIFont.preferredFont(forTextStyle: .headline)
    private var largeTitleFont = UIFont.preferredFont(forTextStyle: .largeTitle)
    private var titleColor: UIColor = .label
    private var largeTitleColor: UIColor = .label

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func update(title: String, subtitle: String?, largeTitle: Bool, showsBack: Bool,
                leadingItems: [UIBarButtonItem], trailingItems: [UIBarButtonItem],
                style: ShellNavigationStyle, material: ShellMaterial,
                showsMediaBackground: Bool) {
        model = Model(title: title, subtitle: subtitle, largeTitle: largeTitle,
                      showsBack: showsBack, leadingItems: leadingItems,
                      trailingItems: trailingItems, style: style, material: material,
                      showsMediaBackground: showsMediaBackground)
        applyModel()
    }

    private func configureView() {
        accessibilityIdentifier = "shell.classic.navigation"
        isAccessibilityElement = false
        backgroundColor = .clear
        addSubview(backdrop)
        for label in [titleLabel, subtitleLabel] {
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.isAccessibilityElement = true
            addSubview(label)
        }
        titleLabel.accessibilityIdentifier = "shell.classic.title"
        titleLabel.accessibilityTraits = .header
        subtitleLabel.accessibilityIdentifier = "shell.classic.subtitle"
        backButton.accessibilityIdentifier = "shell.classic.back"
        backButton.accessibilityLabel = NSLocalizedString("Back", comment: "Navigation back button")
        backButton.setImage(UIImage(systemName: "chevron.backward",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))?
            .imageFlippedForRightToLeftLayoutDirection(), for: .normal)
        backButton.imageView?.isAccessibilityElement = false
        backButton.titleLabel?.isAccessibilityElement = false
        backButton.isHidden = true
        backButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        addSubview(backButton)
    }

    private func applyModel() {
        guard let model = model else { return }
        let style = model.style
        titleFont = style.title.resolvedFont(for: .headline, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        largeTitleFont = style.largeTitle.resolvedFont(for: .largeTitle, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .largeTitle, compatibleWith: traitCollection)
        titleColor = style.title.color ?? .label
        largeTitleColor = style.largeTitle.color ?? .label
        subtitleLabel.font = style.subtitle.resolvedFont(for: .caption1, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        subtitleLabel.textColor = style.subtitle.color ?? .secondaryLabel
        titleLabel.text = model.title
        titleLabel.isHidden = model.title.isEmpty
        subtitleLabel.text = model.subtitle
        subtitleLabel.isHidden = model.subtitle?.isEmpty != false
        backButton.isHidden = !model.showsBack
        let buttonFont = style.buttons.resolvedFont(for: .body, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let buttonColor = style.buttons.color ?? tintColor ?? .systemBlue
        backButton.tintColor = buttonColor
        leadingButtons = configuredButtons(for: model.leadingItems, reusing: leadingButtons,
                                           font: buttonFont, color: buttonColor)
        trailingButtons = configuredButtons(for: model.trailingItems, reusing: trailingButtons,
                                            font: buttonFont, color: buttonColor)
        backdrop.update(material: model.material, showsMediaBackground: model.showsMediaBackground)
        var elements: [Any] = []
        if model.showsBack { elements.append(backButton) }
        elements.append(contentsOf: leadingButtons)
        if !titleLabel.isHidden { elements.append(titleLabel) }
        if !subtitleLabel.isHidden { elements.append(subtitleLabel) }
        elements.append(contentsOf: trailingButtons.reversed())
        accessibilityElements = elements
        setNeedsLayout()
    }

    private func configuredButtons(for items: [UIBarButtonItem],
                                   reusing existing: [ShellClassicActionButton],
                                   font: UIFont, color: UIColor) -> [ShellClassicActionButton] {
        for button in existing.dropFirst(items.count) { button.removeFromSuperview() }
        var buttons = Array(existing.prefix(items.count))
        while buttons.count < items.count {
            let button = ShellClassicActionButton(frame: .zero)
            addSubview(button)
            buttons.append(button)
        }
        for (button, item) in zip(buttons, items) {
            button.update(item: item, font: font, color: color)
        }
        return buttons
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        guard let model = model else { return }
        let inset = min(max(0, topInset), bounds.height)
        let usableHeight = max(0, bounds.height - inset)
        let rowY = bounds.minY + inset + (min(44, usableHeight) - 44) / 2
        let width = bounds.width
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func frame(at logicalX: CGFloat, width buttonWidth: CGFloat) -> CGRect {
            CGRect(x: bounds.minX + (isRTL ? width - logicalX - buttonWidth : logicalX),
                   y: rowY, width: buttonWidth, height: 44)
        }
        var leading: CGFloat = 8
        if model.showsBack {
            backButton.frame = frame(at: leading, width: 44)
            leading += 44
        }
        for button in leadingButtons {
            button.frame = frame(at: leading, width: button.preferredWidth)
            leading += button.preferredWidth
        }
        var trailing = width - 8
        for button in trailingButtons {
            trailing -= button.preferredWidth
            button.frame = frame(at: trailing, width: button.preferredWidth)
        }
        if model.largeTitle && usableHeight > 68 {
            titleLabel.font = largeTitleFont
            titleLabel.textColor = largeTitleColor
            titleLabel.textAlignment = isRTL ? .right : .left
            subtitleLabel.textAlignment = titleLabel.textAlignment
            layoutTitle(in: CGRect(x: bounds.minX + 16, y: bounds.minY + inset + 44,
                                   width: max(0, width - 32), height: usableHeight - 44))
        } else {
            titleLabel.font = titleFont
            titleLabel.textColor = titleColor
            titleLabel.textAlignment = .center
            subtitleLabel.textAlignment = .center
            let start = min(width, leading + 4)
            let end = max(start, trailing - 4)
            let availableWidth = max(0, end - start)
            let titleWidth = (model.title as NSString).size(withAttributes: [.font: titleFont]).width
            let subtitleWidth = ((model.subtitle ?? "") as NSString)
                .size(withAttributes: [.font: subtitleLabel.font as UIFont]).width
            let labelWidth = min(availableWidth, ceil(max(titleWidth, subtitleWidth)))
            let logicalCenter = min(max(width / 2, start + labelWidth / 2), end - labelWidth / 2)
            let center = isRTL ? width - logicalCenter : logicalCenter
            layoutTitle(in: CGRect(x: bounds.minX + center - labelWidth / 2, y: rowY,
                                   width: labelWidth, height: 44))
        }
    }

    private func layoutTitle(in rect: CGRect) {
        let hasTitle = !titleLabel.isHidden
        let hasSubtitle = !subtitleLabel.isHidden
        let subtitleHeight = hasSubtitle ? min(subtitleLabel.font.lineHeight, rect.height) : 0
        let spacing: CGFloat = hasTitle && hasSubtitle ? 1 : 0
        let titleHeight = hasTitle ? min(titleLabel.font.lineHeight, max(0, rect.height - subtitleHeight - spacing)) : 0
        let height = titleHeight + subtitleHeight + spacing
        let y = rect.midY - height / 2
        titleLabel.frame = CGRect(x: rect.minX, y: y, width: rect.width, height: titleHeight)
        subtitleLabel.frame = CGRect(x: rect.minX, y: y + titleHeight + spacing,
                                     width: rect.width, height: subtitleHeight)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyModel()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyModel()
    }
}

@MainActor
final class ShellClassicTabBar: UIView {
    var onSelect: ((Int) -> Void)?
    private(set) var contentHeight: CGFloat = 49
    var bottomInset: CGFloat = 0 {
        didSet {
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    private struct Model {
        let items: [UITabBarItem]
        let selectedIndex: Int
        let style: ShellTabBarStyle
        let material: ShellMaterial
        let showsMediaBackground: Bool
    }

    private let backdrop = ShellClassicBackdrop(separatorAtTop: true)
    private var buttons: [ShellClassicTabButton] = []
    private var model: Model?

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    func update(items: [UITabBarItem], selectedIndex: Int, style: ShellTabBarStyle,
                material: ShellMaterial, showsMediaBackground: Bool) {
        model = Model(items: items, selectedIndex: selectedIndex, style: style,
                      material: material, showsMediaBackground: showsMediaBackground)
        applyModel()
    }

    private func configureView() {
        isAccessibilityElement = false
        backgroundColor = .clear
        addSubview(backdrop)
    }

    private func applyModel() {
        guard let model = model else { return }
        let style = model.style
        let normalFont = style.normal.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        let selectedFont = style.selected.resolvedFont(for: .caption2, traits: traitCollection)
            ?? UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        let newHeight = max(49, ceil(25 + max(normalFont.lineHeight, selectedFont.lineHeight) + 8))
        if contentHeight != newHeight {
            contentHeight = newHeight
            invalidateIntrinsicContentSize()
            superview?.setNeedsLayout()
        }
        while buttons.count > model.items.count { buttons.removeLast().removeFromSuperview() }
        while buttons.count < model.items.count {
            let index = buttons.count
            let button = ShellClassicTabButton(frame: .zero)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(index) }, for: .touchUpInside)
            buttons.append(button)
            addSubview(button)
        }
        for (index, item) in model.items.enumerated() {
            let selected = index == model.selectedIndex
            let role = selected ? style.selected : style.normal
            let color = role.color ?? (selected ? (tintColor ?? .systemBlue) : .secondaryLabel)
            let iconColor = (selected ? style.selectedIconColor : style.normalIconColor)
                ?? (selected ? (tintColor ?? .systemBlue) : .secondaryLabel)
            buttons[index].update(item: item, selected: selected,
                                  font: selected ? selectedFont : normalFont,
                                  color: color, iconColor: iconColor)
        }
        backdrop.update(material: model.material, showsMediaBackground: model.showsMediaBackground)
        accessibilityElements = buttons
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight + max(0, bottomInset))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        guard !buttons.isEmpty else { return }
        let height = max(0, bounds.height - max(0, bottomInset))
        let count = buttons.count
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, button) in buttons.enumerated() {
            let visualIndex = isRTL ? count - 1 - index : index
            let left = bounds.width * CGFloat(visualIndex) / CGFloat(count)
            let right = bounds.width * CGFloat(visualIndex + 1) / CGFloat(count)
            button.frame = CGRect(x: bounds.minX + left, y: bounds.minY,
                                  width: right - left, height: height)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyModel()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        applyModel()
    }
}

@MainActor
private final class ShellClassicActionButton: UIButton {
    private var installedAction: UIAction?
    private(set) var preferredWidth: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isAccessibilityElement = true
        imageView?.isAccessibilityElement = false
        imageView?.contentMode = .scaleAspectFit
        titleLabel?.isAccessibilityElement = false
        titleLabel?.lineBreakMode = .byTruncatingTail
        clipsToBounds = true
    }

    func update(item: UIBarButtonItem, font: UIFont, color: UIColor) {
        if let action = installedAction { removeAction(action, for: .touchUpInside) }
        installedAction = nil
        if let action = item.primaryAction {
            installedAction = action
        } else if item.action != nil {
            installedAction = UIAction { [weak item] _ in
                guard let item = item, item.isEnabled, let selector = item.action else { return }
                UIApplication.shared.sendAction(selector, to: item.target, from: item, for: nil)
            }
        }
        if let action = installedAction { addAction(action, for: .touchUpInside) }
        menu = item.menu
        showsMenuAsPrimaryAction = item.menu != nil
        let image = item.image ?? item.primaryAction?.image
        let title = item.title ?? item.primaryAction?.title
        setImage(image.map { $0.renderingMode == .alwaysOriginal ? $0 : $0.withRenderingMode(.alwaysTemplate) },
                 for: .normal)
        setTitle(image == nil ? title : nil, for: .normal)
        imageView?.isAccessibilityElement = false
        imageView?.contentMode = .scaleAspectFit
        titleLabel?.isAccessibilityElement = false
        titleLabel?.font = font
        tintColor = color
        setTitleColor(color, for: .normal)
        setTitleColor(.tertiaryLabel, for: .disabled)
        contentEdgeInsets = image == nil
            ? UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            : UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        preferredWidth = image == nil
            ? max(44, ceil(((title ?? "") as NSString).size(withAttributes: [.font: font]).width) + 16)
            : 44
        isEnabled = item.isEnabled
        alpha = item.isEnabled ? 1 : 0.45
        accessibilityIdentifier = item.accessibilityIdentifier
        accessibilityLabel = item.accessibilityLabel ?? title
        accessibilityHint = item.accessibilityHint
        accessibilityValue = item.accessibilityValue
        accessibilityTraits = item.isEnabled ? .button : [.button, .notEnabled]
    }

    override var isHighlighted: Bool {
        didSet { alpha = isEnabled ? (isHighlighted ? 0.5 : 1) : 0.45 }
    }
}

@MainActor
private final class ShellClassicTabButton: UIButton {
    private let iconView = UIImageView()
    private let textLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isAccessibilityElement = true
        iconView.isAccessibilityElement = false
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 25)
        textLabel.isAccessibilityElement = false
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.isAccessibilityElement = false
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = .systemRed
        badgeLabel.textColor = .white
        badgeLabel.layer.masksToBounds = true
        for view in [iconView, textLabel, badgeLabel] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
    }

    func update(item: UITabBarItem, selected: Bool, font: UIFont, color: UIColor, iconColor: UIColor) {
        let image = selected ? (item.selectedImage ?? item.image) : item.image
        iconView.image = image.map { $0.renderingMode == .alwaysOriginal ? $0 : $0.withRenderingMode(.alwaysTemplate) }
        iconView.tintColor = iconColor
        textLabel.text = item.title
        textLabel.font = font
        textLabel.textColor = color
        badgeLabel.font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: .systemFont(ofSize: 10, weight: .semibold), compatibleWith: traitCollection)
        badgeLabel.text = item.badgeValue
        badgeLabel.isHidden = item.badgeValue == nil
        isSelected = selected
        isEnabled = item.isEnabled
        alpha = item.isEnabled ? 1 : 0.45
        accessibilityIdentifier = item.accessibilityIdentifier
        accessibilityLabel = item.accessibilityLabel ?? item.title
        accessibilityHint = item.accessibilityHint
        accessibilityValue = item.accessibilityValue ?? item.badgeValue
        var traits: UIAccessibilityTraits = .button
        if selected { traits.insert(.selected) }
        if !item.isEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let titleHeight = min(textLabel.font.lineHeight, bounds.height)
        let totalHeight = 25 + 2 + titleHeight
        let top = bounds.minY + max(0, (bounds.height - totalHeight) / 2)
        iconView.frame = CGRect(x: bounds.midX - 12.5, y: top, width: 25, height: 25)
        textLabel.frame = CGRect(x: bounds.minX + 4, y: iconView.frame.maxY + 2,
                                 width: max(0, bounds.width - 8), height: titleHeight)
        if !badgeLabel.isHidden {
            let empty = badgeLabel.text?.isEmpty != false
            let size = badgeLabel.sizeThatFits(bounds.size)
            let height: CGFloat = empty ? 8 : max(14, ceil(size.height) + 2)
            let width: CGFloat = empty ? 8 : max(height, ceil(size.width) + 8)
            let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
            let x = isRTL ? iconView.frame.minX - width + 2 : iconView.frame.maxX - 2
            badgeLabel.frame = CGRect(x: min(max(bounds.minX, x), max(bounds.minX, bounds.maxX - width)),
                                      y: max(bounds.minY, iconView.frame.minY - 3), width: width, height: height)
            badgeLabel.layer.cornerRadius = height / 2
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isEnabled ? (isHighlighted ? 0.5 : 1) : 0.45 }
    }
}

@MainActor
private final class ShellClassicBackdrop: UIView {
    private let blurView = UIVisualEffectView(effect: nil)
    private let separator = UIView()
    private let separatorAtTop: Bool
    private var material: ShellMaterial = .automatic
    private var showsMediaBackground = false

    init(separatorAtTop: Bool) {
        self.separatorAtTop = separatorAtTop
        super.init(frame: .zero)
        configureView()
    }

    required init?(coder: NSCoder) {
        separatorAtTop = false
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        blurView.isUserInteractionEnabled = false
        separator.isUserInteractionEnabled = false
        addSubview(blurView)
        addSubview(separator)
        NotificationCenter.default.addObserver(self, selector: #selector(reduceTransparencyDidChange),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                                               object: nil)
        refreshAppearance()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(material: ShellMaterial, showsMediaBackground: Bool) {
        self.material = material
        self.showsMediaBackground = showsMediaBackground
        refreshAppearance()
    }

    private func refreshAppearance() {
        let solid = material == .solid || UIAccessibility.isReduceTransparencyEnabled
        isOpaque = solid && !showsMediaBackground
        backgroundColor = isOpaque ? .systemBackground : .clear
        blurView.isHidden = solid || showsMediaBackground
        if blurView.isHidden {
            blurView.effect = nil
        } else if blurView.effect == nil {
            blurView.effect = UIBlurEffect(style: .systemMaterial)
        }
        separator.backgroundColor = .separator
        separator.isHidden = showsMediaBackground
        setNeedsLayout()
    }

    @objc private func reduceTransparencyDidChange() {
        refreshAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        let pixel = 1 / max(1, window?.screen.scale ?? traitCollection.displayScale)
        separator.frame = CGRect(x: bounds.minX, y: separatorAtTop ? bounds.minY : bounds.maxY - pixel,
                                 width: bounds.width, height: pixel)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshAppearance()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }
}
