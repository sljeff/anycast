import UIKit

/// The v2 page header (Figma `header` component 624:30831 — 09 §3.8): a
/// single row — display title over a 12 pt status caption on the leading
/// side, a 48×48 trailing slot — replacing the v1 gradient AppBar with its
/// embedded search field (search moved to the tab-bar circle).
///
/// Figma details: row padding 0 12; the title sits in a fixed 54 pt-tall
/// row (48 pt displayLarge, UPPERCASE); the caption is SF Pro 12 on sand9
/// (`onSurfaceVariant`), 4 pt under the title row. The component's slot
/// hosts a 3D avatar in the design; the app has no avatars, so the
/// settings gear lives there (the "设置入口随 header 重排" decision).
@MainActor
final class HeaderView: UIView {

    struct Configuration {
        let title: String
        /// The 12 pt caption under the title; `nil` collapses the line
        /// (Figma `Show inbox category=false`).
        var statusText: String?
        /// Shows the trailing settings entry in the slot.
        var showsSettings = true

        init(title: String, statusText: String? = nil, showsSettings: Bool = true) {
            self.title = title
            self.statusText = statusText
            self.showsSettings = showsSettings
        }
    }

    /// The trailing slot's settings entry.
    var onSettings: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let settingsButton = UIButton(type: .custom)

    init() {
        super.init(frame: .zero)

        titleLabel.font = TypographyV2.displayLarge.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.accessibilityIdentifier = "header-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .regular)
        )
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = AnycastColor.sand9
        statusLabel.numberOfLines = 1
        statusLabel.accessibilityIdentifier = "header-status"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.setImage(AppIcons.settings, for: .normal)
        settingsButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24),
            forImageIn: .normal
        )
        settingsButton.tintColor = Theme.onSurface
        settingsButton.backgroundColor = AnycastColor.sandAlpha2
        settingsButton.layer.cornerRadius = Spacing.xxl / 2
        settingsButton.layer.cornerCurve = .continuous
        settingsButton.isAccessibilityElement = true
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.accessibilityIdentifier = "header-settings"
        settingsButton.addAction(
            UIAction { [weak self] _ in self?.onSettings?() },
            for: .touchUpInside
        )
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        let titleColumn = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        titleColumn.axis = .vertical
        titleColumn.spacing = Spacing.xs
        titleColumn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleColumn)
        addSubview(settingsButton)

        NSLayoutConstraint.activate([
            // Page-grid margins (16): the header component's own row padding
            // is 0 12 (Figma), but every screen surface below aligns at 16 —
            // one shared inset beats the component-local value.
            titleColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            // A DETERMINATE vertical chain: the title column spans the
            // header top-to-bottom (its height IS the header height) —
            // centerY-only pins left the height ambiguous and Auto Layout
            // stretched the header over the whole screen (the v2-shell
            // first build collapsed the Inbox list to zero height).
            titleColumn.topAnchor.constraint(equalTo: topAnchor),
            titleColumn.bottomAnchor.constraint(equalTo: bottomAnchor),
            settingsButton.centerYAnchor.constraint(equalTo: titleColumn.centerYAnchor),
            settingsButton.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            settingsButton.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            settingsButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleColumn.trailingAnchor, constant: Spacing.md
            ),

            // The 48 pt slot (Figma avatar slot; also the 44 pt minimum
            // hit target).
            settingsButton.widthAnchor.constraint(equalToConstant: Spacing.xxl),
            settingsButton.heightAnchor.constraint(equalToConstant: Spacing.xxl),

            // The title never compresses below the 54 pt Figma row.
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Static height for hosts that size the header outside auto layout.
    static func fittedHeight(for configuration: Configuration) -> CGFloat {
        configuration.statusText == nil ? 62 : 78
    }

    func configure(_ configuration: Configuration) {
        titleLabel.text = configuration.title.uppercased()
        statusLabel.text = configuration.statusText
        statusLabel.isHidden = configuration.statusText == nil
        settingsButton.isHidden = !configuration.showsSettings
    }
}
