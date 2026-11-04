import UIKit

/// The detail sheet's transcript status row (direction A): one 52 pt
/// surfaceContainer capsule pinned above Play. Copy and actions come from
/// `DetailTranscriptContent`. Default through xxxLarge stays one line and
/// truncates the title; accessibility sizes wrap the count and the action
/// onto a second line. The row's height hugs that content and never jumps
/// to a new chrome height when only the number fades in.
@MainActor
final class DetailTranscriptRow: UIView {

    /// Same height as the default Play capsule (`Radius.sheetCapsuleHeight`).
    static let minimumHeight: CGFloat = Radius.sheetCapsuleHeight

    var onAction: ((DetailTranscriptAction) -> Void)?

    private(set) var usesMultilineLayout = false
    private var content = DetailTranscriptState.reduce(status: nil, signedIn: false, allowance: nil)
    private var appliedKind: DetailTranscriptContent.Kind?
    private var appliedValue: String?

    private let mainButton = UIButton(type: .custom)
    private let iconView = UIImageView()
    private let spinner = TranscriptActivityIndicator()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let actionButton = TranscriptActionButton(type: .system)
    private let host = UIStackView()
    private let compactRow = UIStackView()
    private let accessibleColumn = UIStackView()
    private let accessibleTitleRow = UIStackView()
    private var iconWidth: NSLayoutConstraint?
    private var iconHeight: NSLayoutConstraint?
    private var spinnerWidth: NSLayoutConstraint?
    private var spinnerHeight: NSLayoutConstraint?
    private var slotWidth: NSLayoutConstraint?
    private var slotHeight: NSLayoutConstraint?
    /// Explicit height so the row hugs max(52, its content) and the sheet
    /// does not stretch it. Updated after content and trait changes.
    private var rowHeight: NSLayoutConstraint!
    /// Corner shared with Play. The parent sets it from the sheet's
    /// concentric rule; the default is the 28 pt inset.
    private var concentricRadius = Radius.sheetConcentric

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityIdentifier = "detail-transcript-row"
        backgroundColor = Theme.surfaceContainer
        layer.cornerRadius = Radius.sheetConcentric
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        buildContents()
        installHost()
        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self,
            UITraitAccessibilityContrast.self,
            UITraitUserInterfaceStyle.self,
        ]) { (self: Self, _) in
            self.applyTraits()
            self.applyContent(self.content, animated: false)
        }
        applyTraits()
        applyContent(content, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ content: DetailTranscriptContent, animated: Bool) {
        let previousKind = appliedKind
        let previousValue = appliedValue
        let previousTitle = self.content.title
        // The first presentation is not a transition: opening a sheet on an
        // already-ready episode must not announce.
        let announce = previousKind != nil && previousKind != .ready && content.kind == .ready
        let valueOnly = previousKind == content.kind && previousValue != content.value
            && content.title == previousTitle
        self.content = content

        let changes = {
            self.applyContent(content, animated: false)
            self.appliedKind = content.kind
            self.appliedValue = content.value
        }
        let shouldAnimate = animated && window != nil && !Motion.reduceMotion
        if shouldAnimate, valueOnly, !usesMultilineLayout {
            UIView.transition(with: valueLabel, duration: Motion.quick, options: .transitionCrossDissolve, animations: changes)
        } else if shouldAnimate, previousKind != nil, previousKind != content.kind {
            UIView.transition(with: self, duration: Motion.quick, options: .transitionCrossDissolve, animations: changes)
        } else {
            changes()
        }
        if announce {
            UIAccessibility.post(notification: .announcement, argument: "Transcript ready")
        }
    }

    // MARK: - Build

    private func buildContents() {
        mainButton.accessibilityIdentifier = "detail-transcript-main"
        mainButton.addAction(UIAction { [weak self] _ in self?.activateRow() }, for: .touchUpInside)
        // The row itself is the VoiceOver element; the button is the touch target.
        mainButton.isAccessibilityElement = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Theme.onSurfaceVariant
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.onSurfaceVariant
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        actionButton.contentHorizontalAlignment = .leading
        actionButton.addAction(UIAction { [weak self] _ in self?.activateTrailing() }, for: .touchUpInside)
        actionButton.isAccessibilityElement = false
        var actionConfig = UIButton.Configuration.plain()
        actionConfig.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.xs, leading: Spacing.xs, bottom: Spacing.xs, trailing: 0
        )
        actionButton.configuration = actionConfig

        mainButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainButton)
        NSLayoutConstraint.activate([
            mainButton.topAnchor.constraint(equalTo: topAnchor),
            mainButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            mainButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        rowHeight = heightAnchor.constraint(equalToConstant: Self.minimumHeight)
        rowHeight.isActive = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFittedHeight()
    }

    /// Height is max(52, the arrangement). A same-line count change does not
    /// change it; an accessibility-size wrap does.
    private func updateFittedHeight() {
        let width = bounds.width > 1 ? bounds.width : 340
        let fitting = host.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let target = max(Self.minimumHeight, ceil(fitting))
        if rowHeight.constant != target {
            rowHeight.constant = target
        }
    }

    /// One host, two arrangements. The hidden one collapses, so the row's
    /// height is max(52, the visible arrangement) and a count fading in on
    /// the same line does not change it.
    private func installHost() {
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        compactRow.axis = .horizontal
        compactRow.alignment = .center
        compactRow.spacing = Spacing.gap
        compactRow.isLayoutMarginsRelativeArrangement = true
        compactRow.layoutMargins = UIEdgeInsets(top: 0, left: Spacing.pageH, bottom: 0, right: Spacing.cardInner)

        accessibleTitleRow.axis = .horizontal
        accessibleTitleRow.alignment = .center
        accessibleTitleRow.spacing = Spacing.gap
        accessibleColumn.axis = .vertical
        accessibleColumn.alignment = .fill
        accessibleColumn.spacing = Spacing.sm
        accessibleColumn.isLayoutMarginsRelativeArrangement = true
        accessibleColumn.addArrangedSubview(accessibleTitleRow)

        host.axis = .vertical
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addArrangedSubview(compactRow)
        host.addArrangedSubview(accessibleColumn)
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // Keep the arrangement inside the row without forcing a height the
        // explicit rowHeight constraint has not caught up to yet.
        let hostTop = host.topAnchor.constraint(greaterThanOrEqualTo: topAnchor)
        let hostBottom = host.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        hostTop.priority = UILayoutPriority(999)
        hostBottom.priority = UILayoutPriority(999)
        hostTop.isActive = true
        hostBottom.isActive = true
    }

    // MARK: - Render

    private func applyTraits() {
        let multiline = Self.prefersMultilineLayout(traitCollection)
        usesMultilineLayout = multiline
        titleLabel.font = TypographyV2.body.font(traits: traitCollection)
        valueLabel.font = TypographyV2.meta.font(traits: traitCollection)
        titleLabel.numberOfLines = multiline ? 2 : 1
        titleLabel.lineBreakMode = multiline ? .byWordWrapping : .byTruncatingTail
        // Accessibility sizes give the count and the action their own lines
        // so neither is crushed. The title is the only piece that truncates,
        // and only on the single-line arrangement.
        valueLabel.numberOfLines = multiline ? 0 : 1
        valueLabel.lineBreakMode = multiline ? .byWordWrapping : .byTruncatingTail
        valueLabel.setContentCompressionResistancePriority(
            multiline ? .defaultHigh : .required, for: .horizontal
        )
        actionButton.setContentCompressionResistancePriority(
            multiline ? .defaultLow : .required, for: .horizontal
        )
        actionButton.setContentHuggingPriority(
            multiline ? .defaultLow : .required, for: .horizontal
        )
        // The count and the action sit on their own lines at accessibility
        // sizes. 6 pt at the default size (the column is hidden then) scales
        // with the body style so the two lines do not read as one sentence.
        accessibleColumn.spacing = TypographyV2.scaledValue(
            Spacing.sm, style: .body, compatibleWith: traitCollection
        )
        compactRow.isHidden = multiline
        accessibleColumn.isHidden = !multiline
        // Padding has to clear the row's own corner. The default one-line
        // capsule is already clear and stays as designed.
        if multiline {
            accessibleColumn.layoutMargins = Self.accessibilityMargins(radius: concentricRadius)
            accessibleTitleRow.alignment = .center
        }
        layer.cornerRadius = concentricRadius
        applyIconScale()
        // Reparent the shared labels into the visible arrangement.
        let iconSlot = iconContainer()
        if multiline {
            place(iconSlot, in: accessibleTitleRow, at: 0)
            place(titleLabel, in: accessibleTitleRow, at: 1)
            place(valueLabel, in: accessibleColumn, at: 1)
            place(actionButton, in: accessibleColumn, at: 2)
        } else {
            place(iconSlot, in: compactRow, at: 0)
            place(titleLabel, in: compactRow, at: 1)
            place(valueLabel, in: compactRow, at: 2)
            place(actionButton, in: compactRow, at: 3)
        }
        updateFittedHeight()
    }

    /// The sheet tells the row which concentric radius to draw.
    func applyConcentricRadius(_ radius: CGFloat) {
        guard radius != concentricRadius else { return }
        concentricRadius = radius
        applyTraits()
    }

    /// Inset that keeps the icon and text out of the row's corner arc.
    private static func accessibilityMargins(radius: CGFloat) -> UIEdgeInsets {
        let clear = max(Radius.arcContentInset(radius), Spacing.pageH)
        return UIEdgeInsets(
            top: clear,
            left: max(Spacing.pageH, clear),
            bottom: clear,
            right: max(Spacing.cardInner, clear)
        )
    }

    /// Re-reads fonts and the accessibility-size stack after the view joins a window.
    func relayoutForCurrentTraits() {
        applyTraits()
        applyContent(content, animated: false)
    }

    private func applyIconScale() {
        let icon = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: Spacing.cardInner, compatibleWith: traitCollection
        )
        let ring = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: Spacing.pageH, compatibleWith: traitCollection
        )
        iconWidth?.constant = icon
        iconHeight?.constant = icon
        slotWidth?.constant = icon
        slotHeight?.constant = icon
        spinnerWidth?.constant = ring
        spinnerHeight?.constant = ring
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: icon, weight: .regular)
    }

    private func iconContainer() -> UIView {
        // The spinner and the glyph share one slot so the title doesn't shift.
        if iconView.superview !== spinner.superview || iconSlot == nil {
            let slot = UIView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.addSubview(iconView)
            slot.addSubview(spinner)
            let slotW = slot.widthAnchor.constraint(equalToConstant: Spacing.cardInner)
            let slotH = slot.heightAnchor.constraint(equalToConstant: Spacing.cardInner)
            let iconW = iconView.widthAnchor.constraint(equalToConstant: Spacing.cardInner)
            let iconH = iconView.heightAnchor.constraint(equalToConstant: Spacing.cardInner)
            let ringW = spinner.widthAnchor.constraint(equalToConstant: Spacing.pageH)
            let ringH = spinner.heightAnchor.constraint(equalToConstant: Spacing.pageH)
            slotWidth = slotW
            slotHeight = slotH
            iconWidth = iconW
            iconHeight = iconH
            spinnerWidth = ringW
            spinnerHeight = ringH
            NSLayoutConstraint.activate([
                slotW, slotH, iconW, iconH, ringW, ringH,
                iconView.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
                spinner.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            ])
            iconSlot = slot
            applyIconScale()
        }
        return iconSlot!
    }

    private var iconSlot: UIView?

    private func place(_ view: UIView, in stack: UIStackView, at index: Int) {
        if view.superview !== stack {
            view.removeFromSuperview()
            stack.insertArrangedSubview(view, at: min(index, stack.arrangedSubviews.count))
        }
    }

    private func applyContent(_ content: DetailTranscriptContent, animated: Bool) {
        titleLabel.text = content.title
        valueLabel.text = content.value
        valueLabel.isHidden = content.value == nil

        let reduceMotion = Motion.reduceMotion || UIAccessibility.isReduceMotionEnabled
        let showSpinner = content.symbol == .spinner && !reduceMotion
        spinner.isHidden = !showSpinner
        spinner.setSpinning(showSpinner)
        iconView.isHidden = showSpinner
        iconView.image = Self.image(for: content.symbol, reduceMotion: reduceMotion)
        iconView.tintColor = Theme.onSurfaceVariant

        let hasAction = content.actionTitle != nil
        actionButton.isHidden = !hasAction
        applyActionTitle(content)
        actionButton.isEnabled = hasAction

        let enabled = content.rowAction != nil
        mainButton.isEnabled = enabled
        isAccessibilityElement = true
        accessibilityLabel = content.accessibilityLabel
        accessibilityHint = content.accessibilityHint
        accessibilityTraits = enabled ? .button : .staticText
        accessibilityCustomActions = content.accessibilityCustomActions.map { action in
            UIAccessibilityCustomAction(name: Self.customActionName(action)) { [weak self] _ in
                self?.onAction?(action)
                return true
            }
        }
        updateFittedHeight()
        _ = animated
    }

    /// Accessibility sizes wrap; xxxLarge and below stay one truncating line.
    static func prefersMultilineLayout(_ traits: UITraitCollection) -> Bool {
        traits.preferredContentSizeCategory.isAccessibilityCategory
    }

    private func applyActionTitle(_ content: DetailTranscriptContent) {
        guard let title = content.actionTitle else {
            actionButton.configuration?.title = nil
            actionButton.configuration?.attributedTitle = nil
            return
        }
        let highContrast = content.trailingUpgradesContrast
            && traitCollection.accessibilityContrast == .high
        let color = highContrast ? Theme.onSurface : Theme.primary
        let font = TypographyV2.body.font(traits: traitCollection)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = usesMultilineLayout ? .byWordWrapping : .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if highContrast {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        var config = actionButton.configuration ?? .plain()
        config.title = nil
        config.titleLineBreakMode = usesMultilineLayout ? .byWordWrapping : .byTruncatingTail
        config.attributedTitle = AttributedString(NSAttributedString(string: title, attributes: attributes))
        config.baseForegroundColor = color
        actionButton.configuration = config
        actionButton.titleLabel?.numberOfLines = usesMultilineLayout ? 0 : 1
        actionButton.titleLabel?.lineBreakMode = usesMultilineLayout ? .byWordWrapping : .byTruncatingTail
    }

    private static func image(for symbol: DetailTranscriptContent.Symbol, reduceMotion: Bool) -> UIImage? {
        let image: UIImage?
        switch symbol {
        case .sparkle:
            image = AppIcons.aiTranscript
        case .lines:
            image = AppIcons.transcriptLines
        case .warning:
            image = AppIcons.transcriptFailed
        case .spinner:
            image = reduceMotion ? AppIcons.more : nil
        }
        return image?.withRenderingMode(.alwaysTemplate)
    }

    private static func customActionName(_ action: DetailTranscriptAction) -> String {
        switch action {
        case .generate: return "Generate"
        case .read: return "Read transcript"
        case .askAI: return "Ask AI"
        case .getPlus: return "Get Plus"
        }
    }

    // MARK: - Hits

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, bounds.contains(point) else { return nil }
        if !actionButton.isHidden, actionButton.isEnabled {
            let frame = actionButton.convert(actionButton.bounds, to: self)
            var hit = frame
            let minimum = AnycastIconButton.standardDiameter
            if hit.width < minimum {
                hit.origin.x -= (minimum - hit.width) / 2
                hit.size.width = minimum
            }
            hit.origin.y = bounds.minY
            hit.size.height = bounds.height
            if hit.contains(point) { return actionButton }
        }
        // Generating is not a button, but it still swallows the touch so the
        // sheet doesn't treat the row as empty space.
        guard content.rowAction != nil else { return self }
        return mainButton
    }

    override func accessibilityActivate() -> Bool {
        activateRow()
        return content.rowAction != nil
    }

    private func activateRow() {
        guard let action = content.rowAction else { return }
        onAction?(action)
    }

    private func activateTrailing() {
        guard let action = content.trailingAction else { return }
        onAction?(action)
    }
}

