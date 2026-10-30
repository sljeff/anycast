import UIKit
import AnycastKit

/// Player page 2 (PlayerAI/Subtitles, 03 §2.10) in the Anycast 2.0
/// transcript form (option A): a left-aligned header — the 44 pt episode
/// cover beside "Transcript" over the episode title — then the transcript
/// lines, ONE status capsule slot (following / back to now / jump undo /
/// generation and translation states), and the shared scrubber + transport
/// with the ••• menu and Ask AI flanking it, above the page selector.
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
        /// Gap between the lyrics and the status capsule slot.
        static let lyricsToCapsule: CGFloat = Spacing.md
    }

    /// In-memory for now (no persisted setting): when false, a loaded
    /// translation is not rendered, copied or counted — the page shows the
    /// transcript as mono.
    static var showsTranslation = true

    // MARK: Chrome

    private let headerArtwork = UIImageView()
    private var headerArtworkURL: String?
    private let headerTitleLabel = UILabel()
    private let titleLabel = UILabel()
    private let contentHost = UIView()
    private let capsule = TranscriptStatusCapsuleView()
    private lazy var transport = PlayerTransportView(context: context, transportGap: Spacing.gap)
    private let moreButton = AnycastIconButton(
        style: .tonal, icon: AppIcons.more, accessibilityLabel: "More transcript actions", glyphSize: 20
    )
    private let askAIButton = AnycastIconButton(
        style: .tonal, icon: AppIcons.aiChat, accessibilityLabel: "Ask AI", glyphSize: 20
    )

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
    /// The last tap-jump, until the undo capsule times out or is used.
    private let jumpUndo = PlaybackJumpUndo()

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

        lyricsView.onTapLine = { [weak self] index in self?.jumpToLine(index) }
        jumpUndo.onChange = { [weak self] in self?.updateCapsule() }
        lyricsView.onFollowingChanged = { [weak self] isFollowing in
            // Dragging away means the user moved on from the jump.
            if !isFollowing { self?.jumpUndo.clear() }
            self?.updateCapsule()
        }
        lyricsView.contextMenuProvider = { [weak self] index in self?.makeLineMenu(for: index) }

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
            jumpUndo.clear()
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

        lyricsView.isHidden = true
        lyricsView.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(lyricsView)

        capsule.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(capsule)

        transport.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transport)
        buildTransportAccessories()

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageHeader),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            headerArtwork.widthAnchor.constraint(equalToConstant: Layout.headerArtwork),
            headerArtwork.heightAnchor.constraint(equalToConstant: Layout.headerArtwork),

            contentHost.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            contentHost.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageHeader),
            contentHost.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.gap),

            lyricsView.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            lyricsView.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            lyricsView.topAnchor.constraint(equalTo: contentHost.topAnchor),
            lyricsView.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),

            capsule.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            capsule.topAnchor.constraint(equalTo: contentHost.bottomAnchor, constant: Layout.lyricsToCapsule),

            transport.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            transport.topAnchor.constraint(equalTo: capsule.bottomAnchor),
            transport.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -PlayerTransportView.Layout.toSelector),
        ])
    }

    /// ••• (menu) left and Ask AI right of the transport: 44 pt round
    /// buttons with a subtle player-text fill. Player colors only — the
    /// player is always dark, so nothing adapts to the appearance.
    private func buildTransportAccessories() {
        for button in [moreButton, askAIButton] {
            button.configuration?.baseBackgroundColor = Theme.playerText.withAlphaComponent(0.08)
            button.configuration?.baseForegroundColor = Theme.playerText
        }
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.moreMenuElements() ?? [])
            },
        ])
        askAIButton.addAction(UIAction { [weak self] _ in self?.openChat() }, for: .touchUpInside)
        transport.setAccessories(leading: moreButton, trailing: askAIButton)
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
        // No episode (queue drained while the sheet is open): the 44 pt
        // artwork tile and the empty title row read like a failed load —
        // drop them; the capsule names the state.
        headerArtwork.isHidden = episode == nil
        titleLabel.isHidden = episode == nil
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
        let wasReady = isReady
        renderedState = state

        // The `Subtitles` widget states (player.dart 1.2.1+38): every
        // wrapper state around the row fetches (unavailable / loading /
        // load-failed) shows in the status capsule; a blank page was the QA
        // crawl's "near-black transcript page".
        if case .ready = state {
            lyricsView.isHidden = false
            // A fresh document starts out following again.
            if !wasReady {
                lyricsView.resetFollowing()
                jumpUndo.clear()
            }
            // Every translation phase renders the lyrics — the in-flight or
            // failed translation rows show the main lyric with the inline
            // status in the capsule (player.dart:834-864).
            reloadLyrics()
        } else {
            lyricsView.isHidden = true
            jumpUndo.clear()
        }
        askAIButton.isEnabled = isReady
        askAIButton.alpha = isReady ? 1 : 0.38
        updateCapsule()
    }

    private var isReady: Bool {
        if case .ready? = renderedState { return true }
        return false
    }

    // MARK: - Status capsule (one state at a time)

    /// Picks the capsule content: generation states while the transcript is
    /// not ready; once ready, the jump undo, then back-to-now, then the
    /// inline translation status, then the quiet following chip.
    private func updateCapsule() {
        capsule.show(capsuleContent())
    }

    private func capsuleContent() -> TranscriptStatusCapsuleView.Content? {
        guard let state = renderedState else { return nil }
        switch state {
        case .unavailable:
            return .init(
                id: "unavailable", leading: .none,
                message: PlayerProgressVisualState.nothingPlayingMessage
            )
        case .loading:
            return .init(id: "loading", leading: .spinner, message: "Loading transcript")
        case .loadFailed:
            return .init(
                id: "loadFailed", leading: .icon(UIImage(systemName: "arrow.triangle.2.circlepath")),
                message: "Couldn't load transcript",
                action: ("Retry", { [weak self] in
                    guard let self, let url = self.loadedURL, !url.isEmpty else { return }
                    self.loadTranscriptRow(url: url)
                })
            )
        case .prompt:
            return .init(
                id: "prompt", leading: .icon(UIImage(systemName: "sparkles")),
                message: "AI transcript",
                action: ("Generate", { [weak self] in self?.generateTranscript() })
            )
        case .processing:
            // The server reports no percentage, so just a spinner.
            return .init(id: "processing", leading: .spinner, message: "Generating transcript")
        case .failed:
            return .init(
                id: "failed", leading: .icon(UIImage(systemName: "exclamationmark.triangle")),
                message: "Couldn't transcribe",
                action: ("Retry", { [weak self] in self?.generateTranscript() })
            )
        case .ready(let translation):
            if let undo = jumpUndo.capsuleContent(undo: { [weak self] in self?.undoJump() }) {
                return undo
            }
            if !lyricsView.isFollowing {
                return .init(
                    id: "backToNow", style: .filledButton,
                    leading: .icon(UIImage(systemName: "chevron.down")),
                    message: "Back to now",
                    action: ("Back to now", { [weak self] in self?.lyricsView.returnToNow() })
                )
            }
            switch translation {
            case .translating:
                // Baseline Row[RefreshProgressIndicator, "Translating
                // subtitles..."] (player.dart 1.2.1+38).
                return .init(id: "translating", leading: .spinner, message: "Translating subtitles…")
            case .loadingTranslation:
                return .init(id: "loadingTranslation", leading: .spinner, message: "Loading translation…")
            case .translationUnavailable:
                return .init(id: "translationUnavailable", message: "Translation unavailable")
            case .mono, .bilingual:
                return .init(id: "following", leading: .dot, message: "Following")
            }
        }
    }

    // MARK: - Tap to jump

    /// A line tap seeks to the line's start and keeps the play state. The
    /// list does not scroll: the touched line stays put and only the
    /// highlight moves. The capsule offers Undo for a few seconds.
    private func jumpToLine(_ index: Int) {
        guard lyricsView.lines.indices.contains(index) else { return }
        let line = lyricsView.lines[index]
        // Blank spacer lines (the LRC `[end]` rows) are not jump targets.
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let previous = Int(context.playback.positionData.positionMilliseconds)
        lyricsView.jump(toLine: index)
        seek(toMilliseconds: line.startMilliseconds)
        jumpUndo.record(from: previous, to: line.startMilliseconds)
    }

    /// A moment an AI reply cites: the same jump as a line tap, landing on
    /// the line playing at that time.
    private func jump(toMilliseconds milliseconds: Int) {
        let previous = Int(context.playback.positionData.positionMilliseconds)
        if isReady, !lyricsView.lines.isEmpty {
            lyricsView.jump(toLine: LyricDocument.activeLineIndex(
                lines: lyricsView.lines, positionMilliseconds: milliseconds
            ))
        }
        seek(toMilliseconds: milliseconds)
        jumpUndo.record(from: previous, to: milliseconds)
    }

    private func undoJump() {
        guard let jump = jumpUndo.take() else { return }
        let index = LyricDocument.activeLineIndex(
            lines: lyricsView.lines, positionMilliseconds: jump.previousMilliseconds
        )
        lyricsView.jump(toLine: index)
        seek(toMilliseconds: jump.previousMilliseconds)
    }

    private func seek(toMilliseconds milliseconds: Int) {
        #if DEBUG
        if demoMode { demoPositionMilliseconds = milliseconds }
        #endif
        Task { await context.playback.seek(Int64(milliseconds)) }
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

    // MARK: - Lyrics

    private func reloadLyrics() {
        lyricsView.updateDocument(
            lines: currentLyricLines(),
            positionMilliseconds: Int(context.playback.positionData.positionMilliseconds)
        )
    }

    private func currentLyricLines() -> [LyricLine] {
        guard let subtitleRow else { return [] }
        let mainLRC = LRC.render(rawJSON: subtitleRow.subtitle)
        var translationLRC: String? {
            guard Self.showsTranslation, case .ready(.bilingual)? = renderedState else { return nil }
            return LRC.render(rawJSON: translationRow?.translation)
        }
        return LyricDocument.parse(mainLRC: mainLRC, translationLRC: translationLRC)
    }

    // MARK: - Line context menu (long-press)

    private func makeLineMenu(for index: Int) -> UIMenu? {
        guard lyricsView.lines.indices.contains(index) else { return nil }
        let text = lyricsView.lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let episodeTitle = context.playback.currentEpisode?.title ?? ""

        return UIMenu(children: [
            UIAction(title: "Ask AI about this", image: UIImage(systemName: "sparkles")) { [weak self] _ in
                self?.openChat(draftQuestion: "Can you explain this part of the episode? \"\(text)\"")
            },
            UIAction(title: "Play from here", image: AppIcons.play) { [weak self] _ in
                self?.jumpToLine(index)
            },
            UIAction(title: "Copy", image: AppIcons.copy) { [weak self] _ in
                UIPasteboard.general.string = text
                self?.showToast("Copied")
            },
            UIAction(title: "Share quote", image: AppIcons.share) { [weak self] _ in
                let quote = episodeTitle.isEmpty ? "\"\(text)\"" : "\"\(text)\" — \(episodeTitle)"
                let activity = UIActivityViewController(activityItems: [quote], applicationActivities: nil)
                self?.topMostPresented().present(activity, animated: true)
            },
        ])
    }

    // MARK: - ••• menu

    private func moreMenuElements() -> [UIMenuElement] {
        let enabled: UIMenuElement.Attributes = isReady ? [] : .disabled
        var elements: [UIMenuElement] = []
        // The toggle only exists once a translation has actually loaded.
        if case .ready(.bilingual)? = renderedState {
            elements.append(UIAction(
                title: "Show translation",
                state: Self.showsTranslation ? .on : .off
            ) { [weak self] _ in
                Self.showsTranslation.toggle()
                self?.reloadLyrics()
            })
        }
        elements.append(UIAction(
            title: "Copy transcript", image: AppIcons.copy, attributes: enabled
        ) { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = LyricDocument.plainText(lines: self.lyricsView.lines)
            self.showToast("Copied")
        })
        elements.append(UIAction(
            title: "Export subtitles", image: AppIcons.exportFile, attributes: enabled
        ) { [weak self] _ in
            self?.exportTranscript()
        })
        return elements
    }

    private func showToast(_ text: String) {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(text, in: window, duration: 2)
    }

    // MARK: - Actions

    /// Opens the chat sheet. `draftQuestion` pre-fills the input (long-press
    /// "Ask AI about this"); the chat asks for the current line lazily so a
    /// quick-ask can quote what is playing.
    private func openChat(draftQuestion: String? = nil) {
        let chat = ChatViewController(
            context: context,
            draftQuestion: draftQuestion,
            currentLineProvider: { [weak self] in self?.lyricsView.activeLineText },
            onJump: { [weak self] milliseconds in self?.jump(toMilliseconds: milliseconds) }
        )
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

    /// The status capsule's current content id (smoke-test probe).
    var demoCapsuleID: String? { capsule.currentID }

    /// Taps a lyric line as the user would (smoke-test hook).
    func demoTapLine(_ index: Int) { lyricsView.onTapLine?(index) }

    /// Lyric lines on screen (smoke-test probe).
    var demoLines: [LyricLine] { lyricsView.lines }

    /// 60 four-second segments so the demo list scrolls well past a
    /// viewport (the first lines are fixed samples of the styles).
    private static let demoSegmentCount = 60

    private static let demoSegmentsJSON: String = demoJSON { index in
        switch index {
        case 0: "Welcome to the demo transcript."
        case 1: "This line is longer so the active style can be observed."
        case 2: "Drag the lyrics to stop following and see Back to now."
        case 3: "Tapping a line jumps there and offers Undo."
        default: "Demo line \(index + 1): the transcript follows the active line as it plays."
        }
    }

    private static let demoTranslationJSON: String = demoJSON { index in
        "演示字幕第 \(index + 1) 行：字幕跟随当前播放行。"
    }

    private static func demoJSON(_ text: (Int) -> String) -> String {
        let segments = (0..<demoSegmentCount).map { index in
            "{\"start\":\(Double(index) * 4),\"end\":\(Double(index + 1) * 4),\"text\":\"\(text(index))\"}"
        }
        return "[\(segments.joined(separator: ","))]"
    }
    #endif
}
