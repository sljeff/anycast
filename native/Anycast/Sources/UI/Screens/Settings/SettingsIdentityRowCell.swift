import UIKit

/// The Settings account rows (Membership B "SettingsAccount"): the identity
/// row (44 pt avatar, title, subtitle, trailing action text or chevron) and
/// the Plus offer row (title, subtitle, gold action text) under it, both on
/// the surface plate. Fill-only press feedback, like `SettingsRowCell`.
final class SettingsIdentityRowCell: UICollectionViewListCell {

    static let avatarSize: CGFloat = 44

    private let avatarView = UIView()
    private let glyphView = UIImageView()
    private let initialLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionLabel = UILabel()
    private let chevronView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "chevron.forward"))
        view.preferredSymbolConfiguration = IconMetrics.disclosureConfiguration()
        return view
    }()
    private var avatarSideConstraints: [NSLayoutConstraint] = []
    private let rowStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.backgroundColor = AnycastColor.sandAlpha4
        avatarView.layer.cornerRadius = Self.avatarSize / 2
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.contentMode = .center
        glyphView.tintColor = Theme.onSurfaceVariant
        glyphView.image = UIImage(systemName: "person.fill")
        glyphView.preferredSymbolConfiguration = IconMetrics.avatarGlyphConfiguration()
        initialLabel.font = TypographyV2.body.font()
        initialLabel.adjustsFontForContentSizeCategory = true
        initialLabel.textColor = Theme.onSurface
        initialLabel.textAlignment = .center
        for inner in [glyphView, initialLabel] {
            inner.translatesAutoresizingMaskIntoConstraints = false
            avatarView.addSubview(inner)
            NSLayoutConstraint.activate([
                inner.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
                inner.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            ])
        }
        let avatarWidth = avatarView.widthAnchor.constraint(equalToConstant: Self.avatarSize)
        let avatarHeight = avatarView.heightAnchor.constraint(equalToConstant: Self.avatarSize)
        avatarSideConstraints = [avatarWidth, avatarHeight]
        NSLayoutConstraint.activate([avatarWidth, avatarHeight])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: SettingsIdentityRowCell, _) in
            cell.applyAvatarMetrics()
        }
        avatarView.setContentHuggingPriority(.required, for: .horizontal)
        avatarView.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Labels truncate rather than wrap.
        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        actionLabel.font = TypographyV2.meta.font()
        actionLabel.textColor = Theme.primary
        for label in [titleLabel, subtitleLabel, actionLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
        }
        actionLabel.setContentHuggingPriority(.required, for: .horizontal)
        actionLabel.setContentCompressionResistancePriority(UILayoutPriority(740), for: .horizontal)
        chevronView.tintColor = Theme.onSurfaceVariant
        chevronView.contentMode = .center
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = Spacing.xxs
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = Spacing.gap
        for view in [avatarView, textStack, actionLabel, chevronView] {
            rowStack.addArrangedSubview(view)
        }
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)

        let top = rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12)
        let bottom = rowStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        let minimumHeight = contentView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: SettingsRowCell.minimumHeight
        )
        minimumHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: SettingsRowCell.horizontalInset
            ),
            rowStack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -SettingsRowCell.horizontalInset
            ),
            top, bottom, minimumHeight,
        ])

        automaticallyUpdatesBackgroundConfiguration = false
        configurationUpdateHandler = { [unowned self] _, state in
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = (state.isHighlighted || state.isSelected)
                ? AccountStyle.pressed(Theme.surface) : Theme.surface
            self.backgroundConfiguration = background
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Avatar disc tracks title2 with the glyph, from the 44 pt design size.
    private func applyAvatarMetrics() {
        let side = IconMetrics.scaledUp(Self.avatarSize, textStyle: .title2, compatibleWith: traitCollection)
        for constraint in avatarSideConstraints { constraint.constant = side }
        // From the constraint, not the bounds: the disc sits inside a stack
        // that has not laid out yet when the cell's own layout pass runs.
        avatarView.layer.cornerRadius = side / 2
    }

    /// Identity row on the surface plate.
    func configure(identity: AccountPageModel.IdentityContent) {
        apply(title: identity.title, subtitle: identity.subtitle)
        avatarView.isHidden = false
        switch identity.avatar {
        case .glyph:
            glyphView.isHidden = false
            initialLabel.isHidden = true
        case .initial(let letter):
            glyphView.isHidden = true
            initialLabel.isHidden = false
            initialLabel.text = letter
        }
        switch identity.trailing {
        case .action(let text):
            actionLabel.text = text
            actionLabel.isHidden = false
            chevronView.isHidden = true
        case .chevron:
            actionLabel.isHidden = true
            chevronView.isHidden = false
        }
        accessibilityValue = identity.subtitle
    }

    /// The Plus offer row: no avatar, the gold action text trailing.
    func configureUpgrade(subtitle: String, action: String) {
        apply(title: AccountPageModel.upgradePlateTitle, subtitle: subtitle)
        avatarView.isHidden = true
        actionLabel.text = action
        actionLabel.isHidden = false
        chevronView.isHidden = true
        accessibilityValue = subtitle
    }

    private func apply(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        setNeedsUpdateConfiguration()
    }
}