/// Trailing word. Its hit area is the full row height and at least 44 pt wide,
/// even when the text itself is narrower (Retry) or shorter than the row.
private final class TranscriptActionButton: UIButton {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var rect = bounds
        let minimum = AnycastIconButton.standardDiameter
        if rect.width < minimum {
            rect.origin.x -= (minimum - rect.width) / 2
            rect.size.width = minimum
        }
        if let row = enclosingRow {
            let rowBounds = convert(row.bounds, from: row)
            rect.origin.y = rowBounds.minY
            rect.size.height = rowBounds.height
        }
        return rect.contains(point)
    }

    private var enclosingRow: UIView? {
        var view = superview
        while let current = view {
            if current is DetailTranscriptRow { return current }
            view = current.superview
        }
        return nil
    }
}

/// 16 pt ring used while a transcript is generating. Reduce Motion swaps it
/// for a static ellipsis before this view is shown.
private final class TranscriptActivityIndicator: UIView {

    private let track = CAShapeLayer()
    private let head = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for shape in [track, head] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = 2
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        track.frame = bounds
        head.frame = bounds
        track.path = path.cgPath
        head.path = path.cgPath
        head.strokeStart = 0
        head.strokeEnd = 0.28
        applyColors()
    }

    func setSpinning(_ spinning: Bool) {
        if spinning {
            guard head.animation(forKey: "spin") == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = CGFloat.pi * 2
            animation.duration = 0.9
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            head.add(animation, forKey: "spin")
        } else {
            head.removeAnimation(forKey: "spin")
        }
    }

    private func applyColors() {
        track.strokeColor = AnycastColor.sandAlpha4.resolvedColor(with: traitCollection).cgColor
        head.strokeColor = Theme.onSurfaceVariant.resolvedColor(with: traitCollection).cgColor
    }
}
