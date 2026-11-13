import UIKit

/// The single empty / error block: up to two sentences in Body size and the
/// secondary colour (no icon, no title weight), and optional actions,
/// centered in the layout margins (it yields to them when taller). Host it as a collection
/// background (feed `alignBackgroundViewMargins()`) or pin it to a page.
class EmptyStateView: UIView {

    struct Content {
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

    init() {
        super.init(frame: .zero)

        titleLabel.font = TypographyV2.meta.font()
        titleLabel.textColor = Theme.onSurfaceVariant
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

        column = UIStackView(arrangedSubviews: [titleLabel, messageLabel, actionColumn])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = Spacing.md
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
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            widthCap,
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            centersContent,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The quiet text link under (or instead of) the primary action: Body
    /// size, secondary colour, underlined, with a minimum hit height.
    static func linkButton(title: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            outgoing.foregroundColor = Theme.onSurfaceVariant
            outgoing.underlineStyle = .single
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.textAlignment = .center
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: IconMetrics.minimumHit).isActive = true
        return button
    }

    func configure(_ content: Content) {
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
            ? Spacing.pageHeader : Spacing.xs
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
        for row in [titleLabel, messageLabel, actionColumn] where !row.isHidden {
            if let previous {
                let custom = column.customSpacing(after: previous)
                height += custom == UIStackView.spacingUseDefault ? column.spacing : custom
            }
            height += rowHeight(row, columnWidth: columnWidth, textLimit: textLimit)
            previous = row
        }
        return ceil(height + margins.top + margins.bottom)
    }

    /// Labels measure their wrapped text with `sizeThatFits`. The button row
    /// does not: `UIView.sizeThatFits` returns the current
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
