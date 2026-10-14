import UIKit

/// Shared page header: an Anycast 2.0 display title with Search and Settings
/// glass actions; Search opens the search sheet in its entry state.
@MainActor
final class HeaderView: UIView {

    struct Configuration {
        let title: String
        var statusText: String?
        var showsSearch = true
        var showsSettings = true

        init(
            title: String,
            statusText: String? = nil,
            showsSearch: Bool = true,
            showsSettings: Bool = true
        ) {
            self.title = title
            self.statusText = statusText
            self.showsSearch = showsSearch
            self.showsSettings = showsSettings
        }
    }

    var onSearch: (() -> Void)?
    var onSettings: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let searchButton = AnycastIconButton(
        style: .glass,
        icon: AppIcons.search,
        accessibilityLabel: "Search",
        diameter: AnycastIconButton.largeDiameter,
        glyphSize: 20
    )
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
        // Two action buttons narrow the title column; "Discover" would truncate.
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleLabel.accessibilityIdentifier = "header-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = TypographyV2.bodySmall.font()
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AnycastColor.sand9
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
        addSubview(searchButton)
        addSubview(settingsButton)

        NSLayoutConstraint.activate([
            titleColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            titleColumn.topAnchor.constraint(equalTo: topAnchor),
            titleColumn.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleColumn.trailingAnchor.constraint(lessThanOrEqualTo: searchButton.leadingAnchor, constant: -Spacing.md),

            searchButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -Spacing.md),
            searchButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

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
        searchButton.isHidden = !configuration.showsSearch
        settingsButton.isHidden = !configuration.showsSettings
    }

    private func configureActions() {
        searchButton.accessibilityIdentifier = "header-search"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        settingsButton.accessibilityIdentifier = "header-settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
    }
}
