import UIKit
import AnycastKit

/// Player page 0, "This episode": the episode's chapters (read from the
/// show notes, see `EpisodeChapters`) on one grouped plate with the
/// playing chapter in gold, then the show notes, whose timestamps are
/// links. Tapping a chapter or a timestamp seeks there and offers Undo in
/// the status capsule — the same jump the transcript page makes. The
/// header mirrors the transcript page's (cover beside the page name over
/// the episode title). Speed and the sleep timer live on the main page.
final class EpisodePageViewController: UIViewController {

    private let context: UIContext
    private let observation = ObservationLoop()

    private enum Layout {
        static let headerArtwork: CGFloat = 44
        static let headerArtworkRadius: CGFloat = 14
        /// Header → first content block, and between blocks.
        static let blockGap: CGFloat = Spacing.pageHeader
        /// Row text insets (the old settings card's), dividers align to them.
        static let rowLeading = Spacing.cardInner
        static let rowTrailing = Spacing.pageH
        /// Capsule → page selector, matching the transcript page's panel.
        static let capsuleBottom: CGFloat = 20
        /// The fades at the top (under the header) and bottom of the content.
        static let topFade: CGFloat = Spacing.pageHeader
        static let bottomFade: CGFloat = 32
    }

    // MARK: Header

    private let headerArtwork = UIImageView()
    private var headerArtworkURL: String?
    private let headerTitleLabel = UILabel()
    private let episodeTitleLabel = UILabel()
    private let header = UIStackView()

    // MARK: Content

    /// Hosts the scroll view under an alpha fade mask (a scroll view's own
    /// mask would scroll with its content). A mask, not a colour band: the
    /// player's backdrop is a gradient no fade colour could match.
    private let scrollHost = UIView()
    private let fadeMask = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let chaptersPlate = UIStackView()
    private var chapterRows: [ChapterRowView] = []
    private var chapters: [EpisodeChapter] = []
    private var currentChapterIndex: Int?
    /// The notes render through the shared show-notes pipeline; link taps
    /// route to `openLink` (`anycast-seek:` jumps, anything else opens like
    /// every other show-notes link).
    private let notesTextView = ShowNotesTextView()
    private let emptyLabel = UILabel()
    private var renderedCacheKey: String?
    /// Episode + style metrics of the last notes render; doubles as the
    /// re-entrancy guard against the metric echoes `setDocument` triggers.
    private var renderedNotesSignature: String?

