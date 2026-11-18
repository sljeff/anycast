import UIKit

/// Small builders shared by the onboarding views.
@MainActor
enum OnboardingUI {

    /// A multi-line label in a v2 text style that applies its design line
    /// height and follows Dynamic Type.
    static func label(
        _ text: String,
        style: TypographyV2.Style,
        color: UIColor? = nil,
        monospacedDigits: Bool = false
    ) -> UILabel {
        OnboardingStyledLabel(text: text, style: style, color: color, monospacedDigits: monospacedDigits)
    }

    /// Pins a top and a bottom `ScrollEdgeFade` over `host`'s edges so
    /// scrolled content melts into the page instead of being cut.
    static func addEdgeFades(to host: UIView) {
        let top = ScrollEdgeFade(edge: .top)
        let bottom = ScrollEdgeFade(edge: .bottom)
        host.addSubview(top)
        host.addSubview(bottom)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            top.topAnchor.constraint(equalTo: host.topAnchor),
            top.heightAnchor.constraint(equalToConstant: ScrollEdgeFade.fadeLength),

            bottom.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: ScrollEdgeFade.fadeLength),
        ])
    }
}

/// Applies `TypographyV2.Style.attributes(traits:)` so labels honor exact token
/// line heights and recompute both font and line height on Dynamic Type or
/// text changes.
private final class OnboardingStyledLabel: UILabel {

    private let style: TypographyV2.Style
    private let usesMonospacedDigits: Bool
    private var currentColor: UIColor?
    private var rawText: String?
    private var isReady = false
    private var isApplyingStyle = false

    init(text: String, style: TypographyV2.Style, color: UIColor?, monospacedDigits: Bool) {
        self.style = style
        self.currentColor = color
        self.usesMonospacedDigits = monospacedDigits
        self.rawText = text
        super.init(frame: .zero)
        isReady = true
        adjustsFontForContentSizeCategory = true
        numberOfLines = 0
        lineBreakMode = .byWordWrapping
        applyStyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (label: OnboardingStyledLabel, _) in
            label.applyStyle()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var text: String? {
        get { super.text }
        set {
            if isReady {
                rawText = newValue
                applyStyle()
            } else {
                super.text = newValue
            }
        }
    }

    override var textColor: UIColor! {
        get { super.textColor }
        set {
            if isReady {
                currentColor = newValue
                applyStyle()
            } else {
                super.textColor = newValue
            }
        }
    }

    override var lineBreakMode: NSLineBreakMode {
        didSet {
            if isReady, oldValue != lineBreakMode { applyStyle() }
        }
    }

    override var textAlignment: NSTextAlignment {
        didSet {
            if isReady, oldValue != textAlignment { applyStyle() }
        }
    }

    private func applyStyle() {
        guard isReady, !isApplyingStyle else { return }
        isApplyingStyle = true
        defer { isApplyingStyle = false }

        var attributes = style.attributes(traits: traitCollection)
        if usesMonospacedDigits {
            let font = style.monospacedDigitFont(traits: traitCollection)
            let line = style.resolvedLineHeight(for: font, traits: traitCollection)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = line
            paragraph.maximumLineHeight = line
            attributes[.font] = font
            attributes[.paragraphStyle] = paragraph
        }
        if let currentColor {
            attributes[.foregroundColor] = currentColor
        }
        if let existing = attributes[.paragraphStyle] as? NSParagraphStyle,
           let paragraph = existing.mutableCopy() as? NSMutableParagraphStyle {
            paragraph.lineBreakMode = lineBreakMode
            paragraph.alignment = textAlignment
            attributes[.paragraphStyle] = paragraph
        }

        super.font = attributes[.font] as? UIFont
        super.textColor = attributes[.foregroundColor] as? UIColor
        super.attributedText = rawText.map { NSAttributedString(string: $0, attributes: attributes) }
    }
}

// MARK: - Artwork tiles

/// Draws distinct warm-hued editorial tiles in code for the onboarding's
/// sample shows (no image assets, no grey letter placeholders).
@MainActor
enum OnboardingArtworkTile {

    private static var cache: [String: UIImage] = [:]

    static func image(for show: String) -> UIImage {
        if let cached = cache[show] { return cached }
        let side: CGFloat = 88
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            draw(show: show, in: CGRect(x: 0, y: 0, width: side, height: side), cg: context.cgContext)
        }
        cache[show] = image
        return image
    }

