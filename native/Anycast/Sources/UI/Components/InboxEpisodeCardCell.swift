import UIKit
import Kingfisher
import AnycastKit

/// Value payload for the inbox row.
struct InboxCardContent {
    /// The playback relation shown as a badge on the show artwork.
    enum Status: Equatable {
        case none
        case playing
        case queued
    }

    var title: String
    /// The show name, first part of the second line.
    var showName: String
    /// "10h ago"-style relative date, second part of the second line.
    var dateText: String = ""
    /// "44m"-style duration, right-aligned beside the text column.
    var durationText: String = ""
    var imageURL: String?
    var status: Status = .none
}

/// One inbox episode as a row of a grouped plate (`GroupedPlateView`, the
/// section's background — see `PodcastCardCell.makeGroupedLayout`): a 44 pt
/// cover — badged when the episode is playing or queued — the Emphasis
/// title on up to two lines over the Meta "Show · date" line, and the
/// duration right-aligned and never truncated. Rows after the first draw a
/// hairline from the text on; touching fills the row (no scale). Whole-row
/// tap opens the Detail sheet; the menu is the list's long-press context
/// menu, mirrored here as VoiceOver custom actions.
final class InboxEpisodeCardCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxEpisodeCardCell"

    /// The show artwork's side; the inbox prefetches covers at this size.
    static let artworkSide: CGFloat = 44
    /// 12 + the 44 pt cover + 12; the text column grows past it with a
    /// second title line and Dynamic Type.
    static let minimumHeight: CGFloat = artworkSide + Spacing.gap * 2

    private enum Layout {
        static let badgeSide: CGFloat = 18
    }

    /// Whole-row tap → open the Detail sheet.
    var onCardTap: (() -> Void)?
    /// The context-menu payload, mirrored as VoiceOver custom actions
    /// (rotor parity with the list's long-press menu, 09 §7a-C1).
    var menuActions: [EpisodeCardAction] = [] {
        didSet { applyMenuActions() }
    }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let durationLabel = UILabel()
    private let coverView = UIImageView()
    private let statusBadge = UIImageView()
    private var badgeSideConstraints: [NSLayoutConstraint] = []
    private let separator = UIView()
    private var textTrailingToDuration: NSLayoutConstraint?
    private var textTrailingToEdge: NSLayoutConstraint?

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
        onCardTap = nil
        menuActions = []
        setPosition(isFirst: false, isLast: false)
        // A reused cell must never inherit a card-entrance pose.
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    // MARK: - Configure

    func configure(_ content: InboxCardContent) {
        titleLabel.text = content.title
        // The show line keeps the feed's own casing.
        subtitleLabel.text = [content.showName, content.dateText]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        durationLabel.text = content.durationText
        let hasDuration = !content.durationText.isEmpty
        durationLabel.isHidden = !hasDuration
        textTrailingToDuration?.isActive = hasDuration
        textTrailingToEdge?.isActive = !hasDuration
        apply(status: content.status)

        contentView.accessibilityLabel = content.title
        contentView.accessibilityValue = [subtitleLabel.text, content.durationText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let url = content.imageURL.flatMap(URL.init(string:))
        if url != renderedCoverURL {
            renderedCoverURL = url
            coverView.kf.cancelDownloadTask()
            coverView.setArtwork(url, title: content.showName, side: Self.artworkSide)
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
            statusBadge.backgroundColor = Theme.primary
            statusBadge.tintColor = Theme.onPrimary
            statusBadge.accessibilityLabel = "Playing"
        case .queued:
            statusBadge.isHidden = false
            statusBadge.image = AppIcons.addedToList
            statusBadge.backgroundColor = AnycastColor.grass9
            statusBadge.tintColor = Theme.onPrimary
            statusBadge.accessibilityLabel = "In playlist"
        }
    }

    /// Where the row sits on its plate: the first row has no hairline, and
    /// the first and last rows round their press fill into the plate.
    func setPosition(isFirst: Bool, isLast: Bool) {
        separator.isHidden = isFirst
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        contentView.layer.maskedCorners = corners
        contentView.layer.cornerRadius = corners.isEmpty ? 0 : Radius.card
    }

    /// Grouped-plate rows answer a touch with a fill, never a scale.
    override var isHighlighted: Bool {
        didSet {
            let fill = isHighlighted ? AnycastColor.sandAlpha5 : .clear
            UIView.animate(withDuration: isHighlighted ? 0.1 : Motion.quick) {
                self.contentView.backgroundColor = fill
            }
        }
    }

    // MARK: - Build

    private func build() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerCurve = .continuous
        contentView.isAccessibilityElement = true
        contentView.accessibilityTraits = [.button]
        contentView.accessibilityHint = "Opens episode details"
        contentView.accessibilityIdentifier = "inbox-episode-row"
        contentView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        )

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = TypographyV2.meta.color
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.adjustsFontForContentSizeCategory = true

        durationLabel.font = TypographyV2.meta.font().monospacedDigits()
        durationLabel.textColor = TypographyV2.meta.color
        durationLabel.numberOfLines = 1
        durationLabel.textAlignment = .right
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.alignment = .fill

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.sm
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHighest

        statusBadge.contentMode = .center
        statusBadge.tintColor = Theme.onPrimary
        statusBadge.layer.cornerRadius = Layout.badgeSide / 2
        statusBadge.layer.borderWidth = Spacing.hairline
        statusBadge.setDynamicBorderColor(Theme.surface)
        statusBadge.clipsToBounds = true
        statusBadge.isAccessibilityElement = false
        statusBadge.isHidden = true

        separator.backgroundColor = Theme.outline
        separator.isUserInteractionEnabled = false

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: InboxEpisodeCardCell, _) in
            cell.applyBadgeMetrics()
        }

        for view in [textColumn, coverView, statusBadge, durationLabel, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        let badgeWidth = statusBadge.widthAnchor.constraint(equalToConstant: Layout.badgeSide)
        let badgeHeight = statusBadge.heightAnchor.constraint(equalToConstant: Layout.badgeSide)
        badgeSideConstraints = [badgeWidth, badgeHeight]
        let toDuration = textColumn.trailingAnchor.constraint(
            equalTo: durationLabel.leadingAnchor, constant: -Spacing.gap
        )
        let toEdge = textColumn.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor, constant: -Spacing.pageH
        )
        textTrailingToDuration = toDuration
        textTrailingToEdge = toEdge
        toEdge.isActive = false

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),

            coverView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            coverView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: Self.artworkSide),
            coverView.heightAnchor.constraint(equalToConstant: Self.artworkSide),

            badgeWidth, badgeHeight,
            statusBadge.centerXAnchor.constraint(equalTo: coverView.trailingAnchor, constant: -Spacing.xxs),
            statusBadge.centerYAnchor.constraint(equalTo: coverView.topAnchor, constant: Spacing.xxs),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            toDuration,
            textColumn.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.gap),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.gap),
            textColumn.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            durationLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.topAnchor.constraint(equalTo: contentView.topAnchor),
            separator.leadingAnchor.constraint(equalTo: textColumn.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.pageH),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        applyBadgeMetrics()
    }

    /// Status badge stays at least 18 pt and grows with caption metrics.
    private func applyBadgeMetrics() {
        let side = IconMetrics.scaledUp(Layout.badgeSide, textStyle: .caption1, compatibleWith: traitCollection)
        for constraint in badgeSideConstraints { constraint.constant = side }
        statusBadge.layer.cornerRadius = side / 2
        statusBadge.preferredSymbolConfiguration = IconMetrics.symbolConfiguration(
            pointSize: 9, weight: .bold, textStyle: .caption1, compatibleWith: traitCollection
        )
    }

    // MARK: - Actions

    private func applyMenuActions() {
        contentView.accessibilityCustomActions = menuActions.map { action in
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
