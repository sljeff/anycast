import UIKit
import Kingfisher
import AnycastKit

/// Player page 1 (PlayerMain, player.dart:146-235, 03 §2.10) in the Anycast
/// 2.0 now-playing form: a centered artwork with a soft shadow, the episode
/// title (wraps to two lines) over the show name (taps open the Channel
/// sheet on top) with the share shortcut (shortlink → system share sheet)
/// beside them, the scrubber, and the transport (−10 s / play-pause with
/// the loading animation / +30 s, play centered) plus the K6 retry
/// affordance. The column sits on one vertical rhythm (title → scrubber →
/// transport → page selector) and all slack goes above the artwork, so the
/// controls stay together near the selector. Background belongs to the
/// container.
final class PlayerMainPageViewController: UIViewController {

    private let context: UIContext
    private let observation = ObservationLoop()

    private let coverFrame = UIView()
    private let coverView = UIImageView()
    private let shareButton = AnycastIconButton(
        style: .plain, icon: AppIcons.share, accessibilityLabel: "Share episode", glyphSize: 20
    )
    private let shareSpinner = UIActivityIndicatorView(style: .medium)
    private let titleBlock = PlayerTitleBlockView()
    private let stateMessageLabel = UILabel()
    private let progressBar = PlayerProgressBarView()
    private let replayButton = AnycastIconButton(
        style: .plain, icon: AppIcons.replay10, accessibilityLabel: "Seek back 10 seconds",
        diameter: Layout.transportSlot, glyphSize: IconStyle.playerTransport.pointSize
    )
    private let playPauseButton = UIButton(type: .custom)
    private let playPauseIcon = PlayPauseIconControl(size: IconStyle.playerPrimary.pointSize)
    private let forwardButton = AnycastIconButton(
        style: .plain, icon: AppIcons.forward30, accessibilityLabel: "Seek forward 30 seconds",
        diameter: Layout.transportSlot, glyphSize: IconStyle.playerTransport.pointSize
    )
    private let retryRow = UIStackView()
    private var bottomStack = UIStackView()

