import UIKit

/// Small builders shared by the onboarding views.
@MainActor
enum OnboardingUI {

    /// A multi-line label in a v2 text style that follows Dynamic Type.
    static func label(_ text: String, style: TypographyV2.Style, color: UIColor? = nil) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = style.font()
        label.textColor = color ?? style.color
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }
}

// MARK: - Thread

/// A scrolling column of onboarding content. Items are only ever appended:
/// each one plays its entrance once, when it first appears, and nothing
/// already on screen is rebuilt when a later item arrives.
final class OnboardingThreadView: UIView {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var hasPlayedEntrance = false

    init() {
        super.init(frame: .zero)

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = Spacing.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Spacing.md),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.pageHeader),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Adds `view` under everything already shown. Before the step's first
    /// appearance this only builds the column; afterwards the new item
    /// animates in and the column scrolls to show it.
    func append(_ view: UIView, spacingBefore: CGFloat? = nil) {
        if let spacingBefore, let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(spacingBefore, after: last)
        }
        stack.addArrangedSubview(view)
        guard hasPlayedEntrance else { return }
        layoutIfNeeded()
        animateEntrance(of: view, delay: 0)
        scrollToBottom()
    }

    /// Plays the staggered entrance of the items built before the step was
    /// shown. Only the first call does anything. `onSettled` runs when the
    /// last item's animation has finished — immediately when the entrance
    /// is skipped (already played, or Reduce Motion).
    func playEntranceIfNeeded(onSettled: (() -> Void)? = nil) {
        guard !hasPlayedEntrance else {
            onSettled?()
            return
        }
        hasPlayedEntrance = true
        let items = stack.arrangedSubviews
        guard !Motion.reduceMotion, !items.isEmpty else {
            onSettled?()
            return
        }
        for (index, view) in items.enumerated() {
            let position = min(index, Motion.cardEntranceMaxStaggered)
            let delay = Double(position) * Motion.cardEntranceStagger * 2
            let isLast = index == items.indices.last
            animateEntrance(of: view, delay: delay) {
                if isLast { onSettled?() }
            }
        }
    }

    private func animateEntrance(of view: UIView, delay: TimeInterval, completion: (() -> Void)? = nil) {
        guard !Motion.reduceMotion else {
            completion?()
            return
        }
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: Motion.cardEntranceOffset)
        UIView.animate(
            withDuration: Motion.standard,
            delay: delay,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                view.alpha = 1
                view.transform = .identity
            },
            completion: { _ in completion?() }
        )
    }

    /// Scrolls so `view` is visible, without animation. Used before the
    /// queue lesson's fly-in: its endpoint is sampled from the tray's
    /// position at animation start, so the tray must already be on screen.
    func reveal(_ view: UIView) {
        let rect = view.convert(view.bounds, to: scrollView)
        scrollView.scrollRectToVisible(rect, animated: false)
    }

    private func scrollToBottom() {
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        guard bottom > -scrollView.adjustedContentInset.top else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: !Motion.reduceMotion)
    }
}

// MARK: - Bubble

/// A chat bubble: Anycast's on the leading side on a surface plate, the
/// listener's on the trailing side in the inverse ink.
final class OnboardingBubbleView: UIView {

    enum Author {
        case anycast
        case listener
    }

    private static let maxWidthFraction: CGFloat = 0.86

    init(_ author: Author, text: String) {
        super.init(frame: .zero)

        let plate = UIView()
        plate.backgroundColor = author == .anycast ? Theme.surface : Theme.onSurface
        plate.layer.cornerRadius = Radius.card
        plate.layer.cornerCurve = .continuous
        plate.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)

        let label = OnboardingUI.label(
            text, style: TypographyV2.body, color: author == .anycast ? Theme.onSurface : Theme.surface
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(label)

        let side: NSLayoutConstraint
        let slack: NSLayoutConstraint
        switch author {
        case .anycast:
            side = plate.leadingAnchor.constraint(equalTo: leadingAnchor)
            slack = plate.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        case .listener:
            side = plate.trailingAnchor.constraint(equalTo: trailingAnchor)
            slack = plate.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
        }
        NSLayoutConstraint.activate([
            side,
            slack,
            plate.topAnchor.constraint(equalTo: topAnchor),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor),
            plate.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: Self.maxWidthFraction),

            label.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.pageH),
            label.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.pageH),
            label.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.gap),
            label.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.gap),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Chip

