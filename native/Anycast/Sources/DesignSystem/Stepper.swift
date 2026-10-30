import UIKit

/// The − | + capsule stepper (Anycast 2.0 UI kit `AnycastStepperView`,
/// shared by the speed and sleep-timer controls). Each tap is one step;
/// the owner applies it and calls `setEnabled` at the range ends.
///
/// While a half is pressed a `sandAlpha4` pill (that half of the capsule,
/// clipped to its contour) fades in over the capsule fill and out on
/// release; the selection haptic fires once, on touch-down.
final class AnycastStepperView: UIView {

    let minusButton = UIButton(type: .system)
    let plusButton = UIButton(type: .system)
    /// Pressed-state pills, one per half, laid out in `layoutSubviews`.
    let minusHighlight = UIView()
    let plusHighlight = UIView()

    init(
        background: UIColor = AnycastColor.sandAlpha4,
        tint: UIColor = Theme.onSurface,
        divider dividerColor: UIColor = AnycastColor.sandAlpha8,
        minusLabel: String,
        plusLabel: String,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) {
        super.init(frame: .zero)
        backgroundColor = background
        layer.cornerCurve = .continuous
        // Clips the half pills to the capsule contour.
        clipsToBounds = true

        for highlight in [minusHighlight, plusHighlight] {
            highlight.backgroundColor = AnycastColor.sandAlpha4
            highlight.alpha = 0
            highlight.isUserInteractionEnabled = false
            addSubview(highlight)
        }

        Self.configure(minusButton, symbol: "minus", label: minusLabel, tint: tint, action: onMinus)
        Self.configure(plusButton, symbol: "plus", label: plusLabel, tint: tint, action: onPlus)
        bindHighlight(of: minusButton, to: minusHighlight)
        bindHighlight(of: plusButton, to: plusHighlight)

        let divider = UIView()
        divider.backgroundColor = dividerColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: Spacing.hairline),
            divider.heightAnchor.constraint(equalToConstant: Spacing.pageH),
        ])

        let stack = UIStackView(arrangedSubviews: [minusButton, divider, plusButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xs),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let half = bounds.width / 2
        minusHighlight.frame = CGRect(x: 0, y: 0, width: half, height: bounds.height)
        plusHighlight.frame = CGRect(x: half, y: 0, width: half, height: bounds.height)
    }

    func setEnabled(minus: Bool, plus: Bool) {
        minusButton.isEnabled = minus
        plusButton.isEnabled = plus
    }

    /// Touch-down shows the pill and fires the haptic (an enabled button
    /// only — a disabled one gets no touch events); release, cancel or
    /// dragging out hides it. Reduce Motion toggles without a fade.
    private func bindHighlight(of button: UIButton, to highlight: UIView) {
        button.addAction(UIAction { [weak button] _ in
            guard button?.isEnabled == true else { return }
            Haptics.selection()
            Self.setHighlight(highlight, visible: true)
        }, for: .touchDown)
        button.addAction(UIAction { [weak button] _ in
            guard button?.isEnabled == true else { return }
            Self.setHighlight(highlight, visible: true)
        }, for: .touchDragEnter)
        button.addAction(UIAction { _ in
            Self.setHighlight(highlight, visible: false)
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    private static func setHighlight(_ highlight: UIView, visible: Bool) {
        let alpha: CGFloat = visible ? 1 : 0
        guard !Motion.reduceMotion else {
            highlight.layer.removeAllAnimations()
            highlight.alpha = alpha
            return
        }
        UIView.animate(
            withDuration: visible ? Motion.pressIn : Motion.pressRelease,
            delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]
        ) { highlight.alpha = alpha }
    }

    private static func configure(
        _ button: UIButton, symbol: String, label: String, tint: UIColor, action: @escaping () -> Void
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = IconStyle.stepperControl.configuration
        configuration.baseForegroundColor = tint
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
            button.heightAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addPressFeedback(haptic: false)
    }
}