    private let capsule = TranscriptStatusCapsuleView()
    private let jumpUndo = PlaybackJumpUndo()

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        build()
        jumpUndo.onChange = { [weak self] in self?.updateCapsule() }
        renderEpisode()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
                _ = self.context.playback.positionData
            },
            onChange: { [weak self] in
                self?.renderEpisode()
                self?.renderCurrentChapter()
            }
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The last line can scroll clear of the Undo capsule.
        let bottom = Layout.capsuleBottom + TranscriptStatusCapsuleView.height
        if scrollView.contentInset.bottom != bottom {
            scrollView.contentInset.bottom = bottom
        }
        let height = scrollHost.bounds.height
        fadeMask.frame = scrollHost.bounds
        guard height > 0 else { return }
        let top = min(Layout.topFade / height, 0.5)
        let end = max(1 - Layout.bottomFade / height, top)
        fadeMask.locations = [0, NSNumber(value: top), NSNumber(value: end), 1]
    }

    // MARK: - Build

    private func build() {
        headerArtwork.contentMode = .scaleAspectFill
        headerArtwork.clipsToBounds = true
        headerArtwork.layer.cornerRadius = Layout.headerArtworkRadius
        headerArtwork.layer.cornerCurve = .continuous
        headerArtwork.backgroundColor = AnycastColor.sandAlpha3
        headerArtwork.isAccessibilityElement = false
        headerArtwork.translatesAutoresizingMaskIntoConstraints = false

        headerTitleLabel.text = "This episode"
        headerTitleLabel.font = TypographyV2.emphasis.font()
        headerTitleLabel.textColor = Theme.playerText
        episodeTitleLabel.font = TypographyV2.meta.font()
        episodeTitleLabel.textColor = Theme.playerSecondary
        for label in [headerTitleLabel, episodeTitleLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
        }
        let titles = UIStackView(arrangedSubviews: [headerTitleLabel, episodeTitleLabel])
        titles.axis = .vertical
        header.addArrangedSubview(headerArtwork)
        header.addArrangedSubview(titles)
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = Spacing.gap
        header.translatesAutoresizingMaskIntoConstraints = false

        chaptersPlate.axis = .vertical
        chaptersPlate.isLayoutMarginsRelativeArrangement = true
        chaptersPlate.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.xs, leading: 0, bottom: Spacing.xs, trailing: 0
        )
        chaptersPlate.backgroundColor = AnycastColor.sandAlpha3
        chaptersPlate.layer.cornerRadius = Radius.card
        chaptersPlate.layer.cornerCurve = .continuous
        chaptersPlate.accessibilityIdentifier = "player-episode-chapters"

        // The document arrives pre-styled from ShowNotesStore, and the view
        // must NOT be one a11y element: that would swallow the links' and
        // images' own accessibility.
        notesTextView.accessibilityIdentifier = "player-episode-notes"
        notesTextView.onLinkTap = { [weak self] url in self?.openLink(url) }
        // Images zoom above whatever sheet stack is live.
        notesTextView.presentImage = { [weak self] image, thumbnail in
            guard let self else { return }
            ZoomingImageViewController.present(
                thumbnail: thumbnail, imageURL: image.url, alt: image.alt,
                from: self.topMostPresented()
            )
        }
        // Dynamic Type changes resize the document: re-render through the
        // signature-guarded path.
        notesTextView.onMetricsChange = { [weak self] in self?.renderNotes() }

        emptyLabel.text = "No show notes for this episode."
        emptyLabel.font = TypographyV2.meta.font()
        emptyLabel.textColor = Theme.playerSecondary
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0

        contentStack.axis = .vertical
        contentStack.spacing = Layout.blockGap
        for block in [chaptersPlate, notesTextView, emptyLabel] as [UIView] {
            contentStack.addArrangedSubview(block)
        }
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.accessibilityIdentifier = "player-episode-scroll"
        scrollView.addSubview(contentStack)
        scrollHost.addSubview(scrollView)
        fadeMask.colors = [UIColor.clear, .white, .white, .clear].map(\.cgColor)
        scrollHost.layer.mask = fadeMask
        scrollHost.translatesAutoresizingMaskIntoConstraints = false

        capsule.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollHost)
        view.addSubview(header)
        view.addSubview(capsule)

        let column = Spacing.pageHeader
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: column),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -column),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            headerArtwork.widthAnchor.constraint(equalToConstant: Layout.headerArtwork),
            headerArtwork.heightAnchor.constraint(equalToConstant: Layout.headerArtwork),

            // Content fades out just under the header.
            scrollHost.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: scrollHost.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: scrollHost.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: scrollHost.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: scrollHost.trailingAnchor),

            // The padding rides inside the content so offset 0 is "at rest",
            // clear of the top fade.
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Layout.blockGap),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: column),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -column),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * column),

            capsule.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: column),
            capsule.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -column),
            capsule.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.capsuleBottom),
        ])
    }

    // MARK: - Rendering

    /// Episode-driven parts (header, chapters, notes); change-driven since
    /// it runs on every position tick.
    private func renderEpisode() {
        let episode = context.playback.currentEpisode
        let cacheKey = episode?.enclosureUrl ?? "player-episode-none"
        guard cacheKey != renderedCacheKey else { return }
        renderedCacheKey = cacheKey
        jumpUndo.clear()
        scrollView.contentOffset = .zero

        episodeTitleLabel.text = episode?.title ?? ""
        let imageURL = episode?.imageUrl ?? ""
        if imageURL != headerArtworkURL {
            headerArtworkURL = imageURL
            headerArtwork.kf.cancelDownloadTask()
            headerArtwork.setArtwork(URL(string: imageURL), title: episode?.channelTitle)
        }

        chapters = EpisodeChapters.chapters(description: episode?.description, cacheKey: episode?.enclosureUrl)
        rebuildChapterRows()

        renderNotes()
    }

    /// Renders the notes through the shared show-notes store, timestamps
    /// linked as `anycast-seek:`. An empty rich document degrades to the
    /// plain text the cards render.
    private func renderNotes() {
        let episode = context.playback.currentEpisode
        let html = episode?.description ?? ""
        let cacheKey = episode?.enclosureUrl ?? "player-episode-none"
        let signature = cacheKey + "#" + ShowNotesStyle.metricSignature(traitCollection: traitCollection)
        guard signature != renderedNotesSignature else { return }
        renderedNotesSignature = signature

        let payload = HtmlText.displayPayload(for: html)
        if case .empty = payload {
            setNotes(NSAttributedString())
            notesTextView.isHidden = true
            emptyLabel.isHidden = episode == nil
            return
        }
        notesTextView.isHidden = false
        emptyLabel.isHidden = true
        let traits = traitCollection
        // Plain-string payloads keep their newlines — the normalizer
        // collapses all whitespace.
        if case .text(let plain) = payload {
            setNotes(ShowNotesStore.shared.attributedFallback(
                plain: plain, style: ShowNotesStyle(), traits: traits
            ))
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
            // A newer render (episode or trait change) superseded this one.
            guard self.renderedNotesSignature == signature else { return }
            self.setNotes(attributed)
        }
    }

    private func setNotes(_ attributed: NSAttributedString) {
        notesTextView.setDocument(
            EpisodeChapters.linkingTimestamps(in: attributed),
            imageLoader: KingfisherShowNotesImageLoader.shared
        )
    }

    private func rebuildChapterRows() {
        chapterRows.forEach { $0.removeFromSuperview() }
        chaptersPlate.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chapterRows = chapters.enumerated().map { index, chapter in
            let row = ChapterRowView(chapter: chapter)
            row.addAction(UIAction { [weak self] _ in self?.jumpToChapter(index) }, for: .touchUpInside)
            return row
        }
        for (index, row) in chapterRows.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = AnycastColor.sandAlpha3
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.heightAnchor.constraint(equalToConstant: Spacing.hairline).isActive = true
                let inset = UIView()
                inset.addSubview(divider)
                NSLayoutConstraint.activate([
                    divider.topAnchor.constraint(equalTo: inset.topAnchor),
                    divider.bottomAnchor.constraint(equalTo: inset.bottomAnchor),
                    divider.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: Layout.rowLeading),
                    divider.trailingAnchor.constraint(equalTo: inset.trailingAnchor, constant: -Layout.rowTrailing),
                ])
                chaptersPlate.addArrangedSubview(inset)
            }
            chaptersPlate.addArrangedSubview(row)
        }
        chaptersPlate.isHidden = chapters.isEmpty
        currentChapterIndex = nil
        renderCurrentChapter()
    }

    private func renderCurrentChapter() {
        let position = Int(context.playback.positionData.positionMilliseconds)
        let index = EpisodeChapters.index(at: position, in: chapters)
        guard index != currentChapterIndex else { return }
        currentChapterIndex = index
        for (rowIndex, row) in chapterRows.enumerated() {
            row.isCurrent = rowIndex == index
        }
    }

    // MARK: - Jumps

    private func jumpToChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        jump(to: chapters[index].startMilliseconds)
    }

    private func openLink(_ url: URL) {
        if let target = EpisodeChapters.seekTarget(of: url) {
            jump(to: target)
        } else {
            HTMLContentRenderer.playerShared.onLinkTap?(url)
        }
    }

    private func jump(to milliseconds: Int) {
        let previous = Int(context.playback.positionData.positionMilliseconds)
        Task { await context.playback.seek(Int64(milliseconds)) }
        jumpUndo.record(from: previous, to: milliseconds)
    }

    private func undoJump() {
        guard let jump = jumpUndo.take() else { return }
        Task { await context.playback.seek(Int64(jump.previousMilliseconds)) }
    }

    private func updateCapsule() {
        capsule.show(jumpUndo.capsuleContent(undo: { [weak self] in self?.undoJump() }))
    }
}

