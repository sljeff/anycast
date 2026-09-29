import UIKit
import Kingfisher
import MarqueeLabel
import AnycastKit

/// Player page 1 (PlayerMain, player.dart:146-235, 03 §2.10): centered
/// square cover with the share shortcut (shortlink → system share sheet),
/// the TitleBar (channel image / marquee-gated title / palette-safe channel
/// name — both channel affordances open the Channel sheet on top), the
/// progress bar with remaining-time labels, and the transport controls
/// (−10 s / play-pause with loading lottie / +30 s) plus the K6 retry
/// affordance. Background and palette gradient belong to the container.
final class PlayerMainPageViewController: UIViewController {

    private let context: UIContext
    private let observation = ObservationLoop()

    private let coverView = UIImageView()
    private let shareButton = UIButton(type: .custom)
    private let shareSpinner = UIActivityIndicatorView(style: .medium)
    private let titleBar = PlayerTitleBarView()
    private let stateMessageLabel = UILabel()
    private let progressBar = PlayerProgressBarView()
    private let replayButton = UIButton(type: .custom)
    private let playPauseButton = UIButton(type: .custom)
    private let playPauseIcon = PlayPauseIconControl(size: 48)
    private let forwardButton = UIButton(type: .custom)
    private let retryRow = UIStackView()

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
        // Cover: square at the padded content width (Dart `Get.width - 48`
        // — bounds-relative here), corner radius 8.
        let coverContainer = UIView()
        coverContainer.translatesAutoresizingMaskIntoConstraints = false
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.primaryBackground
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Episode artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(coverView)

