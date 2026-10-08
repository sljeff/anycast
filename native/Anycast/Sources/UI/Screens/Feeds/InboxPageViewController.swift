import UIKit
import os
import AnycastKit

/// Tab0 Inbox page (lib/pages/feeds.dart, 03 §2.3; v2 per 09 §3.2/§3.8 and
/// the batch-1 Inbox redesign): the v2 header, category strip, and hint
/// card scroll WITH the card list (Figma 1787:7899 scroll column) over the
/// feedEpisode table, with the full refresh trigger set — pull-to-refresh
/// (UIRefreshControl, A4 adaptation), refreshOnStart, a 2 s-after-creation
/// auto fetch, a periodic auto fetch every `autoRefreshInterval` seconds
/// (DB default 300, restarted on settings change, K36), and the Tab0
/// re-tap path. Every 60 s the inbox/history overage trim runs
/// (states/player.dart:344-349). Cards are the v2 text-forward
/// InboxEpisodeCardCell; actions follow `InboxActionPlanner` exactly
/// (play / add-with-fly-in / remove) through the native-first surfaces:
/// whole-card tap opens Detail, long-press opens the context menu, the
/// card's `more` button pulls the same menu down, and a trailing swipe
/// removes (09 §7a-C1; 05 §6.3 P0).
final class InboxPageViewController: UIViewController, TabZeroTopRefresh {

    /// Scroll-column sections (Figma column order); the whole set collapses
    /// when the inbox is empty — the ImportBlock empty state carries its
    /// own header (03 §2.3 v2 裁定).
    private enum Section {
        static let header = 0
        static let strip = 1
        static let hint = 2
        static let cards = 3
        static let tail = 4
        static let count = 5
    }

    private let context: UIContext

    /// The FULL inbox list — every write path (trim, remove, reload)
    /// operates here; the data source renders the category-filtered view.
    private var episodes: [FeedEpisodeRow] = []
    private var lastSignature: [String?] = []
    /// rssFeedUrl → lowercase category set (from `subscription.categories`).
    private var categoriesByFeed: [String: Set<String>] = [:]
    private var selectedCategory: String?

    private let header = HeaderView()
    private let categoryStrip = CategoryStripView()
    private lazy var categoryHintCard: UIView = buildCategoryHintCard()
    private let collectionView: UICollectionView
    private let refreshControl = UIRefreshControl()
    private let emptyStateView = InboxEmptyStateView()
    private let htmlRenderer = HTMLContentRenderer()

    private let gate: InboxRefreshGate
    private let fetcher = RSSFetcher(client: HTTPClient(), userAgent: AppConfiguration.rssUserAgent)

    private var autoRefreshTimer: Timer?
    private var trimTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    /// EasyRefresh single-flight: no second concurrent refresh.
    private var isRefreshing = false

    /// The category-filtered projection the list renders.
    private var displayedEpisodes: [FeedEpisodeRow] {
        InboxCategoryFilter.displayed(
            episodes: episodes, selected: selectedCategory, categoriesByFeed: categoriesByFeed
        )
    }

    // MARK: - Init (the shell constructs `init(context:)`)