// MARK: - Chapter row

/// Start time (meta, monospaced) beside the chapter title (body, one line);
/// the playing chapter turns gold. The whole row is the tap target.
@MainActor
private final class ChapterRowView: UIControl {

    /// Equal vertical padding of every row.
    private static let verticalPadding: CGFloat = 14

    var isCurrent = false {
        didSet {
            guard isCurrent != oldValue else { return }
            render()
        }
    }

    private let chapter: EpisodeChapter
    private let timeLabel = UILabel()
    private let titleLabel = UILabel()

    init(chapter: EpisodeChapter) {
        self.chapter = chapter
        super.init(frame: .zero)

        timeLabel.text = PlayerProgressClock.positionText(Int64(chapter.startMilliseconds))
        timeLabel.font = TypographyV2.meta.font().monospacedDigits()
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.text = chapter.title
        titleLabel.font = TypographyV2.body.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail

        let row = UIStackView(arrangedSubviews: [timeLabel, titleLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Spacing.gap
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.cardInner),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.pageH),
            // The titles share one edge whatever the time's width.
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(chapter.title), \(timeLabel.text ?? "")"
        addPressFeedback()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func render() {
        timeLabel.textColor = isCurrent ? Theme.primary : Theme.playerSecondary
        titleLabel.textColor = isCurrent ? Theme.primary : Theme.playerText
        accessibilityValue = isCurrent ? "Playing" : nil
    }
}
