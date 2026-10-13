import UIKit

/// Shared page header: an Anycast 2.0 display title, Settings action, and the
/// Flutter search field with its original submit-to-results behavior.
@MainActor
final class HeaderView: UIView, UITextFieldDelegate {

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

    var onSearch: ((String) -> Void)?
    var onSettings: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let searchField = UITextField()
    private let settingsButton = AnycastIconButton(
        style: .glass,
        icon: AppIcons.settings,
        accessibilityLabel: "Settings",
        diameter: AnycastIconButton.largeDiameter,
        glyphSize: 20
    )
    private var searchFieldTopConstraint: NSLayoutConstraint!
    private var searchFieldHeightConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)

        titleLabel.font = TypographyV2.displayLarge.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityIdentifier = "header-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = TypographyV2.bodySmall.font()
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AnycastColor.sand9
        statusLabel.numberOfLines = 1
        statusLabel.accessibilityIdentifier = "header-status"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        configureSearchField()
        configureSettingsAction()

        let titleColumn = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        titleColumn.axis = .vertical
        titleColumn.alignment = .leading
        titleColumn.spacing = Spacing.xs
        titleColumn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleColumn)
        addSubview(settingsButton)
        addSubview(searchField)

        searchFieldTopConstraint = searchField.topAnchor.constraint(
            equalTo: titleColumn.bottomAnchor, constant: Spacing.gap
        )
        searchFieldHeightConstraint = searchField.heightAnchor.constraint(
            equalToConstant: Self.searchFieldHeight(for: traitCollection)
        )

        NSLayoutConstraint.activate([
            titleColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            titleColumn.topAnchor.constraint(equalTo: topAnchor),
            titleColumn.trailingAnchor.constraint(lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -Spacing.md),

            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            settingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            searchFieldTopConstraint,
            searchFieldHeightConstraint,
            searchField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ configuration: Configuration) {
        titleLabel.text = configuration.title
        statusLabel.text = configuration.statusText
        statusLabel.isHidden = configuration.statusText == nil
        searchField.isHidden = !configuration.showsSearch
        searchField.accessibilityElementsHidden = !configuration.showsSearch
        searchFieldTopConstraint.constant = configuration.showsSearch ? Spacing.gap : 0
        searchFieldHeightConstraint.constant = configuration.showsSearch
            ? Self.searchFieldHeight(for: traitCollection) : 0
        settingsButton.isHidden = !configuration.showsSettings
    }

    private func configureSearchField() {
        searchField.applyAnycastStyle(placeholder: "Shows, episodes, and more", icon: AppIcons.search)
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.clearButtonMode = .whileEditing
        searchField.accessibilityLabel = "Search"
        searchField.accessibilityIdentifier = "header-search-field"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureSettingsAction() {
        settingsButton.accessibilityIdentifier = "header-settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
    }

    @objc private func searchSubmitted() {
        let query = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchField.resignFirstResponder()
        onSearch?(query)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        searchSubmitted()
        return false
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            let showsSearch = !searchField.isHidden
            searchFieldHeightConstraint.constant = showsSearch
                ? Self.searchFieldHeight(for: traitCollection) : 0
        }
    }

    private static func searchFieldHeight(for traits: UITraitCollection) -> CGFloat {
        let textHeight = TypographyV2.bodyLarge.font(traits: traits).lineHeight + Spacing.md * 2
        return max(48, ceil(textHeight))
    }
}
