import UIKit
import Kingfisher
import AnycastKit

/// Value payload for the v2 inbox card (09 §10 批次1, component 744:9107):
/// text-forward — the v1 cover-row card (EpisodeCardCell) stays for the
/// Channel/Search/Playlist/History lists until their own batches.
struct InboxCardContent {
    var title: String
    /// The show name under the state row's 36pt cover ("Just pod" slot).
    var showName: String
    /// "Nov 21, 2025"-style date beside the show name.
    var dateText: String
    /// The gold pill ("episode count" property; duration mapping pending
    /// design review — frames show a fixed "99+").
    var badgeText: String
    var descriptionHTML: String?
    var imageURL: String?
    var descriptionPlainText: String?
}

/// The v2 inbox card (Figma Container `363:3558` type=inbox card
/// `744:9107`, 2026-10-02 component + frame render re-measured): surface
/// card, hairline sandAlpha3 stroke, shadow 0/1/20 4%, radius 34 (the
/// component value — §5's earlier "radius16" note was a misread); a
/// 17pt uppercase title over a 14pt description, and a 60pt state row
/// (36pt circular show cover · show name + date at 12pt · gold count
/// pill · `more` menu button). Whole-card tap opens the Detail sheet;
/// the `more` button pulls down the same UIMenu the long-press context
/// menu shows (09 §7a-C1 batch-1 completion).
///
/// The inter-card gap (Figma scroll column gap 12) is baked into the cell
/// as 6pt top + 6pt bottom insets — the card section is a list section
/// (swipe actions) and list sections carry no inter-item spacing.
final class InboxEpisodeCardCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxEpisodeCardCell"
    /// Half of the 12pt Figma column gap on each side of the card.
    static let verticalGap: CGFloat = 6
    static let cardRadius: CGFloat = 34
    static let stateRowHeight: CGFloat = 60

    /// Whole-card tap → open the Detail sheet.
    var onCardTap: (() -> Void)?
    /// The context-menu payload, mirrored for VoiceOver custom actions and
    /// rendered as the `more` button's pull-down menu (09 §7a-C1).
    var menuActions: [EpisodeCardAction] = [] {
        didSet { applyMenuActions() }
    }

    private let cardContainer = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let coverView = UIImageView()
    private let showNameLabel = UILabel()
    private let dateLabel = UILabel()
    private let badgeLabel = UILabel()
    let moreButton = UIButton(type: .system)

    private var descriptionTask: Task<Void, Never>?
    /// Guards the cover load against reconfigure storms (EpisodeCardCell
    /// precedent: an unconditional reload restarts an in-flight download).
    private var renderedCoverURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        descriptionTask?.cancel()
        descriptionTask = nil
        onCardTap = nil
        menuActions = []
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cardContainer.layer.shadowPath = UIBezierPath(
            roundedRect: cardContainer.bounds, cornerRadius: Self.cardRadius
        ).cgPath
    }

    // MARK: - Configure

    func configure(_ content: InboxCardContent) {
        // TITLE-case display language (component textStyle textCase: TITLE);
        // VoiceOver reads the original casing.
        titleLabel.text = content.title.localizedUppercase
        titleLabel.accessibilityLabel = content.title
        showNameLabel.text = content.showName.localizedUppercase
        dateLabel.text = content.dateText
        badgeLabel.text = content.badgeText

        if let plain = content.descriptionPlainText {
            descriptionLabel.text = plain
        } else if let html = content.descriptionHTML {
            descriptionTask?.cancel()
            descriptionLabel.text = ""
            descriptionTask = Task { [weak self] in
                let text = await PlainTextHTMLCache.shared.plainText(for: html)
                guard let self, !Task.isCancelled else { return }
                self.descriptionLabel.text = text
                // Resolve the label's frame in THIS turn — the card's height
                // hangs off an inequality, so a mere setNeedsLayout lets the
                // label sit at its zero-height frame until some later pass
                // (walk-based tests see "text but zero height" mid-flight).
                // The follow-up tick covers the case where the text lands
                // before the list section gave the cell its final frame.
                self.invalidateIntrinsicContentSize()
                self.setNeedsLayout()
                self.layoutIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    self?.layoutIfNeeded()
                }
            }
        } else {
            descriptionLabel.text = ""
        }

        let url = content.imageURL.flatMap(URL.init(string:))
        if url != renderedCoverURL {
            renderedCoverURL = url
            coverView.kf.cancelDownloadTask()
            coverView.kf.setImage(with: url, placeholder: nil, options: [.transition(.none)])
        }
    }

    // MARK: - Build

    private func build() {
        contentView.backgroundColor = .clear

        cardContainer.backgroundColor = Theme.surface
        cardContainer.layer.borderWidth = 1
        cardContainer.layer.cornerRadius = Self.cardRadius
        cardContainer.layer.cornerCurve = .continuous
        cardContainer.layer.shadowColor = UIColor.black.cgColor
        cardContainer.layer.shadowOpacity = 0.04
        cardContainer.layer.shadowOffset = CGSize(width: 0, height: 1)
        cardContainer.layer.shadowRadius = 10
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardContainer)
        cardContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        )
        cardContainer.isAccessibilityElement = false

        let titleMetrics = UIFontMetrics(forTextStyle: .body)
        titleLabel.font = titleMetrics.scaledFont(for: .systemFont(ofSize: 17, weight: .regular))
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 3
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        // The card action for VoiceOver (sighted users tap the whole card);
        // the menu payload hangs off it as custom actions below.
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = [.button]

        let descriptionMetrics = UIFontMetrics(forTextStyle: .subheadline)
        descriptionLabel.font = descriptionMetrics.scaledFont(
            for: .systemFont(ofSize: 14, weight: .regular)
        )
        descriptionLabel.textColor = Theme.onSurfaceVariant
        descriptionLabel.numberOfLines = 3
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.lineBreakMode = .byTruncatingTail
        // Same regression hook as the v1 card: tests assert the async
        // description gains a non-zero frame once the text lands.
        descriptionLabel.accessibilityIdentifier = "episode-card-description"

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.spacing = 4
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(textColumn)

        // State row (component #744:9112): 36pt circular show cover, show
        // name + date at 12pt (gap 12), gold count pill, more button.
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 18
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHighest
        coverView.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(coverView)

        let metaMetrics = UIFontMetrics(forTextStyle: .caption1)
        showNameLabel.font = metaMetrics.scaledFont(for: .systemFont(ofSize: 12, weight: .regular))
        showNameLabel.textColor = Theme.onSurfaceVariant
        showNameLabel.adjustsFontForContentSizeCategory = true
        showNameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        dateLabel.font = metaMetrics.scaledFont(for: .systemFont(ofSize: 12, weight: .regular))
        dateLabel.textColor = Theme.onSurfaceVariant
        dateLabel.adjustsFontForContentSizeCategory = true

        let metaRow = UIStackView(arrangedSubviews: [showNameLabel, dateLabel])
        metaRow.axis = .horizontal
        metaRow.spacing = 12
        metaRow.alignment = .center
        metaRow.distribution = .fill
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(metaRow)

        let badge = UIView()
        badge.backgroundColor = AnycastColor.goldAlpha3
        badge.layer.cornerRadius = 18
        badge.layer.cornerCurve = .continuous
        badge.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(badge)

        badgeLabel.font = descriptionMetrics.scaledFont(
            for: .systemFont(ofSize: 14, weight: .regular)
        )
        badgeLabel.textColor = AnycastColor.goldAlpha9
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeLabel)

        moreButton.setImage(AppIcons.more, for: .normal)
        moreButton.tintColor = AnycastColor.sandAlpha9
        moreButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24), forImageIn: .normal
        )
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "More actions"
        moreButton.accessibilityIdentifier = "inbox-card-more"
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(moreButton)

        // The context column ends 8pt above the 60pt state row (the
        // component row's bottom padding); without this the card height is
        // underdetermined and the text can overlap the state row.
        // defaultHigh, not required: in a context that pins the cell to a
        // stale height (private-shell windows before self-sizing measures),
        // a required guard crushes the description to zero height instead
        // of overflowing — degrade to overlap there.
        let bottomGuard = textColumn.bottomAnchor.constraint(
            lessThanOrEqualTo: cardContainer.bottomAnchor,
            constant: -(Self.stateRowHeight + 8)
        )
        bottomGuard.priority = .defaultHigh

        NSLayoutConstraint.activate([
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalGap),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalGap),

            textColumn.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 20),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -20),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 16),
            bottomGuard,

            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 16),
            coverView.centerYAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -Self.stateRowHeight / 2),
            coverView.widthAnchor.constraint(equalToConstant: 36),
            coverView.heightAnchor.constraint(equalToConstant: 36),

            metaRow.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 10),
            metaRow.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
            metaRow.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -12),

            badge.centerYAnchor.constraint(equalTo: coverView.centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor),
            badge.heightAnchor.constraint(equalToConstant: 36),
            badgeLabel.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 16),
            badgeLabel.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -16),
            badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            moreButton.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            moreButton.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 60),
            moreButton.heightAnchor.constraint(equalToConstant: 60),
        ])
    }

    // MARK: - Actions

    /// The menu payload in three shapes: the more button's pull-down menu,
    /// and VoiceOver custom actions on the title (rotor parity with the
    /// list's context menu).
    private func applyMenuActions() {
        moreButton.menu = UIMenu(children: menuActions.map { action in
            UIAction(title: action.accessibilityLabel, image: action.icon) { _ in
                action.handler()
            }
        })
        titleLabel.accessibilityCustomActions = menuActions.map { action in
            UIAccessibilityCustomAction(name: action.accessibilityLabel) { _ in
                action.handler()
                return true
            }
        }
    }

    @objc private func cardTapped() {
        onCardTap?()
    }
}
