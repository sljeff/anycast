import UIKit
import Kingfisher
import AnycastKit

/// The episode Detail sheet (design canvas D3, adopted 2026-10-21): it opens
/// at a 460 pt medium detent — on iOS 26 a floating card inset from the
/// screen edges — and drags up to large. Content sits 28 pt in: the cover
/// beside the title, the show (opens the Channel sheet ON TOP — 03 §10.1)
/// and the date · duration line, then the HTML show notes. At an
/// accessibility size the title stays full width and the cover sits beside
/// the channel line, shrunk so it does not grow with the text. Corners on
/// this sheet are concentric with the 54 pt sheet corner
/// (`Radius.concentric`). The actions stay at the bottom in thumb reach over
/// a soft fade — unless that identity still does not fit, in which case the
/// header, transcript row and actions scroll together. A fold fade covers a
/// card the viewport cuts, and it stays above the sheet arc. A Play capsule
/// carries the episode's progress ("Resume · 32m left") and a ••• menu with
/// Add to playlist, Share episode, Copy link and the remaining actions.
/// A transcript status row sits in the same thumb reach, just above the
/// actions: whether this episode can be transcribed, what it costs, and the
/// one next step. Preserved v1 behaviors: actions auto-dismiss this sheet
/// after firing (03 §10.1 wrapper quirk), share → shortlink →
/// UIActivityViewController. Transcript taps that open the player dismiss
/// the sheet themselves; Generate stays here.
///
/// Presenters inject behavior: `openChannel`, `shortenURL`, the action
/// closures inside `EpisodeCardAction`, and whether the episode is already
/// in the playlist.
@MainActor
final class DetailViewController: UIViewController {

    struct Episode {
        var title: String
        var channelTitle: String
        var pubDateMilliseconds: Int64?
        /// Enclosure duration; nil or zero hides it from the meta line and
        /// the Play label.
        var durationMilliseconds: Int64?
        /// How much has been played; above zero the Play capsule resumes.
        var playedMilliseconds: Int64?
        var imageURL: String?
        var rssFeedURL: String
        var enclosureURL: String
        var descriptionHTML: String

        init(
            title: String,
            channelTitle: String,
            pubDateMilliseconds: Int64? = nil,
            durationMilliseconds: Int64? = nil,
            playedMilliseconds: Int64? = nil,
            imageURL: String? = nil,
            rssFeedURL: String,
            enclosureURL: String,
            descriptionHTML: String = ""
        ) {
            self.title = title
            self.channelTitle = channelTitle
            self.pubDateMilliseconds = pubDateMilliseconds
            self.durationMilliseconds = durationMilliseconds
            self.playedMilliseconds = playedMilliseconds
            self.imageURL = imageURL
            self.rssFeedURL = rssFeedURL
            self.enclosureURL = enclosureURL
            self.descriptionHTML = descriptionHTML
        }
    }

    /// Identifies the channel to open on top of this sheet
    /// (Detail does not close — 03 §10.1).
    struct ChannelReference {
        var rssFeedURL: String
        var title: String
    }

    /// The Play capsule's label and the share of it filled as progress.
    struct PlayLabel: Equatable {
        var title: String
        var fraction: Double

        /// "Resume · 32m left" once played, "Play · 80m" before, "Play"
        /// without a known duration.
        static func make(durationMilliseconds: Int64?, playedMilliseconds: Int64?) -> PlayLabel {
            let duration = durationMilliseconds ?? 0
            let played = playedMilliseconds ?? 0
            guard duration > 0 else { return PlayLabel(title: "Play", fraction: 0) }
            if played > 0 {
                let left = PlaylistCardDisplay.timeLeft(
                    durationMilliseconds: duration, playedMilliseconds: played
                )
                return PlayLabel(
                    title: "Resume · \(left)",
                    fraction: min(Double(played) / Double(duration), 1)
                )
            }
            return PlayLabel(title: "Play · \(TimeFormats.formatDuration(duration))", fraction: 0)
        }
    }

    var openChannel: ((ChannelReference) -> Void)?
    /// Shortens the share URL through /api/shortlink; nil or a nil result
    /// degrades to the original URL (G12 contract).
    var shortenURL: ((URL) async -> URL?)?

    private let episode: Episode
    /// The episode already sits in the playlist: the menu shows a disabled
    /// "In playlist" in place of the add action.
    private let isInPlaylist: Bool
    private let actions: [EpisodeCardAction]
    /// LEGACY parameter, kept in the init/present signatures so existing
    /// call sites stay untouched: the show notes no longer route through
    /// HTMLContentRenderer. The notes render through ShowNotesStore into
    /// the ShowNotesTextView below; this instance is stored but unused.
    private let htmlRenderer: HTMLContentRenderer
    private let now: () -> Date
    /// Nil only for callers that have no playback context (the row hides).
    private let transcript: DetailTranscriptCoordinator?
    /// Snapshot stand-in. When set, the row paints this and does not read the account.
    private let transcriptPreview: DetailTranscriptContent?

