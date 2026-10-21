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

/// The generic episode card (lib/widgets/card.dart:30-297, 03 §2.11) in the
/// Anycast 2.0 UI kit row form (`QueueRowCell`): the shared card plate
/// (radius 32, hairline), an 80 pt rounded cover (tap → Detail), a two-line
/// 20 pt title, channel name (max 114pt) + duration/relative time, and a
/// 2-line description. Whole-card tap toggles the action drawer — a split
/// capsule of equal segments (UI kit `QueueSplitCapsuleButtonGroup`);
/// playlist cards add the progress backdrop and the download indicator. Lists that took the native-first path (09 §7a-C1,
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
    static let cardRowHeight: CGFloat = 112   // 80pt cover + 16pt padding ×2 (09 §5)
    static let stripHeight: CGFloat = 60
    /// The drawer capsule inside the strip (12 pt above it, then 48 pt).
    static let drawerHeight: CGFloat = 48
    static let spacing: CGFloat = Spacing.pageH // list row gap (09 §5 gap16)

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
    private let rightTextLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressBackdrop = EpisodeProgressBackdrop()
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
        rightTextLabel.text = content.rightText

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
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.isAccessibilityElement = true
        coverView.accessibilityTraits = [.button]
        coverView.accessibilityLabel = "Episode details"
        cardContainer.addSubview(coverView)
        coverView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(coverTapped)))

        // UI kit row title: 20 pt regular, wraps to two lines.
        titleLabel.font = TypographyV2.cardTitle.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        // The card action for VoiceOver (sighted users tap the whole card);
        // strip-less lists also hang the menu actions off it below.
        titleLabel.isAccessibilityElement = true
        titleLabel.accessibilityTraits = [.button]
        titleLabel.onActivate = { [weak self] in self?.onCardTap?() }

        let metaMetrics = UIFontMetrics(forTextStyle: .caption1)
        channelLabel.font = TypographyV2.caption.font()
        channelLabel.textColor = Theme.onSurfaceVariant
        channelLabel.numberOfLines = 1
        channelLabel.adjustsFontForContentSizeCategory = true

        // Tabular figures (FontFeature.tabularFigures in the Dart row).
        rightTextLabel.font = metaMetrics.scaledFont(
            for: ThemeRegistry.current.typography.font(12, .regular, .text).monospacedDigits()
        )
        rightTextLabel.textColor = Theme.onSurfaceVariant
        rightTextLabel.numberOfLines = 1
        rightTextLabel.adjustsFontForContentSizeCategory = true
        rightTextLabel.textAlignment = .right

        descriptionLabel.font = TypographyV2.bodyCompact.font()
        descriptionLabel.textColor = Theme.onSurfaceVariant
        descriptionLabel.numberOfLines = 2
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

        let metaRow = UIStackView(arrangedSubviews: [channelLabel])
        metaRow.axis = .horizontal
        metaRow.distribution = .fill
        metaRow.alignment = .center
        metaRow.spacing = 8
        metaRow.addArrangedSubview(rightTextLabel)
        downloadSlot.isHidden = true
        metaRow.addArrangedSubview(downloadSlot)
        textColumn.addArrangedSubview(metaRow)
        textColumn.addArrangedSubview(descriptionLabel)

        // Channel name caps at 114pt so the right text never starves
        // (ConstrainedBox maxWidth 114, card.dart:150-162).
        channelMaxWidth = channelLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 114)

        // Progress backdrop: 4pt strip along the card bottom edge.
        progressBackdrop.trackColor = AnycastColor.sandAlpha3
        progressBackdrop.fillColor = Theme.primary
        progressBackdrop.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(progressBackdrop)

        // Download indicator (16×16) in the meta row's trailing slot.
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

            // 112 pt is the minimum (80pt cover + 16pt padding ×2); the card
            // self-sizes taller when the scaled fonts demand it (hosts use
            // .estimated heights). The cover pins to the top only, so the
            // extra space at accessibility sizes goes to the text column.
            cardContainer.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Self.cardRowHeight),
            cardContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            coverView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: Spacing.pageH),
            coverView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.pageH),
            coverView.widthAnchor.constraint(equalToConstant: 80),
            coverView.heightAnchor.constraint(equalToConstant: 80),

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.pageH),
            textColumn.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -Spacing.pageH),
            textColumn.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.pageH),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -Spacing.pageH),
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
