import UIKit
import Kingfisher
import AnycastKit

/// Value payload for the inbox card.
struct InboxCardContent {
    /// The playback relation shown as a badge on the show artwork.
    enum Status: Equatable {
        case none
        case playing
        case queued
    }

    var title: String
    /// The show name beside the artwork.
    var showName: String
    /// "Nov 21, 2025 · 45 min"-style meta beside the show name.
    var metaText: String
    var descriptionHTML: String?
    var imageURL: String?
    var descriptionPlainText: String?
    var status: Status = .none
}

/// The inbox card in the Anycast 2.0 UI kit form (`EpisodeCardCell`): the
/// shared card plate (radius 32) carrying the title (20 pt, two lines,
/// sentence case) over a two-line description, and a bottom row with the
/// 36 pt circular show artwork — badged when the episode is playing or
/// queued — the show name and date, and the `more` menu button. Whole-card
/// tap opens the Detail sheet; the `more` button pulls down the same UIMenu
/// the long-press context menu shows (09 §7a-C1).
///
/// The inter-card gap (12) is baked into the cell as 6 pt top + 6 pt
/// bottom insets — the card section is a list section (swipe actions) and
/// list sections carry no inter-item spacing.
final class InboxEpisodeCardCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxEpisodeCardCell"
    /// Half of the 12 pt column gap on each side of the card.
    static let verticalGap: CGFloat = Spacing.sm

    private enum Layout {
        static let artworkSide: CGFloat = 36
        static let badgeSide: CGFloat = 18
    }

    /// Whole-card tap → open the Detail sheet.
    var onCardTap: (() -> Void)?
    /// The context-menu payload, mirrored for VoiceOver custom actions and
    /// rendered as the `more` button's pull-down menu (09 §7a-C1).
    var menuActions: [EpisodeCardAction] = [] {
        didSet { applyMenuActions() }
    }

    private let cardContainer = CardSurfaceView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let coverView = UIImageView()
    private let statusBadge = UIImageView()
    private let showNameLabel = UILabel()
    private let metaLabel = UILabel()
    let moreButton = UIButton(type: .system)

    private var descriptionTask: Task<Void, Never>?
    /// Guards the description resolve: a reconfigure with the same HTML must
    /// not blank the text and restart the async parse each time.
    private var renderedDescriptionHTML: String?
    /// Guards the cover load against reconfigure storms (an unconditional
    /// reload restarts an in-flight download).
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
        renderedDescriptionHTML = nil
        onCardTap = nil
        menuActions = []
        // A reused cell must never inherit a card-entrance pose.
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    // MARK: - Configure

    func configure(_ content: InboxCardContent) {
        titleLabel.text = content.title
        // The show line keeps the feed's own casing.
        showNameLabel.text = content.showName
        showNameLabel.accessibilityLabel = content.showName
        metaLabel.text = content.metaText
        apply(status: content.status)

        if let plain = content.descriptionPlainText {
            renderedDescriptionHTML = nil
            descriptionLabel.text = plain
        } else if let html = content.descriptionHTML {
            if html != renderedDescriptionHTML {
                renderedDescriptionHTML = html
                descriptionTask?.cancel()
                descriptionLabel.text = ""
                descriptionTask = Task { [weak self] in
                    let text = await PlainTextHTMLCache.shared.plainText(for: html)
                    guard let self, !Task.isCancelled else { return }
                    self.descriptionLabel.text = text
                    // Resolve the label's frame in THIS turn — walk-based
                    // tests otherwise see "text but zero height" mid-flight;
                    // the follow-up tick covers text landing before the list
                    // section gave the cell its final frame.
                    self.invalidateIntrinsicContentSize()
                    self.setNeedsLayout()
                    self.layoutIfNeeded()
                    DispatchQueue.main.async { [weak self] in
                        self?.layoutIfNeeded()
                    }
                }
            }
        } else {
            renderedDescriptionHTML = nil
            descriptionLabel.text = ""
        }

        let url = content.imageURL.flatMap(URL.init(string:))
        if url != renderedCoverURL {
            renderedCoverURL = url
            coverView.kf.cancelDownloadTask()
            coverView.setArtwork(url, title: content.showName)
        }
    }

    /// Playing > queued; no badge otherwise (UI kit status badge).
    func apply(status: InboxCardContent.Status) {
        switch status {
        case .none:
            statusBadge.isHidden = true
        case .playing:
            statusBadge.isHidden = false
            statusBadge.image = UIImage(systemName: "waveform")
            statusBadge.backgroundColor = AnycastColor.gold9
            statusBadge.accessibilityLabel = "Playing"
        case .queued:
            statusBadge.isHidden = false
            statusBadge.image = UIImage(systemName: "checkmark")
            statusBadge.backgroundColor = AnycastColor.grass9
            statusBadge.accessibilityLabel = "In playlist"
        }
    }

    // MARK: - Build

    private func build() {
        contentView.backgroundColor = .clear

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardContainer)
        cardContainer.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        )

        titleLabel.font = TypographyV2.cardTitle.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true
        // The card action for VoiceOver (sighted users tap the whole card);
        // the menu payload hangs off it as custom actions below.
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = [.button]

        descriptionLabel.font = TypographyV2.bodyCompact.font()
        descriptionLabel.textColor = Theme.onSurfaceVariant
        descriptionLabel.numberOfLines = 2
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.adjustsFontForContentSizeCategory = true
        // Regression hook: tests assert the async description gains a
        // non-zero frame once the text lands.
        descriptionLabel.accessibilityIdentifier = "episode-card-description"

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xs

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Layout.artworkSide / 2
        coverView.backgroundColor = Theme.surfaceContainerHighest

        statusBadge.contentMode = .center
        statusBadge.tintColor = .white
        statusBadge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        statusBadge.layer.cornerRadius = Layout.badgeSide / 2
        statusBadge.layer.borderWidth = Spacing.hairline
        statusBadge.setDynamicBorderColor(Theme.surface)
        statusBadge.clipsToBounds = true
        statusBadge.isAccessibilityElement = true
        statusBadge.isHidden = true

        for label in [showNameLabel, metaLabel] {
            label.font = TypographyV2.caption.font()
            label.textColor = Theme.onSurfaceVariant
            label.adjustsFontForContentSizeCategory = true
        }
        showNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        var moreConfig = UIButton.Configuration.plain()
        moreConfig.image = AppIcons.more
        moreConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        moreConfig.baseForegroundColor = AnycastColor.sandAlpha9
        moreConfig.contentInsets = .zero
        moreButton.configuration = moreConfig
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "More actions"
        moreButton.accessibilityIdentifier = "inbox-card-more"

        for view in [textColumn, coverView, statusBadge, showNameLabel, metaLabel, moreButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cardContainer.addSubview(view)
        }

        NSLayoutConstraint.activate([
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalGap),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalGap),

            textColumn.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: Spacing.cardInner),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -Spacing.cardInner),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.pageH),

            // Bottom row: its height and the text column above it define
            // the card height.
            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: Spacing.pageH),
            coverView.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: Layout.artworkSide),
            coverView.heightAnchor.constraint(equalToConstant: Layout.artworkSide),

            statusBadge.widthAnchor.constraint(equalToConstant: Layout.badgeSide),
            statusBadge.heightAnchor.constraint(equalToConstant: Layout.badgeSide),
            statusBadge.centerXAnchor.constraint(equalTo: coverView.trailingAnchor, constant: -Spacing.xxs),
            statusBadge.centerYAnchor.constraint(equalTo: coverView.topAnchor, constant: Spacing.xxs),

            showNameLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            showNameLabel.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            metaLabel.leadingAnchor.constraint(equalTo: showNameLabel.trailingAnchor, constant: Spacing.gap),
            metaLabel.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -Spacing.xs),

            moreButton.topAnchor.constraint(equalTo: textColumn.bottomAnchor, constant: Spacing.xs + Spacing.sm),
            moreButton.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -Spacing.md),
            moreButton.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -Spacing.sm),
            moreButton.widthAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
            moreButton.heightAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
        ])
    }

    // MARK: - Actions

    /// The menu payload in two shapes: the more button's pull-down menu,
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
