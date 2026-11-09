import UIKit

/// The single empty / error / loading block (Anycast 2.0 UI kit
/// `AnycastContentUnavailable`): a 64 pt tinted disc with a glyph or a
/// spinner, a title, a message, and optional actions, centered in the
/// layout margins (it yields to them when taller). Host it as a collection
/// background (feed `alignBackgroundViewMargins()`) or pin it to a page.
class EmptyStateView: UIView {

    struct Content {
        var icon: UIImage?
        var showsSpinner = false
        var title: String?
        var message: String?
        /// Buttons (or rows of buttons), stacked under the message.
        var actions: [UIView] = []
        /// Spoken form of `title` when the visible text is shortened.
        /// VoiceOver reads this instead of the label's text.
        var titleAccessibilityLabel: String? = nil
        /// The search result sentence is a heading; other empty states are not.
        var titleIsHeader = false
    }

    private let disc = UIView()
    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionColumn = UIStackView()
    /// Assigned after `super.init`: the constraints refer to this view, and a
    /// `let` cannot be filled in once `super.init` has returned.
    private var column: UIStackView!
    private var centersContent: NSLayoutConstraint!
    private var pinsContentToTop: NSLayoutConstraint!
    private var widthCap: NSLayoutConstraint!
    private var widthFill: NSLayoutConstraint!
    /// The sentence before a too-wide token is given character breaks.
    private var plainTitle: String?

    private static let discSize: CGFloat = 64
    private static let glyphSize: CGFloat = 28
    private var discConstraints: [NSLayoutConstraint] = []

    init() {
        super.init(frame: .zero)

        disc.backgroundColor = AnycastColor.sandAlpha3
        disc.layer.cornerRadius = Self.discSize / 2
        disc.layer.cornerCurve = .continuous
        disc.translatesAutoresizingMaskIntoConstraints = false

        iconView.tintColor = Theme.primary
        iconView.contentMode = .center
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: EmptyStateView, _) in
            view.applyDiscMetrics()
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(iconView)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(spinner)

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        messageLabel.font = TypographyV2.meta.font()
        messageLabel.textColor = Theme.onSurfaceVariant
        for label in [titleLabel, messageLabel] {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }

        actionColumn.axis = .vertical
        actionColumn.alignment = .center
        actionColumn.spacing = Spacing.md

