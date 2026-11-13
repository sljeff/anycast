import UIKit
import AnycastKit

/// Shared "the add was refused" surface for the detail row, the player
/// capsule, and the playlist card. A 403 whose refreshed account has no
/// transcripts left opens the existing quota paywall; every other refusal
/// stays a toast. The refreshed `remaining` is written into the allowance
/// cache so the detail row can show the new count without a second read.
@MainActor
enum TranscriptRequests {

    static func generate(
        enclosureURL: String,
        context: UIContext,
        from presenter: UIViewController,
        episode: PaywallModel.Episode,
        cache: TranscriptAllowanceCache = .shared,
        onSettled: (() -> Void)? = nil
    ) {
        guard !enclosureURL.isEmpty else { return }
        guard AuthAccountSnapshot.current(context: context).signedIn else {
            LoginSheetViewController.present(
                from: presenter.topMostPresented(),
                context: context,
                source: .transcribe
            ) {
                start(
                    enclosureURL: enclosureURL,
                    context: context,
                    from: presenter,
                    episode: episode,
                    cache: cache,
                    onSettled: onSettled
                )
            }
            return
        }
        start(
            enclosureURL: enclosureURL,
            context: context,
            from: presenter,
            episode: episode,
            cache: cache,
            onSettled: onSettled
        )
    }

    /// After a caller already invoked `subtitles.add` (the playlist card).
    static func presentFailure(
        signal: APIClient.ErrorSignal,
        context: UIContext,
        from presenter: UIViewController,
        episode: PaywallModel.Episode,
        cache: TranscriptAllowanceCache = .shared
    ) async {
        switch signal {
        case .errorMessage(let text):
            if await presentPaywallIfExhausted(
                context: context, from: presenter, episode: episode, cache: cache
            ) { return }
            if let window = presenter.view.window {
                ToastPresenter.shared.show(text, in: window, duration: 3)
            }
        case .errorBody(let status, let body):
            if let window = presenter.view.window {
                ToastPresenter.shared.show("Error \(status): \(body)", in: window, duration: 3)
            }
        case .loginRequired:
            break
        }
    }

    /// True when Paywall C was presented. Always stores a successful
    /// re-read, including when the paywall stays closed.
    @discardableResult
    static func presentPaywallIfExhausted(
        context: UIContext,
        from presenter: UIViewController,
        episode: PaywallModel.Episode,
        cache: TranscriptAllowanceCache = .shared
    ) async -> Bool {
        let allowance = await refresh(context: context, cache: cache)
        guard PaywallModel.shouldPresentQuotaPaywall(
            refreshedRemaining: allowance?.remaining,
            isSubscribed: allowance?.isSubscribed ?? false
        ), presenter.view.window != nil else { return false }
        PaywallViewController.present(
            from: presenter.topMostPresented(),
            context: context,
            variant: .quota(episode)
        )
        return true
    }

    @discardableResult
    static func refresh(
        context: UIContext,
        cache: TranscriptAllowanceCache = .shared
    ) async -> TranscriptAllowance? {
        let uid = AuthAccountSnapshot.current(context: context).uid
        guard let uid else { return nil }
        let subscribed = await context.purchases.isSubscribed()
        // The account may have changed while the entitlement read was in flight.
        guard AuthAccountSnapshot.current(context: context).uid == uid else { return nil }
        guard let remaining = await AccountRemaining.fetch(context: context) else {
            return nil
        }
        guard AuthAccountSnapshot.current(context: context).uid == uid else { return nil }
        let allowance = TranscriptAllowance(remaining: remaining, isSubscribed: subscribed)
        cache.store(allowance, uid: uid)
        return allowance
    }

    private static func start(
        enclosureURL: String,
        context: UIContext,
        from presenter: UIViewController,
        episode: PaywallModel.Episode,
        cache: TranscriptAllowanceCache,
        onSettled: (() -> Void)?
    ) {
        Task { @MainActor in
            let wasSignedIn = AuthAccountSnapshot.current(context: context).signedIn
            let signal = await context.subtitles.add(url: enclosureURL)
            if let signal {
                await presentFailure(
                    signal: signal,
                    context: context,
                    from: presenter,
                    episode: episode,
                    cache: cache
                )
            } else {
                noteAccepted(context: context, url: enclosureURL, wasSignedIn: wasSignedIn, cache: cache)
            }
            onSettled?()
        }
    }