        shareButton.setImage(AppIcons.share, for: .normal)
        shareButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18), forImageIn: .normal
        )
        shareButton.tintColor = UIColor.white.withAlphaComponent(0.5)
        shareButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        shareButton.layer.cornerRadius = 18
        shareButton.layer.cornerCurve = .continuous
        shareButton.isAccessibilityElement = true
        shareButton.accessibilityLabel = "Share episode"
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.addSubview(shareButton)
        shareSpinner.color = .white
        shareSpinner.hidesWhenStopped = true
        shareSpinner.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addSubview(shareSpinner)

        let transport = buildControls()

        stateMessageLabel.font = Typography.defaultText.font()
        stateMessageLabel.textColor = Theme.primaryLightMax
        stateMessageLabel.adjustsFontForContentSizeCategory = true
        stateMessageLabel.isHidden = true

        let progressBlock = UIStackView(arrangedSubviews: [stateMessageLabel, progressBar])
        progressBlock.axis = .vertical
        progressBlock.spacing = 4
        progressBlock.alignment = .leading
        // The bar itself spans the full width; only the labels hug the lead.
        progressBar.widthAnchor.constraint(equalTo: progressBlock.widthAnchor).isActive = true

        retryRow.axis = .horizontal
        retryRow.alignment = .center
        retryRow.distribution = .fill
        retryRow.isHidden = true
        let retryButton = UIButton(type: .custom)
        var retryConfig = UIButton.Configuration.gray()
        if let retryIcon = UIImage(systemName: "arrow.clockwise") {
            retryConfig.image = retryIcon
            retryConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16)
        }
        retryConfig.title = "Retry"
        retryConfig.baseForegroundColor = Theme.primaryLightMax
        retryConfig.baseBackgroundColor = Theme.cardBackground
        retryConfig.cornerStyle = .capsule
        retryConfig.imagePadding = 8
        retryConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        retryButton.configuration = retryConfig
        retryButton.isAccessibilityElement = true
        retryButton.accessibilityLabel = "Retry playback"
        retryButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.context.playback.retry() }
            },
            for: .touchUpInside
        )
        retryRow.addArrangedSubview(retryButton)

        // Dart PlayerMain is a Column(mainAxisAlignment:
        // .spaceEvenly) (player.dart:219-300): the four blocks share the
        // page height through EQUAL flexible gaps — grabber at the top,
        // cover, then spacing before the title/progress group. A plain
        // pinned `.fill` stack left the fixed-height blocks collapsed at
        // the top with all slack in one dead gap above the page tab, and
        // its fill-stretch conflicted with the cover cap, shrinking the
        // cover below the design width. Five equal spacers (required
        // equality) reproduce spaceEvenly deterministically; they collapse
        // together on short windows. The content blocks hug at required so
        // the stack can never stretch them — only the spacers absorb slack.
        // retryRow trails transport inside the last gap's span.
        let gaps = (0..<5).map { _ in UIView() }
        gaps.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        let root = UIStackView(arrangedSubviews: [
            gaps[0], coverContainer, gaps[1], titleBar, gaps[2],
            progressBlock, gaps[3], transport, retryRow, gaps[4],
        ])
        root.axis = .vertical
        root.isLayoutMarginsRelativeArrangement = true
        root.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        for pair in zip(gaps, gaps.dropFirst()) {
            pair.0.heightAnchor.constraint(equalTo: pair.1.heightAnchor).isActive = true
        }
        for block in [coverContainer, titleBar, progressBlock, transport, retryRow] {
            block.setContentHuggingPriority(.required, for: .vertical)
            block.setContentCompressionResistancePriority(.required, for: .vertical)
        }

        // Square at the content width; on very short scalable windows the
        // square yields (priority 999) to a height-share cap so the column
        // never overflows (07 §4 hard requirement). Equal width/height caps
        // keep it SQUARE when they bind — the shrunk cover centers instead
        // of stretching to the full width.
        let coverAspect = coverView.heightAnchor.constraint(equalTo: coverView.widthAnchor)
        coverAspect.priority = .init(999)
        let coverWidth = coverView.widthAnchor.constraint(
            equalTo: coverContainer.widthAnchor
        )
        coverWidth.priority = .init(999)
        let coverHeightCap = coverView.heightAnchor.constraint(
            lessThanOrEqualTo: root.heightAnchor, multiplier: 0.55
        )
        let coverWidthCap = coverView.widthAnchor.constraint(
            lessThanOrEqualTo: root.heightAnchor, multiplier: 0.55
        )

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            coverView.centerXAnchor.constraint(equalTo: coverContainer.centerXAnchor),
            coverView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),
            coverWidth,
            coverAspect,
            coverHeightCap,
            coverWidthCap,

            shareButton.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -4),
            shareButton.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: -4),
            shareButton.widthAnchor.constraint(equalToConstant: 36),
            shareButton.heightAnchor.constraint(equalToConstant: 36),
            shareSpinner.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            shareSpinner.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),

            retryRow.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])
    }

    /// replay_10 / 72×72 green play-pause / forward_30 (player.dart:1303-1367);
    /// the −10 s / +30 s deltas are the Dart Controls' seekByRelative values.
    private func buildControls() -> UIView {
        replayButton.setImage(AppIcons.replay10, for: .normal)
        replayButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 48), forImageIn: .normal
        )
        forwardButton.setImage(AppIcons.forward30, for: .normal)
        forwardButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 48), forImageIn: .normal
        )
        for button in [replayButton, forwardButton] {
            button.tintColor = Theme.primaryLightMax
            button.isAccessibilityElement = true
        }
        replayButton.accessibilityLabel = "Seek back 10 seconds"
        forwardButton.accessibilityLabel = "Seek forward 30 seconds"

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

        playPauseButton.backgroundColor = Theme.brandGreen
        playPauseButton.layer.cornerRadius = 36
        playPauseButton.layer.cornerCurve = .continuous
        playPauseButton.isAccessibilityElement = true
        playPauseButton.accessibilityLabel = "Play or pause"
        playPauseIcon.isUserInteractionEnabled = false
        playPauseIcon.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.addSubview(playPauseIcon)
        playPauseButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                Task { await self.context.playback.togglePlay() }
            },
            for: .touchUpInside
        )

        let row = UIStackView(arrangedSubviews: [replayButton, playPauseButton, forwardButton])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            playPauseButton.widthAnchor.constraint(equalToConstant: 72),
            playPauseButton.heightAnchor.constraint(equalToConstant: 72),
            playPauseIcon.centerXAnchor.constraint(equalTo: playPauseButton.centerXAnchor),
            playPauseIcon.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            // Explicit size: the intrinsicContentSize already declares 48,
            // but the loading lottie's canvas must never be able to stretch
            // the control past the 72 pt button (R2).
            playPauseIcon.widthAnchor.constraint(equalToConstant: 48),
            playPauseIcon.heightAnchor.constraint(equalToConstant: 48),
        ])
        return row
    }

    private func bind() {
        shareButton.addAction(
            UIAction { [weak self] _ in self?.shareTapped() },
            for: .touchUpInside
        )
        titleBar.onOpenChannel = { [weak self] in self?.openChannel() }
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

        let coverURL = (episode?.imageUrl.flatMap(URL.init(string:)))
            ?? URL(string: "https://placehold.co/400/000000/FFF.png?text=No+Episode")
        if coverURL != renderedCoverURL {
            renderedCoverURL = coverURL
            coverView.kf.cancelDownloadTask()
            coverView.kf.setImage(with: coverURL)
        }

        titleBar.update(
            title: episode?.title ?? "",
            channelTitle: episode?.channelTitle ?? "",
            rssFeedURL: episode?.rssFeedUrl
        ) { [weak self] rss in
            guard let self else { return }
            Task { await self.fetchChannel(rssFeedURL: rss) }
        }
        updateChannelNameColor(imageURL: episode?.imageUrl)

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
        let tint: UIColor = controlsEnabled
            ? Theme.primaryLightMax
            : Theme.primaryLightMax.withAlphaComponent(0.38)
        replayButton.tintColor = tint
        forwardButton.tintColor = tint
        playPauseButton.alpha = controlsEnabled ? 1 : 0.38

        playPauseIcon.update(
            snapshot: .init(
                enclosureURL: episode?.enclosureUrl,
                currentEnclosureURL: episode?.enclosureUrl,
                isPlaying: context.playback.isPlaying,
                isLoading: context.playback.isLoading
            ),
            tint: Theme.primaryLightMax
        )

        // K6: error surfaced by the shell toast; this is the manual retry.
        retryRow.isHidden = context.playback.playbackError == nil
    }

    /// The Dart TitleBar reads the subscription row (controller.channel) for
    /// the channel image; the page owns the async hop off the main actor.
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
        guard rssFeedURL == titleBar.channelURLString else { return }
        titleBar.applyChannel(
            imageURL: subscription?.imageUrl ?? "",
            channelTitle: subscription?.title ?? ""
        )
    }

    /// Channel-name color = getTextSafeColor(dominant) — the palette rule
    /// (formatters.dart:139-153; luminance < 0.2 falls back to 0x10B981).
    private var paletteImageURL: String?

    private func updateChannelNameColor(imageURL: String?) {
        guard let imageURL, !imageURL.isEmpty else {
            titleBar.setDominantColor(nil)
            paletteImageURL = nil
            return
        }
        guard imageURL != paletteImageURL else { return }
        paletteImageURL = imageURL
        if let cached = context.palette.cachedDominantColor(for: imageURL) {
            titleBar.setDominantColor(cached)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let color = await self.context.palette.dominantColor(from: imageURL)
            guard self.paletteImageURL == imageURL else { return }
            self.titleBar.setDominantColor(color)
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

// MARK: - TitleBar (player.dart:300-399)

/// Channel image (64×64 r12, tap → Channel) + title (24 pt w600; marquee
/// only when the MEASURED width overflows — K33) + channel name (16 pt w600,
/// `getTextSafeColor(dominant)` → 0x10B981 when the dominant is too dark;
/// also taps to Channel).
@MainActor
private final class PlayerTitleBarView: UIView {

    var onOpenChannel: (() -> Void)?

    private let imageButton = UIButton(type: .custom)
    private let imageView = UIImageView()
    private let titleContainer = UIView()
    private var titleLabel = UILabel()
    private let channelButton = UIButton(type: .system)
    private var titleIsMarquee = false
    private var currentTitle = ""
    private var laidOutWidth: CGFloat = 0
    private(set) var channelURLString = ""
    private var fetchedImageURL: String?
    /// The episode-side fallback title last pushed by `update`; render()
    /// runs every position tick, so the push must be change-driven or it
    /// would rebuild the button configuration and revert a display name
    /// already fetched from the subscription row.
    private var lastEpisodeChannelTitle = ""

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 64))

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = Theme.primaryBackground
        imageView.image = AppIcons.photo
        imageView.tintColor = Theme.primaryLightMax
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageButton.addSubview(imageView)

        for button in [imageButton, channelButton] {
            button.addAction(
                UIAction { [weak self] _ in self?.onOpenChannel?() },
                for: .touchUpInside
            )
        }
        imageButton.isAccessibilityElement = true
        imageButton.accessibilityLabel = "Open channel"

        applyTitleFont()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleLabel)

        var channelConfig = UIButton.Configuration.plain()
        channelConfig.baseForegroundColor = Theme.tabSelectedGreen
        channelConfig.contentInsets = .zero
        channelButton.configuration = channelConfig
        channelButton.titleLabel?.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 16, weight: .semibold)
        )
        channelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        channelButton.contentHorizontalAlignment = .leading
        channelButton.isAccessibilityElement = true
        channelButton.accessibilityLabel = "Open channel"

        imageButton.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        channelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageButton)
        addSubview(titleContainer)
        addSubview(channelButton)

        NSLayoutConstraint.activate([
            imageButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageButton.topAnchor.constraint(equalTo: topAnchor),
            imageButton.widthAnchor.constraint(equalToConstant: 64),
            imageButton.heightAnchor.constraint(equalToConstant: 64),

            imageView.leadingAnchor.constraint(equalTo: imageButton.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageButton.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageButton.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageButton.bottomAnchor),

            titleContainer.leadingAnchor.constraint(equalTo: imageButton.trailingAnchor, constant: 6),
            titleContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleContainer.topAnchor.constraint(equalTo: topAnchor),
            titleContainer.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleContainer.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: titleContainer.bottomAnchor),

            channelButton.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            channelButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            channelButton.topAnchor.constraint(equalTo: titleContainer.bottomAnchor, constant: 6),
            channelButton.heightAnchor.constraint(equalToConstant: 24),

            heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyTitleFont() {
        let font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .semibold)
        )
        if titleLabel is MarqueeLabel {
            (titleLabel as! MarqueeLabel).font = font
        } else {
            titleLabel.font = font
            titleLabel.adjustsFontForContentSizeCategory = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = titleContainer.bounds.width
        if abs(width - laidOutWidth) > 0.5 {
            laidOutWidth = width
            applyTitle()
        }
    }

    /// Pushes the current episode; `loadChannel` kicks the subscription
    /// fetch (image + authoritative channel title) once per rss URL.
    func update(
        title: String,
        channelTitle: String,
        rssFeedURL: String?,
        loadChannel: @MainActor (String) -> Void
    ) {
        if title != currentTitle {
            currentTitle = title
            applyTitle()
        }
        if !channelTitle.isEmpty, channelTitle != lastEpisodeChannelTitle {
            lastEpisodeChannelTitle = channelTitle
            setChannelTitle(channelTitle)
        }
        if let rssFeedURL {
            guard rssFeedURL != channelURLString else { return }
            channelURLString = rssFeedURL
            fetchedImageURL = nil
            loadChannel(rssFeedURL)
        } else {
            // No feed URL (no episode / a row without one): skip the fetch
            // and clear the identity so an in-flight fetch for the previous
            // episode cannot land on the current one.
            channelURLString = ""
        }
    }

    func applyChannel(imageURL: String, channelTitle: String) {
        if !channelTitle.isEmpty {
            setChannelTitle(channelTitle)
        }
        guard imageURL != fetchedImageURL else { return }
        fetchedImageURL = imageURL
        if imageURL.isEmpty {
            imageView.kf.cancelDownloadTask()
            imageView.image = AppIcons.photo
        } else {
            imageView.kf.setImage(
                with: URL(string: imageURL),
                placeholder: AppIcons.photo,
                options: [.transition(.none)]
            )
        }
    }

    /// Dominant color for the channel-name safe-color rule; nil resets to
    /// the app link green (the Dart fallback applies to every too-dark
    /// dominant, including the palette fallback itself).
    func setDominantColor(_ color: UIColor?) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if let color, color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let rgb = (UInt32(red * 255) << 16) | (UInt32(green * 255) << 8) | UInt32(blue * 255)
            setChannelColor(PlayerPaletteRules.channelNameColor(dominantRGB: rgb | 0xFF00_0000))
        } else {
            // Luminance 0 → the fallback green applies.
            setChannelColor(PlayerPaletteRules.channelNameColor(dominantRGB: 0))
        }
    }

    private func setChannelTitle(_ title: String) {
        var config = channelButton.configuration ?? UIButton.Configuration.plain()
        config.title = title
        channelButton.configuration = config
        channelButton.accessibilityLabel = "Open channel \(title)"
    }

    private func setChannelColor(_ color: UIColor) {
        var config = channelButton.configuration ?? UIButton.Configuration.plain()
        config.baseForegroundColor = color
        channelButton.configuration = config
    }

    /// The K33 gate: swap UILabel ↔ MarqueeLabel on measured overflow
    /// (Dart estimated `title.length * 24`; the port measures the real
    /// width through MarqueeLabelFactory).
    private func applyTitle() {
        guard laidOutWidth > 0 else { return }
        let font = titleLabel.font ?? UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: 24, weight: .semibold)
        )
        let needsMarquee = MarqueeLabelFactory.titleNeedsMarquee(
            currentTitle, font: font, availableWidth: laidOutWidth
        )
        if needsMarquee != titleIsMarquee {
            let textColor = Theme.primaryLightMax
            titleLabel.removeFromSuperview()
            if needsMarquee {
                titleLabel = MarqueeLabelFactory.makePlayerTitle(font: font, textColor: textColor)
                titleIsMarquee = true
            } else {
                titleLabel = UILabel()
                applyTitleFont()
                titleLabel.textColor = textColor
                titleIsMarquee = false
            }
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleContainer.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleContainer.trailingAnchor),
                titleLabel.topAnchor.constraint(equalTo: titleContainer.topAnchor),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: titleContainer.bottomAnchor),
            ])
        }
        (titleLabel as? MarqueeLabel)?.text = currentTitle
        if !(titleLabel is MarqueeLabel) {
            (titleLabel as UILabel).text = currentTitle
        }
    }
}
