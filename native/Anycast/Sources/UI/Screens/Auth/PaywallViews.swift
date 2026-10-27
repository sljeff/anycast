import UIKit

// Building blocks of the standalone paywall: the dark transcript card (A's
// language demo, C's episode card), the language chips, the plan rows, the
// quota figures and the info rows of the "What's in Plus" sheet.

// MARK: - Language chips

/// The row of language chips under the card: 44 pt tall, meta text, the
/// selected chip in player text and the rest dimmed. Radio semantics: one
/// selected chip, announced as selected to VoiceOver.
final class PaywallChipsView: UIStackView {

    var onPick: ((Int) -> Void)?

    private var chips: [UIButton] = []

    init(languages: [PaywallModel.Language], selectedIndex: Int) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .fill
        spacing = Spacing.xs
        for (index, language) in languages.enumerated() {
            let chip = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = language.label
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: Spacing.gap, bottom: 0, trailing: Spacing.gap
            )
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = TypographyV2.meta.font()
                return outgoing
            }
            chip.configuration = configuration
            chip.titleLabel?.adjustsFontForContentSizeCategory = true
            chip.accessibilityIdentifier = "paywall-chip-\(language.code)"
            chip.heightAnchor.constraint(equalToConstant: 44).isActive = true
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            chip.setContentHuggingPriority(.required, for: .horizontal)
            chip.addAction(UIAction { [weak self] _ in self?.onPick?(index) }, for: .touchUpInside)
            addArrangedSubview(chip)
            chips.append(chip)
        }
        // Trailing slack so the chips hug their text.
        let slack = UIView()
        slack.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        slack.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        addArrangedSubview(slack)
        setSelected(selectedIndex)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSelected(_ index: Int) {
        for (offset, chip) in chips.enumerated() {
            let isOn = offset == index
            chip.configuration?.baseForegroundColor = isOn ? Theme.playerText : Theme.playerSecondary
            chip.alpha = isOn ? 1 : 0.6
            chip.accessibilityTraits = isOn ? [.button, .selected] : .button
        }
    }
}

// MARK: - Transcript card

/// The dark card that is the paywall's focal object (player palette,
/// radius 24). Variant A shows an example transcript whose highlighted line
/// swaps its translation per language chip; variant C shows the episode the
/// user just tried with a prompt line above the chips.
final class PaywallCardView: UIView {

    enum Content {
        case demo
        case episode(PaywallModel.Episode)
    }

    /// Height of the demo's line window.
    private static let linesHeight: CGFloat = 180
    private static let fadeHeight: CGFloat = 22

    var onPick: ((Int) -> Void)? {
        get { chips.onPick }
        set { chips.onPick = newValue }
    }

    private let chips: PaywallChipsView
    private let linesWindow = UIView()
    private let linesStack = UIStackView()
    private var translationLabels: [UILabel] = []

