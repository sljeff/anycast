import UIKit
import AnycastKit

/// Player page 2 (PlayerAI/Subtitles, 03 §2.10) in the Anycast 2.0
/// transcript form (type B, adopted 2026-10-21): a left-aligned header — the
/// 44 pt episode cover beside "Transcript" over the episode title — then the
/// transcript states directly on the player backdrop. Every non-ready state
/// is one capsule panel above the page selector (thumb reach); the ready
/// state is the bilingual lyrics view with the drag time bar, the AI-chat /
/// export overlay and the play-pause morph.
///
/// Row state is derived from the poll controllers plus async row fetches;
/// polling cadence, K27 error policy and the K9 5-strike rule all live in
/// AnycastKit — this controller only observes and renders
/// (TranscriptStateReducer is the pure mapping).
final class SubtitlesPageViewController: UIViewController {

    private let context: UIContext

    private enum Layout {
        static let headerArtwork: CGFloat = 44
        static let headerArtworkRadius: CGFloat = 14
        /// The status capsule sits 20 pt above the page selector
        /// (contentHost already ends `Spacing.pageH` above it).
        static let panelBottomGap: CGFloat = 20 - Spacing.pageH
    }

    // MARK: Chrome

    private let headerArtwork = UIImageView()
    private var headerArtworkURL: String?
    private let headerTitleLabel = UILabel()
    private let titleLabel = UILabel()
    private let contentHost = UIView()

    // MARK: Observed state

    private var loadedURL: String?
    private var rowPhase: TranscriptRowPhase = .fetching
    private var subtitleRow: SubtitleRow?
    private var translationRowPhase: TranslationRowPhase = .idle
    private var translationRow: TranslationRow?
    private var renderedState: TranscriptVisualState?

    // MARK: Ready-state views (kept alive across state swaps so scroll and
    // follow position survive)

    private let lyricsView = LyricsView()
    private var lyricsBottomConstraint: NSLayoutConstraint?
    private var inlineStatus: UIView?
    private var overlay: GlassContainerView?

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
        headerArtwork.contentMode = .scaleAspectFill
        headerArtwork.clipsToBounds = true
        headerArtwork.layer.cornerRadius = Layout.headerArtworkRadius
        headerArtwork.layer.cornerCurve = .continuous
        headerArtwork.backgroundColor = AnycastColor.sandAlpha3
        headerArtwork.isAccessibilityElement = false
        headerArtwork.translatesAutoresizingMaskIntoConstraints = false

        headerTitleLabel.text = "Transcript"
        headerTitleLabel.font = TypographyV2.emphasis.font()
        headerTitleLabel.textColor = Theme.playerText
        titleLabel.font = TypographyV2.meta.font()
        titleLabel.textColor = Theme.playerSecondary
        for label in [headerTitleLabel, titleLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
        }

