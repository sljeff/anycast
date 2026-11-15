import UIKit

/// A tinted capsule holding a row of icon buttons (Anycast 2.0 UI kit
/// `AnycastButtonGroup`, fixed layout): buttons hug their content at a
/// fixed spacing; the capsule follows the row's height.
final class AnycastButtonGroup: UIView {

    let stack = UIStackView()

    init(
        buttons: [UIView],
        background: UIColor,
        spacing: CGFloat = Spacing.pageHeader,
        insets: NSDirectionalEdgeInsets = .init(top: Spacing.md, leading: Spacing.large, bottom: Spacing.md, trailing: Spacing.large)
    ) {
        super.init(frame: .zero)
        backgroundColor = background
        layer.cornerCurve = .continuous

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.forEach(stack.addArrangedSubview)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.leading),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.trailing),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