    private enum Layout {
        /// UI kit player artwork: 320 pt, inset 36 from the screen edges.
        static let artworkMaxSide: CGFloat = 320
        static let artworkInset = Spacing.pageSection
        /// The transport's touch slots (UI kit `playerControls` container).
        static let transportSlot: CGFloat = 72
        /// Gap between the play slot and the skip slots (glyph centers
        /// ~100 pt apart, as in the UI kit).
        static let transportGap = Spacing.sectionGap
        /// The one vertical rhythm, measured between VISIBLE edges: subtitle
        /// → scrubber track, time labels → transport glyphs and transport
        /// glyphs → page selector.
        static let rhythm: CGFloat = 28
        /// Frame-to-ink slack hidden inside each block (measured on device),
        /// subtracted so the rhythm is the gap the eye sees: the scrubber
        /// track and the show-name text sit well inside their frames, the
        /// time-label band and the 72 pt transport slot pad the skip glyphs.
        static let titleToScrubber = rhythm - 24
        static let scrubberToTransport = rhythm - 28
        static let transportToSelector = rhythm - 13
        /// Line height of the scrubber's time labels at the default size.
        static let timeLabelLine: CGFloat = 16
    }

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
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.updateScrubberSpacing()
        }
        bind()
        render()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
                _ = self.context.playback.positionData
                _ = self.context.playback.isPlaying
                _ = self.context.playback.isLoading
                _ = self.context.playback.playbackError
            },
            onChange: { [weak self] in self?.render() }
        )
    }

    // MARK: - Build

    private func build() {
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.artwork
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Episode artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverFrame.addSubview(coverView)

        shareButton.tintColor = Theme.playerSecondary
        shareButton.configuration?.baseForegroundColor = Theme.playerSecondary
        shareSpinner.color = Theme.playerText
        shareSpinner.hidesWhenStopped = true
        shareSpinner.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addSubview(shareSpinner)

        let titleRow = UIStackView(arrangedSubviews: [titleBlock, shareButton])
        titleRow.axis = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = Spacing.gap

        stateMessageLabel.font = TypographyV2.caption.font()
        stateMessageLabel.textColor = Theme.playerSecondary
        stateMessageLabel.textAlignment = .center
        stateMessageLabel.adjustsFontForContentSizeCategory = true
        stateMessageLabel.isHidden = true

        retryRow.axis = .vertical
        retryRow.alignment = .center
        retryRow.isHidden = true
        let retryButton = AnycastButton.make(
            .secondary, title: "Retry", image: UIImage(systemName: "arrow.clockwise")
        )
        retryButton.accessibilityLabel = "Retry playback"
        retryButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.context.playback.retry() }
            },
            for: .touchUpInside
        )
        retryRow.addArrangedSubview(retryButton)

        let controls = buildControls()
        bottomStack = UIStackView(arrangedSubviews: [stateMessageLabel, progressBar, controls, retryRow])
        bottomStack.axis = .vertical
        bottomStack.setCustomSpacing(Spacing.xs, after: stateMessageLabel)
        updateScrubberSpacing()
        bottomStack.setCustomSpacing(Spacing.pageH, after: controls)

        for block in [coverFrame, titleRow, bottomStack] {
            block.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(block)
        }

        // All slack lives above the artwork: the title, scrubber and
        // transport keep fixed gaps and sit toward the page selector.
        let topBalance = UILayoutGuide()
        view.addLayoutGuide(topBalance)

        // Square artwork at the inset width, capped at 320 pt; on short
        // windows it yields to a share of the page height so the column
        // never overflows (07 §4 hard requirement).
        let coverWidth = coverFrame.widthAnchor.constraint(
            equalTo: view.widthAnchor, constant: -Layout.artworkInset * 2
        )
        coverWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            topBalance.topAnchor.constraint(equalTo: view.topAnchor),
            topBalance.bottomAnchor.constraint(equalTo: coverFrame.topAnchor),
            topBalance.heightAnchor.constraint(greaterThanOrEqualToConstant: Spacing.pageHeader),

            coverFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coverWidth,
            coverFrame.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.artworkMaxSide),
            coverFrame.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -Layout.artworkInset * 2),
            coverFrame.heightAnchor.constraint(equalTo: coverFrame.widthAnchor),
            coverFrame.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.45),
            coverView.topAnchor.constraint(equalTo: coverFrame.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverFrame.bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverFrame.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverFrame.trailingAnchor),

            titleRow.topAnchor.constraint(equalTo: coverFrame.bottomAnchor, constant: Spacing.pageHeader),
            titleRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            titleRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),

            bottomStack.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: Layout.titleToScrubber),
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageHeader),
            bottomStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.transportToSelector),

            shareSpinner.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            shareSpinner.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),
        ])
    }

    /// The scrubber's time labels hang below its fixed-height frame, so the
    /// gap to the transport grows with the label font to keep the visible
    /// gap at the rhythm under Dynamic Type.
    private func updateScrubberSpacing() {
        let metrics = UIFontMetrics(forTextStyle: .footnote)
        let growth = metrics.scaledValue(for: Layout.timeLabelLine, compatibleWith: traitCollection) - Layout.timeLabelLine
        bottomStack.setCustomSpacing(Layout.scrubberToTransport + growth, after: progressBar)
    }

    /// replay_10 / play-pause / forward_30 (player.dart:1303-1367); the
    /// −10 s / +30 s deltas are the Dart Controls' seekByRelative values.
    /// UI kit transport: bare glyphs, play exactly centered with the skips
    /// placed symmetrically (their glyph widths differ, so no spacers).
    private func buildControls() -> UIView {
        replayButton.addAction(
            UIAction { [weak self] _ in self?.context.playback.seekByRelative(-10_000) },
            for: .touchUpInside
        )
        forwardButton.addAction(
            UIAction { [weak self] _ in self?.context.playback.seekByRelative(30_000) },
            for: .touchUpInside
        )
        replayButton.accessibilityIdentifier = "player-replay-10"
        forwardButton.accessibilityIdentifier = "player-forward-30"
        for button in [replayButton, forwardButton] {
            button.configuration?.baseForegroundColor = Theme.playerText
        }

        playPauseButton.isAccessibilityElement = true
        playPauseButton.accessibilityLabel = "Play or pause"
        playPauseIcon.isUserInteractionEnabled = false
        playPauseIcon.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addSubview(playPauseIcon)
        playPauseButton.addPressFeedback(scale: Motion.pressScaleStrong)
        playPauseButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.context.playback.togglePlay() }
            },
            for: .touchUpInside
        )

        let row = UIView()
        for button in [replayButton, playPauseButton, forwardButton] as [UIView] {
            button.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(button)
        }
        NSLayoutConstraint.activate([
            playPauseButton.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            playPauseButton.topAnchor.constraint(equalTo: row.topAnchor),
            playPauseButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: Layout.transportSlot),
            playPauseButton.heightAnchor.constraint(equalToConstant: Layout.transportSlot),
            playPauseIcon.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            playPauseIcon.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            // Explicit size: the loading lottie's canvas must never be able
            // to stretch the control past its slot (R2).
            playPauseIcon.widthAnchor.constraint(equalToConstant: IconStyle.playerPrimary.pointSize),
            playPauseIcon.heightAnchor.constraint(equalToConstant: IconStyle.playerPrimary.pointSize),

            replayButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            replayButton.trailingAnchor.constraint(equalTo: playPauseButton.leadingAnchor, constant: -Layout.transportGap),
            replayButton.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor),
            forwardButton.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: Layout.transportGap),
            forwardButton.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
        return row
    }

    private func bind() {
        shareButton.addAction(
            UIAction { [weak self] _ in self?.shareTapped() },
            for: .touchUpInside
        )
        titleBlock.onOpenChannel = { [weak self] in self?.openChannel() }
        progressBar.onSeek = { [weak self] position in
            guard let self else { return }
            Task { await self.context.playback.seek(position) }
        }
    }

    // MARK: - Rendering (ObservationLoop-driven)

    /// Last URL handed to the cover view — see PlayerBarView.renderedCoverURL;
    /// render() runs every position tick, so the cover load must be
    /// change-driven, not unconditional.
    private var renderedCoverURL: URL?

    private func render() {
        let episode = context.playback.currentEpisode
        let position = context.playback.positionData

        // A missing cover shows the shared local placeholder (no remote
        // "No Episode" image request).
        let coverURL = episode?.imageUrl.flatMap(URL.init(string:))
        if coverURL != renderedCoverURL || coverURL == nil {
            renderedCoverURL = coverURL
            coverView.kf.cancelDownloadTask()
            coverView.setArtwork(coverURL, title: episode?.channelTitle)
        }

        titleBlock.update(
            title: episode?.title ?? "",
            channelTitle: episode?.channelTitle ?? "",
            rssFeedURL: episode?.rssFeedUrl
        ) { [weak self] rss in
            guard let self else { return }
            Task { await self.fetchChannel(rssFeedURL: rss) }
        }

        let state = PlayerProgressVisualState.resolve(
            hasEpisode: (episode?.enclosureUrl?.isEmpty == false),
            isLoading: context.playback.isLoading,
            durationMilliseconds: position.durationMilliseconds
        )
        if let message = state.message {
            stateMessageLabel.text = message
            stateMessageLabel.isHidden = false
        } else {
            stateMessageLabel.isHidden = true
        }
        progressBar.setAllowsSeek(state.allowsSeek)
        progressBar.update(
            positionMilliseconds: position.positionMilliseconds,
            bufferedMilliseconds: position.bufferedMilliseconds,
            durationMilliseconds: position.durationMilliseconds
        )

        // Dart gates every control on loading + having an episode
        // (Controls, player.dart:1310-1313); disabled tints to 38%.
        let controlsEnabled = !context.playback.isLoading
            && episode?.enclosureUrl?.isEmpty == false
        replayButton.isEnabled = controlsEnabled
        forwardButton.isEnabled = controlsEnabled
        playPauseButton.isEnabled = controlsEnabled
        let alpha: CGFloat = controlsEnabled ? 1 : 0.38
        replayButton.alpha = alpha
        forwardButton.alpha = alpha
        playPauseButton.alpha = alpha

        playPauseIcon.update(
            snapshot: .init(
                enclosureURL: episode?.enclosureUrl,
                currentEnclosureURL: episode?.enclosureUrl,
                isPlaying: context.playback.isPlaying,
                isLoading: context.playback.isLoading
            ),
            tint: Theme.playerText
        )

        // K6: error surfaced by the shell toast; this is the manual retry.
        retryRow.isHidden = context.playback.playbackError == nil
    }

    /// The Dart TitleBar reads the subscription row (controller.channel) for
    /// the show's display name; the page owns the async hop off the main actor.
    private func fetchChannel(rssFeedURL: String) async {
        let subscription: SubscriptionRow?
        do {
            subscription = try await context.database.subscriptionRepository().get(byRSSFeedURL: rssFeedURL)
        } catch {
            // A failed DB read is NOT "no channel data": keep whatever the
            // title bar already renders instead of clearing it to the
            // placeholders. Clearing only happens for a genuinely different
            // episode whose fetch SUCCEEDED and found no row.
            return
        }
        // A fast episode switch can outpace this fetch; landing a stale
        // response would paint the previous episode's channel title/image
        // onto the new one (same identity guard as
        // SubtitlesPageViewController.updateHeader).
        guard rssFeedURL == titleBlock.channelURLString else { return }
        // Unsubscribed shows have no row: keep the episode's own show name.
        if let title = subscription?.title, !title.isEmpty {
            titleBlock.setChannelTitle(title)
        }
    }

    // MARK: - Actions

    /// Dart jumpToChannel (player.dart:591-601): the sheet is configured with
    /// the CURRENT episode's feed URL and presented as an expand sheet.
    private func openChannel() {
        guard let rss = context.playback.currentEpisode?.rssFeedUrl else { return }
        let channel = ChannelViewController(context: context, rssFeedURL: rss)
        AppSheets.presentExpand(channel, from: topMostPresented())
    }

    /// player.dart:175-224 — spinner → /api/shortlink → system share panel
    /// with "title\n\nurl" (shortlink failure degrades to the full URL).
    private func shareTapped() {
        guard let episode = context.playback.currentEpisode,
              let rss = episode.rssFeedUrl, let enclosure = episode.enclosureUrl,
              let url = URL(string: ShareURL.player(rssFeedURL: rss, enclosureURL: enclosure))
        else { return }
        shareSpinner.startAnimating()
        let api = context.api
        let title = episode.title ?? ""
        Task { [weak self] in
            let short = await api.getShortURL(for: url) ?? url
            guard let self, self.shareSpinner.isAnimating else { return }
            self.shareSpinner.stopAnimating()
            let activity = UIActivityViewController(
                activityItems: ["\(title)\n\n\(short.absoluteString)"],
                applicationActivities: nil
            )
            self.topMostPresented().present(activity, animated: true)
        }
    }
}

