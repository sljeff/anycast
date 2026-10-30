import UIKit
import Kingfisher
import AnycastKit

/// Player page 1 (PlayerMain, player.dart:146-235, 03 §2.10) in the Anycast
/// 2.0 now-playing form: the artwork just under the grabber, the episode
/// title (wraps to two lines) over the show name (taps open the Channel
/// sheet on top) with the share shortcut (shortlink → system share sheet)
/// beside them, then — down by the page selector — the scrubber with the
/// current chapter under it (taps open This episode), and the transport
/// (−10 s / play-pause with the loading animation / +30 s, play centered —
/// the shared `PlayerTransportView`) flanked by playback speed and the
/// sleep timer, each a menu, in the slots the transcript page gives ••• and
/// Ask AI; plus the K6 retry affordance. Slack goes between the title and
/// the scrubber, so the controls stay in the thumb zone. Background belongs
/// to the container.
final class PlayerMainPageViewController: UIViewController {

    private let context: UIContext
    private let observation = ObservationLoop()
    private let chapterObservation = ObservationLoop()

    private let coverFrame = UIView()
    private let coverView = UIImageView()
    private let shareButton = AnycastIconButton(
        style: .plain, icon: AppIcons.share, accessibilityLabel: "Share episode", glyphSize: 20
    )
    private let shareSpinner = UIActivityIndicatorView(style: .medium)
    private let titleBlock = PlayerTitleBlockView()
    private lazy var transport = PlayerTransportView(context: context, transportGap: Spacing.gap)
    private let speedButton = AnycastIconButton(
        style: .tonal, icon: nil, accessibilityLabel: "Playback speed", glyphSize: 20
    )
    private let sleepButton = AnycastIconButton(
        style: .tonal, icon: AppIcons.sleepTimer, accessibilityLabel: "Sleep timer", glyphSize: 20
    )
    private let chapterButton = UIButton(type: .system)
    private var chapters: [EpisodeChapter] = []
    private var sleepTicker: Timer?
    private let retryRow = UIStackView()
    private var bottomStack = UIStackView()

    private enum Layout {
        /// The page's one content column: the artwork, title row, scrubber
        /// and transport all share these side insets.
        static let columnInset = Spacing.pageHeader
        /// Frame-to-ink slack at the share button's trailing side (the
        /// 20 pt `square.and.arrow.up` is ~22.5 pt of ink centered in the
        /// 44 pt hit target, measured), hung outside the column so the
        /// glyph's ink, not the frame, meets the column's trailing edge.
        static let shareInkInset: CGFloat = 10.75
        /// The one vertical rhythm, measured between VISIBLE edges: subtitle
        /// → scrubber track, time labels → transport glyphs and transport
        /// glyphs → page selector.
        static let rhythm: CGFloat = 28
        /// Frame-to-ink slack hidden inside each block (measured on device),
        /// subtracted so the rhythm is the gap the eye sees: the scrubber
        /// track and the show-name text sit well inside their frames, the
        /// time-label band and the 72 pt transport slot pad the skip glyphs.
        static let titleToScrubber = rhythm - 24
        static let transportToSelector = PlayerTransportView.Layout.toSelector
        /// Clears the sheet's system grabber (as on This episode).
        static let contentTop: CGFloat = 36
    }

