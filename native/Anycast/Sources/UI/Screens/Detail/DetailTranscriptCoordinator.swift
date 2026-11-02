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
        let subscribed = await context.purchases.isSubscribed()
        guard let result = try? await context.api.getUser(), case .user(let user) = result else {
            return nil
        }
        let allowance = TranscriptAllowance(remaining: user.remaining, isSubscribed: subscribed)
        cache.store(allowance)
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
            if signal == nil {
                noteAccepted(context: context, url: enclosureURL, wasSignedIn: wasSignedIn, cache: cache)
            } else {
                await presentFailure(
                    signal: signal,
                    context: context,
                    from: presenter,
                    episode: episode,
                    cache: cache
                )
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
    /// returns the stored row. Not called when this episode is already current.
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
        self.signedIn = AuthAccountSnapshot.current(context: context).signedIn
        self.allowance = signedIn ? cache.current() : nil
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
        if let cached = cache.current() {
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
            self.allowance = self.signedIn ? self.cache.current() : nil
            self.onChange?()
        }
    }

    private func presentPaywall(from presenter: UIViewController) {
        PaywallViewController.present(
            from: presenter.topMostPresented(),
            context: context,
            variant: .quota(paywallEpisode)
        )
    }

    /// Makes this episode the current one (Play's queue preparation, without
    /// starting audio unless the policy says so), closes the detail sheet,
    /// and opens the player on the transcript page.
    private func openPlayer(askAI: Bool, from presenter: UIViewController) {
        Task { @MainActor in
            await ensureCurrentEpisode()
            let anchor = presenter.presentingViewController ?? presenter
            let present = {
                PlayerPageContainer.present(
                    from: anchor.topMostPresented(),
                    context: self.context,
                    initialPage: PlayerPageContainer.transcriptPageIndex,
                    opensChat: askAI
                )
            }
            if presenter.presentingViewController != nil {
                presenter.dismiss(animated: !Motion.reduceMotion, completion: present)
            } else {
                present()
            }
        }
    }

    private func ensureCurrentEpisode() async {
        let currentURL = context.playback.currentEpisode?.enclosureUrl
        if currentURL == enclosureURL, !(currentURL ?? "").isEmpty {
            if policy.autoplayWhenOpeningTranscript, !context.playback.isPlaying {
                await context.playback.play()
            }
            return
        }
        guard let row = await prepareEpisode() else { return }
        if policy.autoplayWhenOpeningTranscript {
            await context.playback.playByEpisode(row)
        } else {
            await context.playback.setByEpisode(row)
            await context.playback.reloadQueue()
        }
    }
}