    init(content: Content, selectedIndex: Int) {
        chips = PaywallChipsView(languages: PaywallModel.languages, selectedIndex: selectedIndex)
        super.init(frame: .zero)
        backgroundColor = Theme.playerBackground
        layer.cornerRadius = Radius.card
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = Spacing.md
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        switch content {
        case .demo:
            column.addArrangedSubview(Self.label(
                PaywallModel.demoMeta, font: TypographyV2.meta.font(), color: Theme.playerSecondary
            ))
            column.addArrangedSubview(buildLinesWindow(language: PaywallModel.languages[selectedIndex]))
        case .episode(let episode):
            column.addArrangedSubview(buildEpisodeRow(episode))
            let prompt = Self.label(
                PaywallModel.quotaPrompt, font: TypographyV2.body.font(), color: Theme.playerText
            )
            prompt.numberOfLines = 0
            column.addArrangedSubview(prompt)
        }
        column.addArrangedSubview(buildChipsRow())

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.pageH),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.cardInner),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.cardInner),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Build

    private static func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func buildEpisodeRow(_ episode: PaywallModel.Episode) -> UIView {
        let artwork = UIImageView()
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 12
        artwork.layer.cornerCurve = .continuous
        artwork.backgroundColor = Theme.playerWarm
        artwork.isAccessibilityElement = false
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.setArtwork(episode.artworkURL, title: episode.showName)

        let title = Self.label(episode.title, font: TypographyV2.emphasis.font(), color: Theme.playerText)
        let meta = Self.label(episode.metaLine, font: TypographyV2.meta.font(), color: Theme.playerSecondary)
        let texts = UIStackView(arrangedSubviews: [title, meta])
        texts.axis = .vertical

        let row = UIStackView(arrangedSubviews: [artwork, texts])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: Spacing.md, trailing: 0)
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 56),
            artwork.heightAnchor.constraint(equalToConstant: 56),
        ])
        row.isAccessibilityElement = true
        row.accessibilityLabel = "\(episode.title), \(episode.metaLine)"
        return row
    }

    /// Five blocks (two before, the highlighted line, two after) centered in
    /// a clipped window, so the highlighted line stays in the middle and the
    /// neighbors fade out at both edges.
    private func buildLinesWindow(language: PaywallModel.Language) -> UIView {
        linesWindow.clipsToBounds = true
        linesWindow.isAccessibilityElement = true
        linesWindow.accessibilityLabel = "Example transcript with translation"

        linesStack.axis = .vertical
        linesStack.alignment = .fill
        linesStack.spacing = Spacing.sm
        linesStack.isUserInteractionEnabled = false
        linesStack.translatesAutoresizingMaskIntoConstraints = false
        linesWindow.addSubview(linesStack)

        for line in language.before { linesStack.addArrangedSubview(makeBlock(highlighted: false, original: line.original)) }
        linesStack.addArrangedSubview(makeBlock(highlighted: true, original: PaywallModel.highlightedLine))
        for line in language.after { linesStack.addArrangedSubview(makeBlock(highlighted: false, original: line.original)) }
        applyTranslations(language)

        let top = PaywallFadeView(edge: .top)
        let bottom = PaywallFadeView(edge: .bottom)
        for fade in [top, bottom] {
            fade.translatesAutoresizingMaskIntoConstraints = false
            linesWindow.addSubview(fade)
        }
        NSLayoutConstraint.activate([
            linesWindow.heightAnchor.constraint(equalToConstant: Self.linesHeight),
            linesStack.leadingAnchor.constraint(equalTo: linesWindow.leadingAnchor),
            linesStack.trailingAnchor.constraint(equalTo: linesWindow.trailingAnchor),
            linesStack.centerYAnchor.constraint(equalTo: linesWindow.centerYAnchor),
            top.topAnchor.constraint(equalTo: linesWindow.topAnchor),
            top.leadingAnchor.constraint(equalTo: linesWindow.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: linesWindow.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: Self.fadeHeight),
            bottom.bottomAnchor.constraint(equalTo: linesWindow.bottomAnchor),
            bottom.leadingAnchor.constraint(equalTo: linesWindow.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: linesWindow.trailingAnchor),
            bottom.heightAnchor.constraint(equalToConstant: Self.fadeHeight),
        ])
        return linesWindow
    }

    private func makeBlock(highlighted: Bool, original: String) -> UIView {
        let originalLabel = Self.label(
            original, font: TypographyV2.body.font(),
            color: highlighted ? Theme.playerText : Theme.playerSecondary
        )
        let translation = Self.label("", font: TypographyV2.body.font(), color: AnycastColor.goldDark9)
        translation.alpha = highlighted ? 1 : 0.7
        translationLabels.append(translation)
        let block = UIStackView(arrangedSubviews: [originalLabel, translation])
        block.axis = .vertical
        block.spacing = Spacing.xs
        // The highlighted block reserves a little more height for its
        // cross-fading translation.
        if highlighted {
            block.isLayoutMarginsRelativeArrangement = true
            block.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: Spacing.xs, trailing: 0)
        }
        return block
    }

    private func applyTranslations(_ language: PaywallModel.Language) {
        let translations = language.before.map(\.translation)
            + [language.translation]
            + language.after.map(\.translation)
        for (label, text) in zip(translationLabels, translations) {
            label.text = text
        }
    }

    private func buildChipsRow() -> UIView {
        let container = UIView()
        let line = UIView()
        line.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        line.translatesAutoresizingMaskIntoConstraints = false
        chips.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        container.addSubview(chips)
        NSLayoutConstraint.activate([
            // The chips' own 12 pt text inset lines their text up with the
            // card's 20 pt content edge; the hairline spans 8 pt in.
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.heightAnchor.constraint(equalToConstant: Spacing.hairline),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -(Spacing.cardInner - Spacing.md)),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: Spacing.cardInner - Spacing.md),
            chips.topAnchor.constraint(equalTo: container.topAnchor),
            chips.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            chips.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: -Spacing.gap),
            chips.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: Spacing.gap),
        ])
        return container
    }

    // MARK: Update

    func setLanguage(index: Int, animated: Bool) {
        chips.setSelected(index)
        guard !translationLabels.isEmpty else { return }
        let language = PaywallModel.languages[index]
        let apply = { self.applyTranslations(language) }
        if animated, !Motion.reduceMotion {
            UIView.transition(
                with: linesWindow, duration: Motion.emphasized, options: .transitionCrossDissolve,
                animations: apply
            )
        } else {
            apply()
        }
    }
}