/// A capsule chip. Selection is the button's own `isSelected`, so a tap
/// restyles only this chip; VoiceOver reads the selected state from it.
final class OnboardingChipButton: UIButton {

    private static let minimumHeight: CGFloat = 44

    init(title: String) {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.cornerStyle = .capsule
        // A chip wider than its row wraps instead of truncating, so the
        // flow layout can give it a taller frame at large text sizes.
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.row, leading: Spacing.pageH, bottom: Spacing.row, trailing: Spacing.pageH
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.body.font()
            return outgoing
        }
        self.configuration = configuration
        configurationUpdateHandler = { button in
            var updated = button.configuration
            updated?.baseBackgroundColor = button.isSelected ? Theme.onSurface : Theme.surface
            updated?.baseForegroundColor = button.isSelected ? Theme.surface : Theme.onSurface
            button.configuration = updated
        }
        titleLabel?.adjustsFontForContentSizeCategory = true
        accessibilityLabel = title
        heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight).isActive = true
        addPressFeedback(scale: Motion.pressScaleSubtle)
    }

    /// Stops the chip from answering again after a one-shot answer. The
    /// `.notEnabled` trait keeps VoiceOver from announcing a dead control
    /// as tappable.
    func disableAnswering() {
        isUserInteractionEnabled = false
        accessibilityTraits.insert(.notEnabled)
    }

    /// Self-sizing against a constrained width. A configured button's
    /// standard measurement keeps its title on one line even when
    /// `titleLineBreakMode` says wrap — measure the wrapped title
    /// directly, honoring the configuration's insets, so a chip wider
    /// than its row reports a narrower, taller size instead of
    /// overflowing its capsule.
    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        let singleLine = super.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalFittingPriority,
            verticalFittingPriority: verticalFittingPriority
        )
        guard singleLine.width > targetSize.width, let title = configuration?.title else {
            return singleLine
        }
        let insets = configuration?.contentInsets ?? NSDirectionalEdgeInsets()
        let maxWidth = targetSize.width - insets.leading - insets.trailing
        guard maxWidth > 0 else { return singleLine }

        let text = NSAttributedString(string: title, attributes: [.font: TypographyV2.body.font()])
        let textBounds = text.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = max(Self.minimumHeight, ceil(textBounds.height) + insets.top + insets.bottom)
        return CGSize(width: targetSize.width, height: height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Lays its subviews out left to right, wrapping to a new row when the
/// next one does not fit. Its height follows its content.
final class OnboardingFlowLayoutView: UIView {

    private let spacing: CGFloat = Spacing.md
    private var contentHeight: CGFloat = 44

    init(items: [UIView]) {
        super.init(frame: .zero)
        for item in items { addSubview(item) }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: OnboardingFlowLayoutView, _) in
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for item in subviews where !item.isHidden {
            var size = item.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if size.width > width {
                // Wider than the whole row: it wraps onto its own line.
                // Remeasure at the constrained width so wrapped text gets
                // a taller frame instead of overflowing the capsule.
                size = item.systemLayoutSizeFitting(
                    CGSize(width: width, height: UIView.layoutFittingExpandedSize.height),
                    withHorizontalFittingPriority: .required,
                    verticalFittingPriority: .fittingSizeLevel
                )
            }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            // Bounds and center, not frame: a pressed chip carries a scale
            // transform, and a frame set under a transform is undefined.
            item.bounds = CGRect(origin: .zero, size: size)
            item.center = CGPoint(x: x + size.width / 2, y: y + size.height / 2)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let height = y + rowHeight
        if abs(height - contentHeight) > 0.5 {
            contentHeight = height
            invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - Option row

/// A tappable row with a title, a line of detail and a disclosure chevron.
final class OnboardingOptionRow: UIControl {

    init(title: String, detail: String) {
        super.init(frame: .zero)

        backgroundColor = Theme.surface
        layer.cornerRadius = Radius.card
        layer.cornerCurve = .continuous

        let titleLabel = OnboardingUI.label(title, style: TypographyV2.emphasis)
        let detailLabel = OnboardingUI.label(detail, style: TypographyV2.meta)
        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs

        let chevron = UIImageView(image: AppIcons.disclosure)
        chevron.tintColor = Theme.onSurfaceVariant
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [texts, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        // Touches fall through to the control.
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.chip),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.chip),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(detail)"
        accessibilityTraits = .button
        addPressFeedback(scale: Motion.pressScaleSubtle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Waveform

/// The welcome step's decorative waveform: a row of bars that breathe out
/// of step with each other. Reduce Motion leaves the bars still.
final class OnboardingWaveformView: UIView {

    private static let levels: [CGFloat] = [0.3, 0.55, 0.85, 0.5, 0.7, 1, 0.6, 0.8, 0.45, 0.65, 0.35]
    private static let barWidth: CGFloat = 4
    private static let maxBarHeight: CGFloat = 44
    private static let animationKey = "onboarding.wave"

    private var bars: [UIView] = []

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = false

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.sm
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        for level in Self.levels {
            let bar = UIView()
            bar.backgroundColor = Theme.onSurfaceVariant
            bar.alpha = 0.55
            bar.layer.cornerRadius = Self.barWidth / 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: Self.barWidth),
                bar.heightAnchor.constraint(equalToConstant: Self.maxBarHeight * level),
            ])
            row.addArrangedSubview(bar)
            bars.append(bar)
        }

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Self.maxBarHeight),
        ])

        // Layer animations are dropped when the app leaves the foreground.
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAnimation),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshAnimation),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshAnimation()
    }

    @objc private func refreshAnimation() {
        for bar in bars { bar.layer.removeAnimation(forKey: Self.animationKey) }
        guard window != nil, !Motion.reduceMotion else { return }
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = 1
            animation.toValue = 0.4
            animation.duration = 0.9 + Double(index % 3) * 0.2
            animation.beginTime = now + Double(index) * 0.09
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.layer.add(animation, forKey: Self.animationKey)
        }
    }
}

