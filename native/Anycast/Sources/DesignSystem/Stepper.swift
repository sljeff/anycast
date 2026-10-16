import UIKit

/// The − | + capsule stepper (Anycast 2.0 UI kit `AnycastStepperView`,
/// shared by the speed and sleep-timer controls). Each tap is one step;
/// the owner applies it and calls `setEnabled` at the range ends.
final class AnycastStepperView: UIView {

    let minusButton = UIButton(type: .system)
    let plusButton = UIButton(type: .system)

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

        Self.configure(minusButton, symbol: "minus", label: minusLabel, tint: tint, action: onMinus)
        Self.configure(plusButton, symbol: "plus", label: plusLabel, tint: tint, action: onPlus)

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
    }

    func setEnabled(minus: Bool, plus: Bool) {
        minusButton.isEnabled = minus
        plusButton.isEnabled = plus
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
        button.addAction(UIAction { _ in
            Haptics.selection()
            action()
        }, for: .touchUpInside)
        button.addPressFeedback(haptic: false)
    }
}