    init(context: UIContext, now: @escaping @MainActor () -> Date = { Date() }) {
        self.context = context
        self.gate = InboxRefreshGate(now: now)
        // Placeholder layout; the real section provider is attached after
        // super.init once self is complete.
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        self.collectionView = collection
        super.init(nibName: nil, bundle: nil)
        // Scroll-flow chrome (09 §10 批次1): header/strip/hint are list
        // cells now, the card section is a list section so it can carry
        // native swipe actions, and the history pill closes the column.
        collection.collectionViewLayout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.makeSection(index: index, environment: environment)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        autoRefreshTimer?.invalidate()
        trimTimer?.invalidate()
        // Notification observers hold self weakly; the page is resident for
        // the whole session (the shell prewarms it).
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        configureChrome()
        buildCollectionView()

        // load(episodes) on init (feed_episode.dart:30).
        Task { [weak self] in await self?.reload() }

        // The shell dispatches Tab0 re-taps through the context (03 §1.1).
        context.tabs.tabZeroTopRefresh = self

        startAutoRefreshTimer()
        startTrimTimer()
        observeSettingsLimits()

        // refreshOnStart: true — one automatic refresh on first build
        // (feeds.dart:39); the 2 s delayed auto fetch follows
        // (feed_episode.dart:34-37).
        fireIfPermitted(.firstAppear)
        let delayed = Timer(timeInterval: InboxRefreshSchedule.delayedAutoSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireIfPermitted(.delayedAuto) }
        }
        RunLoop.main.add(delayed, forMode: .common)
    }

    // MARK: - v2 chrome (09 §3.2/§3.8; scroll-flow hosting since 批次1)

    /// The header/strip/hint views are configured here and HOSTED by the
    /// first three list cells (Figma scrolls them with the column) — the
    /// cells re-parent the shared views on dequeue, so exactly one
    /// materialized host exists at a time.
    private func configureChrome() {
        header.configure(HeaderView.Configuration(title: "Inbox", statusText: nil))
        header.onSettings = { [weak self] in
            guard let self else { return }
            AppSheets.presentExpand(SettingsViewController(context: self.context), from: self.topMostPresented())
        }

        categoryStrip.onSelect = { [weak self] value in
            guard let self else { return }
            self.selectedCategory = value
            self.renderList()
        }
        categoryStrip.accessibilityIdentifier = "inbox-category-strip"
    }

    /// The "see all podcast" hint card under the strip (Figma 599:30354:
    /// sandAlpha2 fill, radius 16).
    private func buildCategoryHintCard() -> UIView {
        let card = UIView()
        card.backgroundColor = AnycastColor.sandAlpha2
        card.layer.cornerRadius = Radius.md
        card.layer.cornerCurve = .continuous

        let titleLabel = UILabel()
        titleLabel.text = "see all podcast"
        titleLabel.font = TypographyV2.titleSmall.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface

        let messageLabel = UILabel()
        messageLabel.text =
            "show messages from every category listed together for a quick glance at your inbox."
        messageLabel.font = TypographyV2.bodySmall.font()
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = Theme.onSurfaceVariant
        messageLabel.numberOfLines = 0

        let column = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        column.axis = .vertical
        column.spacing = Spacing.xxs
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Spacing.pageH),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Spacing.pageH),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: Spacing.chip),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Spacing.chip),
        ])
        return card
    }

    /// "updated {relative} - {n} unlistened" (Figma header status line).
    static func headerStatusText(lastRefresh: Date?, episodeCount: Int, now: Date = Date()) -> String {
        let relative: String
        if let lastRefresh {
            let milliseconds = Int64(lastRefresh.timeIntervalSince1970 * 1000)
            relative = RelativeTimeFormatter.format(milliseconds, now: now)
        } else {
            relative = "—"
        }
        return "updated \(relative) - \(episodeCount) unlistened"
    }

    private func refreshChromeStatus() {
        header.configure(HeaderView.Configuration(
            title: "Inbox",
            statusText: Self.headerStatusText(
                lastRefresh: gate.lastRefresh, episodeCount: episodes.count
            )
        ))
    }

    // MARK: - Collection view (03 §2.3 v2: 16 pt sides, 12 pt column gaps;
    // the 64 pt bottom clearance retired — the shell's
    // additionalSafeAreaInsets already anchors resting content above the
    // chrome, 09 §10 决策⑥)

    /// Figma scroll column (1787:7899): padding 0/16, vertical gap 12 —
    /// the header/strip/hint sections carry the gap as their bottom
    /// insets, the cards bake half the gap into the cell.
    private func makeSection(
        index: Int, environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        switch index {
        case Section.header:
            return chromeSection(bottomInset: Spacing.gap)
        case Section.strip:
            return chromeSection(bottomInset: Spacing.gap)
        case Section.hint:
            // 6 here + the card cell's 6pt top inset = the 12pt column gap.
            return chromeSection(bottomInset: InboxEpisodeCardCell.verticalGap)
        case Section.cards:
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            config.backgroundColor = .clear
            // The config-level provider (not the UICollectionViewDelegate
            // method) — measured on iOS 27 the delegate selector never
            // fires for a list section nested in a compositional section
            // provider, the swipe surface never engages.
            config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.trailingSwipeActions(at: indexPath)
            }
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        case Section.tail:
            return chromeSection(bottomInset: Spacing.gap)
        default:
            return nil
        }
    }

    /// One self-sizing chrome row (header / strip / hint / history pill).
    private func chromeSection(bottomInset: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1), heightDimension: .estimated(120)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [
            NSCollectionLayoutItem(layoutSize: size)
        ])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: 0, bottom: bottomInset, trailing: 0
        )
        return section
    }

    private func buildCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true   // empty state stays pull-refreshable (03 §10.1)
        collectionView.dataSource = self
        collectionView.delegate = self   // context menu + swipe actions (09 §7a-C1)
        collectionView.register(
            InboxEpisodeCardCell.self,
            forCellWithReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier
        )
        collectionView.register(
            ChromeHostingCell.self, forCellWithReuseIdentifier: ChromeHostingCell.reuseIdentifier
        )
        collectionView.register(
            HistoryTailCell.self, forCellWithReuseIdentifier: HistoryTailCell.reuseIdentifier
        )

        refreshControl.addTarget(self, action: #selector(refreshControlTriggered), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Full-bleed top: the chrome scrolls under the status bar and
            // the safe-area-adjusted inset keeps the resting header below
            // it (Figma scroll column starts below the status bar).
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        emptyStateView.onExplore = { [weak self] in
            // v2 09 §3.5: Discover retired — discovery lives behind the
            // search circle; the empty state's Explore opens it.
            guard let self else { return }
            AppSheets.presentForm(SearchEntryViewController(context: self.context), from: self.topMostPresented())
        }
        emptyStateView.onImportOPML = { [weak self] in
            // Get.dialog(ImportExportBlock) — the T9 stub is the correct
            // presentation target for now.
            guard let self else { return }
            ImportExportDialogViewController.present(from: self, context: self.context)
        }
        emptyStateView.onHelp = { [weak self] in
            // ImportInstructions sheet (feeds.dart:178-193).
            guard let self else { return }
            ImportInstructionsViewController.present(from: self)
        }
    }

    // MARK: - Data

    private func reload() async {
        guard let rows = try? await context.database.feedRepository().listAll() else {
            // A failed read keeps the current list — rendering the empty
            // state here would claim the inbox has no episodes at all.
            return
        }
        episodes = rows
        await reloadCategories()
        renderList()
    }

    /// Loads the subscription category map and refreshes the strip
    /// (09 §3.2: the strip derives from `subscription.categories`).
    private func reloadCategories() async {
        let subscriptions = (try? await context.database.subscriptionRepository().listAll()) ?? []
        categoriesByFeed = InboxCategoryFilter.categoriesByFeed(from: subscriptions)
        categoryStrip.configure(
            categories: subscriptions.compactMap { $0.categories },
            selected: selectedCategory
        )
        // A selection that vanished (unsubscribed its last source) resets
        // to the all chip, like the strip's own configure does.
        if selectedCategory != nil, categoryStrip.currentSelection == nil {
            selectedCategory = nil
        }
        refreshChromeStatus()
    }

    /// Plain no-animation rebuild (08 §7.2 — the Flutter Obx rebuild).
    private func renderList() {
        let displayed = displayedEpisodes
        let signature = displayed.map(\.enclosureUrl)
        if signature != lastSignature {
            lastSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
        }
        collectionView.backgroundView = displayed.isEmpty ? emptyStateView : nil
        refreshChromeStatus()
    }

    // MARK: - Refresh (feeds.dart:229-249 fetchNewEpisodes)

    private func fireIfPermitted(_ trigger: InboxRefreshTrigger) {
        guard gate.permits(trigger) else { return }
        callRefresh()
    }

    /// callRefresh: begin the spinner programmatically (EasyRefresh's
    /// callRefresh shows the header; here the system control's animation),
    /// then run the SAME fetch path as the pull — the previous version only
    /// began refreshing and never ended it, leaving the header spinning for
    /// the whole session on the refreshOnStart/auto triggers (R4).
    private func callRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshControl.beginRefreshing()
        let controlHeight = refreshControl.bounds.height > 0 ? refreshControl.bounds.height : 80
        let revealY = -controlHeight
        if collectionView.contentOffset.y > revealY {
            collectionView.setContentOffset(CGPoint(x: 0, y: revealY), animated: true)
        }
        performRefresh()
    }

    @objc private func refreshControlTriggered() {
        guard !isRefreshing else { return }
        isRefreshing = true
        performRefresh()
    }

    /// The single fetch → settle path every trigger funnels through.
    private func performRefresh() {
        Task { [weak self] in
            await self?.fetchNewEpisodes()
            guard let self else { return }
            self.isRefreshing = false
            self.refreshControl.endRefreshing()
        }
    }

    private func fetchNewEpisodes() async {
        // fetchNewEpisodes stamps lastRefresh at its start (feeds.dart:237).
        gate.markRefreshStarted()
        let subscriptions = (try? await context.database.subscriptionRepository().listAll()) ?? []
        guard !subscriptions.isEmpty else { return }   // feeds.dart:231-234
        let urls = subscriptions.compactMap(\.rssFeedUrl)
        // onSave fires per 8-URL batch with that batch's parsed results
        // (rss_fetcher.dart fetchPodcastsByUrls). onBatch is a @Sendable
        // nonisolated callback, so each save is an unstructured Task —
        // collect them and drain before reloading: reload reads the
        // database, and a read interleaving a batch's writes shows the
        // list without the newest episodes while nothing re-renders
        // afterwards (the Dart flow reloads per batch and self-corrects).
        let pendingSaves = OSAllocatedUnfairLock(initialState: [Task<Void, Never>]())
        _ = await fetcher.fetchPodcasts(urls: urls, onlyFirstEpisode: false) { [weak self] _, _, batch in
            let save = Task { _ = await self?.save(batch: batch, subscriptions: subscriptions) }
            pendingSaves.withLock { $0.append(save) }
        }
        // Drain under the lock, await outside it: every onBatch call
        // happens before fetchPodcasts returns, so the snapshot is
        // complete by the time this runs.
        let drainedSaves = pendingSaves.withLock { saves -> [Task<Void, Never>] in
            let drained = saves
            saves.removeAll()
            return drained
        }
        for save in drainedSaves {
            await save.value
        }
        await reload()
    }

    /// saveNewEpisodes (feeds.dart:293-303): pure merge, then batch writes.
    private func save(batch: [PodcastImportData?], subscriptions: [SubscriptionRow]) async {
        let result = SaveNewEpisodes.compute(fetched: batch, local: subscriptions)
        let repository = context.database
        if !result.subscriptions.isEmpty {
            try? await repository.subscriptionRepository().addMany(result.subscriptions)
            // The resident Subscriptions page reloads (Obx equivalent).
            NotificationCenter.default.post(
                name: SubscriptionsPageViewController.subscriptionsDidChange,
                object: nil
            )
        }
        if !result.feedEpisodes.isEmpty {
            try? await repository.feedRepository().insertMany(result.feedEpisodes)
        }
    }

    // MARK: - Auto-refresh timer (feed_episode.dart:121-132, K36)

    private func startAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        let interval = InboxRefreshSchedule.autoRefreshInterval(from: context.settingsBox.current)
        let timer = Timer(timeInterval: max(interval, 1), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireIfPermitted(.periodicAuto) }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    /// K36 replicated: an autoRefreshInterval change restarts the timer
    /// immediately (cadence resets from zero).
    private func observeSettingsLimits() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: SettingsCoordinator.limitsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let isIntervalChange = notification.userInfo?[SettingsCoordinator.autoRefreshIntervalKey] != nil
                MainActor.assumeIsolated {
                    guard isIntervalChange else { return }
                    self?.startAutoRefreshTimer()
                }
            }
        )
    }

    // MARK: - 60 s trim (states/player.dart:444-453)

    private func startTrimTimer() {
        trimTimer?.invalidate()
        let timer = Timer(timeInterval: InboxRefreshSchedule.trimIntervalSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trimTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trimTimer = timer
    }

    private func trimTick() {
        let settings = context.settingsBox.current
        Task { [weak self] in
            guard let self else { return }
            // Recompute the plan against the CURRENT in-memory list: a plan
            // captured before this Task would go stale when removeFromInbox
            // or a reload shrank `episodes` in between (the index subrange
            // would trap). The array removal itself runs by URL so it stays
            // idempotent under interleaving.
            let plan = InboxTrimPlanner.plan(count: self.episodes.count, keeping: settings.maxFeedEpisodes)
            if plan.removesAnything {
                let urls = self.episodes[plan.removedIndices].compactMap(\.enclosureUrl)
                try? await self.context.database.feedRepository().removeByEnclosureUrls(urls)
                self.episodes.removeAll { $0.enclosureUrl.map(urls.contains) ?? false }
                self.renderList()
            }
            // History side: same semantics, SQL-side (history.dart:54-67).
            _ = try? await self.context.database.historyRepository().trim(keeping: settings.maxHistoryEpisodes)
        }
    }

    // MARK: - Card actions (feeds.dart:84-131; ordering in InboxActionPlanner)

    private func perform(_ action: InboxEpisodeAction, episode: FeedEpisodeRow, at indexPath: IndexPath?) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: playlistId)
        let steps = InboxActionPlanner.steps(
            for: action,
            currentPlaylistId: context.playback.currentPlaylistId,
            currentEnclosureURL: context.playback.currentEpisode?.enclosureUrl,
            episodeEnclosureURL: enclosureURL
        )
        Task { [weak self] in
            var insertedRow = row
            for step in steps {
                guard let self else { return }
                switch step {
                case .flyInAnimation:
                    await self.runFlyIn(from: indexPath)
                case .insertIntoPlaylist(let index):
                    let repository = self.context.database.playlistRepository()
                    try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: index)
                    if let stored = try? await repository.episode(byEnclosureURL: enclosureURL) {
                        insertedRow = stored
                    }
                case .skipInsertCurrentlyPlaying:
                    break
                case .removeFromInbox:
                    await self.removeFromInbox(urls: [enclosureURL])
                case .playInsertedEpisode:
                    await self.context.playback.playByEpisode(insertedRow)
                case .reloadPlaybackQueue:
                    await self.context.playback.reloadQueue()
                }
            }
        }
    }

    /// AnimatedPlaylistIndicator FIRST, insert in its completion. From the
    /// Detail sheet (indexPath nil) the animation is skipped — the landed
    /// Detail-action precedent (ChannelEpisodeListBinder.detailActions).
    /// v2 strip-less cards have no add button: the card CENTER is the
    /// origin (09 §7a-C1).
    private func runFlyIn(from indexPath: IndexPath?) async {
        guard let indexPath, let window = view.window else { return }
        let start: CGPoint
        if let cell = collectionView.cellForItem(at: indexPath) {
            start = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: window)
        } else {
            start = window.center
        }
        await withCheckedContinuation { continuation in
            context.flyInAnimator.fly(from: start, in: window) {
                continuation.resume()
            }
        }
    }

    private func removeFromInbox(urls: [String]) async {
        try? await context.database.feedRepository().removeByEnclosureUrls(urls)
        episodes.removeAll { $0.enclosureUrl.map(urls.contains) ?? false }
        renderList()
    }

    // MARK: - Detail (whole-card and cover tap, card.dart:129-138 + 09 §7a-C1)

    private func presentDetail(episode: FeedEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl else { return }
        // Status tag pills (v2 tag row): the inbox source plus live queue
        // membership ("queued" when the playback queue carries this episode).
        var tags = ["inbox"]
        if context.playback.queue.contains(where: { $0.enclosureUrl == enclosureURL }) {
            tags.append("queued")
        }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationSeconds: episode.duration,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? "",
            enclosureURL: enclosureURL,
            descriptionHTML: episode.description ?? ""
        )
        DetailViewController.present(
            from: self,
            episode: detailEpisode,
            actions: detailActions(for: episode),
            htmlRenderer: htmlRenderer,
            openChannel: { [weak self] reference in
                guard let self else { return }
                // Detail stays open; the channel stacks on top (03 §10.1).
                let seed = SubscriptionRow(
                    rssFeedUrl: reference.rssFeedURL,
                    title: reference.title
                )
                ChannelViewController.present(
                    from: self.topMostPresented(),
                    context: self.context,
                    rssFeedURL: reference.rssFeedURL,
                    seed: seed
                )
            },
            shortenURL: { [weak self] url in
                await self?.context.api.getShortURL(for: url) ?? url
            },
            tags: tags
        )
    }

    /// The same three actions render inside Detail (card.dart:115); the
    /// add action there fires without the fly-in overlay.
    private func detailActions(for episode: FeedEpisodeRow) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(icon: AppIcons.play, accessibilityLabel: "Play") { [weak self] in
                self?.perform(.play, episode: episode, at: nil)
            },
            EpisodeCardAction(icon: AppIcons.addToList, accessibilityLabel: "Add to playlist") { [weak self] in
                self?.perform(.addToPlaylist, episode: episode, at: nil)
            },
            EpisodeCardAction(icon: AppIcons.remove, accessibilityLabel: "Remove from inbox") { [weak self] in
                self?.perform(.remove, episode: episode, at: nil)
            },
        ]
    }

    // MARK: - Tab0 re-tap (03 §1.1; the Inbox list even when Subscriptions shows)

    func tabZeroReTapped() {
        let isAtTop = collectionView.contentOffset.y <= 0.5
        switch TabZeroRetap.action(hasClient: true, isAtTop: isAtTop) {
        case .scrollToTop:
            let top = CGPoint(x: 0, y: -collectionView.adjustedContentInset.top)
            // Plain animated setContentOffset — the old UIView.animate
            // wrapper around setContentOffset(animated: false) +
            // layoutIfNeeded() jumped the offset inside the block before
            // any property animation could run.
            collectionView.setContentOffset(top, animated: true)
        case .refresh:
            callRefresh()
        }
    }
}