/// A 22 pt gradient from the player background to clear, fading the demo
/// card's context lines at the window edges.
private final class PaywallFadeView: UIView {

    enum Edge { case top, bottom }

    private let edge: Edge
    private let gradient = CAGradientLayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        let solid = Theme.playerBackground.cgColor
        let clear = Theme.playerBackground.withAlphaComponent(0).cgColor
        gradient.colors = edge == .top ? [solid, clear] : [clear, solid]
        layer.addSublayer(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - Quota figures

/// Variant C's two value figures: "50 / more every month" and
/// "≈4¢ / each, on Yearly", the value in the approved display face.
final class PaywallFiguresView: UIStackView {

    init(figures: [PaywallModel.Figure]) {
        super.init(frame: .zero)
        update(figures)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Replaces the columns; the per-transcript price arrives with the
    /// offering, after the view is built.
    func update(_ figures: [PaywallModel.Figure]) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        axis = .horizontal
        alignment = .top
        distribution = .fillEqually
        spacing = Spacing.gap
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: Spacing.xs, leading: 0, bottom: 0, trailing: 0)
        for figure in figures {
            let value = UILabel()
            value.text = figure.value
            value.font = TypographyV2.displayLarge.font().monospacedDigits()
            value.textColor = Theme.onSurface
            value.adjustsFontForContentSizeCategory = true
            value.adjustsFontSizeToFitWidth = true
            value.minimumScaleFactor = 0.6
            value.numberOfLines = 1
            let caption = UILabel()
            caption.text = figure.caption
            caption.font = TypographyV2.meta.font()
            caption.textColor = Theme.onSurfaceVariant
            caption.adjustsFontForContentSizeCategory = true
            let column = UIStackView(arrangedSubviews: [value, caption])
            column.axis = .vertical
            column.spacing = Spacing.xs
            column.isAccessibilityElement = true
            column.accessibilityLabel = "\(figure.value) \(figure.caption)"
            addArrangedSubview(column)
        }
    }
}

// MARK: - Plan row

/// One radio row of the plan group: ring or check, title with the optional
/// ink "Save X%" badge, subtitle, and the right-aligned price. The selected
/// row sits on the gold plate; press feedback is a `sandAlpha5` fill only.
final class PaywallPlanRowView: UIControl {

    let period: PaywallModel.Period

    private let ring = UIView()
    private let check = UIImageView()
    private let titleLabel = UILabel()
    private let badge = PaywallBadgeView()
    private let subtitleLabel = UILabel()
    private let priceLabel = UILabel()
    private let pressOverlay = UIView()

    init(row: PaywallModel.PlanRow) {
        period = row.period
        super.init(frame: .zero)

        pressOverlay.backgroundColor = AnycastColor.sandAlpha5
        pressOverlay.alpha = 0
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pressOverlay)

        ring.layer.cornerRadius = 11
        ring.layer.borderWidth = 1.5
        ring.setDynamicBorderColor(AnycastColor.sandAlpha8)
        ring.translatesAutoresizingMaskIntoConstraints = false
        check.image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        )
        check.tintColor = Theme.primary
        check.contentMode = .center
        check.translatesAutoresizingMaskIntoConstraints = false
        let indicator = UIView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.addSubview(ring)
        indicator.addSubview(check)
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 22),
            indicator.heightAnchor.constraint(equalToConstant: 22),
            ring.widthAnchor.constraint(equalToConstant: 22),
            ring.heightAnchor.constraint(equalToConstant: 22),
            check.widthAnchor.constraint(equalToConstant: 22),
            check.heightAnchor.constraint(equalToConstant: 22),
            ring.centerXAnchor.constraint(equalTo: indicator.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
            check.centerXAnchor.constraint(equalTo: indicator.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: indicator.centerYAnchor),
        ])

        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        priceLabel.font = TypographyV2.emphasis.font().monospacedDigits()
        priceLabel.textColor = Theme.onSurface
        priceLabel.textAlignment = .right
        for label in [titleLabel, subtitleLabel, priceLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
        }
        priceLabel.setContentHuggingPriority(.required, for: .horizontal)
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, badge, UIView()])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = Spacing.md
        let labels = UIStackView(arrangedSubviews: [titleRow, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = Spacing.xxs

        let content = UIStackView(arrangedSubviews: [indicator, labels, priceLabel])
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = Spacing.gap
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: AccountRowView.minimumHeight)
        minimumHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            pressOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            pressOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            pressOverlay.topAnchor.constraint(equalTo: topAnchor),
            pressOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AccountRowView.horizontalInset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AccountRowView.horizontalInset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.gap),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.gap),
            minimumHeight,
        ])

        isAccessibilityElement = true
        configure(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ row: PaywallModel.PlanRow) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        priceLabel.text = row.price
        badge.setText(row.badge)
        ring.alpha = row.isSelected ? 0 : 1
        check.alpha = row.isSelected ? 1 : 0
        backgroundColor = row.isSelected ? AccountStyle.goldPlate : .clear

        accessibilityLabel = [row.title, row.badge, row.subtitle, row.price]
            .compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = row.isSelected ? [.button, .selected] : .button
    }

    override var isHighlighted: Bool {
        didSet { pressOverlay.alpha = isHighlighted ? 1 : 0 }
    }
}