    /// A request the server accepted may have spent a transcript. Drop the
    /// cached count so the next read is fresh. Login-gated adds return nil
    /// too, but they are not signed in — those stay cached.
    private static func noteAccepted(
        context: UIContext,
        url: String,
        wasSignedIn: Bool,
        cache: TranscriptAllowanceCache
    ) {
        guard wasSignedIn else { return }
        switch context.subtitles.statuses[url] {
        case "processing", "succeeded":
            cache.invalidate()
        default:
            break
        }
    }
}

enum DetailTranscriptMenuImages {
    static func image(for action: DetailTranscriptAction) -> UIImage? {
        switch action {
        case .generate, .getPlus:
            return AppIcons.aiTranscript
        case .read:
            return AppIcons.transcriptLines
        case .askAI:
            return AppIcons.chatBubble
        }
    }
}

/// Live transcript status for one detail sheet: account allowance, the
/// subtitle map, and the taps (generate in place, paywall, open the player
/// on the transcript page).
@MainActor
final class DetailTranscriptCoordinator {

    let context: UIContext
    let enclosureURL: String
    let paywallEpisode: PaywallModel.Episode
    /// Inserts the episode into the playback queue the way Play does, and
    /// returns the stored row. Not called when this episode is already
    /// current, or while a different episode is playing.
    let prepareEpisode: () async -> PlaylistEpisodeRow?

    private let cache: TranscriptAllowanceCache
    private let policy: DetailTranscriptPolicy
    private(set) var signedIn: Bool
    private(set) var allowance: TranscriptAllowance?
    var onChange: (() -> Void)?

    convenience init(
        context: UIContext,
        episode: DetailViewController.Episode,
        prepareEpisode: @escaping () async -> PlaylistEpisodeRow?
    ) {
        self.init(
            context: context,
            enclosureURL: episode.enclosureURL,
            paywallEpisode: PaywallModel.Episode(
                title: episode.title,
                showName: episode.channelTitle,
                durationMilliseconds: episode.durationMilliseconds,
                artworkURL: episode.imageURL.flatMap(URL.init(string:))
            ),
            prepareEpisode: prepareEpisode
        )
    }

    init(
        context: UIContext,
        enclosureURL: String,
        paywallEpisode: PaywallModel.Episode,
        prepareEpisode: @escaping () async -> PlaylistEpisodeRow?,
        cache: TranscriptAllowanceCache = .shared,
        policy: DetailTranscriptPolicy = .current
    ) {
        self.context = context
        self.enclosureURL = enclosureURL
        self.paywallEpisode = paywallEpisode
        self.prepareEpisode = prepareEpisode
        self.cache = cache
        self.policy = policy
        let account = AuthAccountSnapshot.current(context: context)
        self.signedIn = account.signedIn
        self.allowance = account.uid.flatMap { signedIn ? cache.current(uid: $0) : nil }
    }

    private func cachedAllowance() -> TranscriptAllowance? {
        guard signedIn, let uid = AuthAccountSnapshot.current(context: context).uid else { return nil }
        return cache.current(uid: uid)
    }

    func content() -> DetailTranscriptContent {
        DetailTranscriptState.reduce(
            status: context.subtitles.statuses[enclosureURL],
            signedIn: signedIn,
            allowance: allowance,
            policy: policy
        )
    }

    /// Cache hit: keep the number. Miss or stale: the row stays on the
    /// unknown (no number) presentation until this returns, then only the
    /// number fades in.
    func refreshAllowanceIfNeeded() async {
        signedIn = AuthAccountSnapshot.current(context: context).signedIn
        guard signedIn else {
            allowance = nil
            onChange?()
            return
        }
        if let cached = cachedAllowance() {
            allowance = cached
            onChange?()
            return
        }
        allowance = nil
        onChange?()
        allowance = await TranscriptRequests.refresh(context: context, cache: cache)
        onChange?()
    }