// MARK: - Title block (player.dart:300-399)

/// Episode title (wraps to two lines, then truncates) over the show name;
/// the show name opens the Channel sheet (Dart TitleBar affordance).
@MainActor
private final class PlayerTitleBlockView: UIView {

    var onOpenChannel: (() -> Void)?

    private let titleLabel = UILabel()
    private let channelButton = UIButton(type: .system)
    private(set) var channelURLString = ""
    /// The episode-side show name last pushed by `update`; render() runs
    /// every position tick, so the push must be change-driven or it would
    /// revert a display name already fetched from the subscription row.
    private var lastEpisodeChannelTitle = ""

    init() {
        super.init(frame: .zero)

        titleLabel.font = TypographyV2.headlineMedium.font()
        titleLabel.textColor = Theme.playerText
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        var channelConfig = UIButton.Configuration.plain()
        channelConfig.baseForegroundColor = Theme.playerText.withAlphaComponent(0.7)
        channelConfig.contentInsets = .zero
        channelConfig.titleLineBreakMode = .byTruncatingTail
        channelConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.bodyMedium.font()
            return outgoing
        }
        channelButton.configuration = channelConfig
        channelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        channelButton.contentHorizontalAlignment = .leading
        channelButton.accessibilityLabel = "Open channel"
        channelButton.addAction(
            UIAction { [weak self] _ in self?.onOpenChannel?() },
            for: .touchUpInside
        )

        let stack = UIStackView(arrangedSubviews: [titleLabel, channelButton])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            channelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Spacing.pageHeader),
            channelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: AnycastIconButton.standardDiameter),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Pushes the current episode; `loadChannel` kicks the subscription
    /// fetch (authoritative show name) once per rss URL.
    func update(
        title: String,
        channelTitle: String,
        rssFeedURL: String?,
        loadChannel: @MainActor (String) -> Void
    ) {
        if titleLabel.text != title {
            titleLabel.text = title
        }
        if !channelTitle.isEmpty, channelTitle != lastEpisodeChannelTitle {
            lastEpisodeChannelTitle = channelTitle
            setChannelTitle(channelTitle)
        }
        if let rssFeedURL {
            guard rssFeedURL != channelURLString else { return }
            channelURLString = rssFeedURL
            loadChannel(rssFeedURL)
        } else {
            // No feed URL (no episode / a row without one): skip the fetch
            // and clear the identity so an in-flight fetch for the previous
            // episode cannot land on the current one.
            channelURLString = ""
        }
    }

    func setChannelTitle(_ title: String) {
        channelButton.configuration?.title = title
        channelButton.accessibilityLabel = "Open channel \(title)"
    }
}