    private let scrollView = UIScrollView()
    private let descriptionTextView: ShowNotesTextView
    private let artwork = UIImageView()
    private var artworkSide: NSLayoutConstraint!
    private var headerStack: UIStackView!
    private var infoStack: UIStackView!
    private var contentStack: UIStackView!
    private var contentContainer: UIView!
    private var artworkWrap: UIView!
    /// Cover beside the channel name at accessibility sizes. Not in the
    /// hierarchy at the default size.
    private let identityRow = UIStackView()
    /// Label plus the channel button, as siblings, so the label cannot
    /// swallow the tap.
    private let channelBlock = UIView()
    private var channelButton: UIButton!
    /// Draws the channel name at accessibility sizes. A UIButton title stays
    /// one line tall and clips the wrap; this label is the text, and the
    /// button stays the hit target.
    private let channelNameLabel = UILabel()
    private var channelHitPins: [NSLayoutConstraint] = []
    private var metaLabel: UILabel!
    private let titleLabel = UILabel()
    /// One shot after the first layout, and again when the text size changes,
    /// so the medium detent can grow instead of clipping an accessibility-size header.
    private var needsDetentRefresh = true
    /// Laid-out height of the header plus the pinned chrome. The detent
    /// closure reads this; it is updated from the views' bounds, not from a
    /// nested fitting pass.
    private var accessibilityDetentHeight: CGFloat = Layout.mediumHeight
    private var didMeasureAccessibilityDetent = false
    /// Takes the slack below the meta line so the column stays top-aligned
    /// beside the cover at both detents.
    private let trailingSpacer = UIView()
    private let actionRow = UIStackView()
    private var playButton: UIButton!
    private var moreButton: AnycastIconButton!
    private let transcriptRow = DetailTranscriptRow()
    /// Wraps the row so hiding it (no coordinator, or medium when the
    /// policy says so) collapses to zero without fighting the row's own
    /// minimum height.
    private let transcriptSlot = UIView()
    private let statusLoop = ObservationLoop()
    private var actionRowHeight: NSLayoutConstraint!
    private var actionLeading: NSLayoutConstraint!
    private var actionTrailing: NSLayoutConstraint!
    private var actionSafeBottom: NSLayoutConstraint!
    private var rowBottom: NSLayoutConstraint!
    private var transcriptLeading: NSLayoutConstraint!
    private var transcriptTrailing: NSLayoutConstraint!
    private var scrollAboveTranscript: NSLayoutConstraint!
    private var scrollFullBottom: NSLayoutConstraint!
    private var contentBottom: NSLayoutConstraint!
    /// Active only while the actions scroll with the notes. They pin the
    /// transcript row and Play inside the scroll content.
    private var scrollTranscriptTop: NSLayoutConstraint!
    private var scrollTranscriptLeading: NSLayoutConstraint!
    private var scrollTranscriptTrailing: NSLayoutConstraint!
    private var scrollActionLeading: NSLayoutConstraint!
    private var scrollActionTrailing: NSLayoutConstraint!
    private var scrollActionBottom: NSLayoutConstraint!
    /// Accessibility sizes unpin Play when the title, channel and date do
    /// not fit above it. They then scroll with the notes.
    private var scrollsChrome = false
    /// One flash after the actions join the scroll view, so a cut-off block
    /// reads as more content rather than as the end of the text.
    private var needsScrollHint = false
    private var transcriptGap: NSLayoutConstraint!
    private var transcriptSlotHeight: NSLayoutConstraint!
    private var transcriptRowPins: [NSLayoutConstraint] = []
    private let bottomFade = GradientFadeLayerView()
    private var fadeLeading: NSLayoutConstraint!
    private var fadeTrailing: NSLayoutConstraint!
    private var fadeTop: NSLayoutConstraint!

    private enum Layout {
        static let mediumHeight: CGFloat = 460
        /// Header inset. The bottom stack's inset comes from `Radius.concentric`.
        static let inset: CGFloat = Spacing.sheetContent
        static let artworkMedium: CGFloat = 120
        static let artworkLarge: CGFloat = 160
        static let actionHeight: CGFloat = Radius.sheetCapsuleHeight
        static let fadeHeight: CGFloat = 40
        /// Clear band between the notes' fade and the action row.
        static let rowGap: CGFloat = Spacing.sm
    }

    static let mediumDetent = UISheetPresentationController.Detent.Identifier("detail-medium")