        column = UIStackView(arrangedSubviews: [disc, titleLabel, messageLabel, actionColumn])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = Spacing.md
        column.setCustomSpacing(Spacing.cardInner, after: disc)
        column.setCustomSpacing(Spacing.pageHeader, after: messageLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        centersContent = column.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor)
        centersContent.priority = .defaultHigh
        pinsContentToTop = column.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor)
        pinsContentToTop.isActive = false
        widthCap = column.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        widthFill = column.widthAnchor.constraint(equalTo: layoutMarginsGuide.widthAnchor)
        widthFill.isActive = false
        let discWidth = disc.widthAnchor.constraint(equalToConstant: Self.discSize)
        let discHeight = disc.heightAnchor.constraint(equalToConstant: Self.discSize)
        discConstraints = [discWidth, discHeight]
        NSLayoutConstraint.activate([
            discWidth, discHeight,
            iconView.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: disc.centerYAnchor),

            column.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            widthCap,
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            centersContent,
        ])
        applyDiscMetrics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Decorative disc. Design size at the default content size; grows with title1.
    private func applyDiscMetrics() {
        let side = IconMetrics.scaledUp(Self.discSize, style: TypographyV2.displaySmall, compatibleWith: traitCollection)
        for constraint in discConstraints { constraint.constant = side }
        disc.layer.cornerRadius = side / 2
        iconView.preferredSymbolConfiguration = IconMetrics.symbolConfiguration(
            pointSize: Self.glyphSize, weight: .medium, style: TypographyV2.displaySmall, compatibleWith: traitCollection
        )
    }

    func configure(_ content: Content) {
        iconView.image = content.icon
        iconView.isHidden = content.showsSpinner || content.icon == nil
        disc.isHidden = !content.showsSpinner && content.icon == nil
        if content.showsSpinner { spinner.startAnimating() } else { spinner.stopAnimating() }
        plainTitle = content.title
        titleLabel.text = content.title
        titleLabel.isHidden = content.title == nil
        titleLabel.accessibilityLabel = content.titleAccessibilityLabel
        titleLabel.accessibilityTraits = content.titleIsHeader ? [.staticText, .header] : .staticText
        messageLabel.text = content.message
        messageLabel.isHidden = content.message == nil
        actionColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.actions.forEach(actionColumn.addArrangedSubview)
        actionColumn.isHidden = content.actions.isEmpty
        // With no message the next gap is the stack's 8 pt, which leaves the
        // single button sitting on the sentence. Use the same 24 pt the
        // message-to-action gap already uses. A message keeps the 8 pt title
        // gap, so Playlist and History do not move.
        let titleGap = (content.message == nil && !content.actions.isEmpty)
            ? Spacing.pageHeader : Spacing.md
        column.setCustomSpacing(titleGap, after: titleLabel)
    }

    /// The sentence label, for a VoiceOver layout-changed notification.
    func accessibilityTitleView() -> UIView { titleLabel }

    /// `0` means as many lines as the text needs. Search uses 3 at the
    /// default sizes and 0 at accessibility sizes. A finite limit truncates
    /// the tail with an ellipsis; unlimited text word-wraps. Playlist and
    /// History never call this, so they keep the label's default break mode.
    func setTitleLineLimit(_ lines: Int) {
        let limit = lines > 0 ? lines : 0
        titleLabel.numberOfLines = limit
        titleLabel.lineBreakMode = limit > 0 ? .byTruncatingTail : .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    /// Column width the title will actually be given: the 320 pt cap when
    /// it is on, otherwise the full readable width.
    func columnWidth(fitting width: CGFloat) -> CGFloat {
        let margins = directionalLayoutMargins
        let available = max(0, width - margins.leading - margins.trailing)
        guard widthCap.isActive else { return available }
        return min(available, widthCap.constant)
    }

    /// Breaks a single token that cannot fit on one line. Other words stay
    /// whole, so a query that fits on the next line is not split.
    func fitTitle(toLineWidth lineWidth: CGFloat) {
        guard let plainTitle, lineWidth > 1 else { return }
        let font = titleLabel.font ?? UIFont.preferredFont(forTextStyle: .headline)
        let fitted = SearchResultState.titleFittingLine(plainTitle, lineWidth: lineWidth) { string in
            ceil((string as NSString).size(withAttributes: [.font: font]).width)
        }
        if titleLabel.text != fitted {
            titleLabel.text = fitted
        }
    }

    /// Accessibility sizes pin the block to the top and let it grow to the
    /// readable width. Default through xxxLarge stays centered and capped.
    func setAlignsContentToTop(_ alignsToTop: Bool) {
        centersContent.isActive = !alignsToTop
        pinsContentToTop.isActive = alignsToTop
    }

    func setExpandsToReadableWidth(_ expands: Bool) {
        widthCap.isActive = !expands
        widthFill.isActive = expands
        actionColumn.alignment = expands ? .fill : .center
    }

    /// Height of the column at `width`, including layout margins. Used by a
    /// host scroll view so a short block can center and a tall one can scroll.
    func contentHeight(fittingWidth width: CGFloat) -> CGFloat {
        let margins = directionalLayoutMargins
        let columnWidth = columnWidth(fitting: width)
        titleLabel.preferredMaxLayoutWidth = columnWidth
        messageLabel.preferredMaxLayoutWidth = columnWidth
        let textLimit = CGSize(width: columnWidth, height: CGFloat.greatestFiniteMagnitude)
        // Sum the visible rows at the column width. Measuring the stack at
        // the full page width reports too few lines, and the last line is
        // then clipped with no ellipsis.
        var height: CGFloat = 0
        var previous: UIView?
        for row in [disc, titleLabel, messageLabel, actionColumn] where !row.isHidden {
            if let previous {
                let custom = column.customSpacing(after: previous)
                height += custom == UIStackView.spacingUseDefault ? column.spacing : custom
            }
            height += rowHeight(row, columnWidth: columnWidth, textLimit: textLimit)
            previous = row
        }
        return ceil(height + margins.top + margins.bottom)
    }

    /// Labels measure their wrapped text with `sizeThatFits`. The disc and
    /// the button row do not: `UIView.sizeThatFits` returns the current
    /// bounds, which are still zero the first time this runs.
    private func rowHeight(_ row: UIView, columnWidth: CGFloat, textLimit: CGSize) -> CGFloat {
        if row === titleLabel || row === messageLabel {
            return row.sizeThatFits(textLimit).height
        }
        return row.systemLayoutSizeFitting(
            CGSize(width: columnWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }
}
