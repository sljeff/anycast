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
    private let settingsButton = UIButton(type: .custom)
    private let settingsGlass = GlassContainerView(cornerRadius: Spacing.xxl / 2)
    private var searchFieldTopConstraint: NSLayoutConstraint!
    private var searchFieldHeightConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)

        let displayBase = UIFont.systemFont(ofSize: 48, weight: .black, width: .expanded)
        titleLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: displayBase)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityIdentifier = "header-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .regular)
        )
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
        addSubview(settingsGlass)
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
            titleColumn.trailingAnchor.constraint(lessThanOrEqualTo: settingsGlass.leadingAnchor, constant: -Spacing.md),

            settingsGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            settingsGlass.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            settingsGlass.widthAnchor.constraint(equalToConstant: Spacing.xxl),
            settingsGlass.heightAnchor.constraint(equalToConstant: Spacing.xxl),

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
        settingsGlass.isHidden = !configuration.showsSettings
    }

    private func configureSearchField() {
        let icon = UIImageView(image: AppIcons.search)
        icon.tintColor = Theme.onSurfaceVariant
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
        icon.frame = CGRect(x: 0, y: 0, width: 44, height: 48)

        searchField.leftView = icon
        searchField.leftViewMode = .always
        searchField.placeholder = "Shows, episodes, and more"
        searchField.font = TypographyV2.bodyLarge.font()
        searchField.adjustsFontForContentSizeCategory = true
        searchField.textColor = Theme.onSurface
        searchField.attributedPlaceholder = NSAttributedString(
            string: searchField.placeholder ?? "",
            attributes: [.foregroundColor: Theme.onSurfaceVariant]
        )
        searchField.backgroundColor = Theme.surfaceContainer
        searchField.layer.cornerRadius = Radius.md
        searchField.layer.cornerCurve = .continuous
        searchField.layer.borderWidth = 0.5
        searchField.layer.borderColor = Theme.outlineVariant.resolvedColor(with: traitCollection).cgColor
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.clearButtonMode = .whileEditing
        searchField.accessibilityLabel = "Search"
        searchField.accessibilityIdentifier = "header-search-field"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(self, action: #selector(searchEditingChanged), for: .editingDidBegin)
        searchField.addTarget(self, action: #selector(searchEditingChanged), for: .editingDidEnd)
    }

    private func configureSettingsAction() {
        settingsButton.setImage(AppIcons.settings, for: .normal)
        settingsButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium),
            forImageIn: .normal
        )
        settingsButton.tintColor = Theme.onSurfaceVariant
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.accessibilityIdentifier = "header-settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)

        settingsGlass.translatesAutoresizingMaskIntoConstraints = false
        settingsGlass.backgroundColor = Theme.surfaceContainerHigh
        settingsGlass.layer.shadowColor = UIColor.black.cgColor
        settingsGlass.layer.shadowOpacity = 0.04
        settingsGlass.layer.shadowOffset = CGSize(width: 0, height: 2)
        settingsGlass.layer.shadowRadius = 6
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsGlass.glassContentView.addSubview(settingsButton)
        NSLayoutConstraint.activate([
            settingsButton.leadingAnchor.constraint(equalTo: settingsGlass.glassContentView.leadingAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: settingsGlass.glassContentView.trailingAnchor),
            settingsButton.topAnchor.constraint(equalTo: settingsGlass.glassContentView.topAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: settingsGlass.glassContentView.bottomAnchor),
        ])
    }

    @objc private func searchEditingChanged() {
        searchField.layer.borderColor = (searchField.isFirstResponder ? Theme.primary : Theme.outlineVariant)
            .resolvedColor(with: traitCollection).cgColor
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
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            searchEditingChanged()
        }
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
