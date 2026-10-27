import UIKit

/// One row of a Membership plate: a title, an optional meta line, and an
/// optional trailing value or action. Padding is 12 vertical / 24
/// horizontal on a surface plate and 24 all round on the gold plate. When
/// interactive it is a control with fill-only press feedback (`sandAlpha5`
/// over the plate), never a scale.
final class AccountRowView: UIControl {

    static let horizontalInset: CGFloat = 24
    static let minimumHeight: CGFloat = 56

    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let valueLabel = UILabel()

    /// Static rows (Email, Signed in with) do not highlight.
    var showsPressFeedback = true

    private let pressOverlay = UIView()

    init(verticalPadding: CGFloat = 12) {
        super.init(frame: .zero)

        pressOverlay.backgroundColor = AnycastColor.sandAlpha5
        pressOverlay.alpha = 0
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pressOverlay)

        // Labels truncate rather than wrap.
        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        subtitleLabel.isHidden = true
        valueLabel.font = TypographyV2.meta.font()
        valueLabel.textColor = Theme.onSurfaceVariant
        valueLabel.isHidden = true
        for label in [titleLabel, subtitleLabel, valueLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
        }
        titleLabel.setContentCompressionResistancePriority(UILayoutPriority(760), for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(UILayoutPriority(740), for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = Spacing.xxs
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rowStack = UIStackView(arrangedSubviews: [textStack, valueLabel])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = Spacing.gap
        rowStack.isUserInteractionEnabled = false
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        let minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight)
        minimumHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            pressOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            pressOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            pressOverlay.topAnchor.constraint(equalTo: topAnchor),
            pressOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),

            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding),
            minimumHeight,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { pressOverlay.alpha = isHighlighted && showsPressFeedback ? 1 : 0 }
    }

    func setSubtitle(_ text: String?) {
        subtitleLabel.attributedText = nil
        subtitleLabel.text = text
        subtitleLabel.isHidden = text == nil
    }

    func setValue(_ text: String?, color: UIColor = Theme.onSurfaceVariant) {
        valueLabel.text = text
        valueLabel.textColor = color
        valueLabel.isHidden = text == nil
    }
}

/// A rounded fill holding rows with `sandAlpha4` separators inset 24
/// between them. Clips its rows so press overlays follow the corners.
final class AccountPlateView: UIView {

    init(fill: UIColor, rows: [UIView]) {
        super.init(frame: .zero)
        backgroundColor = fill
        layer.cornerRadius = Radius.card
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        for (index, row) in rows.enumerated() {
            if index > 0 { stack.addArrangedSubview(Self.separator()) }
            stack.addArrangedSubview(row)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func separator() -> UIView {
        let wrapper = UIView()
        let line = UIView()
        line.backgroundColor = AnycastColor.sandAlpha4
        line.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: Spacing.hairline),
            line.leadingAnchor.constraint(
                equalTo: wrapper.leadingAnchor, constant: AccountRowView.horizontalInset
            ),
            line.trailingAnchor.constraint(
                equalTo: wrapper.trailingAnchor, constant: -AccountRowView.horizontalInset
            ),
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }
}

/// The AI-transcripts quota: a title row with "<left> of <total> left", a
/// 6 pt bar, and a meta note, on a surface plate with 24 pt padding. One
/// accessibility element.
final class AccountUsageView: UIView {

    static let barHeight: CGFloat = 6

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let noteLabel = UILabel()
    private let bar = UsageBarView()
    private var content: AccountPageModel.UsageContent?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.surface
        layer.cornerRadius = Radius.card
        layer.cornerCurve = .continuous
        clipsToBounds = true

        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        valueLabel.textColor = Theme.onSurfaceVariant
        valueLabel.textAlignment = .right
        noteLabel.font = TypographyV2.meta.font()
        noteLabel.textColor = Theme.onSurfaceVariant
        for label in [titleLabel, valueLabel, noteLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
        }
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(UILayoutPriority(740), for: .horizontal)

        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.alignment = .firstBaseline
        header.spacing = Spacing.gap

        let stack = UIStackView(arrangedSubviews: [header, bar, noteLabel])
        stack.axis = .vertical
        stack.setCustomSpacing(Spacing.chip, after: header)
        stack.setCustomSpacing(Spacing.gap, after: bar)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AccountStyle.goldPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AccountStyle.goldPadding),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: AccountStyle.goldPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AccountStyle.goldPadding),
        ])

        isAccessibilityElement = true
        applyValueFont()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: AccountUsageView, _: UITraitCollection) in view.applyValueFont()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tabular digits so the count does not jitter as it changes.
    private func applyValueFont() {
        valueLabel.font = TypographyV2.meta.font().monospacedDigits()
    }

    func configure(_ usage: AccountPageModel.UsageContent) {
        content = usage
        titleLabel.text = usage.title
        valueLabel.text = usage.valueText
        noteLabel.text = usage.note
        bar.fraction = usage.fraction
        accessibilityLabel = usage.title
        accessibilityValue = usage.accessibilityValue
    }
}

/// Track and fill of the usage bar: `sandAlpha4` track, `primary` fill,
/// radius 3.
private final class UsageBarView: UIView {

    var fraction: Double = 0 { didSet { setNeedsLayout() } }

    private let fill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AnycastColor.sandAlpha4
        layer.cornerRadius = AccountUsageView.barHeight / 2
        fill.backgroundColor = Theme.primary
        fill.layer.cornerRadius = AccountUsageView.barHeight / 2
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width * CGFloat(min(max(fraction, 0), 1))
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
    }
}