    func handle(_ action: DetailTranscriptAction, from presenter: UIViewController) {
        switch action {
        case .generate:
            generate(from: presenter)
        case .getPlus:
            presentPaywall(from: presenter)
        case .read:
            openPlayer(askAI: false, from: presenter)
        case .askAI:
            if content().kind == .ready {
                openPlayer(askAI: true, from: presenter)
            } else {
                // The policy can surface Ask AI before a transcript exists;
                // there is nothing to ask yet, so it starts generation.
                generate(from: presenter)
            }
        }
    }

    private func generate(from presenter: UIViewController) {
        signedIn = AuthAccountSnapshot.current(context: context).signedIn
        if signedIn,
           policy.openPaywallWithoutProbe,
           let allowance,
           PaywallModel.shouldPresentQuotaPaywall(
            refreshedRemaining: allowance.remaining,
            isSubscribed: allowance.isSubscribed
           ) {
            presentPaywall(from: presenter)
            return
        }
        TranscriptRequests.generate(
            enclosureURL: enclosureURL,
            context: context,
            from: presenter,
            episode: paywallEpisode,
            cache: cache
        ) { [weak self] in
            guard let self else { return }
            self.signedIn = AuthAccountSnapshot.current(context: self.context).signedIn
            self.allowance = self.cachedAllowance()
            self.onChange?()
        }
    }

    private func presentPaywall(from presenter: UIViewController) {
        PaywallViewController.present(
            from: presenter.topMostPresented(),
            context: context,
            variant: .quota(paywallEpisode)
        ) { [weak self] in
            self?.cache.invalidate()
            Task { await self?.refreshAllowanceIfNeeded() }
        }
    }

    /// Opens the transcript page. A different episode that is playing keeps
    /// playing: this one is not inserted and not removed from Inbox. Nothing
    /// playing can load this episode paused. Preparation failure does not
    /// open the player on the other episode.
    private func openPlayer(askAI: Bool, from presenter: UIViewController) {
        let context = self.context
        let prepare = prepareEpisode
        let enclosureURL = self.enclosureURL
        let policy = self.policy
        let browse = TranscriptBrowseTarget(
            enclosureURL: enclosureURL,
            title: paywallEpisode.title,
            channelTitle: paywallEpisode.showName,
            imageURL: paywallEpisode.artworkURL?.absoluteString
        )
        Task { @MainActor in
            let plan = TranscriptOpenPlan.make(
                enclosureURL: enclosureURL,
                currentURL: context.playback.currentEpisode?.enclosureUrl,
                isPlaying: context.playback.isPlaying
            )
            if plan.requiresSuccessfulPrepare {
                guard await Self.loadPrepared(
                    prepare: prepare, context: context, autoplay: policy.autoplayWhenOpeningTranscript
                ) else {
                    Self.showOpenFailure(from: presenter)
                    return
                }
            }
            let anchor = presenter.presentingViewController ?? presenter
            let adopt: () async -> Bool = {
                await Self.loadPrepared(prepare: prepare, context: context, autoplay: true)
            }
            let present = {
                PlayerPageContainer.present(
                    from: anchor.topMostPresented(),
                    context: context,
                    initialPage: PlayerPageContainer.transcriptPageIndex,
                    opensChat: askAI,
                    browse: plan == .browseWhileOtherPlays ? browse : nil,
                    onPlayBrowsed: plan == .browseWhileOtherPlays ? adopt : nil
                )
            }
            if presenter.presentingViewController != nil {
                presenter.dismiss(animated: !Motion.reduceMotion, completion: present)
            } else {
                present()
            }
        }
    }

    /// Inserts the episode the way Play does and loads it. `autoplay` starts
    /// audio; otherwise the item is loaded paused. Returns false when the
    /// caller could not produce a row.
    @discardableResult
    private static func loadPrepared(
        prepare: () async -> PlaylistEpisodeRow?,
        context: UIContext,
        autoplay: Bool
    ) async -> Bool {
        guard let row = await prepare() else { return false }
        if autoplay {
            await context.playback.playByEpisode(row)
        } else {
            await context.playback.setByEpisode(row)
            await context.playback.reloadQueue()
        }
        return true
    }

    private static func showOpenFailure(from presenter: UIViewController) {
        guard let window = presenter.view.window else { return }
        ToastPresenter.shared.show("Couldn't open this transcript", in: window, duration: 3)
    }
}