    private static func draw(show: String, in rect: CGRect, cg: CGContext) {
        switch show {
        case "Morning Notes":
            drawLinearGradient(
                in: rect, cg: cg,
                colors: [
                    UIColor(red: 0.85, green: 0.42, blue: 0.26, alpha: 1),
                    UIColor(red: 0.78, green: 0.54, blue: 0.29, alpha: 1),
                    UIColor(red: 0.29, green: 0.18, blue: 0.15, alpha: 1),
                ],
                locations: [0, 0.55, 1]
            )
            UIColor(red: 0.97, green: 0.90, blue: 0.77, alpha: 0.92).setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.width * 0.295, y: rect.height * 0.227, width: rect.width * 0.41, height: rect.height * 0.41)).fill()

            let ridge = UIBezierPath()
            ridge.move(to: CGPoint(x: 0, y: rect.height * 0.68))
            ridge.addCurve(
                to: CGPoint(x: rect.width, y: rect.height * 0.68),
                controlPoint1: CGPoint(x: rect.width * 0.30, y: rect.height * 0.59),
                controlPoint2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.59)
            )
            ridge.addLine(to: CGPoint(x: rect.width, y: rect.height))
            ridge.addLine(to: CGPoint(x: 0, y: rect.height))
            ridge.close()
            UIColor(red: 0.17, green: 0.13, blue: 0.11, alpha: 0.80).setFill()
            ridge.fill()

            cg.setLineCap(.round)
            cg.setLineWidth(2.5)
            UIColor(red: 0.97, green: 0.90, blue: 0.77, alpha: 0.55).setStroke()
            cg.move(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.78))
            cg.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.78))
            cg.strokePath()
            UIColor(red: 0.97, green: 0.90, blue: 0.77, alpha: 0.35).setStroke()
            cg.move(to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.87))
            cg.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.height * 0.87))
            cg.strokePath()

        case "Craft & Form":
            drawLinearGradient(
                in: rect, cg: cg,
                colors: [
                    UIColor(red: 0.48, green: 0.22, blue: 0.22, alpha: 1),
                    UIColor(red: 0.28, green: 0.13, blue: 0.14, alpha: 1),
                ],
                locations: [0, 1]
            )
            let arch = UIBezierPath()
            let archLeft = rect.width * 0.27
            let archRight = rect.width * 0.73
            let archBottom = rect.height * 0.84
            let archRadius = (archRight - archLeft) / 2
            let archCenter = CGPoint(x: rect.midX, y: rect.height * 0.48)
            arch.move(to: CGPoint(x: archLeft, y: archBottom))
            arch.addLine(to: CGPoint(x: archLeft, y: archCenter.y))
            arch.addArc(withCenter: archCenter, radius: archRadius, startAngle: .pi, endAngle: 0, clockwise: true)
            arch.addLine(to: CGPoint(x: archRight, y: archBottom))
            arch.close()
            UIColor(red: 0.94, green: 0.90, blue: 0.84, alpha: 0.92).setFill()
            arch.fill()

            UIColor(red: 0.85, green: 0.51, blue: 0.35, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.midX - rect.width * 0.105, y: rect.height * 0.35, width: rect.width * 0.21, height: rect.width * 0.21)).fill()

            UIColor(red: 0.36, green: 0.16, blue: 0.17, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: rect.midX - rect.width * 0.09, y: rect.height * 0.62, width: rect.width * 0.18, height: rect.height * 0.22)).fill()

        default:
            drawLinearGradient(
                in: rect, cg: cg,
                colors: [
                    UIColor(red: 0.33, green: 0.39, blue: 0.29, alpha: 1),
                    UIColor(red: 0.53, green: 0.51, blue: 0.31, alpha: 1),
                    UIColor(red: 0.70, green: 0.57, blue: 0.35, alpha: 1),
                ],
                locations: [0, 0.58, 1]
            )
            let duneBack = UIBezierPath()
            duneBack.move(to: CGPoint(x: 0, y: rect.height * 0.72))
            duneBack.addQuadCurve(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.65), controlPoint: CGPoint(x: rect.width * 0.28, y: rect.height * 0.52))
            duneBack.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.59), controlPoint: CGPoint(x: rect.width * 0.80, y: rect.height * 0.71))
            duneBack.addLine(to: CGPoint(x: rect.width, y: rect.height))
            duneBack.addLine(to: CGPoint(x: 0, y: rect.height))
            duneBack.close()
            UIColor(red: 0.84, green: 0.71, blue: 0.47, alpha: 0.85).setFill()
            duneBack.fill()

            let duneFront = UIBezierPath()
            duneFront.move(to: CGPoint(x: 0, y: rect.height * 0.84))
            duneFront.addQuadCurve(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.79), controlPoint: CGPoint(x: rect.width * 0.38, y: rect.height * 0.67))
            duneFront.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.75), controlPoint: CGPoint(x: rect.width * 0.88, y: rect.height * 0.84))
            duneFront.addLine(to: CGPoint(x: rect.width, y: rect.height))
            duneFront.addLine(to: CGPoint(x: 0, y: rect.height))
            duneFront.close()
            UIColor(red: 0.19, green: 0.24, blue: 0.19, alpha: 0.76).setFill()
            duneFront.fill()

            UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.width * 0.61, y: rect.height * 0.22, width: rect.width * 0.18, height: rect.width * 0.18)).fill()
        }
    }

    private static func drawLinearGradient(
        in rect: CGRect, cg: CGContext, colors: [UIColor], locations: [CGFloat]
    ) {
        let cgColors = colors.map(\.cgColor) as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: locations
        ) else { return }
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
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
            // The fades cover the first and last `fadeLength` points, so
            // content at rest starts and ends clear of them.
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: ScrollEdgeFade.fadeLength),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.pageHeader),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        OnboardingUI.addEdgeFades(to: self)
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
            let delay = Double(position) * Motion.cardEntranceStagger
            let isLast = index == items.indices.last
            animateEntrance(of: view, delay: delay) {
                if isLast { onSettled?() }
            }
        }
    }

    /// Fades `view` out and collapses it smoothly in the column, then calls
    /// `completion`. Reduce Motion collapses it at once.
    func collapse(_ view: UIView, then completion: @escaping () -> Void) {
        guard !Motion.reduceMotion else {
            view.isHidden = true
            completion()
            return
        }
        Motion.animate(Motion.stripFadeOut, { view.alpha = 0 }, completion: { [weak self] in
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction],
                animations: {
                    view.isHidden = true
                    self?.layoutIfNeeded()
                },
                completion: { _ in completion() }
            )
        })
    }

    /// Scrolls just far enough that the bottom of `view` is visible above
    /// the bottom fade; does nothing when it already is.
    func scrollToShow(_ view: UIView) {
        layoutIfNeeded()
        let rect = scrollView.convert(view.bounds, from: view)
            .insetBy(dx: 0, dy: -ScrollEdgeFade.fadeLength)
        scrollView.scrollRectToVisible(rect, animated: !Motion.reduceMotion)
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

    private func scrollToBottom() {
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        guard bottom > -scrollView.adjustedContentInset.top else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: bottom), animated: !Motion.reduceMotion)
    }
}

