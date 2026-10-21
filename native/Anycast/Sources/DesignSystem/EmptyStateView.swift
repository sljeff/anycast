import UIKit

/// The single empty / error / loading block (Anycast 2.0 UI kit
/// `AnycastContentUnavailable`): a 64 pt tinted disc with a glyph or a
/// spinner, a title, a message, and optional actions, centered in the
/// layout margins (it yields to them when taller). Host it as a collection
/// background (feed `alignBackgroundViewMargins()`) or pin it to a page.
class EmptyStateView: UIView {

    struct Content {
        var icon: UIImage?
        var showsSpinner = false
        var title: String?
        var message: String?
        /// Buttons (or rows of buttons), stacked under the message.
        var actions: [UIView] = []
    }

    private let disc = UIView()
    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionColumn = UIStackView()

    private static let discSize: CGFloat = 64

    init() {
        super.init(frame: .zero)

        disc.backgroundColor = AnycastColor.sandAlpha3
        disc.layer.cornerRadius = Self.discSize / 2
        disc.layer.cornerCurve = .continuous
        disc.translatesAutoresizingMaskIntoConstraints = false

        iconView.tintColor = Theme.primary
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(iconView)

        spinner.color = Theme.primary
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(spinner)

        titleLabel.font = TypographyV2.headlineMedium.font()
        titleLabel.textColor = Theme.onSurface
        messageLabel.font = TypographyV2.bodyLarge.font()
        messageLabel.textColor = Theme.onSurfaceVariant
        for label in [titleLabel, messageLabel] {
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }

        actionColumn.axis = .vertical
        actionColumn.alignment = .center
        actionColumn.spacing = Spacing.md

        let column = UIStackView(arrangedSubviews: [disc, titleLabel, messageLabel, actionColumn])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = Spacing.md
        column.setCustomSpacing(Spacing.cardInner, after: disc)
        column.setCustomSpacing(Spacing.pageHeader, after: messageLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        let center = column.centerYAnchor.constraint(equalTo: layoutMarginsGuide.centerYAnchor)
        center.priority = .defaultHigh
        NSLayoutConstraint.activate([
            disc.widthAnchor.constraint(equalToConstant: Self.discSize),
            disc.heightAnchor.constraint(equalToConstant: Self.discSize),
            iconView.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: disc.centerYAnchor),

            column.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            center,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ content: Content) {
        iconView.image = content.icon
        iconView.isHidden = content.showsSpinner || content.icon == nil
        disc.isHidden = !content.showsSpinner && content.icon == nil
        if content.showsSpinner { spinner.startAnimating() } else { spinner.stopAnimating() }
        titleLabel.text = content.title
        titleLabel.isHidden = content.title == nil
        messageLabel.text = content.message
        messageLabel.isHidden = content.message == nil
        actionColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.actions.forEach(actionColumn.addArrangedSubview)
        actionColumn.isHidden = content.actions.isEmpty
    }
}
