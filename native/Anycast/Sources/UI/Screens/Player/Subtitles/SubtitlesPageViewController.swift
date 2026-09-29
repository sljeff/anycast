import UIKit
import AnycastKit
import Kingfisher
import Lottie

/// Player page 2 (PlayerAI/Subtitles, 03 §2.10): a bordered rounded
/// container — 60 pt header (channel artwork + 12 pt comfortaa w700
/// two-line episode title) + divider + the transcript five-state content
/// (unavailable / prompt / processing / failed / ready), the ready state
/// being the bilingual lyrics view with the drag time bar, the AI-chat /
/// export overlay and the play-pause morph.
///
/// Row state is derived from the poll controllers plus async row fetches;
/// polling cadence, K27 error policy and the K9 5-strike rule all live in
/// AnycastKit — this controller only observes and renders
/// (TranscriptStateReducer is the pure mapping).
final class SubtitlesPageViewController: UIViewController {

    private let context: UIContext

    // MARK: Chrome

    private let container = UIView()
    private let artworkView = UIImageView()
    private let titleLabel = UILabel()
    private let divider = UIView()
    private let contentHost = UIView()

    // MARK: Observed state

    private var loadedURL: String?
    private var rowPhase: TranscriptRowPhase = .fetching
    private var subtitleRow: SubtitleRow?
    private var translationRowPhase: TranslationRowPhase = .idle
    private var translationRow: TranslationRow?
    private var renderedState: TranscriptVisualState?

    private var loadedRSSFeedURL: String?

    // MARK: Ready-state views (kept alive across state swaps so scroll and
    // follow position survive)

    private let lyricsView = LyricsView()
    private var lyricsBottomConstraint: NSLayoutConstraint?
    private var inlineStatus: UIView?
    private var overlay: GlassContainerView?

    /// The prompt-state question tooltip (10 s transient, 03 §2.10).
    private var infoTooltip: UIView?
    private var infoTooltipTimer: Timer?

    private let stateLoop = ObservationLoop()
    private let progressLoop = ObservationLoop()
    private var languageObserver: NSObjectProtocol?

    #if DEBUG
    private var demoMode = false
    private var demoTimer: Timer?
    private var demoPositionMilliseconds = 0
    #endif

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

        buildChrome()

