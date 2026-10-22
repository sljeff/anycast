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
    /// The meta line's time part after the show name: `"{relative time} ·
    /// {duration}"`, or on playlist cards the duration / `"32m left"`
    /// (card.dart:50-82).
    var rightText: String
    var descriptionHTML: String?
    var imageURL: String?
    /// False inside a single show (ChannelSearch), where the name repeats
    /// on every card; it still names the cover placeholder.
    var showsChannel = true

    // Playlist-variant only
    /// Shows the inline progress meter while the episode has progress.
    var showsProgress = false
    /// Static progress for non-current episodes (playedDuration/duration).
    var progressFraction: Double = 0
    var downloadDisplay: DownloadDisplay = .hidden

    /// Precomputed plain-text description (screen may pass a cached value;
    /// otherwise the cell resolves it through PlainTextHTMLCache).
    var descriptionPlainText: String?
}

/// The generic episode card (lib/widgets/card.dart:30-297, 03 §2.11) in the
/// compact 2.0 form (adopted 2026-10-21): the shared card plate (radius 32,
/// hairline, padding 12), a 64 pt rounded cover (tap → Detail), and three
/// one-line rows in the three text styles — the Emphasis title; the Meta
/// line `show · time` with the download mark after the show name and, on
/// playlist cards with progress, a 36 × 4 meter before the time left; and
/// the Meta description. Whole-card tap toggles the action drawer — a split
/// capsule of equal segments (UI kit `QueueSplitCapsuleButtonGroup`).
/// Lists that took the native-first path (09 §7a-C1,
/// Inbox) render no strip and surface the same actions through the list's
/// context menu, passing them here as `menuActions` for VoiceOver.
///
/// VoiceOver: the container's children carry the labels, so the card itself
/// is not an element — the title acts as the card action button
/// (accessibilityActivate → onCardTap) and carries the menu actions as
/// accessibility custom actions, so every card action stays reachable
/// without sight on strip and strip-less lists alike.
private final class TitleActivatableLabel: UILabel {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

final class EpisodeCardCell: UICollectionViewCell {

    static let reuseIdentifier = "EpisodeCardCell"
    /// 12 pt padding ×2 around the text column (22 title + 4 + 20 meta +
    /// 4 + 20 description), which is taller than the 64 pt cover.
    static let cardRowHeight: CGFloat = 94
    static let coverSide: CGFloat = 64
    static let stripHeight: CGFloat = 60
    /// The drawer capsule inside the strip (12 pt above it, then 48 pt).
    static let drawerHeight: CGFloat = 48
    static let spacing: CGFloat = Spacing.gap // list row gap (compact cards, 12)

    /// Card cover tap → open the Detail sheet.
    var onCoverTap: (() -> Void)?
    /// Whole-card tap → toggle the action strip (route through the list's
    /// CardExpandCoordinator); strip-less lists point this at the card's
    /// primary action instead (Inbox: open the Detail sheet, 09 §7a-C1).
    var onCardTap: (() -> Void)?
    /// Tap on the not-downloaded indicator → start download.
    var onDownloadTap: (() -> Void)?
    /// The actions a strip-less list surfaces through its context menu
    /// (native-first, 09 §7a-C1). Rendering stays with the list — the cell
    /// only mirrors them as VoiceOver custom actions on the title.
    var menuActions: [EpisodeCardAction] = [] {
        didSet { applyMenuActions() }
    }

    private let cardContainer = UIView()
    private let coverView = UIImageView()
    private let titleLabel = TitleActivatableLabel()
    private let channelLabel = UILabel()
    private let separatorLabel = UILabel()
    private let progressMeter = EpisodeProgressBackdrop()
    private let rightTextLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let downloadCircle = UIView()
    private let downloadIcon = UIImageView()
    private let downloadRing = ProgressRingView(lineWidth: 3)
    private let downloadDoneIcon = UIImageView()
    /// The meta row's trailing slot the download indicator centers on.
    private let downloadSlot = UIView()