// MARK: - Category filtering (09 §3.2 — pure, client-side)

/// The Inbox category projection: rssFeedUrl → lowercase category set from
/// the comma-separated `subscription.categories`, and the episode list
/// filtered to feeds carrying the selected category. Matching is
/// case-insensitive; episodes without a known feed drop out under a filter.
nonisolated enum InboxCategoryFilter {

    static func categoriesByFeed(from subscriptions: [SubscriptionRow]) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for subscription in subscriptions {
            guard let feed = subscription.rssFeedUrl else { continue }
            let categories = (subscription.categories ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if !categories.isEmpty {
                map[feed, default: []].formUnion(categories)
            }
        }
        return map
    }

    static func displayed(
        episodes: [FeedEpisodeRow],
        selected: String?,
        categoriesByFeed: [String: Set<String>]
    ) -> [FeedEpisodeRow] {
        guard let selected else { return episodes }
        let wanted = selected.lowercased()
        return episodes.filter { episode in
            guard let feed = episode.rssFeedUrl else { return false }
            return categoriesByFeed[feed]?.contains(wanted) ?? false
        }
    }
}

// MARK: - Data source

extension InboxPageViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        // The whole scroll column collapses on the empty inbox — the
        // ImportBlock empty state carries its own header (03 §2.3 v2 裁定).
        displayedEpisodes.isEmpty ? 0 : Section.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case Section.header, Section.strip, Section.hint, Section.tail:
            return 1
        case Section.cards:
            return displayedEpisodes.count
        default:
            return 0
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        switch indexPath.section {
        case Section.header:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
            (cell as? ChromeHostingCell)?.host(header)
            return cell
        case Section.strip:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
            (cell as? ChromeHostingCell)?.host(categoryStrip)
            return cell
        case Section.hint:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
            (cell as? ChromeHostingCell)?.host(categoryHintCard, horizontalInset: Spacing.pageH)
            return cell
        case Section.cards:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier,
                for: indexPath
            )
            if let card = cell as? InboxEpisodeCardCell,
               displayedEpisodes.indices.contains(indexPath.item) {
                configure(card: card, episode: displayedEpisodes[indexPath.item], at: indexPath)
            }
            return cell
        case Section.tail:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HistoryTailCell.reuseIdentifier, for: indexPath
            )
            (cell as? HistoryTailCell)?.onOpenHistory = { [weak self] in
                guard let self else { return }
                HistoryDialogViewController.present(from: self, context: self.context)
            }
            return cell
        default:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
        }
    }

    private func configure(card: InboxEpisodeCardCell, episode: FeedEpisodeRow, at indexPath: IndexPath) {
        let content = InboxCardContent(
            title: episode.title ?? "",
            showName: episode.channelTitle ?? "",
            dateText: Self.dateText(for: episode),
            badgeText: Self.badgeText(for: episode),
            descriptionHTML: episode.description,
            imageURL: episode.imageUrl
        )
        card.configure(content)
        // The same payload feeds the long-press context menu, the card's
        // `more` pull-down, and the VoiceOver custom actions (09 §7a-C1).
        card.menuActions = actions(for: episode, at: indexPath)
        card.onCardTap = { [weak self] in
            self?.presentDetail(episode: episode)
        }
    }

    /// "Nov 21, 2025"-style date (card.dart date part, v2 state row).
    private static func dateText(for episode: FeedEpisodeRow) -> String {
        TimeFormats.formatDatetime(
            episode.pubDate ?? 0,
            nowEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// The gold count pill. The Figma "episode count" property's semantics
    /// are unconfirmed (frames show a fixed 99+); duration text stands in
    /// pending design review (03 §2.3 v2 裁定).
    private static func badgeText(for episode: FeedEpisodeRow) -> String {
        TimeFormats.formatDuration(episode.duration ?? 0).uppercased()
    }

    private func actions(for episode: FeedEpisodeRow, at indexPath: IndexPath) -> [EpisodeCardAction] {
        [
            EpisodeCardAction(icon: AppIcons.play, accessibilityLabel: "Play") { [weak self] in
                self?.perform(.play, episode: episode, at: indexPath)
            },
            EpisodeCardAction(icon: AppIcons.addToList, accessibilityLabel: "Add to playlist") { [weak self] in
                self?.perform(.addToPlaylist, episode: episode, at: indexPath)
            },
            EpisodeCardAction(icon: AppIcons.remove, accessibilityLabel: "Remove from inbox") { [weak self] in
                self?.perform(.remove, episode: episode, at: indexPath)
            },
        ]
    }
}

// MARK: - Context menu + swipe actions (09 §7a-C1: the strip's actions as
// native surfaces — long-press menu, more pull-down, trailing swipe)

extension InboxPageViewController: UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == Section.cards else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.contextMenu(at: indexPath)
        }
    }

    /// The strip-equivalent menu (Play / Add to playlist / Remove from
    /// inbox) — same handlers the strip buttons ran. Internal so the
    /// in-app regression suite can assert the wiring directly.
    func contextMenu(at indexPath: IndexPath) -> UIMenu? {
        guard indexPath.section == Section.cards,
              displayedEpisodes.indices.contains(indexPath.item) else { return nil }
        let actions = actions(for: displayedEpisodes[indexPath.item], at: indexPath)
        return UIMenu(children: actions.map { action in
            UIAction(title: action.accessibilityLabel, image: action.icon) { _ in
                action.handler()
            }
        })
    }

    /// The trailing swipe surface (09 §7a-C1 批次1): a single destructive
    /// Remove running the same planner path as the menu entry. Internal so
    /// the in-app regression suite can assert the wiring directly.
    func trailingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == Section.cards,
              displayedEpisodes.indices.contains(indexPath.item) else { return nil }
        let episode = displayedEpisodes[indexPath.item]
        let remove = UIContextualAction(
            style: .destructive, title: "Remove",
            handler: { [weak self] _, _, completion in
                self?.perform(.remove, episode: episode, at: nil)
                completion(true)
            }
        )
        remove.image = AppIcons.remove
        return UISwipeActionsConfiguration(actions: [remove])
    }
}