    static func present(
        from presenter: UIViewController,
        episode: Episode,
        actions: [EpisodeCardAction],
        htmlRenderer: HTMLContentRenderer,
        openChannel: ((ChannelReference) -> Void)? = nil,
        shortenURL: ((URL) async -> URL?)? = nil,
        isInPlaylist: Bool = false,
        transcript: DetailTranscriptCoordinator? = nil,
        transcriptPreview: DetailTranscriptContent? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        let controller = DetailViewController(
            episode: episode,
            actions: actions,
            htmlRenderer: htmlRenderer,
            openChannel: openChannel,
            shortenURL: shortenURL,
            isInPlaylist: isInPlaylist,
            transcript: transcript,
            transcriptPreview: transcriptPreview,
            now: now
        )
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            // Medium is the floating 460 pt card; the system draws its inset
            // and corners on iOS 26. Two detents, so the grabber shows.
            sheet.detents = [
                .custom(identifier: mediumDetent) { [weak controller] context in
                    let cap = context.maximumDetentValue
                    let base = min(Layout.mediumHeight, cap)
                    guard let controller,
                          controller.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
                    else { return base }
                    // Accessibility sizes: grow so the title, transcript row and
                    // Play fit. Notes stay in the scroll view. Never below the
                    // regular 460, never past the sheet.
                    return min(max(controller.accessibilityMediumDetentHeight(maximum: cap), base), cap)
                },
                .large(),
            ]
            sheet.selectedDetentIdentifier = mediumDetent
            sheet.prefersGrabberVisible = true
            sheet.delegate = controller
        }
        presenter.present(controller, animated: true)
    }

    init(
        episode: Episode,
        actions: [EpisodeCardAction],
        htmlRenderer: HTMLContentRenderer,
        openChannel: ((ChannelReference) -> Void)? = nil,
        shortenURL: ((URL) async -> URL?)? = nil,
        isInPlaylist: Bool = false,
        transcript: DetailTranscriptCoordinator? = nil,
        transcriptPreview: DetailTranscriptContent? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.episode = episode
        self.actions = actions
        self.htmlRenderer = htmlRenderer
        self.openChannel = openChannel
        self.shortenURL = shortenURL
        self.isInPlaylist = isInPlaylist
        self.transcript = transcript
        self.transcriptPreview = transcriptPreview
        self.now = now
        self.descriptionTextView = ShowNotesTextView()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        build()
        renderDescription()
        startTranscript()
    }

    // MARK: - Build

    private func build() {
        view.backgroundColor = Theme.surface

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let content = buildContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        // The notes fade out above the actions; the scroll view itself ends
        // there (below), so nothing is ever drawn under or beside the row.
        bottomFade.configure(color: Theme.surface, fromTop: false)
        bottomFade.isUserInteractionEnabled = false
        bottomFade.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomFade)

        buildActionRow()
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionRow)

        transcriptSlot.translatesAutoresizingMaskIntoConstraints = false
        transcriptSlot.setContentHuggingPriority(.required, for: .vertical)
        transcriptSlot.setContentCompressionResistancePriority(.required, for: .vertical)
        view.addSubview(transcriptSlot)
        transcriptRow.translatesAutoresizingMaskIntoConstraints = false
        transcriptRow.onAction = { [weak self] action in
            guard let self, let transcript = self.transcript else { return }
            transcript.handle(action, from: self)
        }
        transcriptSlot.addSubview(transcriptRow)
        transcriptRowPins = [
            transcriptRow.topAnchor.constraint(equalTo: transcriptSlot.topAnchor),
            transcriptRow.bottomAnchor.constraint(equalTo: transcriptSlot.bottomAnchor),
            transcriptRow.leadingAnchor.constraint(equalTo: transcriptSlot.leadingAnchor),
            transcriptRow.trailingAnchor.constraint(equalTo: transcriptSlot.trailingAnchor),
        ]
        // Keep a collapsed slot unambiguous. Required pins replace these
        // while the row is showing; the equations match, so they don't fight.
        for anchor in [
            transcriptRow.topAnchor.constraint(equalTo: transcriptSlot.topAnchor),
            transcriptRow.leadingAnchor.constraint(equalTo: transcriptSlot.leadingAnchor),
            transcriptRow.trailingAnchor.constraint(equalTo: transcriptSlot.trailingAnchor),
        ] {
            anchor.priority = .fittingSizeLevel
            anchor.isActive = true
        }

        // 28 pt from the floating card's bottom; at large the home
        // indicator's safe area wins. Accessibility sizes add the sheet
        // corner's arc clearance so Play and ••• stay outside the curve.
        rowBottom = actionRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.inset)
        rowBottom.priority = .defaultHigh
        actionLeading = actionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.inset)
        actionTrailing = actionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.inset)
        actionSafeBottom = actionRow.bottomAnchor.constraint(
            lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        actionRowHeight = actionRow.heightAnchor.constraint(equalToConstant: Layout.actionHeight)
        // The slot hugs the row. Height 0 keeps the notes-to-actions gap
        // unchanged when the row is hidden.
        transcriptGap = transcriptSlot.bottomAnchor.constraint(
            equalTo: actionRow.topAnchor, constant: -Spacing.md
        )
        transcriptSlotHeight = transcriptSlot.heightAnchor.constraint(equalToConstant: 0)
        transcriptLeading = transcriptSlot.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: Layout.inset
        )
        transcriptTrailing = transcriptSlot.trailingAnchor.constraint(
            equalTo: view.trailingAnchor, constant: -Layout.inset
        )
        scrollAboveTranscript = scrollView.bottomAnchor.constraint(
            equalTo: transcriptSlot.topAnchor, constant: -Layout.rowGap
        )
        scrollFullBottom = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        // Used when the identity does not fit above the pinned actions. They
        // stay inactive so the default size keeps Play pinned.
        scrollTranscriptTop = transcriptSlot.topAnchor.constraint(
            equalTo: contentStack.bottomAnchor, constant: Spacing.cardInner
        )
        scrollTranscriptLeading = transcriptSlot.leadingAnchor.constraint(
            equalTo: contentContainer.leadingAnchor, constant: Layout.inset
        )
        scrollTranscriptTrailing = transcriptSlot.trailingAnchor.constraint(
            equalTo: contentContainer.trailingAnchor, constant: -Layout.inset
        )
        scrollActionLeading = actionRow.leadingAnchor.constraint(
            equalTo: contentContainer.leadingAnchor, constant: Layout.inset
        )
        scrollActionTrailing = actionRow.trailingAnchor.constraint(
            equalTo: contentContainer.trailingAnchor, constant: -Layout.inset
        )
        scrollActionBottom = actionRow.bottomAnchor.constraint(
            equalTo: contentContainer.bottomAnchor, constant: -Layout.inset
        )
        fadeTop = bottomFade.topAnchor.constraint(
            equalTo: scrollView.bottomAnchor, constant: -Layout.fadeHeight
        )
        fadeLeading = bottomFade.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        fadeTrailing = bottomFade.trailingAnchor.constraint(equalTo: view.trailingAnchor)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollAboveTranscript,

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            // Vertical-only scrolling: content is exactly as wide as the
            // visible sheet (long text otherwise ran past inset sheets).
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            actionLeading,
            actionTrailing,
            actionRowHeight,
            actionSafeBottom,
            rowBottom,

            transcriptLeading,
            transcriptTrailing,
            transcriptGap,

            fadeTop,
            fadeLeading,
            fadeTrailing,
            bottomFade.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])

        // The notes also melt away under the sheet's top edge once scrolled
        // (the column rests `Layout.inset` below it, exactly at the strip's
        // bottom).
        ScrollEdgeChrome.attachTopEdge(
            to: scrollView, in: view, height: Layout.inset, fadeColor: Theme.surface, restingGap: 0
        )

        // The last line of the notes scrolls to rest above the fade.
        scrollView.contentInset.bottom = Layout.fadeHeight
        applyDetentLayout()
        applyActionRowMetrics()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.needsDetentRefresh = true
            self.applyActionRowMetrics()
            self.applyDetentLayout()
            self.sheetPresentationController?.invalidateDetents()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if accessibility, headerStack != nil {
            let transcriptHeight = transcriptSlot.isHidden ? 0 : transcriptSlot.bounds.height
            // The scroll view's bottom fade covers its last 40 pt. Add that
            // much so a pinned header clears the fade. The sheet still caps
            // this at its maximum; updateChromeScrolling unpins when the cap
            // leaves the date under the fade.
            let bottom = self.sheetChrome().inset
            let measured = Layout.inset + headerStack.bounds.height + Layout.fadeHeight + Layout.rowGap
                + transcriptHeight + Spacing.md + actionRow.bounds.height + bottom
            if !didMeasureAccessibilityDetent || abs(measured - accessibilityDetentHeight) > 1 {
                didMeasureAccessibilityDetent = true
                accessibilityDetentHeight = measured
                needsDetentRefresh = true
            }
            updateScrollContentInsets()
            updateChromeScrolling()
            updateFoldTreatment()
            let overflows = scrollView.contentSize.height > scrollView.bounds.height + 1
            scrollView.showsVerticalScrollIndicator = overflows || scrollsChrome
        } else {
            if scrollsChrome { setScrollsChrome(false) }
            scrollView.showsVerticalScrollIndicator = false
        }
        if needsScrollHint, scrollView.contentSize.height > scrollView.bounds.height + 1 {
            needsScrollHint = false
            scrollView.flashScrollIndicators()
        }
        guard needsDetentRefresh else { return }
        needsDetentRefresh = false
        sheetPresentationController?.invalidateDetents()
    }

    /// Pins Play unless the title, channel and date would sit under the fade
    /// or past the scroll view. The comparison uses the pinned chrome height,
    /// not the live scroll-view frame, so turning scrolling on does not
    /// immediately turn it back off.
    private func updateChromeScrolling() {
        guard view.bounds.height > 1, contentContainer.bounds.width > 1 else { return }
        let transcriptHeight = transcriptSlot.isHidden ? 0 : transcriptSlot.bounds.height
        let transcriptGapHeight = transcriptSlot.isHidden ? 0 : Spacing.md
        let bottomInset = max(sheetChrome().inset, view.safeAreaInsets.bottom)
        let chrome = Layout.rowGap + transcriptHeight + transcriptGapHeight
            + actionRow.bounds.height + bottomInset
        let visibleBottom = view.bounds.height - chrome - Layout.fadeHeight
        let identityBottom = max(
            bottom(of: metaLabel, in: contentContainer),
            bottom(of: channelBlock, in: contentContainer)
        )
        guard identityBottom > 0 else { return }
        let shouldScroll = identityBottom > visibleBottom + 0.5
        guard shouldScroll != scrollsChrome else { return }
        setScrollsChrome(shouldScroll)
        needsDetentRefresh = true
    }

    private func bottom(of view: UIView, in container: UIView) -> CGFloat {
        guard view.bounds.height > 0, view.superview != nil else { return 0 }
        return view.convert(CGPoint(x: 0, y: view.bounds.maxY), to: container).y
    }

    private func setScrollsChrome(_ enabled: Bool) {
        guard enabled != scrollsChrome else { return }
        scrollsChrome = enabled
        let pinned: [NSLayoutConstraint] = [
            scrollAboveTranscript, actionLeading, actionTrailing, actionSafeBottom,
            rowBottom, transcriptLeading, transcriptTrailing, contentBottom,
        ]
        let flowing: [NSLayoutConstraint] = [
            scrollFullBottom, scrollTranscriptTop, scrollTranscriptLeading,
            scrollTranscriptTrailing, scrollActionLeading, scrollActionTrailing,
            scrollActionBottom,
        ]
        if enabled {
            NSLayoutConstraint.deactivate(pinned)
            updateScrollContentInsets()
            contentContainer.addSubview(transcriptSlot)
            contentContainer.addSubview(actionRow)
            NSLayoutConstraint.activate(flowing)
            bottomFade.isHidden = false
            scrollView.contentInset.bottom = 0
            scrollView.showsVerticalScrollIndicator = true
            needsScrollHint = true
        } else {
            NSLayoutConstraint.deactivate(flowing)
            view.addSubview(transcriptSlot)
            view.addSubview(actionRow)
            view.bringSubviewToFront(bottomFade)
            view.bringSubviewToFront(actionRow)
            view.bringSubviewToFront(transcriptSlot)
            NSLayoutConstraint.activate(pinned)
            bottomFade.isHidden = false
            bottomFade.setSolidStop(0)
            fadeLeading.constant = 0
            fadeTrailing.constant = 0
            fadeTop.constant = -Layout.fadeHeight
            scrollView.showsVerticalScrollIndicator = false
            scrollView.verticalScrollIndicatorInsets.bottom = 0
            scrollView.contentInset.bottom = Layout.fadeHeight
        }
    }

    /// Softens a card or Play control the fold cuts through. Hidden once that
    /// control is fully on screen, so a scrolled-to-the-end capsule keeps its
    /// corners. The fade is inset with the chrome, above the sheet arc.
    private func updateFoldTreatment() {
        guard scrollsChrome, scrollView.bounds.height > 1 else { return }
        let fold = scrollView.bounds.maxY
        func sliced(_ candidate: UIView) -> Bool {
            guard !candidate.isHidden, candidate.bounds.height > 1, candidate.superview != nil else {
                return false
            }
            let frame = candidate.convert(candidate.bounds, to: scrollView)
            return frame.minY < fold - 1 && frame.maxY > fold + 1
        }
        bottomFade.isHidden = !sliced(transcriptSlot) && !sliced(actionRow)
    }

    /// Inset, corner radius and control height for the transcript card, Play
    /// and •••. Default text keeps the 52 pt capsule at a 28 pt inset.
    /// Accessibility sizes grow Play until the capsule would cross the sheet
    /// arc, then stop. The inset is whatever makes that capsule concentric.
    private func sheetChrome() -> (inset: CGFloat, radius: CGFloat, height: CGFloat) {
        let base = Radius.sheetCapsuleHeight
        guard traitCollection.preferredContentSizeCategory.isAccessibilityCategory else {
            return (Spacing.sheetContent, Radius.sheetConcentric, base)
        }
        let line = TypographyV2.emphasis.font(traits: traitCollection).lineHeight
        let natural = line + Spacing.gap * 2
        let height = min(max(natural, base), Radius.maximumSheetCapsuleHeight)
        let inset = Radius.sheetCorner - height / 2
        return (inset, Radius.concentric(insetFromSheetEdge: inset), height)
    }

    /// Side and bottom inset for Play once it scrolls with the notes. The
    /// scroll view itself stops at that inset, so a fully revealed Play sits
    /// concentric with the sheet. The fold fade, when it is up, is inset by
    /// the same amount and so stays above the sheet arc.
    private func updateScrollContentInsets() {
        let chrome = sheetChrome()
        let bottom = max(chrome.inset, view.safeAreaInsets.bottom)
        scrollTranscriptLeading.constant = chrome.inset
        scrollTranscriptTrailing.constant = -chrome.inset
        scrollActionLeading.constant = chrome.inset
        scrollActionTrailing.constant = -chrome.inset
        // The scroll view already ends `bottom` above the sheet. Play is the
        // last item, so it must not add that inset a second time.
        scrollActionBottom.constant = 0
        guard scrollsChrome else { return }
        scrollFullBottom.constant = -bottom
        fadeLeading.constant = chrome.inset
        fadeTrailing.constant = -chrome.inset
        fadeTop.constant = -max(Layout.fadeHeight, chrome.radius)
        bottomFade.setSolidStop(0.5)
        // The indicator hugs the trailing edge. End it where the side is straight.
        scrollView.verticalScrollIndicatorInsets.bottom = max(0, Radius.sheetCorner - bottom)
    }

    private func buildContent() -> UIView {
        let container = UIView()

        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = Radius.concentric(insetFromSheetEdge: Layout.inset)
        artwork.layer.cornerCurve = .continuous
        artwork.backgroundColor = Theme.surfaceContainerHighest
        artwork.setArtwork(episode.imageURL.flatMap(URL.init(string:)), title: episode.channelTitle)
        artwork.isAccessibilityElement = true
        artwork.accessibilityLabel = "Episode artwork"
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artworkSide = artwork.widthAnchor.constraint(equalToConstant: Layout.artworkMedium)

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.text = episode.title
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        // The show: a Meta-styled link to the Channel sheet.
        let hostButton = ExpandedHitButton(type: .system)
        channelButton = hostButton
        var hostConfig = UIButton.Configuration.plain()
        hostConfig.title = episode.channelTitle
        hostConfig.baseForegroundColor = TypographyV2.meta.color
        hostConfig.contentInsets = .zero
        hostConfig.titleLineBreakMode = .byTruncatingTail
        hostConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        hostButton.configuration = hostConfig
        hostButton.contentHorizontalAlignment = .leading
        hostButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        hostButton.addAction(UIAction { [weak self] _ in self?.channelTapped() }, for: .touchUpInside)

        let meta = UILabel()
        meta.font = TypographyV2.meta.font()
        meta.textColor = TypographyV2.meta.color
        meta.adjustsFontForContentSizeCategory = true
        meta.numberOfLines = 1
        meta.text = RelativeTimeFormatter.dateAndDuration(
            pubDateMilliseconds: episode.pubDateMilliseconds,
            durationMilliseconds: episode.durationMilliseconds,
            now: now()
        )

        for label in [titleLabel, meta] as [UIView] {
            label.setContentHuggingPriority(.required, for: .vertical)
        }
        hostButton.setContentHuggingPriority(.required, for: .vertical)
        meta.setContentCompressionResistancePriority(.required, for: .vertical)
        metaLabel = meta
        channelNameLabel.textColor = TypographyV2.meta.color
        channelNameLabel.adjustsFontForContentSizeCategory = true
        channelNameLabel.clipsToBounds = false
        channelNameLabel.isAccessibilityElement = false
        channelNameLabel.isUserInteractionEnabled = false
        channelNameLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        channelNameLabel.setContentHuggingPriority(.required, for: .vertical)
        // The label and the button are siblings. A label never turns on
        // isUserInteractionEnabled, so a button inside it cannot receive the tap.
        channelNameLabel.translatesAutoresizingMaskIntoConstraints = false
        channelBlock.translatesAutoresizingMaskIntoConstraints = false
        channelBlock.isUserInteractionEnabled = true
        channelBlock.setContentHuggingPriority(.required, for: .vertical)
        channelBlock.setContentCompressionResistancePriority(.required, for: .vertical)
        channelBlock.addSubview(channelNameLabel)
        NSLayoutConstraint.activate([
            channelNameLabel.topAnchor.constraint(equalTo: channelBlock.topAnchor),
            channelNameLabel.leadingAnchor.constraint(equalTo: channelBlock.leadingAnchor),
            channelNameLabel.trailingAnchor.constraint(equalTo: channelBlock.trailingAnchor),
            channelNameLabel.bottomAnchor.constraint(equalTo: channelBlock.bottomAnchor),
        ])
        identityRow.axis = .horizontal
        identityRow.alignment = .top
        identityRow.spacing = Spacing.pageH
        identityRow.translatesAutoresizingMaskIntoConstraints = false
        let info = UIStackView(arrangedSubviews: [titleLabel, hostButton, meta, trailingSpacer])
        info.axis = .vertical
        infoStack = info
        // Fill gives the title the column width, so it wraps on word
        // boundaries instead of laying out at its one-line intrinsic width.
        info.alignment = .fill
        info.spacing = Spacing.xs

        // The cover sits in a wrapper so the header can be full width while
        // the image keeps its own side. The wrapper's trailing pin is 999:
        // a fill stack may widen the wrapper, and that pin yields instead
        // of stretching the image.
        artworkWrap = UIView()
        artworkWrap.translatesAutoresizingMaskIntoConstraints = false
        artworkWrap.addSubview(artwork)
        let artworkTrailing = artworkWrap.trailingAnchor.constraint(equalTo: artwork.trailingAnchor)
        artworkTrailing.priority = UILayoutPriority(999)
        artworkWrap.setContentHuggingPriority(.required, for: .horizontal)
        artworkWrap.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: artworkWrap.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: artworkWrap.leadingAnchor),
            artwork.bottomAnchor.constraint(equalTo: artworkWrap.bottomAnchor),
            artworkTrailing,
        ])

        let header = UIStackView(arrangedSubviews: [artworkWrap, info])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = Spacing.pageH
        headerStack = header

        // Show-notes pipeline wiring. The document arrives pre-styled from
        // ShowNotesStore (ShowNotesStyle owns fonts/colors), so the view
        // gets no manual typography here. Links keep the system default
        // action. Images zoom above whatever sheet stack is live; weak self
        // breaks the view-owns-closure-owns-self cycle.
        descriptionTextView.presentImage = { [weak self] image, thumbnail in
            guard let self else { return }
            ZoomingImageViewController.present(
                thumbnail: thumbnail,
                imageURL: image.url,
                alt: image.alt,
                from: self.topMostPresented()
            )
        }
        // Image loads and dynamic-type/appearance changes resize the
        // document; re-render through the same signature-guarded path
        // (see renderDescription) so layout stays valid without an echo
        // loop.
        descriptionTextView.onMetricsChange = { [weak self] in
            self?.renderDescription()
        }

        let stack = UIStackView(arrangedSubviews: [header, descriptionTextView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Spacing.cardInner
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        contentStack = stack
        contentContainer = container
        contentBottom = stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.inset)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.inset),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.inset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.inset),
            contentBottom,
            artworkSide,
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
            info.heightAnchor.constraint(greaterThanOrEqualTo: artwork.heightAnchor),
        ])
        return container
    }

    /// Large gives the cover 160 pt and the title four lines; medium is
    /// 120 pt and three lines. Both keep the column top-aligned. Accessibility
    /// sizes keep the title full width and put a smaller cover beside the
    /// channel name and date, so the cover does not take a row of its own.
    private func applyDetentLayout() {
        let isLarge = sheetPresentationController?.selectedDetentIdentifier == .large
        applyHeaderMetrics(isLarge: isLarge)
        applyTranscriptVisibility(isLarge: isLarge)
    }

    private func applyHeaderMetrics(isLarge: Bool) {
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if accessibility {
            artworkSide.constant = Spacing.sheetTitleH
            titleLabel.numberOfLines = 0
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.lineBreakStrategy = .pushOut
            metaLabel.numberOfLines = 0
            metaLabel.lineBreakMode = .byWordWrapping
            metaLabel.lineBreakStrategy = .pushOut
            showWrappingChannelName()
            arrange(headerStack, [titleLabel, identityRow])
            arrange(identityRow, [artworkWrap, infoStack])
            arrange(infoStack, [channelBlock, metaLabel, trailingSpacer])
            headerStack.axis = .vertical
            headerStack.alignment = .fill
            headerStack.spacing = Spacing.xs
        } else {
            artworkSide.constant = isLarge ? Layout.artworkLarge : Layout.artworkMedium
            titleLabel.numberOfLines = isLarge ? 4 : 3
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.lineBreakStrategy = .standard
            metaLabel.numberOfLines = 1
            metaLabel.lineBreakMode = .byTruncatingTail
            metaLabel.lineBreakStrategy = .standard
            showSingleLineChannelButton()
            arrange(headerStack, [artworkWrap, infoStack])
            arrange(infoStack, [titleLabel, channelButton, metaLabel, trailingSpacer])
            headerStack.axis = .horizontal
            headerStack.alignment = .top
            headerStack.spacing = Spacing.pageH
            if scrollsChrome { setScrollsChrome(false) }
        }
    }

    /// Moves `views` into `stack` in order and drops anything else. A matching
    /// arrangement is left alone so a detent change does not rebuild it.
    private func arrange(_ stack: UIStackView, _ views: [UIView]) {
        let current = stack.arrangedSubviews
        if current.count == views.count && zip(current, views).allSatisfy({ $0.0 === $0.1 }) {
            return
        }
        for view in current where !views.contains(where: { $0 === view }) {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, view) in views.enumerated() {
            if stack.arrangedSubviews.contains(where: { $0 === view }) {
                stack.removeArrangedSubview(view)
            } else {
                view.removeFromSuperview()
            }
            stack.insertArrangedSubview(view, at: min(index, stack.arrangedSubviews.count))
        }
    }

    /// Accessibility sizes: a label wraps the show name on word boundaries
    /// and reports its full height. The button is a sibling overlay on the
    /// same block, so the label cannot swallow the tap, and it keeps the
    /// default size's accessibility label and button trait.
    private func showWrappingChannelName() {
        channelNameLabel.font = TypographyV2.meta.font(traits: traitCollection)
        channelNameLabel.textColor = TypographyV2.meta.color
        channelNameLabel.text = episode.channelTitle
        channelNameLabel.numberOfLines = 0
        channelNameLabel.lineBreakMode = .byWordWrapping
        channelNameLabel.lineBreakStrategy = .pushOut
        channelNameLabel.textAlignment = .natural
        channelNameLabel.isHidden = false
        channelNameLabel.isUserInteractionEnabled = false
        channelBlock.isHidden = false
        channelBlock.isUserInteractionEnabled = true
        if channelButton.superview !== channelBlock {
            NSLayoutConstraint.deactivate(channelHitPins)
            channelButton.removeFromSuperview()
            channelButton.translatesAutoresizingMaskIntoConstraints = false
            channelBlock.addSubview(channelButton)
            channelHitPins = [
                channelButton.topAnchor.constraint(equalTo: channelBlock.topAnchor),
                channelButton.bottomAnchor.constraint(equalTo: channelBlock.bottomAnchor),
                channelButton.leadingAnchor.constraint(equalTo: channelBlock.leadingAnchor),
                channelButton.trailingAnchor.constraint(equalTo: channelBlock.trailingAnchor),
            ]
            NSLayoutConstraint.activate(channelHitPins)
        }
        var config = UIButton.Configuration.plain()
        config.title = nil
        config.baseForegroundColor = TypographyV2.meta.color
        config.contentInsets = .zero
        config.background.backgroundColor = .clear
        channelButton.configuration = config
        channelButton.contentHorizontalAlignment = .leading
        channelButton.setContentHuggingPriority(.defaultLow, for: .vertical)
        channelButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        channelButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        channelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        channelButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        channelButton.accessibilityTraits.insert(.button)
        channelButton.isAccessibilityElement = true
    }

    /// Default sizes: the original one-line truncating button, and no label.
    private func showSingleLineChannelButton() {
        NSLayoutConstraint.deactivate(channelHitPins)
        channelHitPins = []
        channelNameLabel.isHidden = true
        channelBlock.isHidden = true
        if channelButton.superview === channelBlock {
            channelButton.removeFromSuperview()
        }
        channelButton.isHidden = false
        channelButton.setContentHuggingPriority(.required, for: .vertical)
        channelButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        channelButton.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        channelButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        var config = UIButton.Configuration.plain()
        config.title = episode.channelTitle
        config.baseForegroundColor = TypographyV2.meta.color
        config.contentInsets = .zero
        config.titleLineBreakMode = .byTruncatingTail
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        channelButton.configuration = config
        channelButton.contentHorizontalAlignment = .leading
        channelButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        channelButton.accessibilityTraits.insert(.button)
        channelButton.isAccessibilityElement = true
    }

    /// Height of the medium detent at an accessibility size: the header, the
    /// transcript row and Play, from the last layout. Show notes stay in the
    /// scroll view. Before that measurement, use the sheet maximum.
    private func accessibilityMediumDetentHeight(maximum: CGFloat) -> CGFloat {
        guard didMeasureAccessibilityDetent else { return maximum }
        return accessibilityDetentHeight
    }

    /// The row is chrome, not scrolling content. Medium shows it unless the
    /// policy keeps it for the large detent only.
    private func applyTranscriptVisibility(isLarge: Bool) {
        let visible = (transcript != nil || transcriptPreview != nil)
            && (DetailTranscriptPolicy.current.visibleAtMediumDetent || isLarge)
        transcriptRow.isHidden = !visible
        transcriptSlot.isHidden = !visible
        transcriptGap.constant = visible ? -Spacing.md : 0
        transcriptSlotHeight.isActive = !visible
        NSLayoutConstraint.deactivate(transcriptRowPins)
        if visible { NSLayoutConstraint.activate(transcriptRowPins) }
    }

    /// Play and ••• share one height. The transcript card shares their inset
    /// and their corner radius, from `Radius.concentric`.
    private func applyActionRowMetrics() {
        let chrome = sheetChrome()
        actionRow.alignment = .fill
        actionRowHeight.isActive = true
        actionRowHeight.constant = chrome.height
        actionLeading.constant = chrome.inset
        actionTrailing.constant = -chrome.inset
        rowBottom.constant = -max(chrome.inset, view.safeAreaInsets.bottom)
        transcriptLeading.constant = chrome.inset
        transcriptTrailing.constant = -chrome.inset
        let glyph = 17 * chrome.height / Radius.sheetCapsuleHeight
        moreButton.setDiameter(chrome.height, glyphPointSize: glyph)
        transcriptRow.applyConcentricRadius(chrome.radius)
        artwork.layer.cornerRadius = Radius.concentric(insetFromSheetEdge: Layout.inset)
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            fitPlayButton(height: chrome.height)
        }
        updateScrollContentInsets()
    }

    /// Keeps the Play label inside the capped capsule without changing the
    /// default 12 pt inset when the 52 pt height already has room.
    private func fitPlayButton(height: CGFloat) {
        guard var configuration = playButton.configuration else { return }
        let line = TypographyV2.emphasis.font(traits: traitCollection).lineHeight
        let vertical = max(0, min(Spacing.gap, (height - line) / 2))
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: vertical, leading: Spacing.cardInner, bottom: vertical, trailing: Spacing.cardInner
        )
        playButton.configuration = configuration
    }

    // MARK: - Actions (Play capsule with progress; the rest behind •••)

    private var playAction: EpisodeCardAction? {
        actions.first { $0.accessibilityLabel == "Play" }
    }

    private var addAction: EpisodeCardAction? {
        actions.first { $0.accessibilityLabel == "Add to playlist" }
    }

    private var otherActions: [EpisodeCardAction] {
        actions.filter { $0.accessibilityLabel != "Play" && $0.accessibilityLabel != "Add to playlist" }
    }

    private func buildActionRow() {
        actionRow.axis = .horizontal
        actionRow.alignment = .fill
        actionRow.spacing = Spacing.md

        let label = PlayLabel.make(
            durationMilliseconds: episode.durationMilliseconds,
            playedMilliseconds: episode.playedMilliseconds
        )
        let play = AnycastButton.make(.primary, title: label.title, image: AppIcons.play)
        var configuration = play.configuration
        configuration?.background.customView = ProgressCapsuleBackground(fraction: label.fraction)
        play.configuration = configuration
        play.accessibilityLabel = label.title
        play.accessibilityIdentifier = "detail-play"
        if let playAction {
            play.addAction(UIAction { [weak self] _ in self?.fire(playAction) }, for: .touchUpInside)
        }
        playButton = play
        actionRow.addArrangedSubview(play)

        let more = AnycastIconButton(
            style: .tonal, icon: AppIcons.more, accessibilityLabel: "More episode actions",
            diameter: Layout.actionHeight
        )
        moreButton = more
        more.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.overflowMenuChildren() ?? [])
            },
        ])
        more.showsMenuAsPrimaryAction = true
        // Keep the written order when the menu opens upward: destructive
        // last, nearest the button.
        more.preferredMenuElementOrder = .fixed
        actionRow.addArrangedSubview(more)
    }

    private func overflowMenuChildren() -> [UIMenuElement] {
        var groups: [[UIMenuElement]] = []
        let transcriptItems = transcriptMenuElements()
        if !transcriptItems.isEmpty { groups.append(transcriptItems) }

        var items: [UIMenuElement] = []
        if let addAction {
            if isInPlaylist {
                items.append(UIAction(title: "In playlist", image: AppIcons.addedToList, attributes: .disabled) { _ in })
            } else {
                items.append(UIAction(title: "Add to playlist", image: AppIcons.addToList) { [weak self] _ in
                    self?.fire(addAction)
                })
            }
        }
        items.append(UIAction(title: "Share episode", image: AppIcons.share) { [weak self] _ in
            self?.shareTapped()
        })
        items.append(UIAction(title: "Copy link", image: AppIcons.copy) { [weak self] _ in
            self?.copyLinkTapped()
        })
        if !items.isEmpty { groups.append(items) }
        let others = otherActions.map { action in
            UIAction(
                title: action.accessibilityLabel,
                image: action.icon,
                attributes: action.accessibilityLabel.hasPrefix("Remove") ? .destructive : []
            ) { [weak self] _ in self?.fire(action) }
        }
        if !others.isEmpty { groups.append(others) }
        guard groups.count > 1 else { return groups.first ?? [] }
        // Transcript entries, then the episode actions, then destructive —
        // each group under its own divider. Fixed order keeps Remove nearest
        // the button.
        return groups.map { UIMenu(options: .displayInline, children: $0) }
    }

    private func transcriptMenuElements() -> [UIMenuElement] {
        guard let transcript else { return [] }
        return transcript.content().menu.map { item in
            UIAction(
                title: item.title,
                subtitle: item.subtitle,
                image: DetailTranscriptMenuImages.image(for: item.action)
            ) { [weak self] _ in
                guard let self else { return }
                self.transcript?.handle(item.action, from: self)
            }
        }
    }

    private func startTranscript() {
        if let transcriptPreview {
            transcriptRow.apply(transcriptPreview, animated: false)
            return
        }
        guard let transcript else { return }
        transcript.onChange = { [weak self] in
            self?.renderTranscriptRow(animated: true)
        }
        let subtitles = transcript.context.subtitles
        statusLoop.track(
            read: { _ = subtitles.statuses },
            onChange: { [weak self] in self?.renderTranscriptRow(animated: true) }
        )
        renderTranscriptRow(animated: false)
        Task { [weak self] in
            await transcript.refreshAllowanceIfNeeded()
            self?.renderTranscriptRow(animated: true)
        }
    }

    private func renderTranscriptRow(animated: Bool) {
        guard let transcript else { return }
        transcriptRow.apply(transcript.content(), animated: animated)
    }

    // MARK: - Behavior

    /// Signature of the last notes render (enclosure + style metrics).
    /// Doubles as the renderDescription re-entrancy guard: repeated ticks
    /// and the metrics echoes that setDocument itself triggers collapse
    /// here, while a real dynamic-type/appearance change produces a new
    /// signature and re-renders — no render → metrics → render loop.
    private var renderedNotesSignature: String?

    /// Renders the notes through the shared show-notes store: rich HTML →
    /// pre-styled attributed document; an empty rich document (empty,
    /// sanitized-away, or failed payload) degrades to the same plain text
    /// the cards render via PlainTextHTMLCache.
    private func renderDescription() {
        let signature = episode.enclosureURL + "#"
            + ShowNotesStyle.metricSignature(traitCollection: traitCollection)
        guard signature != renderedNotesSignature else { return }
        renderedNotesSignature = signature

        let html = episode.descriptionHTML
        let traits = traitCollection
        // Plain-string payloads (no leading '<') keep their newlines — the
        // normalizer collapses ALL whitespace, which would fuse a plain
        // multi-line description into one paragraph.
        if case .text(let plain) = HtmlText.displayPayload(for: html) {
            descriptionTextView.setDocument(
                ShowNotesStore.shared.attributedFallback(
                    plain: DisplayText.plainText(fromHTML: plain), style: ShowNotesStyle(), traits: traits
                ),
                imageLoader: KingfisherShowNotesImageLoader.shared
            )
            return
        }
        Task { [weak self] in
            guard let self else { return }
            var attributed = await ShowNotesStore.shared.attributedString(
                html: html, style: ShowNotesStyle(), traits: traits
            )
            if attributed.length == 0 {
                let plain = await PlainTextHTMLCache.shared.plainText(for: html)
                attributed = ShowNotesStore.shared.attributedFallback(
                    plain: plain, style: ShowNotesStyle(), traits: traits
                )
            }
            // A newer render (trait change) superseded this one: drop it.
            guard self.renderedNotesSignature == signature else { return }
            self.descriptionTextView.setDocument(
                attributed, imageLoader: KingfisherShowNotesImageLoader.shared
            )
        }
    }

    /// 03 §10.1 wrapper quirk: the Detail pops itself after firing.
    private func fire(_ action: EpisodeCardAction) {
        action.handler()
        dismiss(animated: true)
    }

    private func channelTapped() {
        // 03 §10.1: present the Channel sheet ON TOP; Detail stays open.
        openChannel?(ChannelReference(rssFeedURL: episode.rssFeedURL, title: episode.channelTitle))
    }

    /// anycast.website/player?rssfeedurl=…&enclosureurl=… (detail.dart:174-204)
    private var playerURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "anycast.website"
        components.path = "/player"
        components.queryItems = [
            URLQueryItem(name: "rssfeedurl", value: episode.rssFeedURL),
            URLQueryItem(name: "enclosureurl", value: episode.enclosureURL),
        ]
        return components.url
    }

    private func shareTapped() {
        guard let url = playerURL else { return }
        Task { [weak self] in
            guard let self else { return }
            let short = await self.shortenURL?(url) ?? url
            let activity = UIActivityViewController(
                activityItems: ["\(self.episode.title)\n\n\(short.absoluteString)"],
                applicationActivities: nil
            )
            // The shortlink await can complete while this sheet is already
            // dismissing — present from a presenter that is still attached to
            // the window (the share-handoff precedent) instead of from self.
            let presenter = self.view.window?.rootViewController?.topMostPresented() ?? self
            presenter.present(activity, animated: true)
        }
    }

    /// The same shortened player link as Share, straight to the pasteboard.
    private func copyLinkTapped() {
        guard let url = playerURL else { return }
        Task { [weak self] in
            guard let self else { return }
            let short = await self.shortenURL?(url) ?? url
            UIPasteboard.general.string = short.absoluteString
            if let window = self.view.window {
                ToastPresenter.shared.show("Link copied", in: window)
            }
        }
    }
}

