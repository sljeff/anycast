import UIKit
import Kingfisher
import AnycastKit

/// All text is resolved before a snapshot is applied; cells never load descriptions.
struct InboxCardContent {
    enum Status: Equatable { case none, playing, queued }
    var title: String
    var showName: String
    var dateText: String = ""
    var durationText: String = ""
    var imageURL: String?
    var status: Status = .none
    var descriptionText: String = ""
}

private final class InboxTitleLabel: UILabel {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

private final class InboxCoverView: UIImageView {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

/// A standalone plate with a transparent, non-interactive action spacer.
final class InboxEpisodeCardCell: UICollectionViewCell, ListActionGapHosting, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "InboxEpisodeCardCell"
    static let artworkSide: CGFloat = 64
    static let minimumHeight: CGFloat = 92
    private enum Layout { static let badgeSide: CGFloat = 18 }

    var onCardTap: (() -> Void)?
    var onCoverTap: (() -> Void)?
    var menuActions: [EpisodeCardAction] = [] {
        didSet {
            titleLabel.accessibilityCustomActions = menuActions.map { action in
                UIAccessibilityCustomAction(name: action.accessibilityLabel) { _ in
                    action.handler()
                    return true
                }
            }
        }
    }
    private let plate = UIView()
    private let titleLabel = InboxTitleLabel()
    private let descriptionLabel = UILabel()
    private let showLabel = UILabel()
    private let timeLabel = UILabel()
    private let coverView = InboxCoverView()
    private let statusBadge = UIImageView()
    private var badgeSideConstraints: [NSLayoutConstraint] = []
    private var plateBottom: NSLayoutConstraint!
    private var renderedCoverURL: URL?
    private(set) var actionGap: CGFloat = 0
    var cardFrameInCell: CGRect { plate.convert(plate.bounds, to: self) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onCardTap = nil
        onCoverTap = nil
        menuActions = []
        setActionGap(0)
        // The FLIP position translation rides on the cell's own layer; a
        // reused cell must not carry it into its next position.
        layer.removeAnimation(forKey: ListActionMotion.translationKey)
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    func configure(_ content: InboxCardContent) {
        titleLabel.text = content.title
        descriptionLabel.text = content.descriptionText
        descriptionLabel.isHidden = content.descriptionText.isEmpty
        showLabel.text = content.showName
        let suffix = [content.dateText, content.durationText].filter { !$0.isEmpty }.joined(separator: " · ")
        timeLabel.text = suffix.isEmpty ? "" : (content.showName.isEmpty ? suffix : " · " + suffix)
        timeLabel.isHidden = suffix.isEmpty
        titleLabel.accessibilityValue = [content.showName, content.dateText, content.durationText]
            .filter { !$0.isEmpty }.joined(separator: ", ")
        apply(status: content.status)
        let url = content.imageURL.flatMap(URL.init(string:))
        if url == nil || url != renderedCoverURL || coverView.image == nil {
            renderedCoverURL = url
            coverView.kf.cancelDownloadTask()
            coverView.setArtwork(url, title: content.showName, side: Self.artworkSide)
        }
        resolveLineBudget(width: bounds.width)
    }

    /// Resolve wrapping before self-sizing, using the final proposed card width.
    private func resolveLineBudget(width: CGFloat) {
        let textWidth = max(1, width - 2 * Spacing.gap - Self.artworkSide - Spacing.gap)
        titleLabel.preferredMaxLayoutWidth = textWidth
        descriptionLabel.preferredMaxLayoutWidth = textWidth
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        descriptionLabel.numberOfLines = titleHeight > ceil(titleLabel.font.lineHeight) + 0.5 ? 1 : 2
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        resolveLineBudget(width: layoutAttributes.size.width)
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size.height = ceil(contentView.systemLayoutSizeFitting(
            CGSize(width: layoutAttributes.size.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height)
        return attributes
    }

    func setActionGap(_ gap: CGFloat) {
        actionGap = gap
        plateBottom.constant = -gap
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        cardFrameInCell.contains(point)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        return !touched.isDescendant(of: coverView)
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
            statusBadge.backgroundColor = Theme.onSurfaceVariant
            statusBadge.tintColor = Theme.surface
            statusBadge.accessibilityLabel = "In playlist"
        }
    }


    private func build() {
        contentView.backgroundColor = .clear
        plate.backgroundColor = Theme.surface
        plate.layer.cornerRadius = Radius.largeCard
        plate.layer.cornerCurve = .continuous
        plate.layer.borderWidth = Spacing.hairline
        plate.setDynamicBorderColor(AnycastColor.sandAlpha3)
        plate.accessibilityIdentifier = "inbox-episode-row"
        plate.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(plate)
        plateBottom = plate.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        tap.delegate = self
        plate.addGestureRecognizer(tap)

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 2
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = [.button]
        titleLabel.accessibilityHint = "Shows episode actions"
        titleLabel.accessibilityIdentifier = "inbox-episode-title"
        titleLabel.onActivate = { [weak self] in self?.onCardTap?() }
        for label in [descriptionLabel, showLabel, timeLabel] {
            label.font = TypographyV2.meta.font()
            label.textColor = TypographyV2.meta.color
            label.numberOfLines = 1
        }
        for label in [titleLabel, descriptionLabel, showLabel, timeLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
        }
        descriptionLabel.accessibilityIdentifier = "inbox-episode-description"
        showLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        let metaSpace = UIView()
        metaSpace.setContentHuggingPriority(.init(1), for: .horizontal)
        metaSpace.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let meta = UIStackView(arrangedSubviews: [showLabel, timeLabel, metaSpace])
        meta.axis = .horizontal
        let text = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, meta])
        text.axis = .vertical
        text.spacing = Spacing.xxs

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.isUserInteractionEnabled = true
        coverView.isAccessibilityElement = true
        coverView.accessibilityTraits = [.button]
        coverView.accessibilityLabel = "Episode details"
        coverView.accessibilityIdentifier = "inbox-episode-cover"
        coverView.onActivate = { [weak self] in self?.onCoverTap?() }
        coverView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(coverTapped)))
        statusBadge.contentMode = .center
        statusBadge.layer.borderWidth = Spacing.hairline
        statusBadge.setDynamicBorderColor(Theme.surface)
        statusBadge.clipsToBounds = true
        statusBadge.isAccessibilityElement = false
        statusBadge.isHidden = true
        for child in [coverView, text, statusBadge] {
            child.translatesAutoresizingMaskIntoConstraints = false
            plate.addSubview(child)
        }
        let badgeWidth = statusBadge.widthAnchor.constraint(equalToConstant: Layout.badgeSide)
        let badgeHeight = statusBadge.heightAnchor.constraint(equalToConstant: Layout.badgeSide)
        badgeSideConstraints = [badgeWidth, badgeHeight]
        NSLayoutConstraint.activate([
            plate.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            plate.topAnchor.constraint(equalTo: contentView.topAnchor), plateBottom,
            plate.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),
            coverView.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.gap),
            coverView.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.gap),
            coverView.bottomAnchor.constraint(lessThanOrEqualTo: plate.bottomAnchor, constant: -Spacing.gap),
            coverView.widthAnchor.constraint(equalToConstant: Self.artworkSide),
            coverView.heightAnchor.constraint(equalToConstant: Self.artworkSide),
            text.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            text.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.gap),
            text.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.gap),
            text.bottomAnchor.constraint(lessThanOrEqualTo: plate.bottomAnchor, constant: -Spacing.gap),
            badgeWidth, badgeHeight,
            statusBadge.centerXAnchor.constraint(equalTo: coverView.trailingAnchor, constant: -Spacing.xxs),
            statusBadge.centerYAnchor.constraint(equalTo: coverView.topAnchor, constant: Spacing.xxs),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: InboxEpisodeCardCell, _) in
            cell.applyBadgeMetrics()
            cell.resolveLineBudget(width: cell.bounds.width)
        }
        applyBadgeMetrics()
    }

    /// Status badge stays at least 18 pt and grows with caption metrics.
    private func applyBadgeMetrics() {
        let side = IconMetrics.scaledUp(Layout.badgeSide, textStyle: .caption1, compatibleWith: traitCollection)
        for constraint in badgeSideConstraints { constraint.constant = side }
        statusBadge.layer.cornerRadius = side / 2
        statusBadge.preferredSymbolConfiguration = IconMetrics.symbolConfiguration(
            pointSize: 9, weight: .medium, textStyle: .caption1, compatibleWith: traitCollection
        )
    }


    @objc private func cardTapped() { onCardTap?() }
    @objc private func coverTapped() { onCoverTap?() }
}