        lyricsView.onTapLine = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.context.playback.togglePlay()
                // Dart: PlayPauseAnimation(isPlaying: !isPlaying.value) —
                // the glyph shows the state AFTER the toggle.
                if let window = self.view.window {
                    PlayPauseAnimationView.presentOver(
                        window, isPlaying: self.context.playback.isPlaying
                    )
                }
            }
        }
        lyricsView.onSeekLine = { [weak self] milliseconds in
            guard let self else { return }
            Task { await self.context.playback.seek(Int64(milliseconds)) }
        }

        stateLoop.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode?.enclosureUrl
                _ = self.context.subtitles.statuses
                _ = self.context.translations.statuses
            },
            onChange: { [weak self] in self?.refreshState() }
        )
        progressLoop.track(
            read: { [weak self] in _ = self?.context.playback.positionData },
            onChange: { [weak self] in
                guard let self else { return }
                self.lyricsView.setProgress(
                    positionMilliseconds: Int(self.context.playback.positionData.positionMilliseconds)
                )
            }
        )
        // Target-language switch re-fetches the translation row under the
        // new key (the poller map itself is reset by the controller).
        languageObserver = NotificationCenter.default.addObserver(
            forName: SettingsCoordinator.targetLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.translationRow = nil
                self.translationRowPhase = .idle
                self.refreshState()
            }
        }

        #if DEBUG
        configureDemoIfRequested()
        #endif
        refreshState()
    }

    deinit {
        // UI teardown runs on the main thread; the observer token is not
        // Sendable so the access goes through an isolated assertion.
        MainActor.assumeIsolated {
            infoTooltipTimer?.invalidate()
            #if DEBUG
            // The demo position driver would otherwise keep firing (and
            // retaining the closure) after the page is gone.
            demoTimer?.invalidate()
            #endif
            if let languageObserver {
                NotificationCenter.default.removeObserver(languageObserver)
            }
        }
    }

    // MARK: - Chrome construction

    private func buildChrome() {
        container.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        container.layer.borderColor = Theme.primaryLightMax.withAlphaComponent(0.12).cgColor
        container.layer.borderWidth = 1
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.layer.cornerCurve = .continuous
        artworkView.backgroundColor = Theme.cardBackground
        artworkView.tintColor = Theme.secondaryText
        artworkView.image = AppIcons.playerMain.withTintColor(
            Theme.secondaryText, renderingMode: .alwaysOriginal
        )
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(artworkView)

        titleLabel.font = UIFont(name: "Comfortaa-Bold", size: 12)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        divider.backgroundColor = Theme.primaryLightMax.withAlphaComponent(0.12)
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentHost)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),

            artworkView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            artworkView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            artworkView.widthAnchor.constraint(equalToConstant: 36),
            artworkView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: artworkView.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.topAnchor.constraint(equalTo: container.topAnchor, constant: 60),
            divider.heightAnchor.constraint(equalToConstant: 1),

            contentHost.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            contentHost.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            contentHost.topAnchor.constraint(equalTo: divider.bottomAnchor),
            contentHost.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - State refresh (observation → row loads → render)

    private func refreshState() {
        #if DEBUG
        if demoMode {
            render()
            return
        }
        #endif
        let episode = context.playback.currentEpisode
        updateHeader(episode: episode)

        let url = (episode?.enclosureUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if url != loadedURL {
            loadedURL = url
            subtitleRow = nil
            translationRow = nil
            rowPhase = .fetching
            translationRowPhase = .idle
            if !url.isEmpty {
                loadTranscriptRow(url: url)
            }
        }
        if let status = context.subtitles.statuses[url], status == "succeeded",
           !url.isEmpty, translationRowPhase == .idle {
            loadTranslationRow(url: url)
        }
        render()
    }

    private func loadTranscriptRow(url: String) {
        rowPhase = .fetching
        render()
        Task { @MainActor in
            let repository = self.context.database.subtitleRepository()
            let phase: (TranscriptRowPhase, SubtitleRow?)
            do {
                let row = try await repository.get(byEnclosureURL: url)
                phase = Self.mapSubtitleRow(row)
            } catch {
                phase = (.failed, nil)
            }
            guard self.loadedURL == url else { return }
            self.rowPhase = phase.0
            self.subtitleRow = phase.1
            if phase.0 == .empty {
                // Dart deletes the unusable row and falls back to processing
                // (player.dart:782-786). The poller keeps its own status map.
                try? await repository.delete(byEnclosureURL: url)
            }
            self.render()
        }
    }

    private func loadTranslationRow(url: String) {
        translationRowPhase = .fetching
        render()
        Task { @MainActor in
            let language = self.context.settingsBox.current.targetLanguage
            do {
                let row = try await self.context.database.translationRepository()
                    .get(byEnclosureURL: url, language: language)
                guard self.loadedURL == url else { return }
                self.translationRow = row
                self.translationRowPhase = .loaded
            } catch {
                guard self.loadedURL == url else { return }
                self.translationRowPhase = .failed
            }
            self.render()
        }
    }

    /// Dart payload usability (player.dart:779-787): null / blank / "null"
    /// is unusable (→ processing + delete); a payload that no longer decodes
    /// is the fetch-error panel.
    private static func mapSubtitleRow(_ row: SubtitleRow?) -> (TranscriptRowPhase, SubtitleRow?) {
        guard let row else { return (.empty, nil) }
        guard let payload = row.subtitle,
              !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload != "null"
        else { return (.empty, row) }
        guard row.segments != nil else { return (.failed, row) }
        return (.loaded, row)
    }

    private func updateHeader(episode: PlaylistEpisodeRow?) {
        titleLabel.text = episode?.title ?? ""
        guard let rssFeedURL = episode?.rssFeedUrl, !rssFeedURL.isEmpty else {
            loadedRSSFeedURL = nil
            applyArtwork(imageURL: nil)
            return
        }
        guard rssFeedURL != loadedRSSFeedURL else { return }
        loadedRSSFeedURL = rssFeedURL
        Task { @MainActor in
            let subscription = try? await self.context.database.subscriptionRepository()
                .get(byRSSFeedURL: rssFeedURL)
            guard self.loadedRSSFeedURL == rssFeedURL else { return }
            self.applyArtwork(imageURL: subscription?.imageUrl)
        }
    }

    private func applyArtwork(imageURL: String?) {
        if let imageURL, let url = URL(string: imageURL) {
            artworkView.kf.setImage(with: url, options: [.transition(.none)])
        } else {
            artworkView.image = AppIcons.playerMain.withTintColor(
                Theme.secondaryText, renderingMode: .alwaysOriginal
            )
        }
    }

    // MARK: - Rendering

    private func currentState() -> TranscriptVisualState {
        #if DEBUG
        if demoMode { return .ready(translation: .bilingual) }
        #endif
        return TranscriptStateReducer.reduce(
            hasEpisode: !(loadedURL ?? "").isEmpty,
            subtitleStatus: loadedURL.flatMap { context.subtitles.statuses[$0] },
            row: rowPhase,
            translationStatus: loadedURL.flatMap { context.translations.statuses[$0] },
            translationRow: translationRowPhase
        )
    }

    private func render() {
        let state = currentState()
        guard state != renderedState else { return }
        renderedState = state
        dismissInfoTooltip()
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        lyricsBottomConstraint?.isActive = false
        lyricsBottomConstraint = nil
        inlineStatus = nil
        overlay = nil

        // The `Subtitles` widget state panels (player.dart 1.2.1+38): the
        // wrapper states around the row fetches render status panels too —
        // unavailable / loading / load-failed (a blank page was the QA
        // crawl's "near-black transcript page"; the Dart baseline renders
        // _TranscriptStatusPanel for every wrapper state, player.dart
        // 700-812).
        switch state {
        case .unavailable:
            makeUnavailablePanel()
        case .loading:
            makeLoadingPanel()
        case .loadFailed:
            makeLoadFailedPanel()
        case .prompt:
            makePromptPanel()
        case .processing:
            makeProcessingPanel()
        case .failed:
            makeFailedPanel()
        case .ready(let translation):
            // Every translation phase renders the lyrics area — the
            // in-flight/failed translation rows show the main lyric with
            // the inline status bar (player.dart:834-864).
            installLyricsArea(translation: translation)
        }

        contentHost.setNeedsLayout()
    }

    // MARK: - Status panels (released baseline 1.2.1+38, 03 §2.10)

    private func embedFilling(_ child: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            child.topAnchor.constraint(equalTo: contentHost.topAnchor),
            child.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
    }

    /// Centers a vertical column inside the content host (Dart `Center`).
    private func embedCentered(_ column: UIStackView) {
        column.axis = .vertical
        column.alignment = .center
        column.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: wrapper.leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor),
        ])
        embedFilling(wrapper)
    }

    /// Ungenerated (player.dart 1.2.1+38): "Generate transcript with AI
    /// (Beta)" + green 20×20 question dot with a 10 s tap tooltip + the big
    /// green newDoc capsule that triggers `subtitles.add(url)`.
    private func makePromptPanel() {
        let title = UILabel()
        title.text = "Generate transcript with AI (Beta)"
        title.font = SubtitlesPageViewController.systemFont(size: 16, weight: .regular)
        title.textColor = Theme.primaryLightMax
        title.textAlignment = .center
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true

        let questionDot = UIButton(type: .custom)
        questionDot.backgroundColor = Theme.brandGreen
        questionDot.layer.cornerRadius = 10
        questionDot.layer.cornerCurve = .continuous
        questionDot.setTitle("?", for: .normal)
        questionDot.setTitleColor(Theme.primaryBackgroundDark, for: .normal)
        questionDot.titleLabel?.font = SubtitlesPageViewController.systemFont(size: 12, weight: .regular)
        questionDot.isAccessibilityElement = true
        questionDot.accessibilityLabel = "About AI transcripts"
        questionDot.addAction(
            UIAction { [weak self] _ in
                self?.toggleInfoTooltip(anchor: questionDot)
            },
            for: .touchUpInside
        )

        let headline = UIStackView(arrangedSubviews: [title, questionDot])
        headline.axis = .vertical
        headline.alignment = .center
        headline.spacing = 8

        let generateButton = UIButton(type: .custom)
        generateButton.backgroundColor = Theme.brandGreen
        generateButton.layer.cornerRadius = 24
        generateButton.layer.cornerCurve = .continuous
        generateButton.setImage(AppIcons.newDoc, for: .normal)
        generateButton.tintColor = .white
        generateButton.isAccessibilityElement = true
        generateButton.accessibilityLabel = "Generate transcript"
        generateButton.accessibilityTraits = .button
        generateButton.addAction(
            UIAction { [weak self] _ in self?.generateTranscript() },
            for: .touchUpInside
        )

        let column = UIStackView(arrangedSubviews: [headline, generateButton])
        embedCentered(column)
        column.setCustomSpacing(32, after: headline)
        NSLayoutConstraint.activate([
            questionDot.widthAnchor.constraint(equalToConstant: 20),
            questionDot.heightAnchor.constraint(equalToConstant: 20),

            generateButton.widthAnchor.constraint(equalToConstant: 96),
            generateButton.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    /// Processing: robot_loading + the three baseline lines (player.dart
    /// 1.2.1+38).
    private func makeProcessingPanel() {
        let animation = LottieAnimationView(name: "robot_loading")
        animation.contentMode = .scaleAspectFit
        animation.loopMode = .loop
        animation.play()
        animation.translatesAutoresizingMaskIntoConstraints = false

        func line(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = SubtitlesPageViewController.systemFont(size: size, weight: weight)
            label.textColor = Theme.primaryLightMax
            label.textAlignment = .center
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            return label
        }

        let column = UIStackView(arrangedSubviews: [
            animation,
            line("Generating with AI ...", size: 14, weight: .semibold),
            line("It may take 2 ~ 5 minutes ...", size: 14, weight: .semibold),
            line("Feel free to explore or come back later.", size: 12, weight: .regular),
        ])
        embedCentered(column)
        column.spacing = 8
        column.setCustomSpacing(24, after: animation)
        column.setCustomSpacing(24, after: column.arrangedSubviews[2])
        NSLayoutConstraint.activate([
            animation.widthAnchor.constraint(equalToConstant: 112),
            animation.heightAnchor.constraint(equalToConstant: 112),
        ])
    }

    /// Failed: a single accent Retry capsule (03 §2.10 "Retry"; baseline
    /// code uses the accent fill, the doc's "blue" describes an older
    /// release line).
    private func makeFailedPanel() {
        let retry = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Retry"
        configuration.baseBackgroundColor = Theme.accent
        configuration.baseForegroundColor = Theme.primaryBackgroundDark
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 24, bottom: 10, trailing: 24
        )
        retry.configuration = configuration
        retry.addAction(
            UIAction { [weak self] _ in self?.generateTranscript() },
            for: .touchUpInside
        )
        let column = UIStackView(arrangedSubviews: [retry])
        embedCentered(column)
    }

    // MARK: - Wrapper-state status panels (_TranscriptStatusPanel,
    // player.dart:420-490: 64×64 tinted circle + 30pt icon, centered
    // title/message, optional action)

    private func makeStatusLine(_ text: String, size: CGFloat, weight: UIFont.Weight,
                                color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = SubtitlesPageViewController.systemFont(size: size, weight: weight)
        label.textColor = color
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func makeStatusIcon(_ systemName: String, tintColor: UIColor) -> UIView {
        let circle = UIView()
        circle.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        circle.layer.cornerRadius = 32
        circle.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: systemName))
        icon.tintColor = tintColor
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(icon)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 64),
            circle.heightAnchor.constraint(equalToConstant: 64),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
        ])
        return circle
    }

    /// Unavailable (no episode): "Transcript unavailable" — player.dart:701-710.
    private func makeUnavailablePanel() {
        let column = UIStackView(arrangedSubviews: [
            makeStatusIcon("doc.text", tintColor: Theme.primaryLightMax),
            makeStatusLine("Transcript unavailable", size: 16, weight: .semibold,
                           color: Theme.primaryLightMax),
            makeStatusLine(
                "Choose an episode to view or generate its transcript.",
                size: 14, weight: .regular, color: Theme.secondaryText
            ),
        ])
        embedCentered(column)
        column.spacing = 12
        column.setCustomSpacing(20, after: column.arrangedSubviews[0])
    }

    /// Row fetch in flight: spinner + "Loading transcript…" —
    /// player.dart:806-815.
    private func makeLoadingPanel() {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Theme.accent
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 32),
            spinner.heightAnchor.constraint(equalToConstant: 32),
        ])
        let column = UIStackView(arrangedSubviews: [
            spinner,
            makeStatusLine("Loading transcript…", size: 16, weight: .semibold,
                           color: Theme.primaryLightMax),
            makeStatusLine(
                "Preparing the saved transcript for playback.",
                size: 14, weight: .regular, color: Theme.secondaryText
            ),
        ])
        embedCentered(column)
        column.spacing = 12
        column.setCustomSpacing(20, after: spinner)
    }

    /// Row fetch failed: error icon + "Couldn't load transcript" + a
    /// Try-again action that re-runs the row load — player.dart:789-805.
    private func makeLoadFailedPanel() {
        let retry = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Try again"
        configuration.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        configuration.baseBackgroundColor = Theme.accent
        configuration.baseForegroundColor = Theme.primaryBackgroundDark
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 24, bottom: 10, trailing: 24
        )
        retry.configuration = configuration
        retry.addAction(
            UIAction { [weak self] _ in
                guard let self, let url = self.loadedURL, !url.isEmpty else { return }
                self.loadTranscriptRow(url: url)
            },
            for: .touchUpInside
        )
        let column = UIStackView(arrangedSubviews: [
            makeStatusIcon("arrow.triangle.2.circlepath", tintColor: .systemRed),
            makeStatusLine("Couldn't load transcript", size: 16, weight: .semibold,
                           color: Theme.primaryLightMax),
            makeStatusLine(
                "The saved transcript is temporarily unavailable.",
                size: 14, weight: .regular, color: Theme.secondaryText
            ),
            retry,
        ])
        embedCentered(column)
        column.spacing = 12
        column.setCustomSpacing(20, after: column.arrangedSubviews[0])
        column.setCustomSpacing(24, after: column.arrangedSubviews[2])
    }

    /// The 10 s tap tooltip of the question dot (Dart `Tooltip(showDuration:
    /// 10s, triggerMode: tap)`).
    private func toggleInfoTooltip(anchor: UIView) {
        if infoTooltip != nil {
            dismissInfoTooltip()
            return
        }
        let label = UILabel()
        label.text = "AI transcript may take about 2 ~ 5 minutes"
        label.font = SubtitlesPageViewController.systemFont(size: 12, weight: .regular)
        label.textColor = Theme.primaryLightMax
        label.numberOfLines = 0
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true

        let pill = UIView()
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.87)
        pill.layer.cornerRadius = 8
        pill.layer.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        contentHost.addSubview(pill)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),

            pill.centerXAnchor.constraint(equalTo: contentHost.centerXAnchor),
            pill.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 8),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])
        infoTooltip = pill
        infoTooltipTimer = Timer.scheduledTimer(
            withTimeInterval: 10, repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissInfoTooltip()
            }
        }
    }

    private func dismissInfoTooltip() {
        infoTooltipTimer?.invalidate()
        infoTooltipTimer = nil
        infoTooltip?.removeFromSuperview()
        infoTooltip = nil
    }

    /// `controller.add(url)` with the K27 user-trigger surface: the error
    /// signal from the add itself becomes a toast (background polling is
    /// silent; 401 routes to login inside the poller).
    private func generateTranscript() {
        guard let url = loadedURL else { return }
        Task { @MainActor in
            let signal = await self.context.subtitles.add(url: url)
            guard let signal, let window = self.view.window else { return }
            switch signal {
            case .errorMessage(let text):
                ToastPresenter.shared.show(text, in: window, duration: 3)
            case .errorBody(let status, let body):
                ToastPresenter.shared.show("Error \(status): \(body)", in: window, duration: 3)
            case .loginRequired:
                break
            }
        }
    }

    // MARK: - Ready area (LyricsWithShare)

    private func installLyricsArea(translation: TranslationPhase) {
        // Three-edge embed: the bottom is `lyricsBottomConstraint` (full
        // height in mono/bilingual, above the 48 pt inline status while
        // translating — Dart `height - AnycastSpacing.xxl`).
        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(lyricsView)
        NSLayoutConstraint.activate([
            lyricsView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            lyricsView.topAnchor.constraint(equalTo: contentHost.topAnchor),
        ])
        lyricsView.updateDocument(
            lines: currentLyricLines(),
            positionMilliseconds: Int(context.playback.positionData.positionMilliseconds)
        )

        var inlineMessage: String?
        var inlineSpinner = false
        switch translation {
        case .mono, .bilingual:
            inlineMessage = nil
        case .translating:
            // Baseline Row[RefreshProgressIndicator, "Translating
            // subtitles..."] pinned under the lyrics (player.dart 1.2.1+38).
            inlineMessage = "Translating subtitles..."
            inlineSpinner = true
        case .loadingTranslation:
            inlineMessage = "Loading translation…"
            inlineSpinner = true
        case .translationUnavailable:
            inlineMessage = "Translation unavailable"
            inlineSpinner = false
        }

        var statusTopAnchor = contentHost.bottomAnchor
        if let inlineMessage {
            let status = makeInlineStatus(message: inlineMessage, spinner: inlineSpinner)
            status.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(status)
            NSLayoutConstraint.activate([
                status.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                status.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                status.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
                status.heightAnchor.constraint(equalToConstant: 48),
            ])
            inlineStatus = status
            statusTopAnchor = status.topAnchor
        }
        lyricsBottomConstraint = lyricsView.bottomAnchor.constraint(equalTo: statusTopAnchor)
        lyricsBottomConstraint?.isActive = true

        installOverlay()
    }

    private func currentLyricLines() -> [LyricLine] {
        guard let subtitleRow else { return [] }
        let mainLRC = LRC.render(rawJSON: subtitleRow.subtitle)
        var translationLRC: String? {
            guard case .ready(.bilingual)? = renderedState else { return nil }
            return LRC.render(rawJSON: translationRow?.translation)
        }
        return LyricDocument.parse(mainLRC: mainLRC, translationLRC: translationLRC)
    }

    /// Bottom-right floating overlay (player.dart:1131-1203): AI chat entry
    /// + the export menu, as one grouped glass surface (07 §2.5).
    private func installOverlay() {
        let glass = GlassContainerView(mode: .container, cornerRadius: 20)
        glass.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(glass)
        overlay = glass

        let chatIcon = UIImageView(image: AppIcons.aiChat)
        chatIcon.tintColor = Theme.brandGreen
        chatIcon.contentMode = .scaleAspectFit
        chatIcon.isUserInteractionEnabled = true
        chatIcon.isAccessibilityElement = true
        chatIcon.accessibilityLabel = "AI chat"
        chatIcon.accessibilityTraits = .button
        chatIcon.translatesAutoresizingMaskIntoConstraints = false
        chatIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openChat)))

        let moreButton = UIButton(type: .system)
        moreButton.setImage(AppIcons.more, for: .normal)
        moreButton.tintColor = Theme.secondaryText
        moreButton.isAccessibilityElement = true
        moreButton.accessibilityLabel = "More transcript actions"
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [
            UIAction(
                title: "Export subtitles",
                image: AppIcons.exportFile
            ) { [weak self] _ in
                self?.exportTranscript()
            },
        ])
        moreButton.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [chatIcon, moreButton])
        row.axis = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.glassContentView.addSubview(row)

        NSLayoutConstraint.activate([
            chatIcon.widthAnchor.constraint(equalToConstant: 24),
            chatIcon.heightAnchor.constraint(equalToConstant: 24),
            row.topAnchor.constraint(equalTo: glass.glassContentView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: glass.glassContentView.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: glass.glassContentView.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: glass.glassContentView.trailingAnchor, constant: -4),

            glass.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: lyricsView.bottomAnchor),
        ])
    }

    private func makeInlineStatus(message: String, spinner: Bool) -> UIView {
        var elements: [UIView] = []
        if spinner {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = Theme.accent
            indicator.startAnimating()
            indicator.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                indicator.widthAnchor.constraint(equalToConstant: 18),
                indicator.heightAnchor.constraint(equalToConstant: 18),
            ])
            elements.append(indicator)
        }
        let label = UILabel()
        label.text = message
        label.font = SubtitlesPageViewController.systemFont(size: 15, weight: .semibold)
        label.textColor = Theme.secondaryText
        label.adjustsFontForContentSizeCategory = true
        elements.append(label)

        let row = UIStackView(arrangedSubviews: elements)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    // MARK: - Overlay actions

    @objc private func openChat() {
        let chat = ChatViewController(context: context)
        AppSheets.presentExpand(chat, from: topMostPresented())
    }

    /// K21: exported file is a `.txt` carrying the LRC body; the text is
    /// assembled by the G4-pinned `ExportText` builder, the file name by
    /// the K29 sanitizer.
    private func exportTranscript() {
        guard let episode = context.playback.currentEpisode,
              let subtitleRow
        else { return }

        let mainLRC = LRC.render(rawJSON: subtitleRow.subtitle)
        var translationLRC: String?
        if case .ready(.bilingual)? = renderedState {
            translationLRC = LRC.render(rawJSON: translationRow?.translation)
        }

        let subject = ExportText.deriveSubject(
            title: episode.title, channelTitle: episode.channelTitle
        )
        let text = ExportText.build(
            title: episode.title,
            channelTitle: episode.channelTitle,
            mainLyric: mainLRC,
            translationLyric: translationLRC
        )
        let fileName = ExportText.sanitizedFileName(fromSubject: subject)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName).txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            // The same user-triggered error surface as generateTranscript
            // (K27): a failed export write must not fail silently.
            if let window = view.window {
                ToastPresenter.shared.show("Failed to export transcript", in: window, duration: 3)
            }
            return
        }

        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        topMostPresented().present(activity, animated: true)
    }

    // MARK: - Helpers

    /// Base system fonts; Dynamic Type scaling comes from the label's
    /// `adjustsFontForContentSizeCategory` (single scaling source).
    private static func systemFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    // MARK: - DEBUG rendering demo

    #if DEBUG
    /// Visual-check hook: `simctl launch <udid> <bundle> -t5-demo-lyrics`
    /// injects a fixed bilingual document and drives a synthetic position
    /// so the lyrics renderer can be screenshot without seeded data. No
    /// effect on production paths.
    private func configureDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-t5-demo-lyrics") else { return }
        activateDemoDocument()
    }

    /// DEBUG-only demo injection shared with the hosted visual smoke test
    /// (AnycastAppTests/Subtitles/SubtitlesDemoSmokeTests.swift).
    func activateDemoDocument() {
        demoMode = true
        loadedURL = "demo://t5"
        subtitleRow = SubtitleRow(
            enclosureUrl: loadedURL,
            status: "succeeded",
            subtitle: Self.demoSegmentsJSON,
            language: "en",
            summary: nil
        )
        rowPhase = .loaded
        translationRow = TranslationRow(
            enclosureUrl: loadedURL,
            status: "succeeded",
            translation: Self.demoTranslationJSON,
            language: "zh"
        )
        translationRowPhase = .loaded

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.demoPositionMilliseconds += 3_000
                self.lyricsView.setProgress(positionMilliseconds: self.demoPositionMilliseconds)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        demoTimer = timer
        refreshState()
    }

    /// Whether the ready-state lyrics area is on screen (smoke-test probe).
    var demoIsRenderingLyrics: Bool {
        renderedState == .ready(translation: .bilingual)
    }

    private static let demoSegmentsJSON: String = """
    [
      {"start":0.0,"end":3.0,"text":"Welcome to the demo transcript."},
      {"start":3.0,"end":7.5,"text":"This line is longer so the active style can be observed."},
      {"start":7.5,"end":12.0,"text":"Drag the lyrics to see the time bar."},
      {"start":12.0,"end":18.0,"text":"Tapping a line toggles playback."},
      {"start":18.0,"end":24.0,"text":"The transcript follows the active line."}
    ]
    """

    private static let demoTranslationJSON: String = """
    [
      {"start":0.0,"end":3.0,"text":"欢迎查看演示字幕。"},
      {"start":3.0,"end":7.5,"text":"这一行较长，便于观察活动行样式。"},
      {"start":7.5,"end":12.0,"text":"拖动歌词可看到时间横条。"},
      {"start":12.0,"end":18.0,"text":"点击任意行可切换播放。"},
      {"start":18.0,"end":24.0,"text":"字幕跟随当前播放行。"}
    ]
    """
    #endif
}
