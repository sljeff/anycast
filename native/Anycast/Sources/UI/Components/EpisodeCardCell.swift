import UIKit
import Kingfisher
import AnycastKit

/// A card action button model: screens inject behavior; the cell renders a
/// white circular button (CardBtn in card.dart) with the given icon.
struct EpisodeCardAction {
    let icon: UIImage
    let accessibilityLabel: String
    let handler: () -> Void

    init(icon: UIImage, accessibilityLabel: String, handler: @escaping () -> Void) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.handler = handler
    }
}

/// Download indicator three-state display (03 §2.11).
enum DownloadDisplay: Equatable {
    /// No indicator (non-playlist cards).
    case hidden
    /// Blue 70% circle with a download glyph; tap starts the download.
    case notDownloaded
    /// Progress ring 0…1.
    case downloading(Double)
    /// Green check.
    case downloaded

    static func == (lhs: DownloadDisplay, rhs: DownloadDisplay) -> Bool {
        switch (lhs, rhs) {
        case (.hidden, .hidden), (.notDownloaded, .notDownloaded), (.downloaded, .downloaded):
            return true
        case let (.downloading(a), .downloading(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Value payload for an episode card row — screens map their rows
/// (FeedEpisodeRow / PlaylistEpisodeRow / search hits) into this; the cell
/// stays decoupled from GRDB and from PlaybackService (live progress is
/// pushed by the owning screen via `updateLiveProgress`).
struct EpisodeCardContent {
    var title: String
    var channelTitle: String
    /// Right-aligned meta line: `"{duration} • {relative time}"`, or
    /// `"xx remaining"` on playlist cards (card.dart:50-82).
    var rightText: String
    var descriptionHTML: String?
    var imageURL: String?

    // Playlist-variant only
    var showsProgressBackdrop = false
    /// Static progress for non-current episodes (playedDuration/duration).
    var progressFraction: Double = 0
    var downloadDisplay: DownloadDisplay = .hidden

    /// Precomputed plain-text description (screen may pass a cached value;
    /// otherwise the cell resolves it through PlainTextHTMLCache).
    var descriptionPlainText: String?
}

/// The generic episode card (lib/widgets/card.dart:30-297, 03 §2.11): a
/// rounded-20 bordered 100pt row with an 80×80 rounded-16 cover (tap →
/// Detail), single-line title, channel name (max 114pt) + duration/relative
/// time, and a 2-line htmlToText description. Whole-card tap toggles the
/// 0↔60 action strip (200 ms easeInOut); playlist cards add the progress
/// backdrop and the download indicator.
///
/// VoiceOver: the container's children carry the labels, so the card itself
/// is not an element — the title acts as the strip-toggle button
/// (accessibilityActivate), otherwise the action strip would be unreachable.
private final class TitleActivatableLabel: UILabel {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

final class EpisodeCardCell: UICollectionViewCell {

    static let reuseIdentifier = "EpisodeCardCell"
    static let cardRowHeight: CGFloat = 104   // 80pt cover + 12pt padding ×2
    static let stripHeight: CGFloat = 60
    static let spacing: CGFloat = 12          // list row gap (ListView.separated)

    /// Card cover tap → open the Detail sheet.
    var onCoverTap: (() -> Void)?
    /// Whole-card tap → toggle the action strip (route through the list's
    /// CardExpandCoordinator).
    var onCardTap: (() -> Void)?
    /// Tap on the not-downloaded indicator → start download.
    var onDownloadTap: (() -> Void)?

    private let cardContainer = UIView()
    private let coverView = UIImageView()
    private let titleLabel = TitleActivatableLabel()
    private let channelLabel = UILabel()
    private let rightTextLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressBackdrop = EpisodeProgressBackdrop()
    private let downloadCircle = UIView()
    private let downloadIcon = UIImageView()
    private let downloadRing = ProgressRingView(lineWidth: 3)
    private let downloadDoneIcon = UIImageView()

    private let stripContainer = UIView()
    private var stripHeightConstraint: NSLayoutConstraint!
    private var actionButtons: [UIButton] = []
    private var actions: [EpisodeCardAction] = []
    private var descriptionTask: Task<Void, Never>?
    /// Guards the cover load: visible cards reconfigure on every playback
    /// tick and card expand, and an unconditional cancel+setImage would
    /// restart an in-flight cover download from zero each time.
    private var renderedCoverURL: URL?
    private var channelMaxWidth: NSLayoutConstraint!

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
        onCoverTap = nil
        onCardTap = nil
        onDownloadTap = nil
    }

    // MARK: - Configure

    func configure(_ content: EpisodeCardContent, actions: [EpisodeCardAction]) {
        self.actions = actions

        titleLabel.text = content.title
        channelLabel.text = content.channelTitle
        rightTextLabel.text = content.rightText

        if let plain = content.descriptionPlainText {
            descriptionLabel.text = plain
        } else if let html = content.descriptionHTML {
            // Cancel the prior episode's in-flight resolve and clear the
            // reused text — a stale description must never linger while the
            // new one is parsed.
            descriptionTask?.cancel()
            descriptionLabel.text = ""
            descriptionTask = Task { [weak self] in
                let text = await PlainTextHTMLCache.shared.plainText(for: html)
                guard let self, !Task.isCancelled else { return }
                self.descriptionLabel.text = text
                // The text lands after the card's first layout, and a
                // UILabel's intrinsic-size invalidation does not reach the
                // stack's layout pass (the label could sit at its
                // zero-height frame forever — silently dropping the
                // description). Schedule the relayout explicitly.
                self.setNeedsLayout()
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

        progressBackdrop.isHidden = !content.showsProgressBackdrop
        progressBackdrop.setFraction(content.progressFraction)

        configureDownload(content.downloadDisplay)
        rebuildActionButtons()
        setExpanded(false)
    }

    /// Live progress push for the CURRENT episode (positionData-driven);
    /// also updates the right text ("xx remaining" recalculated by the
    /// screen from the same data — card.dart:71-79).
    func updateLiveProgress(fraction: Double, rightText: String) {
        progressBackdrop.setFraction(fraction)
        rightTextLabel.text = rightText
    }

    /// Live download-state push (PlaybackService.cacheStates).
    func updateDownload(_ display: DownloadDisplay) {
        configureDownload(display)
    }

    /// Action strip height 0↔60 (card.dart:279-291). The owning list drives
    /// the animation through `CardExpandAnimator.refresh`: this method only
    /// moves the target (constraint + visibility) and settles the cell's
    /// layout. The cell must NOT run its own animate block — a self-run
    /// reveal raced the list's layout pass, and a height update that lost
    /// the race left the strip overflowing the un-resized item.
    func setExpanded(_ expanded: Bool) {
        stripHeightConstraint.constant = expanded ? Self.stripHeight : 0
        stripContainer.isHidden = !expanded
        layoutIfNeeded()
    }

    // MARK: - Build

    private func build() {
        contentView.backgroundColor = .clear
        // Any content that outruns its item height must clip instead of
        // painting over neighbor cards (and stealing their taps) — an
        // un-clipped overflow is exactly the strip-over-cards corruption
        // the M3 review hit when a height update raced the strip reveal.
        clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        // Card row (rounded 20, bordered, 12pt inner padding).
        cardContainer.backgroundColor = Theme.cardBackground
        cardContainer.layer.borderColor = Theme.cardOutline.cgColor
        cardContainer.layer.borderWidth = 1
        cardContainer.layer.cornerRadius = 20
        cardContainer.layer.cornerCurve = .continuous
        // The 4pt progress backdrop spans the card's full width with
        // square corners; without clipping it runs straight through the
        // rounded bottom corners instead of following them.
        cardContainer.clipsToBounds = true
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(cardContainer)

        cardContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped)))
        cardContainer.isAccessibilityElement = false // children carry labels

        // Cover (80×80, rounded 16) — its own gesture beats the card tap.
        // UIImageView defaults to isUserInteractionEnabled = false, which
        // would swallow the gesture (tap falls through to the card expand) —
        // the Detail sheet would then be unreachable from every list.
        coverView.isUserInteractionEnabled = true
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 16
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.primaryBackground
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.isAccessibilityElement = true
        coverView.accessibilityTraits = [.button]
        coverView.accessibilityLabel = "Episode details"
        cardContainer.addSubview(coverView)
        coverView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(coverTapped)))

        // 16pt system (PingFang on the Chinese stack) single line — 03 §2.11.
        let titleMetrics = UIFontMetrics(forTextStyle: .headline)
        titleLabel.font = titleMetrics.scaledFont(for: .systemFont(ofSize: 16, weight: .semibold))
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        // The strip toggle for VoiceOver (sighted users tap the whole card).
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = [.button]
        titleLabel.onActivate = { [weak self] in self?.onCardTap?() }

        let metaMetrics = UIFontMetrics(forTextStyle: .caption1)
        channelLabel.font = metaMetrics.scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        channelLabel.textColor = Theme.secondaryText
        channelLabel.numberOfLines = 1
        channelLabel.adjustsFontForContentSizeCategory = true

        // Tabular figures (FontFeature.tabularFigures in the Dart row).
        rightTextLabel.font = metaMetrics.scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        )
        rightTextLabel.textColor = Theme.secondaryText
        rightTextLabel.numberOfLines = 1
        rightTextLabel.adjustsFontForContentSizeCategory = true
        rightTextLabel.textAlignment = .right

        descriptionLabel.font = Typography.cardDescription.font()
        descriptionLabel.textColor = Typography.cardDescription.color
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontForContentSizeCategory = true
        // Layout-regression hook (the description is resolved async — tests
        // assert it gains a non-zero frame once the text lands).
        descriptionLabel.accessibilityIdentifier = "episode-card-description"

        let textColumn = UIStackView(arrangedSubviews: [titleLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(textColumn)

        let metaRow = UIStackView(arrangedSubviews: [channelLabel])
        metaRow.axis = .horizontal
        metaRow.distribution = .fill
        metaRow.alignment = .center
        metaRow.spacing = 8
        metaRow.addArrangedSubview(rightTextLabel)
        textColumn.addArrangedSubview(metaRow)
        textColumn.addArrangedSubview(descriptionLabel)

        // Channel name caps at 114pt so the right text never starves
        // (ConstrainedBox maxWidth 114, card.dart:150-162).
        channelMaxWidth = channelLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 114)

        // Progress backdrop: 4pt strip along the card bottom edge.
        progressBackdrop.trackColor = UIColor.white.withAlphaComponent(0.12)
        progressBackdrop.fillColor = Theme.primary
        progressBackdrop.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(progressBackdrop)

        // Download indicator (16×16, right gap 12 / bottom 16).
        downloadCircle.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        downloadCircle.layer.cornerRadius = 8
        downloadCircle.translatesAutoresizingMaskIntoConstraints = false
        downloadCircle.isHidden = true
        downloadIcon.image = AppIcons.download
        downloadIcon.tintColor = .white
        downloadIcon.contentMode = .scaleAspectFit
        downloadIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadCircle.addSubview(downloadIcon)
        downloadCircle.isAccessibilityElement = true
        downloadCircle.accessibilityTraits = [.button]
        downloadCircle.accessibilityLabel = "Download"
        downloadCircle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(downloadTapped)))
        cardContainer.addSubview(downloadCircle)

        downloadRing.tintColorOverride = UIColor.systemBlue
        downloadRing.translatesAutoresizingMaskIntoConstraints = false
        downloadRing.isHidden = true
        downloadRing.isAccessibilityElement = false
        cardContainer.addSubview(downloadRing)

        downloadDoneIcon.image = AppIcons.downloadDone
        // grass9 dark (AnycastColor.grass9(Brightness.dark), 03 §2.11).
        downloadDoneIcon.tintColor = UIColor(red: 0x63 / 255, green: 0xC1 / 255, blue: 0x74 / 255, alpha: 1)
        downloadDoneIcon.contentMode = .scaleAspectFit
        downloadDoneIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadDoneIcon.isHidden = true
        downloadDoneIcon.isAccessibilityElement = true
        downloadDoneIcon.accessibilityLabel = "Downloaded"
        cardContainer.addSubview(downloadDoneIcon)

        // Action strip below the card (height animated 0↔60).
        stripContainer.translatesAutoresizingMaskIntoConstraints = false
        stripContainer.isHidden = true
        let stripRow = UIStackView()
        stripRow.axis = .horizontal
        stripRow.distribution = .equalSpacing
        stripRow.alignment = .center
        stripRow.translatesAutoresizingMaskIntoConstraints = false
        stripContainer.addSubview(stripRow)
        stripContainer.isUserInteractionEnabled = true
        stack.addArrangedSubview(stripContainer)
        stripHeightConstraint = stripContainer.heightAnchor.constraint(equalToConstant: 0)
        rightTextLabel.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // 104 pt is the minimum (80pt cover + 12pt padding ×2); the card
            // self-sizes taller when the scaled fonts demand it (hosts use
            // .estimated heights). The cover pins to the top only, so the
            // extra space at accessibility sizes goes to the text column.
            cardContainer.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.cardRowHeight),
            cardContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 12),
            coverView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            coverView.widthAnchor.constraint(equalToConstant: 80),
            coverView.heightAnchor.constraint(equalToConstant: 80),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 12),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -12),
            // == the cover height at the default size (identical layout);
            // grows with Dynamic Type where the required equality used to
            // clip the description at accessibility sizes.
            textColumn.heightAnchor.constraint(greaterThanOrEqualTo: coverView.heightAnchor),

            channelMaxWidth,
            rightTextLabel.widthAnchor.constraint(lessThanOrEqualTo: textColumn.widthAnchor, multiplier: 0.5),

            progressBackdrop.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            progressBackdrop.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            progressBackdrop.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),
            progressBackdrop.heightAnchor.constraint(equalToConstant: 4),

            downloadCircle.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            downloadCircle.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -16),
            downloadCircle.widthAnchor.constraint(equalToConstant: 16),
            downloadCircle.heightAnchor.constraint(equalToConstant: 16),
            downloadIcon.centerXAnchor.constraint(equalTo: downloadCircle.centerXAnchor),
            downloadIcon.centerYAnchor.constraint(equalTo: downloadCircle.centerYAnchor),
            downloadIcon.widthAnchor.constraint(equalToConstant: 12),
            downloadIcon.heightAnchor.constraint(equalToConstant: 12),

            downloadRing.centerXAnchor.constraint(equalTo: downloadCircle.centerXAnchor),
            downloadRing.centerYAnchor.constraint(equalTo: downloadCircle.centerYAnchor),
            downloadRing.widthAnchor.constraint(equalToConstant: 16),
            downloadRing.heightAnchor.constraint(equalToConstant: 16),

            downloadDoneIcon.centerXAnchor.constraint(equalTo: downloadCircle.centerXAnchor),
            downloadDoneIcon.centerYAnchor.constraint(equalTo: downloadCircle.centerYAnchor),
            downloadDoneIcon.widthAnchor.constraint(equalToConstant: 16),
            downloadDoneIcon.heightAnchor.constraint(equalToConstant: 16),

            // Row spans the FULL strip width: Dart's AnimatedContainer child
            // is a full-width Row(mainAxisAlignment: spaceEvenly) — equal
            // spacing needs a definite width, and the previous centerX +
            // inequality pair left it ambiguous (buttons could collapse
            // onto each other). Height 48 = 60 strip − 12 top padding, so
            // the 40 pt buttons center exactly like the Dart row.
            stripRow.leadingAnchor.constraint(equalTo: stripContainer.leadingAnchor),
            stripRow.trailingAnchor.constraint(equalTo: stripContainer.trailingAnchor),
            stripRow.topAnchor.constraint(equalTo: stripContainer.topAnchor, constant: 12),
            stripRow.heightAnchor.constraint(equalToConstant: 48),
            stripHeightConstraint,
        ])
    }

    // MARK: - Actions

    @objc private func cardTapped() {
        onCardTap?()
    }

    @objc private func coverTapped() {
        onCoverTap?()
    }

    @objc private func downloadTapped() {
        onDownloadTap?()
    }

    @objc private func actionTapped(_ sender: UIButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].handler()
    }

    private func configureDownload(_ display: DownloadDisplay) {
        downloadCircle.isHidden = display != .notDownloaded
        downloadRing.isHidden = true
        downloadDoneIcon.isHidden = true
        switch display {
        case .hidden:
            break
        case .notDownloaded:
            break
        case let .downloading(progress):
            downloadRing.isHidden = false
            downloadRing.setProgress(progress)
        case .downloaded:
            downloadDoneIcon.isHidden = false
        }
    }

    private func rebuildActionButtons() {
        actionButtons.forEach { $0.removeFromSuperview() }
        actionButtons = []
        guard !actions.isEmpty else { return }
        for (index, action) in actions.enumerated() {
            let button = UIButton(type: .custom)
            button.setImage(action.icon, for: .normal)
            button.tintColor = Theme.primaryBackgroundDark
            button.backgroundColor = Theme.primaryLightMax
            button.layer.cornerRadius = 20
            button.layer.cornerCurve = .continuous
            button.accessibilityLabel = action.accessibilityLabel
            button.tag = index
            button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            if let stripRow = stripContainer.subviews.first as? UIStackView {
                stripRow.addArrangedSubview(button)
            }
            actionButtons.append(button)
        }
    }
}