extension DetailViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFoldTreatment()
    }
}

extension DetailViewController: UISheetPresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        Motion.animate { [weak self] in
            self?.applyDetentLayout()
            self?.view.layoutIfNeeded()
        }
    }
}

/// The Play capsule's fill: the primary ink with the played share washed
/// lighter from the leading edge (`onPrimary` at 18 %).
private final class ProgressCapsuleBackground: UIView {

    private let fill = UIView()
    private let fraction: Double

    init(fraction: Double) {
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = Theme.onSurface
        clipsToBounds = true
        fill.backgroundColor = Theme.surface.withAlphaComponent(0.18)
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(fraction), height: bounds.height)
    }
}

/// A text-sized link whose touch area still reaches the 44 pt minimum.
private final class ExpandedHitButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let grow = max(0, (AnycastIconButton.standardDiameter - bounds.height) / 2)
        return bounds.insetBy(dx: 0, dy: -grow).contains(point)
    }
}

/// A vertical surface-color fade (fully opaque at one edge, clear at the
/// other) for chrome that needs a soft edge without a blur view. The color
/// is re-resolved on appearance changes and when the view joins a window
/// (09 §9a); the opaque end is exactly 1.0 so content behind it never
/// ghosts through.
final class GradientFadeLayerView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var color: UIColor = .clear
    private var fromTop = true
    /// Share of the fade that stays fully opaque at the solid end, so a
    /// clipped card edge disappears instead of reading as a flat cut.
    private var solidStop: CGFloat = 0

    func configure(color: UIColor, fromTop: Bool) {
        self.color = color
        self.fromTop = fromTop
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyColors()
        }
    }

    func setSolidStop(_ stop: CGFloat) {
        let clamped = min(max(stop, 0), 0.8)
        guard clamped != solidStop else { return }
        solidStop = clamped
        applyColors()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The first resolve ran detached (default traits).
        applyColors()
    }

    private func applyColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let resolved = color.resolvedColor(with: traitCollection)
        let opaque = resolved.cgColor
        let clear = resolved.withAlphaComponent(0).cgColor
        if solidStop > 0 {
            let split = fromTop ? solidStop : 1 - solidStop
            gradient.locations = [
                NSNumber(value: 0),
                NSNumber(value: Double(split)),
                NSNumber(value: 1),
            ]
            gradient.colors = fromTop ? [opaque, opaque, clear] : [clear, opaque, opaque]
        } else {
            gradient.locations = [NSNumber(value: 0), NSNumber(value: 1)]
            gradient.colors = fromTop ? [opaque, clear] : [clear, opaque]
        }
    }
}