        let titles = UIStackView(arrangedSubviews: [headerTitleLabel, titleLabel])
        titles.axis = .vertical
        let header = UIStackView(arrangedSubviews: [headerArtwork, titles])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = Spacing.gap
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentHost)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageHeader),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            headerArtwork.widthAnchor.constraint(equalToConstant: Layout.headerArtwork),
            headerArtwork.heightAnchor.constraint(equalToConstant: Layout.headerArtwork),

            contentHost.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            contentHost.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageHeader),
            contentHost.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.gap),
            contentHost.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Spacing.pageH),
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
        let imageURL = episode?.imageUrl ?? ""
        guard imageURL != headerArtworkURL else { return }
        headerArtworkURL = imageURL
        headerArtwork.kf.cancelDownloadTask()
        headerArtwork.setArtwork(URL(string: imageURL), title: episode?.channelTitle)
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

    // MARK: - Status panels (released baseline 1.2.1+38 states, 03 §2.10,
    // in the type B capsule)

    private func embedPanel(_ content: TranscriptStatusPanel.Content) {
        let panel = TranscriptStatusPanel(content)
        panel.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor, constant: -Layout.panelBottomGap),
        ])
    }

    /// Ungenerated: the AI transcript offer; Generate triggers
    /// `subtitles.add(url)`.
    private func makePromptPanel() {
        embedPanel(.init(
            icon: UIImage(systemName: "sparkles"),
            title: "AI transcript",
            subtitle: "Beta · about 2–5 min",
            action: ("Generate", { [weak self] in self?.generateTranscript() })
        ))
    }

    private func makeProcessingPanel() {
        embedPanel(.init(
            showsSpinner: true,
            title: "Generating transcript",
            subtitle: "About 2–5 min · feel free to leave"
        ))
    }

    /// Failed: Retry re-runs the add (03 §2.10 "Retry").
    private func makeFailedPanel() {
        embedPanel(.init(
            icon: UIImage(systemName: "exclamationmark.triangle"),
            title: "Couldn't generate",
            subtitle: "Try again in a moment",
            action: ("Retry", { [weak self] in self?.generateTranscript() })
        ))
    }

    /// Unavailable (no episode) — player.dart:701-710.
    private func makeUnavailablePanel() {
        embedPanel(.init(
            icon: UIImage(systemName: "doc.text"),
            title: "No episode playing",
            subtitle: "Choose one to see its transcript"
        ))
    }

    /// Row fetch in flight — player.dart:806-815.
    private func makeLoadingPanel() {
        embedPanel(.init(
            showsSpinner: true,
            title: "Loading transcript",
            subtitle: "Preparing it for playback"
        ))
    }

    /// Row fetch failed; Retry re-runs the row load —
    /// player.dart:789-805.
    private func makeLoadFailedPanel() {
        embedPanel(.init(
            icon: UIImage(systemName: "arrow.triangle.2.circlepath"),
            title: "Couldn't load transcript",
            subtitle: "It's temporarily unavailable",
            action: ("Retry", { [weak self] in
                guard let self, let url = self.loadedURL, !url.isEmpty else { return }
                self.loadTranscriptRow(url: url)
            })
        ))
    }

    /// `controller.add(url)` with the K27 user-trigger surface: the error
    /// signal from the add itself becomes a toast (background polling is
    /// silent; 401 routes to login inside the poller).
    private func generateTranscript() {
        guard loadedURL != nil else { return }
        // Signed out: sign in first, then generate once the sheet reports
        // success (the add would only bounce off a 401 otherwise).
        guard AuthAccountSnapshot.current(context: context).signedIn else {
            LoginSheetViewController.present(
                from: topMostPresented(), context: context, source: .transcribe
            ) { [weak self] in self?.startTranscriptGeneration() }
            return
        }
        startTranscriptGeneration()
    }

    private func startTranscriptGeneration() {
        guard let url = loadedURL else { return }
        Task { @MainActor in
            let signal = await self.context.subtitles.add(url: url)
            guard let signal, let window = self.view.window else { return }
            switch signal {
            case .errorMessage(let text):
                // A 403 at the quota limit opens the paywall instead of a
                // toast; any other 403 keeps the toast.
                if await self.presentQuotaPaywallIfExhausted() { return }
                ToastPresenter.shared.show(text, in: window, duration: 3)
            case .errorBody(let status, let body):
                ToastPresenter.shared.show("Error \(status): \(body)", in: window, duration: 3)
            case .loginRequired:
                break
            }
        }
    }

    /// Re-reads the account after a refused add: when it has no transcripts
    /// left and the user is not Plus, presents the quota paywall (variant C)
    /// for the current episode and returns true.
    private func presentQuotaPaywallIfExhausted() async -> Bool {
        var remaining: Int?
        if let result = try? await context.api.getUser(), case .user(let user) = result {
            remaining = user.remaining
        }
        let subscribed = remaining == 0 ? await context.purchases.isSubscribed() : false
        guard PaywallModel.shouldPresentQuotaPaywall(refreshedRemaining: remaining, isSubscribed: subscribed),
              let episode = context.playback.currentEpisode, view.window != nil else { return false }
        let summary = PaywallModel.Episode(
            title: episode.title ?? "",
            showName: episode.channelTitle ?? "",
            durationMilliseconds: episode.duration,
            artworkURL: episode.imageUrl.flatMap(URL.init(string:))
        )
        PaywallViewController.present(
            from: topMostPresented(), context: context, variant: .quota(summary)
        )
        return true
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Lines clear the floating overlay instead of running under it.
        lyricsView.bottomClearance = overlay.map { $0.bounds.height + Spacing.gap } ?? 0
    }

    /// Bottom-right floating overlay (player.dart:1131-1203): AI chat entry
    /// + the export menu, as one grouped glass surface (07 §2.5).
    private func installOverlay() {
        let glass = GlassContainerView(mode: .container, cornerRadius: 20)
        glass.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(glass)
        overlay = glass

        let chatIcon = UIImageView(image: AppIcons.aiChat)
        chatIcon.tintColor = Theme.primary
        chatIcon.contentMode = .scaleAspectFit
        chatIcon.isUserInteractionEnabled = true
        chatIcon.isAccessibilityElement = true
        chatIcon.accessibilityLabel = "AI chat"
        chatIcon.accessibilityTraits = .button
        chatIcon.translatesAutoresizingMaskIntoConstraints = false
        chatIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openChat)))

        let moreButton = UIButton(type: .system)
        moreButton.setImage(AppIcons.more, for: .normal)
        moreButton.tintColor = Theme.onSurfaceVariant
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
            indicator.color = Theme.primary
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
        label.font = TypographyV2.meta.font()
        label.textColor = Theme.playerSecondary
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

