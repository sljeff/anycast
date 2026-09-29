import UIKit
import os
import AnycastKit

/// Tab0 Inbox page (lib/pages/feeds.dart, 03 §2.3): a card list over the
/// feedEpisode table with the full refresh trigger set — pull-to-refresh
/// (UIRefreshControl, A4 adaptation), refreshOnStart, a 2 s-after-creation
/// auto fetch, a periodic auto fetch every `autoRefreshInterval` seconds
/// (DB default 300, restarted on settings change, K36), and the Tab0
/// re-tap path. Every 60 s the inbox/history overage trim runs
/// (states/player.dart:344-349). Card actions follow `InboxActionPlanner`
/// exactly (play / add-with-fly-in / remove, 05 §6.3 P0).
final class InboxPageViewController: UIViewController, TabZeroTopRefresh {

    private let context: UIContext

    private var episodes: [FeedEpisodeRow] = []
    private var lastSignature: [String?] = []

    private let collectionView: UICollectionView
    private let refreshControl = UIRefreshControl()
    private let emptyStateView = InboxEmptyStateView()
    private let expandCoordinator = CardExpandCoordinator()
    private let htmlRenderer = HTMLContentRenderer()

    private let gate: InboxRefreshGate
    private let fetcher = RSSFetcher(client: HTTPClient(), userAgent: AppConfiguration.rssUserAgent)

    private var autoRefreshTimer: Timer?
    private var trimTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    /// EasyRefresh single-flight: no second concurrent refresh.
    private var isRefreshing = false

    // MARK: - Init (the shell constructs `init(context:)`)

    init(context: UIContext, now: @escaping @MainActor () -> Date = { Date() }) {
        self.context = context
        self.gate = InboxRefreshGate(now: now)
        // Placeholder layout; the real section provider (which reads the
        // expand state) is attached after super.init once self is complete.
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        self.collectionView = collection
        super.init(nibName: nil, bundle: nil)
        collection.collectionViewLayout = UICollectionViewCompositionalLayout { [weak self] _, _ in
            self?.makeInboxSection()
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
        buildCollectionView()

        // Card expand mutual exclusion (03 §2.11).
        expandCoordinator.onChange = { [weak self] _ in
            self?.refreshExpandedState()
        }

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

    // MARK: - Collection view (03 §2.3: 24 pt sides, 12 pt gaps, 64 pt bottom)

    private func makeInboxSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(EpisodeCardCell.cardRowHeight)
            )
        )
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: item.layoutSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = EpisodeCardCell.spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 64, trailing: 0)
        return section
    }

    private func buildCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true   // empty state stays pull-refreshable (03 §10.1)
        collectionView.dataSource = self
        collectionView.register(
            EpisodeCardCell.self,
            forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier
        )

        refreshControl.addTarget(self, action: #selector(refreshControlTriggered), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        emptyStateView.onExplore = { [weak self] in
            // Get.find<HomeTabController>().onItemTapped(2) (feeds.dart:159-162).
            self?.context.tabs.select(2)
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
        renderList()
    }

    /// Plain no-animation rebuild (08 §7.2 — the Flutter Obx rebuild).
    private func renderList() {
        let signature = episodes.map(\.enclosureUrl)
        if signature != lastSignature {
            lastSignature = signature
            if let expanded = expandCoordinator.expandedIndexPath,
               !episodes.indices.contains(expanded.item) {
                expandCoordinator.close()
            }
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
        }
        collectionView.backgroundView = episodes.isEmpty ? emptyStateView : nil
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
    private func runFlyIn(from indexPath: IndexPath?) async {
        guard let indexPath, let window = view.window else { return }
        let start: CGPoint
        if let cell = collectionView.cellForItem(at: indexPath) as? EpisodeCardCell,
           let button = Self.descendant(tagged: EpisodeCardAction.addActionTag, in: cell) {
            start = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
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

    private static func descendant(tagged tag: Int, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.tag == tag {
            return button
        }
        for subview in view.subviews {
            if let found = descendant(tagged: tag, in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Expand strip (card.dart:109-112, mutual exclusion)

    private func refreshExpandedState() {
        CardExpandAnimator.refresh(
            expandedPath: expandCoordinator.expandedIndexPath,
            in: collectionView
        )
    }

    // MARK: - Detail (cover tap, card.dart:129-138)

    private func presentDetail(episode: FeedEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl else { return }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
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
            }
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

// MARK: - Data source

extension InboxPageViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        episodes.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EpisodeCardCell.reuseIdentifier,
            for: indexPath
        )
        if let card = cell as? EpisodeCardCell, episodes.indices.contains(indexPath.item) {
            configure(card: card, episode: episodes[indexPath.item], at: indexPath)
        }
        return cell
    }

    private func configure(card: EpisodeCardCell, episode: FeedEpisodeRow, at indexPath: IndexPath) {
        let content = EpisodeCardContent(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            rightText: Self.rightText(for: episode),
            descriptionHTML: episode.description,
            imageURL: episode.imageUrl
        )
        card.configure(content, actions: actions(for: episode, at: indexPath))
        card.onCardTap = { [weak self] in
            // onChange already funnels every coordinator change through
            // refreshExpandedState — calling it here too re-ran the whole
            // animated pass twice per tap, nesting the second invalidation
            // inside the first's in-flight animation.
            self?.expandCoordinator.toggle(at: indexPath)
        }
        card.onCoverTap = { [weak self] in
            self?.presentDetail(episode: episode)
        }
        if expandCoordinator.expandedIndexPath == indexPath {
            card.setExpanded(true)
        }
    }

    /// "{duration} • {relative time}" (card.dart:50-51).
    private static func rightText(for episode: FeedEpisodeRow) -> String {
        let duration = TimeFormats.formatDuration(episode.duration ?? 0)
        let date = TimeFormats.formatDatetime(
            episode.pubDate ?? 0,
            nowEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
        return "\(duration) • \(date)"
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