// MARK: - Bubble

/// The conversation's two voices, in the app's own chat language
/// (`ChatBubbleView`): Anycast speaks plain text across the column, the
/// listener answers in a quiet filled bubble on the trailing side.
final class OnboardingBubbleView: UIView {

    enum Author {
        case anycast
        case listener
    }

    /// Cap on the listener's bubble as a fraction of the column.
    private static let maxWidthFraction: CGFloat = 0.75
    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 10

    init(_ author: Author, text: String) {
        super.init(frame: .zero)

        let label = OnboardingUI.label(text, style: TypographyV2.body, color: Theme.onSurface)
        label.translatesAutoresizingMaskIntoConstraints = false

        switch author {
        case .anycast:
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(equalTo: trailingAnchor),
                label.topAnchor.constraint(equalTo: topAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        case .listener:
            let bubble = UIView()
            bubble.backgroundColor = AnycastColor.sandAlpha4
            bubble.layer.cornerRadius = Radius.md
            bubble.layer.cornerCurve = .continuous
            bubble.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bubble)
            bubble.addSubview(label)
            NSLayoutConstraint.activate([
                bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
                bubble.topAnchor.constraint(equalTo: topAnchor),
                bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: Self.maxWidthFraction),

                label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: Self.horizontalPadding),
                label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -Self.horizontalPadding),
                label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: Self.verticalPadding),
                label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -Self.verticalPadding),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Chip & Timestamp Pill

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
            updated?.baseBackgroundColor = button.isSelected ? AnycastColor.sandAlpha4 : Theme.surface
            updated?.baseForegroundColor = Theme.onSurface
            updated?.background.strokeColor = button.isSelected ? Theme.primary : AnycastColor.sandAlpha3
            updated?.background.strokeWidth = button.isSelected ? 1.5 : 1
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

        let text = NSAttributedString(string: title, attributes: TypographyV2.body.attributes(traits: traitCollection))
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