/// The type B status capsule: a leading glyph (or spinner), an Emphasis
/// title over a Meta line, and an optional pill action in the player text
/// color. The player is always dark, so the panel resolves its sand fill
/// in dark.
private final class TranscriptStatusPanel: UIView {

    struct Content {
        var icon: UIImage?
        var showsSpinner = false
        var title: String
        var subtitle: String
        var action: (title: String, handler: () -> Void)?
    }

    private static let height: CGFloat = 68
    private static let actionHeight: CGFloat = 44

    init(_ content: Content) {
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        backgroundColor = AnycastColor.sandAlpha3
        layer.cornerRadius = Self.height / 2
        layer.cornerCurve = .continuous

        let leading: UIView
        if content.showsSpinner {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.color = Theme.playerText
            spinner.startAnimating()
            leading = spinner
        } else {
            let glyph = UIImageView(image: content.icon)
            glyph.tintColor = Theme.playerText
            glyph.contentMode = .center
            glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            leading = glyph
        }
        leading.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = content.title
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.playerText
        let subtitleLabel = UILabel()
        subtitleLabel.text = content.subtitle
        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.playerSecondary
        for label in [titleLabel, subtitleLabel] {
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
        }
        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical

        let row = UIStackView(arrangedSubviews: [leading, text])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        if let action = content.action {
            var configuration = UIButton.Configuration.filled()
            configuration.title = action.title
            configuration.baseBackgroundColor = Theme.playerText
            configuration.baseForegroundColor = Theme.playerBackground
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = TypographyV2.emphasis.font()
                return outgoing
            }
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { _ in action.handler() }, for: .touchUpInside)
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.heightAnchor.constraint(equalToConstant: Self.actionHeight).isActive = true
            row.addArrangedSubview(button)
        }

        // 68 pt (radius 34); larger text sizes may grow it.
        let preferredHeight = heightAnchor.constraint(equalToConstant: Self.height)
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.height),
            preferredHeight,
            leading.widthAnchor.constraint(equalToConstant: 24),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.gap),
            row.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Spacing.gap),
            row.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Spacing.gap),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
