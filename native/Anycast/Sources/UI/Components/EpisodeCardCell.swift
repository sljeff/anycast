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
    /// Circle with a download glyph; tap starts the download.
    case notDownloaded
    /// Progress ring 0…1.
    case downloading(Double)
    /// Check in secondary (sand) ink.
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

    /// The card's composition. `.playlist` is the list-owned-actions card
    /// (09 §7a, Playlist tab): a 72 pt cover, a two-line title and ONE meta
    /// row with no description, so its height (96 pt) is final at the first
    /// layout — no late description can push the action group.
    enum Layout: Equatable {
        case standard
        case playlist
        case show
    }
    var layout: Layout = .standard
    var inPlaylist = false

    /// The now-playing marker at the start of a playlist card's meta row.
    enum NowPlaying: Equatable {
        case none
        /// The current episode, not playing: a static glyph.
        case paused
        /// The current episode, playing: the glyph animates.
        case playing
    }
    var nowPlaying: NowPlaying = .none
}

/// Shared covered episode card. The list owns its action group; this cell
/// reserves only the selected card's transparent gap. Playlist and Show
/// compositions have no description or asynchronous text sizing.
private final class TitleActivatableLabel: UILabel {
    var onActivate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        onActivate?()
        return true
    }
}

final class EpisodeCardCell: UICollectionViewCell, ListActionGapHosting {

    static let reuseIdentifier = "EpisodeCardCell"
    /// 12 pt padding ×2 around the text column (22 title + 4 + 20 meta +
    /// 4 + 20 description), which is taller than the 64 pt cover.
    static let cardRowHeight: CGFloat = 94
    static let coverSide: CGFloat = 64
    /// The playlist composition: 12 + 72 cover + 12.
    static let playlistRowHeight: CGFloat = 96
    static let playlistCoverSide: CGFloat = 72
    /// 12 + two title lines (44) + 4 + fixed meta row (20) + 12.
    static let showRowHeight: CGFloat = 92
    static let spacing: CGFloat = Spacing.gap // list row gap (compact cards, 12)

    /// Card cover tap → open the Detail sheet.
    var onCoverTap: (() -> Void)?
    /// Whole-card tap toggles the list-owned group.
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
    /// Playlist cards only: the animated "wave" glyph of the current episode.
    private let nowPlayingMarker = UIImageView()
    private var nowPlayingState: EpisodeCardContent.NowPlaying = .none
    private let metaRow = UIStackView()
    private let metaColumn = UIStackView()
    private let textColumn = UIStackView()
    private var layout: EpisodeCardContent.Layout = .standard
    private var titleText = ""
    private var coverWidthConstraint: NSLayoutConstraint!
    private var coverHeightConstraint: NSLayoutConstraint!
    private var coverLeadingConstraint: NSLayoutConstraint!
    private var textTrailingConstraint: NSLayoutConstraint!
    private var plateHeightConstraint: NSLayoutConstraint!
    private var plateMinHeightConstraint: NSLayoutConstraint!
    /// Standard: the text column hangs from the top padding.
    private var textTopConstraint: NSLayoutConstraint!
    /// Playlist: the column centres on the cover, never above the padding.
    private var textTopMinConstraint: NSLayoutConstraint!
    private var textCenterConstraint: NSLayoutConstraint!
    private let downloadCircle = MinimumHitAreaView()
    private let cardTapGuard = DownloadTapGuard()
    private let downloadIcon = UIImageView()
    private let downloadRing = ProgressRingView(lineWidth: 3)
    private let downloadDoneIcon = UIImageView()
    /// The meta row's trailing slot the download indicator centers on.
    private let downloadSlot = UIView()

