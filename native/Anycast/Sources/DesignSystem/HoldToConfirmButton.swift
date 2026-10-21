import UIKit

/// A destructive "press and hold to confirm" capsule (e.g. Hold to Clear
/// History). The system control owns the behaviour — every transition runs
/// off UIButton's own control events — and we only paint the look: a tinted
/// fill grows leading → trailing while the finger stays down, and the action
/// fires when it reaches the far edge. One look for iOS 18 and 26.
///
/// Reduce Motion keeps the hold: the fill is progress feedback, not
/// decoration. There is deliberately no press scale. VoiceOver and Switch
/// Control cannot press and hold, so they get `onConfirmRequested` instead
/// and the host shows an inline confirmation.
@MainActor
final class HoldToConfirmButton: UIButton {

    /// Called once when a hold completes.
    var onConfirm: (() -> Void)?
    /// Called instead of the hold when the button is activated by an assistive
    /// technology that cannot press and hold (VoiceOver, Switch Control):
    /// the host shows an inline confirmation instead.
    var onConfirmRequested: (() -> Void)?

    /// Test-only: forces (`true`) or suppresses (`false`) assistive-technology
    /// mode regardless of what the device reports. Leave `nil` in the app.
    static var assistiveTechnologyOverride: Bool?

    private static let minimumHeight: CGFloat = 52
    private static let cancelDuration: TimeInterval = 0.2
    /// Never exactly 0: a zero scale is a singular transform.
    private static let emptyScale: CGFloat = 0.001

    private let idleTitle: String
    private let holdingTitle: String
    private let holdDuration: TimeInterval
    private let fillView = UIView()
    private var animator: UIViewPropertyAnimator?
    private var isHolding = false
    private var isComplete = false

    private var isAssistiveTechnologyActive: Bool {
        Self.assistiveTechnologyOverride
            ?? (UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning)
    }

    init(title: String, holdingTitle: String, image: UIImage?, holdDuration: TimeInterval = 1.2) {
        self.idleTitle = title
        self.holdingTitle = holdingTitle
        self.holdDuration = holdDuration
        super.init(frame: .zero)

        // The tint lives on the view itself, not in the configuration's
        // background view, so the fill (subview 0) paints above it and below
        // the title and image.
        var configuration = UIButton.Configuration.plain()
        configuration.background.backgroundColor = .clear
        configuration.baseForegroundColor = Theme.error
        configuration.cornerStyle = .capsule
        configuration.title = title
        configuration.image = image
        configuration.imagePadding = Spacing.md
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.gap, leading: Spacing.cardInner, bottom: Spacing.gap, trailing: Spacing.cardInner
        )
        // Full-strength colour while pressed: the fill is the press feedback,
        // so the plain style's highlight dimming is overridden.
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.headlineSmall.font()
            outgoing.foregroundColor = Theme.error
            return outgoing
        }
        configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in Theme.error }
        self.configuration = configuration
        titleLabel?.adjustsFontForContentSizeCategory = true

        backgroundColor = AnycastColor.sandAlpha4
        clipsToBounds = true
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight).isActive = true

        fillView.isUserInteractionEnabled = false
        fillView.backgroundColor = UIColor { traits in
            Theme.error.resolvedColor(with: traits).withAlphaComponent(0.18)
        }
        fillView.layer.anchorPoint = CGPoint(x: isRightToLeft ? 1 : 0, y: 0.5)
        fillView.transform = Self.emptyTransform
        // Hidden at rest: even the near-zero scale leaves a visible hairline.
        fillView.alpha = 0
        insertSubview(fillView, at: 0)

        addAction(UIAction { [weak self] _ in self?.touchDown() }, for: .touchDown)
        addAction(UIAction { [weak self] _ in self?.touchUpInside() }, for: .touchUpInside)
        addAction(
            UIAction { [weak self] _ in self?.cancelHold() },
            for: [.touchUpOutside, .touchCancel, .touchDragExit]
        )
        refreshAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Returns to the idle look immediately (no animation), e.g. after Undo.
    func reset() {
        animator?.stopAnimation(true)
        animator = nil
        isHolding = false
        isComplete = false
        fillView.transform = Self.emptyTransform
        fillView.alpha = 0
        configuration?.title = idleTitle
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        // Frame-based layout would fight the anchor point and transform, so
        // the fill's bounds and position are set directly.
        let anchor = fillView.layer.anchorPoint
        fillView.layer.bounds = CGRect(origin: .zero, size: bounds.size)
        fillView.layer.position = CGPoint(x: bounds.width * anchor.x, y: bounds.height / 2)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshAccessibility()
    }

    override func accessibilityActivate() -> Bool {
        onConfirmRequested?()
        return true
    }

    // MARK: - Hold

    private var isRightToLeft: Bool { effectiveUserInterfaceLayoutDirection == .rightToLeft }

    private static var emptyTransform: CGAffineTransform {
        CGAffineTransform(scaleX: emptyScale, y: 1)
    }

    private func touchDown() {
        refreshAccessibility()
        guard !isAssistiveTechnologyActive, !isComplete, !isHolding else { return }
        isHolding = true
        configuration?.title = holdingTitle
        Haptics.tap()
        // The anchor follows the reading direction, which can change after init.
        let anchorX: CGFloat = isRightToLeft ? 1 : 0
        if fillView.layer.anchorPoint.x != anchorX {
            fillView.layer.anchorPoint = CGPoint(x: anchorX, y: 0.5)
            setNeedsLayout()
            layoutIfNeeded()
        }
        fillView.alpha = 1
        let fill = UIViewPropertyAnimator(duration: holdDuration, curve: .linear) { [fillView] in
            fillView.transform = .identity
        }
        fill.addCompletion { [weak self] position in
            guard position == .end else { return }
            self?.completeHold()
        }
        animator = fill
        fill.startAnimation()
    }

    private func touchUpInside() {
        if isAssistiveTechnologyActive, !isComplete {
            onConfirmRequested?()
            return
        }
        cancelHold()
    }

    /// Reverses from wherever the fill currently is; a completed hold stays filled.
    private func cancelHold() {
        guard isHolding, !isComplete else { return }
        isHolding = false
        animator?.stopAnimation(false)
        animator?.finishAnimation(at: .current)
        let back = UIViewPropertyAnimator(duration: Self.cancelDuration, curve: .easeOut) { [fillView] in
            fillView.transform = Self.emptyTransform
        }
        back.addCompletion { [weak self] position in
            guard position == .end, let self, !self.isHolding else { return }
            self.fillView.alpha = 0
        }
        animator = back
        back.startAnimation()
        configuration?.title = idleTitle
    }

    private func completeHold() {
        guard isHolding, !isComplete else { return }
        isComplete = true
        isHolding = false
        Haptics.confirm()
        onConfirm?()
    }

    private func refreshAccessibility() {
        accessibilityLabel = idleTitle
        accessibilityTraits = .button
        accessibilityHint = isAssistiveTechnologyActive ? nil : "Press and hold to confirm."
    }
}
