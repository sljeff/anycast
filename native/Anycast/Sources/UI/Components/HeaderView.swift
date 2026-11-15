import UIKit

/// Shared page header: an Anycast 2.0 display title, a Meta status line and
/// the Settings glass action. Search is its own tab (adopted 2026-10-21), so
/// headers carry no search button.
@MainActor
final class HeaderView: UIView {

    struct Configuration {
        let title: String
        var statusText: String?
        var showsSettings = true

        init(
            title: String,
            statusText: String? = nil,
            showsSettings: Bool = true
        ) {
            self.title = title
            self.statusText = statusText
            self.showsSettings = showsSettings
        }
    }

    var onSettings: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let settingsButton = AnycastIconButton(
        style: .glass,
        icon: AppIcons.settings,
        accessibilityLabel: "Settings",
        diameter: AnycastIconButton.largeDiameter,
        glyphSize: 20
    )

    init() {
        super.init(frame: .zero)

        titleLabel.font = TypographyV2.displayLarge.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        // A long title shrinks a little before it truncates.
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.accessibilityIdentifier = "header-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = TypographyV2.meta.font()
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = TypographyV2.meta.color
        statusLabel.numberOfLines = 1
        statusLabel.accessibilityIdentifier = "header-status"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        configureActions()

        let titleColumn = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        titleColumn.axis = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = Spacing.xs
        titleColumn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleColumn)
        addSubview(settingsButton)

        NSLayoutConstraint.activate([
            titleColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            titleColumn.topAnchor.constraint(equalTo: topAnchor),
            titleColumn.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleColumn.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -Spacing.md),

            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            settingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ configuration: Configuration) {
        titleLabel.text = configuration.title
        statusLabel.text = configuration.statusText
        statusLabel.isHidden = configuration.statusText == nil
        settingsButton.isHidden = !configuration.showsSettings
    }

    private func configureActions() {
        settingsButton.accessibilityIdentifier = "header-settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
    }
}