    private let actionSpacer = UIView()
    private var actionGapConstraint: NSLayoutConstraint!
    private let playlistChip = CapsuleView()
    private let playlistChipLabel = UILabel()
    private let metaSpacer = UIView()
    private var showMetaHeightConstraint: NSLayoutConstraint!
    private var timeWidthConstraint: NSLayoutConstraint!
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
        setActionGap(0)
        layer.removeAnimation(forKey: ListActionMotion.translationKey)
        cancelDescriptionTask()
        renderedDescriptionHTML = nil
        applyNowPlaying(.none)
        onCoverTap = nil
        onCardTap = nil
        onDownloadTap = nil
        menuActions = []
        layer.removeAllAnimations()
        alpha = 1
        // A reused cell must never inherit a card-entrance pose.
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    /// Drops the in-flight description resolve. Called on reuse and on
    /// every configure whose description source differs from the one the
    /// parse belongs to — the completion would otherwise write the prior
    /// episode's text onto the new content (only the source identity
    /// cancels it; a same-HTML reconfigure keeps it running).
    private func cancelDescriptionTask() {
        descriptionTask?.cancel()
        descriptionTask = nil
    }

    // MARK: - Configure

    func configure(_ content: EpisodeCardContent, actions: [EpisodeCardAction]) {
        // The list's cell provider re-applies the selected identity's gap AFTER
        // configure. Reconfiguration can happen without prepareForReuse.
        setActionGap(0)
        menuActions = actions
        contentView.isUserInteractionEnabled = true
        contentView.accessibilityElementsHidden = false
        titleLabel.setRealText(content.title)
        rightTextLabel.setRealText(content.rightText)
        titleLabel.textColor = TypographyV2.emphasis.color
        rightTextLabel.textColor = TypographyV2.meta.color
        coverView.alpha = 1
        applyLayout(content.layout)

        titleText = content.title
        applyTitle()
        channelLabel.text = content.channelTitle
        channelLabel.isHidden = !content.showsChannel
        rightTextLabel.text = content.rightText
        rightTextLabel.isHidden = content.rightText.isEmpty

        playlistChip.isHidden = content.layout != .show || !content.inPlaylist

        if content.layout != .standard {
            // No description line, so nothing to resolve: its late arrival
            // is exactly the height change the list-owned group cannot take.
            cancelDescriptionTask()
            renderedDescriptionHTML = nil
            descriptionLabel.text = ""
        } else if let plain = content.descriptionPlainText {
            if renderedDescriptionHTML != nil {
                cancelDescriptionTask()
            }
            renderedDescriptionHTML = nil
            descriptionLabel.text = plain
        } else if let html = content.descriptionHTML {
            if html != renderedDescriptionHTML {
                // Cancel the prior episode's in-flight resolve and clear the
                // reused text — a stale description must never linger while
                // the new one is parsed.
                cancelDescriptionTask()
                renderedDescriptionHTML = html
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
            if renderedDescriptionHTML != nil {
                cancelDescriptionTask()
            }
            renderedDescriptionHTML = nil
            descriptionLabel.text = ""
        }

        let url = content.imageURL.flatMap(URL.init(string:))
        if url != renderedCoverURL {
            renderedCoverURL = url
            coverView.kf.cancelDownloadTask()
            coverView.setArtwork(url, title: content.channelTitle, side: coverSide)
        }

        showsProgress = content.showsProgress
        applyProgress(content.progressFraction)
        applyNowPlaying(content.nowPlaying)

        configureDownload(content.downloadDisplay)
    }

    var actionGap: CGFloat { actionGapConstraint.constant }

    /// Change only the spacer target. The list must remeasure before settling
    /// layout, otherwise the old item height could compress the card body.
    func setActionGap(_ gap: CGFloat) {
        actionGapConstraint.constant = gap
    }

    var cardFrameInCell: CGRect { cardContainer.convert(cardContainer.bounds, to: self) }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if actionGap > 0, point.y >= bounds.maxY - actionGap { return false }
        return super.point(inside: point, with: event)
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

    // MARK: - Layout

    private var coverSide: CGFloat {
        layout == .playlist ? Self.playlistCoverSide : Self.coverSide
    }

    /// Switches the composition. Applied only on a change — a list renders
    /// one layout for every cell, so this runs once per cell instance, and
    /// the stack → plate hierarchy and the plate-height priority scheme
    /// stay what the list-action tests measure.
    private func applyLayout(_ new: EpisodeCardContent.Layout) {
        guard new != layout else { return }
        layout = new
        let playlist = new == .playlist
        let compact = new != .standard
        let rowHeight = playlist ? Self.playlistRowHeight : (new == .show ? Self.showRowHeight : Self.cardRowHeight)
        showMetaHeightConstraint.isActive = new == .show
        timeWidthConstraint.isActive = new != .show
        plateHeightConstraint.constant = rowHeight
        plateMinHeightConstraint.constant = rowHeight
        coverWidthConstraint.constant = coverSide
        coverHeightConstraint.constant = coverSide
        // The playlist plate follows the prototype's 12 pt padding all round.
        let padding = compact ? Spacing.gap : Spacing.pageH
        coverLeadingConstraint.constant = padding
        textTrailingConstraint.constant = -padding
        if compact {
            textTopConstraint.isActive = false
            textTopMinConstraint.isActive = true
            textCenterConstraint.isActive = true
        } else {
            textTopMinConstraint.isActive = false
            textCenterConstraint.isActive = false
            textTopConstraint.isActive = true
        }
        titleLabel.numberOfLines = compact ? 2 : 1
        descriptionLabel.isHidden = compact
        // Playlist: the meta row spans the column so the download mark sits
        // at its trailing end.
        metaColumn.alignment = compact ? .fill : .leading
        metaRow.spacing = playlist ? Spacing.md : Spacing.sm
        arrangeMetaRow()
        // The placeholder glyph is drawn for the cover's side.
        renderedCoverURL = nil
        applyTitle()
        setNeedsLayout()
    }

    /// Standard: show · download · meter · time. Playlist: marker · meter ·
    /// time · show, with the download mark closing the row. Views are only
    /// re-ordered inside the stack, never removed from the hierarchy (that
    /// would drop the size constraints that reference them) — except the
    /// marker, which has none.
    private func arrangeMetaRow() {
        for view in metaRow.arrangedSubviews {
            metaRow.removeArrangedSubview(view)
            view.isHidden = true
        }
        channelLabel.isHidden = false
        rightTextLabel.isHidden = false
        metaSpacer.isHidden = false
        let order: [UIView]
        if layout == .playlist {
            order = [
                nowPlayingMarker, progressMeter, rightTextLabel, separatorLabel, channelLabel, downloadSlot,
            ]
        } else if layout == .show {
            order = [channelLabel, separatorLabel, rightTextLabel, metaSpacer, playlistChip]
        } else {
            order = [channelLabel, downloadSlot, separatorLabel, progressMeter, rightTextLabel]
        }
        for view in order { metaRow.addArrangedSubview(view) }
    }

    /// The playlist title is attributed so two lines keep the 22 pt line
    /// height; it is re-applied when the content size changes because an
    /// attributed font does not follow Dynamic Type by itself.
    private func applyTitle() {
        guard layout != .standard else {
            titleLabel.text = titleText
            return
        }
        var attributes = TypographyV2.emphasis.attributes(traits: traitCollection)
        let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy()
            as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        attributes[.paragraphStyle] = paragraph
        titleLabel.attributedText = NSAttributedString(string: titleText, attributes: attributes)
    }

    // MARK: - Now playing

    /// Marker state push for playlist cards. Playback ticks never come here
    /// (they use `updateLiveProgress`); only the current episode changing or
    /// play/pause flipping does, and an unchanged state is a no-op so the
    /// symbol effect is not restarted.
    func updateNowPlaying(_ state: EpisodeCardContent.NowPlaying) {
        applyNowPlaying(state)
    }

    private func applyNowPlaying(_ state: EpisodeCardContent.NowPlaying) {
        guard state != nowPlayingState else { return }
        nowPlayingState = state
        nowPlayingMarker.isHidden = state == .none
        refreshMarkerEffect()
    }

    /// Reduce Motion keeps the glyph still. Symbol effects stop when the
    /// view leaves the window, so `didMoveToWindow` re-arms them.
    private func refreshMarkerEffect() {
        nowPlayingMarker.removeAllSymbolEffects()
        if nowPlayingState == .playing, !Motion.reduceMotion {
            nowPlayingMarker.addSymbolEffect(.variableColor.iterative, options: .repeating)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, nowPlayingState == .playing { refreshMarkerEffect() }
    }

    /// Live download-state push (PlaybackService.cacheStates).
    func updateDownload(_ display: DownloadDisplay) {
        configureDownload(display)
    }

    /// The same plate, cover and text constraints as loaded Show cards.
    func configureSkeleton() {
        configure(EpisodeCardContent(
            title: "Placeholder episode title text", channelTitle: "", rightText: "Placeholder meta",
            descriptionHTML: nil, imageURL: nil, showsChannel: false, layout: .show
        ), actions: [])
        titleLabel.setSkeletonBar("Placeholder episode title text")
        rightTextLabel.setSkeletonBar("Placeholder meta")
        coverView.kf.cancelDownloadTask()
        coverView.image = nil
        renderedCoverURL = nil
        contentView.isUserInteractionEnabled = false
        contentView.accessibilityElementsHidden = true
        onCardTap = nil
        onCoverTap = nil
    }

    // MARK: - Build

    /// The hairline is a CGColor (frozen at assignment, 09 §9a).
    private func updateCardStroke() {
        cardContainer.layer.borderColor = AnycastColor.sandAlpha3.resolvedColor(with: traitCollection).cgColor
    }

    private func build() {
        contentView.backgroundColor = .clear
        // The plate never paints over adjacent cards during gap remeasurement.
        clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        // Card row (UI kit: surface plate, radius 32, 16pt inner padding).
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

        let cardTap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        cardTap.delegate = cardTapGuard
        cardContainer.addGestureRecognizer(cardTap)
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

        textColumn.addArrangedSubview(titleLabel)
        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.spacing = Spacing.xs
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(textColumn)

        downloadSlot.isHidden = true
        for view in [channelLabel, downloadSlot, separatorLabel, progressMeter, rightTextLabel] {
            metaRow.addArrangedSubview(view)
        }
        metaRow.axis = .horizontal
        metaRow.distribution = .fill
        metaRow.alignment = .center
        metaRow.spacing = Spacing.sm
        // The time hugs its text; the row's slack stays after it.
        metaColumn.addArrangedSubview(metaRow)
        metaColumn.axis = .vertical
        metaColumn.alignment = .leading
        textColumn.addArrangedSubview(metaColumn)
        textColumn.addArrangedSubview(descriptionLabel)

        // The now-playing glyph (playlist cards): ink, 13 pt, a waveform that
        // sweeps while the episode plays.
        nowPlayingMarker.image = UIImage(systemName: "waveform")
        nowPlayingMarker.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        nowPlayingMarker.tintColor = Theme.onSurface
        nowPlayingMarker.contentMode = .center
        nowPlayingMarker.isHidden = true
        nowPlayingMarker.isAccessibilityElement = true
        nowPlayingMarker.accessibilityLabel = "Now playing"
        nowPlayingMarker.setContentHuggingPriority(.required, for: .horizontal)
        nowPlayingMarker.setContentCompressionResistancePriority(.required, for: .horizontal)

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
        downloadCircle.enableIconLargeContentViewer(title: "Download", image: AppIcons.download)
        downloadCircle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(downloadTapped)))
        cardTapGuard.download = downloadCircle
        cardTapGuard.cover = coverView
        cardContainer.addSubview(downloadCircle)

        downloadRing.tintColorOverride = Theme.primary
        downloadRing.translatesAutoresizingMaskIntoConstraints = false
        downloadRing.isHidden = true
        downloadRing.isAccessibilityElement = false
        cardContainer.addSubview(downloadRing)

        downloadDoneIcon.image = AppIcons.downloadDone
        // Completed is secondary (sand), not a status colour.
        downloadDoneIcon.tintColor = Theme.onSurfaceVariant
        downloadDoneIcon.contentMode = .scaleAspectFit
        downloadDoneIcon.translatesAutoresizingMaskIntoConstraints = false
        downloadDoneIcon.isHidden = true
        downloadDoneIcon.isAccessibilityElement = true
        downloadDoneIcon.accessibilityLabel = "Downloaded"
        cardContainer.addSubview(downloadDoneIcon)

        actionSpacer.isUserInteractionEnabled = false
        stack.addArrangedSubview(actionSpacer)
        actionGapConstraint = actionSpacer.heightAnchor.constraint(equalToConstant: 0)
        actionGapConstraint.isActive = true
        showMetaHeightConstraint = metaRow.heightAnchor.constraint(equalToConstant: 20)
        timeWidthConstraint = rightTextLabel.widthAnchor.constraint(
            lessThanOrEqualTo: textColumn.widthAnchor, multiplier: 0.5)
        timeWidthConstraint.isActive = true
        playlistChip.backgroundColor = AnycastColor.sandAlpha3
        playlistChip.isHidden = true
        playlistChip.accessibilityIdentifier = "episode-card-in-playlist"
        playlistChipLabel.text = "In playlist"
        playlistChipLabel.font = .systemFont(ofSize: 13)
        playlistChipLabel.textColor = Theme.onSurface
        playlistChipLabel.translatesAutoresizingMaskIntoConstraints = false
        playlistChip.addSubview(playlistChipLabel)
        playlistChip.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            playlistChip.heightAnchor.constraint(equalToConstant: 20),
            playlistChipLabel.leadingAnchor.constraint(equalTo: playlistChip.leadingAnchor, constant: 6),
            playlistChipLabel.trailingAnchor.constraint(equalTo: playlistChip.trailingAnchor, constant: -6),
            playlistChipLabel.centerYAnchor.constraint(equalTo: playlistChip.centerYAnchor),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: EpisodeCardCell, _) in
            cell.applyTitle()
        }
        rightTextLabel.setContentHuggingPriority(.required, for: .horizontal)
        separatorLabel.setContentHuggingPriority(.required, for: .horizontal)
        separatorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightTextLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The plate holds its height while the list remeasures the gap.
        let stackBottomPin = stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        stackBottomPin.priority = .defaultHigh
        let plateHeight = cardContainer.heightAnchor.constraint(equalToConstant: Self.cardRowHeight)
        plateHeight.priority = UILayoutPriority(UILayoutPriority.defaultHigh.rawValue + 1)
        plateHeightConstraint = plateHeight
        plateMinHeightConstraint = cardContainer.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Self.cardRowHeight)
        coverWidthConstraint = coverView.widthAnchor.constraint(equalToConstant: Self.coverSide)
        coverHeightConstraint = coverView.heightAnchor.constraint(equalToConstant: Self.coverSide)
        coverLeadingConstraint = coverView.leadingAnchor.constraint(
            equalTo: cardContainer.leadingAnchor, constant: Spacing.pageH)
        textTrailingConstraint = textColumn.trailingAnchor.constraint(
            equalTo: cardContainer.trailingAnchor, constant: -Spacing.pageH)
        textTopConstraint = textColumn.topAnchor.constraint(
            equalTo: cardContainer.topAnchor, constant: Spacing.gap)
        textTopMinConstraint = textColumn.topAnchor.constraint(
            greaterThanOrEqualTo: cardContainer.topAnchor, constant: Spacing.gap)
        textCenterConstraint = textColumn.centerYAnchor.constraint(equalTo: coverView.centerYAnchor)
        textCenterConstraint.priority = .defaultHigh

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
            plateMinHeightConstraint,
            cardContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor),

            coverLeadingConstraint,
            coverView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: Spacing.gap),
            coverWidthConstraint,
            coverHeightConstraint,

            textColumn.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: Spacing.gap),
            textTrailingConstraint,
            textTopConstraint,
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -Spacing.gap),
            metaRow.widthAnchor.constraint(lessThanOrEqualTo: textColumn.widthAnchor),

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

        ])
    }

    // MARK: - Actions

    /// Mirrors `menuActions` onto the title as accessibility custom actions
    /// — the VoiceOver equivalent of the context menu (09 §7a-C1).
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


}

/// Card taps pass through except on the download control, whose hit area
/// is larger than the 16 pt disc.
@MainActor
private final class DownloadTapGuard: NSObject, UIGestureRecognizerDelegate {
    weak var download: UIView?
    weak var cover: UIView?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let cover, cover.bounds.contains(touch.location(in: cover)) { return false }
        guard let download, !download.isHidden else { return true }
        return download.point(inside: touch.location(in: download), with: nil) == false
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