    /// The speed menu: the stepper's 0.5–2 ×0.25 stops, with the rarely
    /// used 0.5× set apart at the bottom.
    private static let speedStops = PlayerSliderMath.stops(min: 0.5, max: 2.0, divisions: 6)
    private static let sleepMinutes = [10, 20, 30, 45, 60]

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
        bind()
        render()
        renderSpeed()
        renderSleep()

        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
                _ = self.context.playback.playbackError
            },
            onChange: { [weak self] in self?.render() }
        )
        chapterObservation.track(
            read: { [weak self] in
                _ = self?.context.playback.positionData
                _ = self?.context.playback.speed
            },
            onChange: { [weak self] in
                self?.renderChapter()
                self?.renderSpeed()
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderSleep()
        // The sleep countdown lives in SleepTimerController; this only
        // re-reads it so the button's minutes tick down.
        guard sleepTicker == nil else { return }
        sleepTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.renderSleep() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sleepTicker?.invalidate()
        sleepTicker = nil
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

        buildTransportAccessories()
        bottomStack = UIStackView(arrangedSubviews: [transport, retryRow])
        bottomStack.axis = .vertical
        bottomStack.setCustomSpacing(Spacing.pageH, after: transport)

        for block in [coverFrame, titleRow, bottomStack] {
            block.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(block)
        }

        // Square artwork at the column width, centered; on short windows
        // (or under large Dynamic Type) the required top gap squeezes it
        // smaller (07 §4 hard requirement: nothing is pushed off-screen).
        let column = UILayoutGuide()
        view.addLayoutGuide(column)
        // Below the scrubber's compression resistance: when space runs out
        // the artwork gives way first, not the title or the controls.
        let coverWidth = coverFrame.widthAnchor.constraint(equalTo: column.widthAnchor)
        coverWidth.priority = UILayoutPriority(700)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.columnInset),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.columnInset),

            coverFrame.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.contentTop),

            coverFrame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coverWidth,
            coverFrame.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            coverFrame.heightAnchor.constraint(equalTo: coverFrame.widthAnchor),
            coverView.topAnchor.constraint(equalTo: coverFrame.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverFrame.bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: coverFrame.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: coverFrame.trailingAnchor),

            titleRow.topAnchor.constraint(equalTo: coverFrame.bottomAnchor, constant: Spacing.pageHeader),
            titleRow.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            titleRow.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: Layout.shareInkInset),

            // The slack: the controls stay down by the selector.
            bottomStack.topAnchor.constraint(greaterThanOrEqualTo: titleRow.bottomAnchor, constant: Layout.titleToScrubber),
            bottomStack.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.transportToSelector),

            shareSpinner.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            shareSpinner.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),
        ])
    }

    /// Speed left and sleep timer right of the transport, styled like the
    /// transcript page's ••• and Ask AI; the current chapter under the
    /// scrubber.
    private func buildTransportAccessories() {
        for button in [speedButton, sleepButton] {
            button.configuration?.baseBackgroundColor = Theme.playerText.withAlphaComponent(0.08)
            button.configuration?.baseForegroundColor = Theme.playerText
            button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = TypographyV2.body.font().monospacedDigits()
                return outgoing
            }
            button.configuration?.titleLineBreakMode = .byClipping
            button.showsMenuAsPrimaryAction = true
        }
        speedButton.accessibilityIdentifier = "player-speed"
        sleepButton.accessibilityIdentifier = "player-sleep"
        speedButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.speedMenuElements() ?? [])
            },
        ])
        sleepButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.sleepMenuElements() ?? [])
            },
        ])
        transport.setAccessories(leading: speedButton, trailing: sleepButton)

        var chapterConfig = UIButton.Configuration.plain()
        chapterConfig.baseForegroundColor = Theme.playerSecondary
        chapterConfig.contentInsets = .zero
        chapterConfig.titleLineBreakMode = .byTruncatingTail
        chapterConfig.image = UIImage(systemName: "chevron.right")
        chapterConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            font: TypographyV2.meta.font(), scale: .small
        )
        chapterConfig.imagePlacement = .trailing
        chapterConfig.imagePadding = Spacing.xs
        chapterConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        chapterButton.configuration = chapterConfig
        chapterButton.contentHorizontalAlignment = .leading
        chapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        chapterButton.accessibilityIdentifier = "player-current-chapter"
        chapterButton.addAction(UIAction { [weak self] _ in self?.openEpisodePage() }, for: .touchUpInside)
    }

    private func bind() {
        shareButton.addAction(
            UIAction { [weak self] _ in self?.shareTapped() },
            for: .touchUpInside
        )
        titleBlock.onOpenChannel = { [weak self] in self?.openChannel() }
    }

    // MARK: - Rendering (ObservationLoop-driven)

    /// Last URL handed to the cover view — see PlayerBarView.renderedCoverURL;
    /// render() runs every position tick, so the cover load must be
    /// change-driven, not unconditional.
    private var renderedCoverURL: URL?

    private func render() {
        let episode = context.playback.currentEpisode
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

        // K6: error surfaced by the shell toast; this is the manual retry.
        retryRow.isHidden = context.playback.playbackError == nil

        let parsed = EpisodeChapters.chapters(description: episode?.description, cacheKey: episode?.enclosureUrl)
        if parsed != chapters {
            chapters = parsed
            transport.setChapterMarks(parsed.map { Int64($0.startMilliseconds) })
            transport.setScrubberFooter(parsed.isEmpty ? nil : chapterButton)
        }
        renderChapter()
    }

    /// The playing chapter's title under the scrubber.
    private func renderChapter() {
        guard !chapters.isEmpty else { return }
        let position = Int(context.playback.positionData.positionMilliseconds)
        let index = EpisodeChapters.index(at: position, in: chapters) ?? 0
        let title = chapters[index].title
        guard chapterButton.configuration?.title != title else { return }
        chapterButton.configuration?.title = title
        chapterButton.accessibilityLabel = "Chapter: \(title)"
        chapterButton.accessibilityHint = "Shows this episode's chapters and notes"
    }

    private func renderSpeed() {
        let index = PlayerSliderMath.nearestIndex(for: Double(context.playback.speed), in: Self.speedStops)
        let text = PlayerSliderMath.speedText(Self.speedStops[index])
        guard speedButton.configuration?.title != text else { return }
        speedButton.configuration?.title = text
        speedButton.accessibilityValue = text
    }

    /// Off: the moon. Counting down: the minutes left, in gold. End of
    /// episode: the moon in gold.
    private func renderSleep() {
        let timer = context.sleepTimer
        let remaining = timer.remainingMilliseconds ?? 0
        if remaining > 0 {
            sleepButton.setIcon(nil)
            sleepButton.configuration?.title = "\(timer.countdownMinutes)m"
            sleepButton.configuration?.baseForegroundColor = Theme.primary
            sleepButton.accessibilityValue = "\(timer.countdownMinutes) minutes left"
        } else {
            sleepButton.configuration?.title = nil
            sleepButton.setIcon(AppIcons.sleepTimer)
            sleepButton.configuration?.baseForegroundColor = timer.stopsAtEpisodeEnd ? Theme.primary : Theme.playerText
            sleepButton.accessibilityValue = timer.stopsAtEpisodeEnd ? "End of episode" : "Off"
        }
    }

    // MARK: - Menus

    private func speedMenuElements() -> [UIMenuElement] {
        let current = PlayerSliderMath.nearestIndex(for: Double(context.playback.speed), in: Self.speedStops)
        let actions = Self.speedStops.enumerated().map { index, stop in
            UIAction(
                title: PlayerSliderMath.speedText(stop),
                state: index == current ? .on : .off
            ) { [weak self] _ in
                self?.context.playback.setSpeed(Float(stop))
                self?.renderSpeed()
            }
        }
        // Everyday speeds first; the slow 0.5× sits apart below them.
        return [
            UIMenu(title: "Playback speed", options: .displayInline, children: Array(actions.dropFirst())),
            UIMenu(options: .displayInline, children: [actions[0]]),
        ]
    }

    private func sleepMenuElements() -> [UIMenuElement] {
        let timer = context.sleepTimer
        let remaining = timer.remainingMilliseconds ?? 0
        let counting = remaining > 0
        let title = counting ? "Sleep timer · \(timer.countdownMinutes) min left" : "Sleep timer"

        var timerItems: [UIMenuElement] = [
            UIAction(title: "Off", state: !counting && !timer.stopsAtEpisodeEnd ? .on : .off) { [weak self] _ in
                self?.context.sleepTimer.stop()
                self?.renderSleep()
            },
        ]
        for minutes in Self.sleepMinutes {
            timerItems.append(UIAction(title: "\(minutes) minutes") { [weak self] _ in
                self?.context.sleepTimer.setCountdown(minutes: minutes)
                Haptics.timerSet()
                self?.renderSleep()
            })
        }
        let position = context.playback.positionData
        let left = max(position.durationMilliseconds - position.positionMilliseconds, 0)
        let endOfEpisode = UIAction(
            title: "End of episode",
            subtitle: left > 0 ? "\(Int((Double(left) / 60_000).rounded(.up))) min" : nil,
            state: timer.stopsAtEpisodeEnd ? .on : .off
        ) { [weak self] _ in
            self?.context.sleepTimer.setStopAtEpisodeEnd()
            Haptics.timerSet()
            self?.renderSleep()
        }
        timerItems.append(endOfEpisode)

        // Continuous play: what happens whenever an episode finishes.
        let continuous = context.playback.continuousPlaying
        let afterItems: [UIMenuElement] = [
            UIAction(title: "Play next in playlist", state: continuous ? .on : .off) { [weak self] _ in
                self?.context.playback.setContinuousPlaying(true)
            },
            UIAction(title: "Stop", state: continuous ? .off : .on) { [weak self] _ in
                self?.context.playback.setContinuousPlaying(false)
            },
        ]
        return [
            UIMenu(title: title, options: .displayInline, children: timerItems),
            UIMenu(title: "When an episode ends", options: .displayInline, children: afterItems),
        ]
    }

    private func openEpisodePage() {
        var ancestor = parent
        while let controller = ancestor, !(controller is PlayerPageContainer) {
            ancestor = controller.parent
        }
        (ancestor as? PlayerPageContainer)?.selectPage(0)
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
            outgoing.font = TypographyV2.meta.font()
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