/// A tappable timestamp citation pill (`▶ 00:42`) in gold (`Theme.primary`),
/// matching `ChatBubbleView`'s jump buttons.
final class OnboardingTimestampPillButton: UIButton {

    private static let minimumHeight: CGFloat = 44

    init(timestamp: String) {
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.filled()
        configuration.title = timestamp
        configuration.cornerStyle = .capsule
        configuration.image = AppIcons.play
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            textStyle: TypographyV2.meta.scalingTextStyle, scale: .small
        )
        configuration.imagePadding = Spacing.sm
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.row, leading: Spacing.chip, bottom: Spacing.row, trailing: Spacing.chip
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.monospacedDigitFont()
            return outgoing
        }
        self.configuration = configuration
        configurationUpdateHandler = { button in
            var updated = button.configuration
            updated?.baseBackgroundColor = button.isSelected ? AnycastColor.sandAlpha4 : AnycastColor.goldAlpha3
            updated?.baseForegroundColor = Theme.primary
            updated?.background.strokeColor = button.isSelected ? Theme.primary : AnycastColor.goldAlpha7
            updated?.background.strokeWidth = button.isSelected ? 1.5 : 1
            button.configuration = updated
        }
        titleLabel?.adjustsFontForContentSizeCategory = true
        accessibilityLabel = OnboardingCopy.jumpToTimestamp(timestamp)
        heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight).isActive = true
        addPressFeedback(scale: Motion.pressScaleSubtle)
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

// MARK: - Grouped plate

/// Rows on one plate, as in the Inbox's grouped list: `GroupedPlateView`'s
/// fill, radius and hairline, and between rows the Inbox's separator (0.5 pt
/// `Theme.outline`) from `separatorInset` to the trailing page edge. The
/// plate clips, so a row's press fill follows its corners.
final class OnboardingGroupedPlate: UIView {

    private static let separatorHeight: CGFloat = 0.5

    /// `separatorInset` is where the rows' text column starts.
    init(rows: [UIView], separatorInset: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = Theme.surface
        layer.cornerRadius = Radius.card
        layer.cornerCurve = .continuous
        layer.borderWidth = Spacing.hairline
        clipsToBounds = true
        updateStroke()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateStroke()
        }

        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // None above the first row, so none after the last.
        for row in rows.dropFirst() {
            let separator = UIView()
            separator.backgroundColor = Theme.outline
            separator.isUserInteractionEnabled = false
            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator)
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: row.topAnchor),
                separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: separatorInset),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
                separator.heightAnchor.constraint(equalToConstant: Self.separatorHeight),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateStroke() {
        layer.borderColor = AnycastColor.sandAlpha3.resolvedColor(with: traitCollection).cgColor
    }
}

// MARK: - Option row

/// A tappable row of a grouped plate: a title, a line of detail and a
/// disclosure chevron. A touch fills the row, never scales it.
final class OnboardingOptionRow: UIControl {

    init(title: String, detail: String) {
        super.init(frame: .zero)

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet {
            let fill = isHighlighted ? AnycastColor.sandAlpha5 : .clear
            UIView.animate(withDuration: isHighlighted ? Motion.pressIn : Motion.quick) {
                self.backgroundColor = fill
            }
        }
    }
}

// MARK: - Playlist tray

/// The "Playlist" tray of the inbox lesson: the sample episodes added so
/// far. Updating it appends rows for newly added episodes and removes rows
/// for removed ones; rows that stay are left alone.
final class OnboardingPlaylistTrayView: UIView {

    private let rowsStack = UIStackView()
    private let emptyLabel = OnboardingUI.label(OnboardingCopy.playlistEmpty, style: TypographyV2.meta)
    private var rows: [(id: String, view: UIView)] = []

    /// Exposed for unit tests to inspect rendered row count and titles.
    var rowCount: Int { rows.count }

    init() {
        super.init(frame: .zero)

        let plate = CardSurfaceView(radius: Radius.card)
        plate.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plate)

        let titleLabel = OnboardingUI.label(OnboardingCopy.playlist, style: TypographyV2.emphasis)
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
        title.numberOfLines = 1
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let minutes = OnboardingUI.label(
            OnboardingCopy.minutes(episode.minutes), style: TypographyV2.meta, monospacedDigits: true
        )
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