// MARK: - Scroll-flow chrome hosting (批次1: the Figma column scrolls)

/// Hosts one of the shared chrome views (header / strip / hint card) inside
/// a self-sizing list cell. Exactly one cell per section is ever alive, so
/// re-parenting the shared view on (re)dequeue is safe.
final class ChromeHostingCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxChromeHostingCell"

    func host(_ view: UIView, horizontalInset: CGFloat = 0) {
        guard view.superview !== contentView else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: horizontalInset
            ),
            view.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -horizontalInset
            ),
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}

/// The "history ›" transparent pill closing the scroll column (Figma
/// 1787:7899 tail; the v2 history screen itself is batch 2).
final class HistoryTailCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxHistoryTailCell"

    var onOpenHistory: (() -> Void)?

    private let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "history"
        configuration.image = UIImage(systemName: "chevron.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: 4, bottom: 0, trailing: 4
        )
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 13, weight: .regular))
        button.tintColor = Theme.onSurfaceVariant
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "inbox-history-tail"
        button.addAction(
            UIAction { [weak self] _ in self?.onOpenHistory?() },
            for: .touchUpInside
        )
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.pageH),
            button.topAnchor.constraint(equalTo: contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

// MARK: - Empty state (ImportBlock, feeds.dart:147-197)


/// AnycastEmptyState + the ImportBlock action column: 64 pt circle icon,
/// big title, message, then Explore (filled green) over a row with the
/// outlined Import OPML button and the round help button. Hosted as the
/// collection background so the page stays pull-to-refreshable.
final class InboxEmptyStateView: UIView {

    var onExplore: (() -> Void)?
    var onImportOPML: (() -> Void)?
    var onHelp: (() -> Void)?

    init() {
        super.init(frame: .zero)

        let iconCircle = UIView()
        iconCircle.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        iconCircle.layer.cornerRadius = 32
        iconCircle.layer.cornerCurve = .continuous
        iconCircle.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "tray"))
        icon.tintColor = Theme.primary
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = "It’s empty here."
        titleLabel.font = Typography.secondaryTitle.font()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let messageLabel = UILabel()
        messageLabel.text = "Let's change that!"
        messageLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16))
        messageLabel.textColor = Theme.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        let explore = UIButton(type: .system)
        var exploreConfiguration = UIButton.Configuration.filled()
        exploreConfiguration.image = AppIcons.explore
        exploreConfiguration.imagePadding = 8
        exploreConfiguration.title = "Explore"
        exploreConfiguration.baseBackgroundColor = Theme.brandGreen
        exploreConfiguration.baseForegroundColor = .white
        exploreConfiguration.cornerStyle = .capsule
        exploreConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 12, leading: 20, bottom: 12, trailing: 20
        )
        explore.configuration = exploreConfiguration
        explore.titleLabel?.font = Typography.mainText.font()
        explore.addAction(UIAction { [weak self] _ in self?.onExplore?() }, for: .touchUpInside)

        let importButton = UIButton(type: .system)
        var importConfiguration = UIButton.Configuration.plain()
        importConfiguration.image = UIImage(systemName: "arrow.down.doc")
        importConfiguration.imagePadding = 8
        importConfiguration.title = "Import OPML"
        importConfiguration.baseForegroundColor = Theme.primaryLightMax
        importConfiguration.background.strokeColor = Theme.primaryLightMax
        importConfiguration.background.strokeWidth = 1
        importConfiguration.cornerStyle = .capsule
        importConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 12, leading: 20, bottom: 12, trailing: 20
        )
        importButton.configuration = importConfiguration
        importButton.titleLabel?.font = Typography.mainText.font()
        importButton.addAction(UIAction { [weak self] _ in self?.onImportOPML?() }, for: .touchUpInside)

        let help = UIButton(type: .system)
        help.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        help.tintColor = Theme.secondaryText
        help.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        help.layer.cornerRadius = 24
        help.layer.cornerCurve = .continuous
        help.isAccessibilityElement = true
        help.accessibilityLabel = "Import help"
        help.addAction(UIAction { [weak self] _ in self?.onHelp?() }, for: .touchUpInside)
        help.widthAnchor.constraint(equalToConstant: 48).isActive = true
        help.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let buttonRow = UIStackView(arrangedSubviews: [importButton, help])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 8

        let actionColumn = UIStackView(arrangedSubviews: [explore, buttonRow])
        actionColumn.axis = .vertical
        actionColumn.alignment = .center
        actionColumn.spacing = 8

        let column = UIStackView(arrangedSubviews: [iconCircle, titleLabel, messageLabel, actionColumn])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 8
        column.setCustomSpacing(20, after: iconCircle)
        column.setCustomSpacing(24, after: messageLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            iconCircle.widthAnchor.constraint(equalToConstant: 64),
            iconCircle.heightAnchor.constraint(equalToConstant: 64),
            icon.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),
            explore.heightAnchor.constraint(equalToConstant: 48),
            importButton.heightAnchor.constraint(equalToConstant: 48),

            column.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            column.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
