import UIKit

/// The AppBar logo treatment (self-drawn widget #12, 07 §3): title text with
/// a vertical #059669 → transparent gradient (03 §2.2), implemented with a
/// CAGradientLayer mask over the label.
final class GradientTextLabel: UIView {

    private let label = UILabel()
    private let gradientLayer = CAGradientLayer()

    var text: String? {
        didSet {
            label.text = text
            setNeedsLayout()
        }
    }

    /// The semantic style for the label (default: `mainTitle`, 44pt comfortaa
    /// w700 tracking 4.4 per 03 §2.2).
    var style: Typography.Style = .mainTitle {
        didSet { applyStyle() }
    }

    init(style: Typography.Style = .mainTitle) {
        super.init(frame: .zero)
        self.style = style

        isAccessibilityElement = true
        accessibilityTraits = [.staticText]

        label.numberOfLines = 1
        label.adjustsFontForContentSizeCategory = true
        addSubview(label)

        gradientLayer.type = .axial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.colors = [
            Theme.appBarGradientStart.cgColor,
            Theme.appBarGradientEnd.cgColor,
        ]
        gradientLayer.locations = [0, 1]
        gradientLayer.frame = bounds
        layer.mask = gradientLayer

        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // `adjustsFontForContentSizeCategory` does not re-apply on an
        // ATTRIBUTED string — the styled run keeps its old font until this
        // rebuilds it. (layoutSubviews alone only tracks the frame.)
        if traitCollection.preferredContentSizeCategory
            != previousTraitCollection?.preferredContentSizeCategory {
            applyStyle()
        }
    }

    override var intrinsicContentSize: CGSize {
        label.intrinsicContentSize
    }

    private func applyStyle() {
        // The label renders in white; the gradient mask carries the color.
        let attributes = style.attributes()
        label.attributedText = NSAttributedString(
            string: text ?? "",
            attributes: attributes.merging([.foregroundColor: UIColor.white]) { _, new in new }
        )
        accessibilityLabel = text
        setNeedsLayout()
    }
}