// MARK: - Up Next tray

/// The "Up Next" tray of the queue lesson and the last step: the sample
/// episodes added so far. Updating it appends rows for newly added episodes
/// and removes rows for removed ones; rows that stay are left alone.
final class OnboardingUpNextTrayView: UIView {

    private let rowsStack = UIStackView()
    private let emptyLabel = OnboardingUI.label(OnboardingCopy.upNextEmpty, style: TypographyV2.meta)
    private var rows: [(id: String, view: UIView)] = []

    init() {
        super.init(frame: .zero)

        let plate = CardSurfaceView(radius: Radius.card)
        plate.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)

        let titleLabel = OnboardingUI.label(OnboardingCopy.upNext, style: TypographyV2.emphasis)
        titleLabel.accessibilityTraits = .header

        rowsStack.axis = .vertical
        rowsStack.spacing = Spacing.md

        let column = UIStackView(arrangedSubviews: [titleLabel, emptyLabel, rowsStack])
        column.axis = .vertical
        column.spacing = Spacing.md
        column.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(column)
        rowsStack.isHidden = true

        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: trailingAnchor),
            plate.topAnchor.constraint(equalTo: topAnchor),
            plate.bottomAnchor.constraint(equalTo: bottomAnchor),

            column.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.pageH),
            column.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.pageH),
            column.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.chip),
            column.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.chip),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setEpisodes(_ episodes: [OnboardingSampleEpisode], animated: Bool) {
        let ids = Set(episodes.map(\.id))
        for row in rows where !ids.contains(row.id) {
            rowsStack.removeArrangedSubview(row.view)
            row.view.removeFromSuperview()
        }
        rows.removeAll { !ids.contains($0.id) }

        for episode in episodes where !rows.contains(where: { $0.id == episode.id }) {
            let view = Self.makeRow(episode)
            rowsStack.addArrangedSubview(view)
            rows.append((episode.id, view))
            if animated, !Motion.reduceMotion {
                view.alpha = 0
                Motion.animate { view.alpha = 1 }
            }
        }

        emptyLabel.isHidden = !rows.isEmpty
        rowsStack.isHidden = rows.isEmpty
    }

    private static func makeRow(_ episode: OnboardingSampleEpisode) -> UIView {
        let title = OnboardingUI.label(episode.title, style: TypographyV2.body)
        let minutes = OnboardingUI.label(OnboardingCopy.minutes(episode.minutes), style: TypographyV2.meta)
        minutes.numberOfLines = 1
        minutes.setContentHuggingPriority(.required, for: .horizontal)
        minutes.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [title, minutes])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Spacing.gap
        return row
    }
}