    private let stripContainer = UIView()
    /// A tonal capsule, not glass: the cell clips (strip-race guard), and a
    /// clipped glass shadow reads as a hard rectangle.
    private let drawer = CapsuleView()
    private let drawerRow = UIStackView()
    private var stripHeightConstraint: NSLayoutConstraint!
    private var actionButtons: [UIButton] = []
    private var actions: [EpisodeCardAction] = []
    private var descriptionTask: Task<Void, Never>?
    /// Guards the description resolve: a reconfigure with the same HTML must
    /// not blank the text and restart the async parse each time.
    private var renderedDescriptionHTML: String?
    /// Guards the cover load: visible cards reconfigure on every playback
    /// tick and card expand, and an unconditional cancel+setImage would
    /// restart an in-flight cover download from zero each time.
    private var renderedCoverURL: URL?
    private var showsProgress = false

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
        onCoverTap = nil
        onCardTap = nil
        onDownloadTap = nil
        menuActions = []
        // A reused cell must never inherit a card-entrance pose.
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    // MARK: - Configure

    func configure(_ content: EpisodeCardContent, actions: [EpisodeCardAction]) {
        self.actions = actions

        titleLabel.text = content.title
        channelLabel.text = content.channelTitle
        channelLabel.isHidden = !content.showsChannel
        rightTextLabel.text = content.rightText
        rightTextLabel.isHidden = content.rightText.isEmpty

        if let plain = content.descriptionPlainText {
            renderedDescriptionHTML = nil
            descriptionLabel.text = plain
        } else if let html = content.descriptionHTML {
            if html != renderedDescriptionHTML {
                renderedDescriptionHTML = html
                // Cancel the prior episode's in-flight resolve and clear the
                // reused text — a stale description must never linger while
                // the new one is parsed.
                descriptionTask?.cancel()
                descriptionLabel.text = ""
                descriptionTask = Task { [weak self] in
                    let text = await PlainTextHTMLCache.shared.plainText(for: html)
                    guard let self, !Task.isCancelled else { return }
                    self.descriptionLabel.text = text
                    // The text lands after the card's first layout, and a
                    // UILabel's intrinsic-size invalidation does not reach
                    // the stack's layout pass (the label could sit at its
                    // zero-height frame forever — silently dropping the
                    // description). Re-run self-sizing so the card grows to
                    // the wrapped text instead of clipping it.
                    self.invalidateIntrinsicContentSize()
                    self.setNeedsLayout()
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
            coverView.setArtwork(url, title: content.channelTitle)
        }

        showsProgress = content.showsProgress
        applyProgress(content.progressFraction)

        configureDownload(content.downloadDisplay)
        rebuildActionButtons()
        setExpanded(false)
    }

    /// Live progress push for the CURRENT episode (positionData-driven);
    /// also updates the time text ("32m left" recalculated by the screen
    /// from the same data — card.dart:71-79).
    func updateLiveProgress(fraction: Double, rightText: String) {
        rightTextLabel.text = rightText
        rightTextLabel.isHidden = rightText.isEmpty
        applyProgress(fraction)
    }

    /// The meter shows only on progress cards with something played; the
    /// time left beside it reads in the primary text color, a plain time in
    /// the Meta color.
    private func applyProgress(_ fraction: Double) {
        let visible = showsProgress && fraction > 0
        progressMeter.isHidden = !visible
        progressMeter.setFraction(fraction)
        let percent = Int((min(max(fraction.isFinite ? fraction : 0, 0), 1) * 100).rounded())
        progressMeter.accessibilityLabel = "\(percent) percent played"
        rightTextLabel.textColor = visible ? Theme.onSurface : TypographyV2.meta.color
        // No time and no meter, or no show name before it: no dangling
        // separator.
        separatorLabel.isHidden = channelLabel.isHidden || (!visible && rightTextLabel.isHidden)
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
    ///
    /// Always lands on the SETTLED pose: the drawer at alpha 1 / identity
    /// with any reveal or fade cancelled, so a reconfigure never leaves a
    /// half-faded strip behind and the next reveal starts from a known state.
    func setExpanded(_ expanded: Bool) {
        drawer.layer.removeAllAnimations()
        drawer.alpha = 1
        drawer.transform = .identity
        stripHeightConstraint.constant = expanded ? Self.stripHeight : 0
        stripContainer.isHidden = !expanded
        layoutIfNeeded()
    }

    /// Whether the strip is open as a layout target (a fade-out in flight
    /// still counts as open until `setExpanded(false)` closes it).
    var isStripExpanded: Bool { !stripContainer.isHidden }

    /// Parks the just-opened drawer in its pre-reveal pose (invisible, one
    /// `stripRevealOffset` up under the card). Call right after
    /// `setExpanded(true)`, without animation, then run `revealStrip()`.
    func prepareStripReveal() {
        drawer.alpha = 0
        if !Motion.reduceMotion {
            drawer.transform = CGAffineTransform(translationX: 0, y: -Motion.stripRevealOffset)
        }
    }

    /// The drawer slides down out of the card while fading in. Only the
    /// strip moves — the card's own content never does. Reduce Motion
    /// fades only.
    func revealStrip() {
        let settle = {
            self.drawer.alpha = 1
            self.drawer.transform = .identity
        }
        if Motion.reduceMotion {
            UIView.animate(
                withDuration: Motion.standard, delay: 0,
                options: [.curveEaseOut, .allowUserInteraction], animations: settle
            )
        } else {
            UIView.animate(
                withDuration: Motion.standard, delay: 0,
                usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                options: [.allowUserInteraction], animations: settle
            )
        }
    }

    /// Brings a half-faded drawer back to the settled open pose — a strip
    /// that is re-targeted open while its fade-out is still running. A
    /// reveal in flight is left alone (its model values are already final).
    func cancelStripFade() {
        guard drawer.alpha < 1 else { return }
        drawer.layer.removeAllAnimations()
        drawer.alpha = 1
        drawer.transform = .identity
    }

    /// Fades the drawer out ahead of the height close; `completion` runs
    /// when the fade ends or is superseded, and must tolerate both.
    func fadeOutStrip(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: Motion.stripFadeOut, delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: { self.drawer.alpha = 0 },
            completion: { _ in completion() }
        )
    }

    // MARK: - Build

    /// The hairline is a CGColor (frozen at assignment, 09 §9a).
    private func updateCardStroke() {
        cardContainer.layer.borderColor = AnycastColor.sandAlpha3.resolvedColor(with: traitCollection).cgColor
    }

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

        // Card row (UI kit: surface plate, radius 32, sandAlpha3 hairline;
        // 16pt inner padding).
        cardContainer.backgroundColor = Theme.surface
        cardContainer.layer.borderWidth = Spacing.hairline
        updateCardStroke()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateCardStroke()
        }
        cardContainer.layer.cornerRadius = Radius.largeCard
        cardContainer.layer.cornerCurve = .continuous
        // Content never paints past the rounded plate.
        cardContainer.clipsToBounds = true
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(cardContainer)

        cardContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped)))
        cardContainer.isAccessibilityElement = false // children carry labels

        // Cover (64×64, rounded 16) — its own gesture beats the card tap.
        // UIImageView defaults to isUserInteractionEnabled = false, which
        // would swallow the gesture (tap falls through to the card expand) —
        // the Detail sheet would then be unreachable from every list.
        coverView.isUserInteractionEnabled = true
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.isAccessibilityElement = true
        coverView.accessibilityTraits = [.button]
        coverView.accessibilityLabel = "Episode details"
        cardContainer.addSubview(coverView)
        coverView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(coverTapped)))

        // Emphasis title on one line; labels truncate rather than wrap.
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        // The card action for VoiceOver (sighted users tap the whole card);
        // strip-less lists also hang the menu actions off it below.
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = [.button]
        titleLabel.onActivate = { [weak self] in self?.onCardTap?() }

        // Meta line: the show name gives way first; the separator, meter
        // and time keep their size.
        channelLabel.font = TypographyV2.meta.font()
        channelLabel.textColor = TypographyV2.meta.color
        channelLabel.numberOfLines = 1
        channelLabel.adjustsFontForContentSizeCategory = true
        channelLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        separatorLabel.text = "·"
        separatorLabel.font = TypographyV2.meta.font()
        separatorLabel.textColor = TypographyV2.meta.color
        separatorLabel.adjustsFontForContentSizeCategory = true
        separatorLabel.isAccessibilityElement = false

        progressMeter.trackColor = AnycastColor.sandAlpha4
        progressMeter.fillColor = Theme.primary
        progressMeter.minimumFillWidth = 3
        progressMeter.layer.cornerRadius = 2
        progressMeter.clipsToBounds = true
        progressMeter.isAccessibilityElement = true
        progressMeter.accessibilityIdentifier = "episode-card-meter"
        progressMeter.isHidden = true

        // Tabular figures (FontFeature.tabularFigures in the Dart row).
        rightTextLabel.font = TypographyV2.meta.font().monospacedDigits()
        rightTextLabel.textColor = TypographyV2.meta.color
        rightTextLabel.numberOfLines = 1
        rightTextLabel.adjustsFontForContentSizeCategory = true

        descriptionLabel.font = TypographyV2.meta.font()
        descriptionLabel.textColor = TypographyV2.meta.color
        descriptionLabel.numberOfLines = 1
        descriptionLabel.adjustsFontForContentSizeCategory = true
        // Layout-regression hook (the description is resolved async — tests
        // assert it gains a non-zero frame once the text lands).
        descriptionLabel.accessibilityIdentifier = "episode-card-description"

        let textColumn = UIStackView(arrangedSubviews: [titleLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.spacing = Spacing.xs
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(textColumn)

        downloadSlot.isHidden = true
        let metaRow = UIStackView(arrangedSubviews: [
            channelLabel, downloadSlot, separatorLabel, progressMeter, rightTextLabel,
        ])
        metaRow.axis = .horizontal
        metaRow.distribution = .fill
        metaRow.alignment = .center
        metaRow.spacing = Spacing.sm
        // The time hugs its text; the row's slack stays after it.
        let metaColumn = UIStackView(arrangedSubviews: [metaRow])
        metaColumn.axis = .vertical
        metaColumn.alignment = .leading
        textColumn.addArrangedSubview(metaColumn)
        textColumn.addArrangedSubview(descriptionLabel)

        // Download indicator (16×16) in the slot after the show name.
        downloadCircle.backgroundColor = Theme.primary
        downloadCircle.layer.cornerRadius = 8
        downloadCircle.translatesAutoresizingMaskIntoConstraints = false
        downloadCircle.isHidden = true
        downloadIcon.image = AppIcons.download
        downloadIcon.tintColor = Theme.onPrimary
        downloadIcon.contentMode = .scaleAspectFit
        downloadIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadCircle.addSubview(downloadIcon)
        downloadCircle.isAccessibilityElement = true
        downloadCircle.accessibilityTraits = [.button]
        downloadCircle.accessibilityLabel = "Download"
        downloadCircle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(downloadTapped)))
        cardContainer.addSubview(downloadCircle)

        downloadRing.tintColorOverride = Theme.primary
        downloadRing.translatesAutoresizingMaskIntoConstraints = false
        downloadRing.isHidden = true
        downloadRing.isAccessibilityElement = false
        cardContainer.addSubview(downloadRing)

        downloadDoneIcon.image = AppIcons.downloadDone
        // grass9 (03 §2.11), appearance-aware.
        downloadDoneIcon.tintColor = AnycastColor.grass9
        downloadDoneIcon.contentMode = .scaleAspectFit
        downloadDoneIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadDoneIcon.isHidden = true
        downloadDoneIcon.isAccessibilityElement = true
        downloadDoneIcon.accessibilityLabel = "Downloaded"
        cardContainer.addSubview(downloadDoneIcon)

        // Action drawer below the card (strip height animated 0↔60).
        stripContainer.translatesAutoresizingMaskIntoConstraints = false
        stripContainer.isHidden = true
        drawer.backgroundColor = AnycastColor.sandAlpha3
        drawer.translatesAutoresizingMaskIntoConstraints = false
        stripContainer.addSubview(drawer)
        drawerRow.axis = .horizontal
        drawerRow.alignment = .fill
        drawerRow.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(drawerRow)
        stripContainer.isUserInteractionEnabled = true
        stack.addArrangedSubview(stripContainer)
        // While the item height animates, the cell frame lags the strip's
        // height target by a few frames. The tail absorbs a taller frame and
        // the soft bottom pin gives way to a shorter one, so the card plate
        // keeps its size and position and only the strip area grows/closes.
        let tail = UIView()
        tail.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        tail.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        stack.addArrangedSubview(tail)
        stripHeightConstraint = stripContainer.heightAnchor.constraint(equalToConstant: 0)
        rightTextLabel.setContentHuggingPriority(.required, for: .horizontal)
        separatorLabel.setContentHuggingPriority(.required, for: .horizontal)
        separatorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightTextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The strip target is set before the item resizes, so the stack and
        // the cell briefly disagree on height. The bottom pin is breakable
        // (the stack overflows into the clipped area) and the plate holds
        // its own height, so only the strip moves while the cell catches up.
        let stackBottomPin = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        stackBottomPin.priority = .defaultHigh
        let plateHeight = cardContainer.heightAnchor.constraint(equalToConstant: Self.cardRowHeight)
        plateHeight.priority = UILayoutPriority(UILayoutPriority.defaultHigh.rawValue + 1)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackBottomPin,
            plateHeight,

            // 94 pt is the minimum (12 pt padding around the text column); the card
            // self-sizes taller when the scaled fonts demand it (hosts use
            // .estimated heights). The cover pins to the top only, so the
            // extra space at accessibility sizes goes to the text column.
            cardContainer.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.cardRowHeight),
            cardContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: Spacing.gap),
            coverView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.gap),
            coverView.widthAnchor.constraint(equalToConstant: Self.coverSide),
            coverView.heightAnchor.constraint(equalToConstant: Self.coverSide),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -Spacing.gap),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.gap),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -Spacing.gap),
            metaRow.widthAnchor.constraint(lessThanOrEqualTo: textColumn.widthAnchor),
            rightTextLabel.widthAnchor.constraint(lessThanOrEqualTo: textColumn.widthAnchor, multiplier: 0.5),

            progressMeter.widthAnchor.constraint(equalToConstant: 36),
            progressMeter.heightAnchor.constraint(equalToConstant: 4),

            downloadSlot.widthAnchor.constraint(equalToConstant: 16),
            downloadSlot.heightAnchor.constraint(equalToConstant: 16),
            downloadCircle.centerXAnchor.constraint(equalTo: downloadSlot.centerXAnchor),
            downloadCircle.centerYAnchor.constraint(equalTo: downloadSlot.centerYAnchor),
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

            // The drawer spans the full strip width, 12 pt under the card;
            // its segments split the width equally.
            drawer.leadingAnchor.constraint(equalTo: stripContainer.leadingAnchor),
            drawer.trailingAnchor.constraint(equalTo: stripContainer.trailingAnchor),
            drawer.topAnchor.constraint(equalTo: stripContainer.topAnchor, constant: Spacing.gap),
            drawer.heightAnchor.constraint(equalToConstant: Self.drawerHeight),
            drawerRow.leadingAnchor.constraint(equalTo: drawer.leadingAnchor, constant: Spacing.xs),
            drawerRow.trailingAnchor.constraint(equalTo: drawer.trailingAnchor, constant: -Spacing.xs),
            drawerRow.topAnchor.constraint(equalTo: drawer.topAnchor),
            drawerRow.bottomAnchor.constraint(equalTo: drawer.bottomAnchor),
            stripHeightConstraint,
        ])
    }

    // MARK: - Actions

    /// Mirrors `menuActions` onto the title as accessibility custom actions
    /// — the VoiceOver equivalent of the context menu (strip-less lists,
    /// 09 §7a-C1). Strip lists pass nothing and keep their strip buttons.
    private func applyMenuActions() {
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
        downloadSlot.isHidden = display == .hidden
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

    /// Equal segments split by hairlines; destructive (remove) actions in
    /// the error ink.
    private func rebuildActionButtons() {
        drawerRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionButtons = []
        guard !actions.isEmpty else { return }
        var firstButton: UIButton?
        for (index, action) in actions.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = AnycastColor.sandAlpha3
                divider.widthAnchor.constraint(equalToConstant: Spacing.hairline).isActive = true
                let dividerHost = UIView()
                dividerHost.addSubview(divider)
                divider.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    divider.centerXAnchor.constraint(equalTo: dividerHost.centerXAnchor),
                    divider.centerYAnchor.constraint(equalTo: dividerHost.centerYAnchor),
                    divider.heightAnchor.constraint(equalToConstant: Spacing.pageHeader),
                    dividerHost.widthAnchor.constraint(equalToConstant: Spacing.hairline),
                ])
                drawerRow.addArrangedSubview(dividerHost)
            }
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.image = action.icon.withRenderingMode(.alwaysTemplate)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            configuration.baseForegroundColor = action.accessibilityLabel.hasPrefix("Remove") ? Theme.error : Theme.onSurface
            button.configuration = configuration
            button.accessibilityLabel = action.accessibilityLabel
            button.tag = index
            button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
            button.addPressFeedback()
            drawerRow.addArrangedSubview(button)
            if let firstButton {
                button.widthAnchor.constraint(equalTo: firstButton.widthAnchor).isActive = true
            } else {
                firstButton = button
            }
            actionButtons.append(button)
        }
    }
}

/// A view whose corners always make a capsule of its current height.
final class CapsuleView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
    }
}