/// The "Save X%" badge: an ink pill (onSurface fill, surface text), 22 pt
/// tall. Hidden when there is nothing to say.
final class PaywallBadgeView: UIView {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.onSurface
        layer.cornerCurve = .continuous
        label.font = TypographyV2.meta.font()
        label.textColor = Theme.surface
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.md),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.md),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.xxs),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.xxs),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setText(_ text: String?) {
        label.text = text
        isHidden = text == nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - Plans status

/// The plans area while offerings load or when they are unavailable: a
/// quiet message with Retry, never placeholder prices.
final class PaywallPlansStatusView: UIView {

    var onRetry: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        messageLabel.text = PaywallModel.unavailableMessage
        messageLabel.font = TypographyV2.meta.font()
        messageLabel.textColor = Theme.onSurfaceVariant
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true

        var configuration = UIButton.Configuration.plain()
        configuration.title = PaywallModel.retryTitle
        configuration.baseForegroundColor = Theme.onSurface
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.emphasis.font()
            return outgoing
        }
        retryButton.configuration = configuration
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.accessibilityIdentifier = "paywall-retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)

        let column = UIStackView(arrangedSubviews: [spinner, messageLabel, retryButton])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = Spacing.md
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AccountRowView.horizontalInset),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AccountRowView.horizontalInset),
            heightAnchor.constraint(equalToConstant: 2 * AccountRowView.minimumHeight + Spacing.hairline),
        ])
        setLoading(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setLoading(_ loading: Bool) {
        spinner.isHidden = !loading
        messageLabel.isHidden = loading
        retryButton.isHidden = loading
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

// MARK: - Info rows

/// A leading glyph or dot, a body title and a meta subtitle, 12 / 24 padded:
/// one row of the "What's in Plus" sheet.
final class PaywallInfoRowView: UIView {

    enum Leading {
        case image(UIImage?)
        case dot(filled: Bool)
    }

    init(leading: Leading, title: String, subtitle: String) {
        super.init(frame: .zero)

        let leadingView: UIView
        switch leading {
        case .image(let image):
            let imageView = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
            imageView.tintColor = Theme.onSurfaceVariant
            imageView.contentMode = .scaleAspectFit
            imageView.widthAnchor.constraint(equalToConstant: 22).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 22).isActive = true
            leadingView = imageView
        case .dot(let filled):
            let dot = UIView()
            dot.layer.cornerRadius = 5
            if filled {
                dot.backgroundColor = Theme.primary
            } else {
                dot.layer.borderWidth = 1.5
                dot.setDynamicBorderColor(AnycastColor.sandAlpha8)
            }
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
            // The dot sits in a 22 pt cell like the glyphs, so text aligns.
            let cell = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dot)
            NSLayoutConstraint.activate([
                cell.widthAnchor.constraint(equalToConstant: 22),
                dot.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.heightAnchor.constraint(equalToConstant: 22),
            ])
            leadingView = cell
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        subtitleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.adjustsFontForContentSizeCategory = true
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = Spacing.xxs

        let row = UIStackView(arrangedSubviews: [leadingView, labels])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AccountRowView.horizontalInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AccountRowView.horizontalInset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.gap),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.gap),
            heightAnchor.constraint(greaterThanOrEqualToConstant: AccountRowView.minimumHeight),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(subtitle)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
