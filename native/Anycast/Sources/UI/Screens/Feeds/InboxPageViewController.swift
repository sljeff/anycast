import UIKit
import os
import Kingfisher
import AnycastKit

/// Inbox keeps its header pinned and its shelf/strip in the scrolling column.
/// Standalone cards share one list-owned action group; all row mutations are
/// synchronous diffable applies inside the group's FLIP transaction.
final class InboxPageViewController: UIViewController, TabZeroTopRefresh {

    nonisolated enum Section: Hashable, Sendable { case shelf, strip, cards }
    nonisolated private enum Item: Hashable, Sendable {
        case shelf, strip
        case episode(String)
        case unidentified(Int)
    }
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var renderedRows: [Item: FeedEpisodeRow] = [:]
    /// enclosureUrl → (source HTML, resolved plain text). Keyed by URL so a
    /// reload reuses the previous parse for unchanged rows instead of
    /// round-tripping every description through the HTML actor again.
    private var plainDescriptions: [String: (html: String, plain: String)] = [:]
    private(set) var actionController: ListActionController!
    /// Counts actual snapshot applications, including user leaves (review/test hook).
    private(set) var snapshotApplyCount = 0
    private var actionsInFlight: Set<String> = []

    private let context: UIContext

    /// The FULL inbox list — every write path (trim, remove, reload)
    /// operates here; the data source renders the category-filtered view.
    private var episodes: [FeedEpisodeRow] = []
    private var lastSignature: [String?] = []
    /// rssFeedUrl → lowercase category set (from `subscription.categories`).
    private var categoriesByFeed: [String: Set<String>] = [:]
    private var selectedCategory: String?

    private let header = HeaderView()
    private let shelf = ShowsShelfView()
    private let categoryStrip = CategoryStripView()
    private let playbackObservation = ObservationLoop()
    private let collectionView: UICollectionView
    private let refreshControl = UIRefreshControl()
    private let emptyStateView = InboxEmptyStateView()
    /// Empty-inbox link, shown only when History has rows. Hidden once the
    /// inbox has cards.
    private let historyFooterButton = HistoryLinkButton(accessibilityIdentifier: "inbox-listening-history")
    private let htmlRenderer = HTMLContentRenderer()

    private let gate: InboxRefreshGate
    private let fetcher = RSSFetcher(client: HTTPClient(), userAgent: AppConfiguration.rssUserAgent)

    private var autoRefreshTimer: Timer?
    private var trimTimer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []
    /// EasyRefresh single-flight: no second concurrent refresh.
    private var isRefreshing = false
    /// Subscriptions in shelf order (most recently updated first).
    private var shows: [SubscriptionRow] = []
    /// The section kinds currently rendered, top to bottom.
    private var sections: [Section] = [.cards]
    /// The first non-empty card list rises in once per instance
    /// (`CardEntranceAnimator`); later reloads never replay it.
    private var didPlayEntrance = false
    private var lastChromeHeight: CGFloat = 0

    /// The first `reload()` has landed; a refresh before it cannot tell
    /// new rows from rows the list simply had not loaded yet.
    private var didLoadOnce = false
    /// The subscriptions have been read at least once; before that an empty
    /// `shows` only means "not loaded yet", not "follows nothing".
    private var didLoadSubscriptions = false
    /// Monotonic: an older overlapping reload never replaces a newer one.
    private var reloadGeneration = 0
    /// A refresh the reader did not ask for is running (header: "Updating…").
    private var isSilentRefreshing = false
    /// Rows the last refresh added; cleared when the next refresh starts.
    private var newRowCount = 0
    private var coverPrefetcher: ImagePrefetcher?
    /// A model/snapshot transaction is applying; incoming renders wait for
    /// its commit. The gate reopens before additive travel finishes.
    private let updateGate = UpdateGate()

    /// An import landed while a refresh was already running; that refresh
    /// predates the new subscriptions, so one more pass must follow it.
    private var needsRefreshAfterImport = false

    /// The actions waiting out one shared Undo window: Removes (rows stay in
    /// `episodes` and the DB until the commit) or Adds (already durable;
    /// Undo moves the rows back). One kind at a time; the other kind commits
    /// the pending batch first.
    private let batch = PendingBatch<InboxBatchKind, InboxBatchItem>()
    /// Rows of a Remove batch, and of committed removals whose write is still
    /// running: every displayed list is the source minus these URLs.
    private var hiddenRemovalURLs: Set<String> = []

    /// The category-filtered projection the list renders, without the rows
    /// pending removal.
    private var displayedEpisodes: [FeedEpisodeRow] {
        InboxCategoryFilter.displayed(
            episodes: episodes, selected: selectedCategory, categoriesByFeed: categoriesByFeed,
            excluding: hiddenRemovalURLs
        )
    }

    // MARK: - Init (the shell constructs `init(context:)`)

    init(
        context: UIContext,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.context = context
        self.gate = InboxRefreshGate(now: now)
        // Placeholder layout; the real section provider is attached after
        // super.init once self is complete.
        let collection = ListActionCollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        self.collectionView = collection
        super.init(nibName: nil, bundle: nil)
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.makeSection(index: index, environment: environment)
        }
        collection.collectionViewLayout = layout
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        autoRefreshTimer?.invalidate()
        trimTimer?.invalidate()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Lifecycle

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncTopInset()
        actionController?.collectionViewDidLayout()
        // The empty state centers in the room beneath the chrome rows, not
        // behind them (the shelf and strip scroll with the list).
        var chromeHeight: CGFloat = 0
        if collectionView.backgroundView === emptyStateView {
            collectionView.layoutIfNeeded()
            chromeHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        }
        collectionView.alignBackgroundViewMargins(additionalTop: chromeHeight)
        if chromeHeight != lastChromeHeight {
            lastChromeHeight = chromeHeight
            view.setNeedsLayout()
        }
    }

    /// The list spans the whole page; this inset (on top of the safe area)
    /// puts the first row below the pinned header, same gap as the Playlist
    /// page. A list resting at its top follows the new inset.
    private func syncTopInset() {
        let top = header.bounds.height + Spacing.xs
        guard collectionView.contentInset.top != top else { return }
        let wasAtTop = collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 0.5
        collectionView.contentInset.top = top
        if wasAtTop {
            collectionView.contentOffset.y = -collectionView.adjustedContentInset.top
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // The Undo capsule belongs to this page: leaving it commits.
        Task { await batch.commitNow() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playEntranceIfNeeded()
        // History may have changed while another tab was in front.
        historyFooterButton.refresh(pageIsEmpty: displayedEpisodes.isEmpty, database: context.database)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        configureChrome()
        buildHeader()
        buildCollectionView()

        // load(episodes) on init (feed_episode.dart:30).
        Task { [weak self] in await self?.reload() }

        // The shell dispatches Tab0 re-taps through the context (03 §1.1).
        context.tabs.tabZeroTopRefresh = self

        batch.onCommit = { ToastPresenter.shared.dismissAction(capsuleIdentifier: "inbox-removal-capsule") }

        startAutoRefreshTimer()
        startTrimTimer()
        observeSettingsLimits()
        observeSubscriptionChanges()

        // Card badges follow the playing episode and the playlist.
        playbackObservation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisodeContent?.enclosureUrl
                _ = self.context.playback.queueEnclosureURLs.count
            },
            onChange: { [weak self] in self?.refreshVisibleCardStatus() }
        )

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

    /// The header/shelf/strip views are configured here. The shelf and strip
    /// are HOSTED by the chrome list cells (Figma scrolls them with the
    /// column) — the cells re-parent the shared views on dequeue, so exactly
    /// one materialized host exists at a time. The header is pinned by
    /// `buildHeader`.
    private func configureChrome() {
        // The status line is reserved from the first frame: a label that
        // appears later changes the header's height.
        header.configure(HeaderView.Configuration(
            title: "Podcast",
            statusText: Self.headerStatusText(lastRefresh: nil, episodeCount: 0)
        ))
        header.onSettings = { [weak self] in
            guard let self else { return }
            AppSheets.presentExpand(SettingsViewController(context: self.context), from: self.topMostPresented())
        }

        shelf.onSelect = { [weak self] show in self?.openChannel(show) }
        shelf.onAllShows = { [weak self] in self?.presentShowsSheet() }
        shelf.accessibilityIdentifier = "inbox-shows-shelf"

        categoryStrip.onSelect = { [weak self] value in
            guard let self else { return }
            self.selectedCategory = value
            self.renderList(allowsDiff: false)
        }
        categoryStrip.accessibilityIdentifier = "inbox-category-strip"
    }

    /// "updated {relative} · {n} unlistened" (Figma header status line).
    static func headerStatusText(lastRefresh: Date?, episodeCount: Int, now: Date = Date()) -> String {
        InboxHeaderStatus.text(
            isUpdating: false, newCount: 0,
            lastRefresh: lastRefresh, episodeCount: episodeCount, now: now
        )
    }

    private func refreshChromeStatus() {
        let status = InboxHeaderStatus.text(
            isUpdating: isSilentRefreshing,
            newCount: newRowCount,
            lastRefresh: gate.lastRefresh,
            episodeCount: episodes.filter { !($0.enclosureUrl.map(hiddenRemovalURLs.contains) ?? false) }.count
        )
        // Nothing followed: there is nothing to be "updated" or "unlistened".
        let followsNothing = didLoadSubscriptions && shows.isEmpty
        header.configure(HeaderView.Configuration(title: "Podcast", statusText: followsNothing ? nil : status))
    }

    /// The section kinds for the current content, top to bottom.
    static func sections(hasShelf: Bool, hasStrip: Bool, hasCards: Bool) -> [Section] {
        var kinds: [Section] = []
        if hasShelf { kinds.append(.shelf) }
        if hasStrip { kinds.append(.strip) }
        kinds.append(.cards)
        return kinds
    }

    private func sectionKind(_ index: Int) -> Section? {
        sections.indices.contains(index) ? sections[index] : nil
    }

    // MARK: - Collection view (03 §2.3 v2: 16 pt sides, 12 pt column gaps;
    // the 64 pt bottom clearance retired — the shell's
    // additionalSafeAreaInsets already anchors resting content above the
    // chrome, 09 §10 决策⑥)

    /// Figma scroll column (1787:7899): padding 0/16, vertical gap 12 —
    /// the shelf section carries the gap as its bottom inset, the strip
    /// half of it, and the cards bake the other half into the cell.
    /// Followed directly by cards, a chrome row carries only the other
    /// half; the strip's 44 pt row already pads its chips. The first
    /// section tops up the gap the pinned header leaves above the list.
    private func makeSection(
        index: Int, environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        guard let section = makeSectionBody(index: index, environment: environment) else { return nil }
        if index == 0 {
            section.contentInsets.top += Spacing.gap - Spacing.xs
        }
        return section
    }

    private func makeSectionBody(
        index: Int, environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection? {
        guard sections.indices.contains(index) else { return nil }
        let next = sections.indices.contains(index + 1) ? sections[index + 1] : nil
        let gapBeforeCards = Spacing.gap
        switch sections[index] {
        case .shelf:
            return Self.chromeSection(
                height: ShowsShelfLayout.itemSide,
                bottomInset: next == .cards ? gapBeforeCards : Spacing.xs
            )
        case .strip:
            return Self.chromeSection(height: CategoryStripView.chipHeight, bottomInset: gapBeforeCards)
        case .cards:
            return Self.rowsSection()
        }
    }

    static func rowsSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(120))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = EpisodeCardCell.spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: Spacing.sm, trailing: Spacing.pageH
        )
        return section
    }

    /// Shelf and strip have fixed heights so estimates cannot move the cards
    /// after the first layout.
    static func chromeSection(height: CGFloat?, bottomInset: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: height.map { .absolute($0) } ?? .estimated(120)
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

    /// Pins the header above the list exactly like the Playlist header
    /// (top = safe area top), so the three tab headers share positions and
    /// a pull moves only the list.
    private func buildHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
    }

    private func buildCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true   // empty state stays pull-refreshable (03 §10.1)
        collectionView.delegate = self
        collectionView.register(
            InboxEpisodeCardCell.self,
            forCellWithReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier
        )
        collectionView.register(
            ChromeHostingCell.self, forCellWithReuseIdentifier: ChromeHostingCell.reuseIdentifier
        )
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { [weak self] collection, path, item in
            self?.cell(in: collection, at: path, item: item)
        }
        actionController = ListActionController(
            collectionView: collectionView,
            itemsProvider: { [weak self] id in self?.groupItems(for: id) ?? [] },
            idAt: { [weak self] path in
                guard let item = self?.dataSource.itemIdentifier(for: path),
                      case .episode(let id) = item else { return nil }
                return id
            },
            indexPathFor: { [weak self] id in self?.dataSource.indexPath(for: .episode(id)) },
            safeArea: { [weak self] in self?.actionSafeLines() ?? (0, 0) }
        )

        refreshControl.addTarget(self, action: #selector(refreshControlTriggered), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // The list runs under the pinned header (content fades out
            // behind it); `syncTopInset` keeps the resting first row where
            // it sat when the list started below the header.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // With the list below the pinned header the automatic lookup no
        // longer finds it for the tab bar's minimize-on-scroll.
        setBottomEdgeScrollView(collectionView)
        view.bringSubviewToFront(header)   // the list now runs under it
        ScrollEdgeChrome.attach(
            chrome: header, to: collectionView, edge: .top, in: view, reach: view.topAnchor
        )

        emptyStateView.onFindShow = { [weak self] in
            // The Search tab.
            self?.context.tabs.select(3)
        }
        emptyStateView.onShowAll = { [weak self] in
            guard let self else { return }
            self.selectedCategory = nil
            self.categoryStrip.resetSelection()
            self.renderList(allowsDiff: false)
        }
        emptyStateView.onImport = { [weak self] in
            // The steps for each app (all end with sharing to Anycast), and
            // a button for someone who already has the file.
            guard let self else { return }
            ImportInstructionsViewController.present(from: self) { [weak self] instructions in
                guard let self else { return }
                ImportFlow.chooseFile(from: instructions, context: self.context) { [weak instructions] in
                    // Done closes the sheet and the instructions under it.
                    instructions?.presentingViewController?.dismiss(animated: true)
                }
            }
        }

        historyFooterButton.addAction(
            UIAction { [weak self] _ in self?.presentHistory() },
            for: .touchUpInside
        )
        historyFooterButton.install(in: view)
    }

    private func presentHistory() {
        HistoryDialogViewController.present(from: self, context: context)
    }

    // MARK: - Data

    func reload() async {
        reloadGeneration += 1
        let generation = reloadGeneration
        let repository = context.database.feedRepository()
        guard let rows = try? await repository.listAll() else {
            // A failed read keeps the current list — rendering the empty
            // state here would claim the inbox has no episodes at all.
            return
        }
        // A newer reload owns the list; this older read must not replace it.
        guard generation == reloadGeneration else { return }
        // Categories first: nothing may suspend between assigning the rows
        // and rendering them, or a layout pass could see the new rows
        // before the diff that announces them.
        await reloadCategories()
        // Resolve every description before exposing rows to the cell
        // provider. Keyed by enclosure URL; an unchanged description reuses
        // the previous parse, only new or changed HTML reaches the actor.
        var descriptions: [String: (html: String, plain: String)] = [:]
        descriptions.reserveCapacity(rows.count)
        for row in rows {
            guard let url = row.enclosureUrl else { continue }
            let html = row.description ?? ""
            if let cached = plainDescriptions[url], cached.html == html {
                descriptions[url] = cached
            } else {
                descriptions[url] = (html, await PlainTextHTMLCache.shared.plainText(for: html))
            }
        }
        guard generation == reloadGeneration else { return }
        // The model and its text commit together inside the snapshot transaction.
        renderList(allowsDiff: true, incoming: rows, generation: generation) { [weak self] in
            guard let self else { return }
            self.episodes = rows
            self.plainDescriptions = descriptions
            self.didLoadOnce = true
        }
        prefetchCovers()
    }

    /// Warms the first screenful of covers into the cache at the size the
    /// cards use; the options come from the same helper `setArtwork` uses, so
    /// the cache keys match.
    private func prefetchCovers() {
        let urls = displayedEpisodes.prefix(Self.prefetchCoverCount)
            .compactMap { $0.imageUrl.flatMap(URL.init(string:)) }
        coverPrefetcher?.stop()
        guard !urls.isEmpty else { coverPrefetcher = nil; return }
        let prefetcher = ImagePrefetcher(
            urls: urls, options: ArtworkSizing.processingOptions(side: InboxEpisodeCardCell.artworkSide)
        )
        coverPrefetcher = prefetcher
        prefetcher.start()
    }

    private static let prefetchCoverCount = 12

    /// Loads the subscriptions and refreshes what derives from them: the
    /// category map and strip (09 §3.2: the strip derives from
    /// `subscription.categories`) and the shows shelf.
    private func reloadCategories() async {
        let subscriptions = (try? await context.database.subscriptionRepository().listAll()) ?? []
        categoriesByFeed = InboxCategoryFilter.categoriesByFeed(from: subscriptions)
        categoryStrip.configure(
            categories: subscriptions.compactMap { $0.categories },
            selected: selectedCategory
        )
        shows = ShowsShelfLayout.ordered(subscriptions)
        didLoadSubscriptions = true
        shelf.configure(shows: shows)
        // A selection that vanished (unsubscribed its last source) resets
        // to the all chip, like the strip's own configure does.
        if selectedCategory != nil, categoryStrip.currentSelection == nil {
            selectedCategory = nil
        }
        refreshChromeStatus()
    }

    /// Keep incoming rows and their commit together while the gate is closed.
    /// A newer reload supersedes any parked older generation.
    private func renderList(
        allowsDiff: Bool = false,
        incoming: [FeedEpisodeRow]? = nil,
        generation: Int? = nil,
        commit: (() -> Void)? = nil
    ) {
        updateGate.submitOrDefer { [weak self] in
            guard let self else { return }
            if let generation, generation != self.reloadGeneration { return }
            self.performRender(allowsDiff: allowsDiff, incoming: incoming, commit: commit)
        }
    }

    private func performRender(
        allowsDiff: Bool, incoming: [FeedEpisodeRow]?, commit: (() -> Void)?
    ) {
        let displayed = incoming.map {
            InboxCategoryFilter.displayed(
                episodes: $0, selected: selectedCategory, categoriesByFeed: categoriesByFeed,
                excluding: hiddenRemovalURLs
            )
        } ?? displayedEpisodes
        let signature = displayed.map(\.enclosureUrl)
        let newSections = Self.sections(hasShelf: !shows.isEmpty, hasStrip: categoryStrip.hasFilters, hasCards: !displayed.isEmpty)
        let plan = InboxListDiff.plan(old: lastSignature, new: signature, sectionsUnchanged: newSections == dataSource.snapshot().sectionIdentifiers)
        // Identity-only refreshes do not reconfigure surviving cells or apply a
        // second snapshot when a deferred removal's database write settles.
        if plan == .unchanged {
            commit?()
        } else {
            let anchors = actionController.selectedID == nil && allowsDiff
                && collectionView.contentOffset.y > -collectionView.adjustedContentInset.top + 0.5
                ? visibleAnchors(oldSignature: lastSignature) : []
            updateGate.begin()
            let anchorID = anchors.first { signature.contains($0) }
            actionController.itemsDidChange(preservingItem: anchorID) {
                commit?()
                self.applySnapshot()
            }
            updateGate.end()
        }
        finishListUpdate()
        playEntranceIfNeeded()
    }

    /// Exactly one non-animated apply; called only inside a controller mutation.
    private func applySnapshot() {
        let rows = displayedEpisodes
        sections = Self.sections(hasShelf: !shows.isEmpty, hasStrip: categoryStrip.hasFilters, hasCards: !rows.isEmpty)
        lastSignature = rows.map(\.enclosureUrl)
        renderedRows.removeAll(keepingCapacity: true)
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections(sections)
        for section in sections {
            switch section {
            case .shelf: snapshot.appendItems([.shelf], toSection: section)
            case .strip: snapshot.appendItems([.strip], toSection: section)
            case .cards:
                let ids = rows.enumerated().map { index, row -> Item in
                    let candidate = row.enclosureUrl.map(Item.episode) ?? .unidentified(index)
                    let id = renderedRows[candidate] == nil ? candidate : .unidentified(index)
                    renderedRows[id] = row
                    return id
                }
                snapshot.appendItems(ids, toSection: section)
            }
        }
        snapshotApplyCount += 1
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func finishListUpdate() {
        applyEmptyState()
        historyFooterButton.refresh(pageIsEmpty: displayedEpisodes.isEmpty, database: context.database)
        refreshChromeStatus()
    }

    private func actionSafeLines() -> (top: CGFloat, bottom: CGFloat) {
        var bottom = collectionView.bounds.height - collectionView.safeAreaInsets.bottom
        if let shell = tabBarController as? MainTabBarController,
           let line = shell.bottomChromeTopY(in: collectionView) {
            bottom = line - collectionView.bounds.minY
        }
        return (collectionView.adjustedContentInset.top, bottom - 52)
    }

    private func groupItems(for id: String) -> [ListActionItem] {
        guard let episode = renderedRows[.episode(id)] else { return [] }
        let path = dataSource.indexPath(for: .episode(id))
        return [
            ListActionItem(id: "play", content: .icon(AppIcons.play), accessibilityLabel: "Play") { [weak self] in
                self?.perform(.play, episode: episode, at: path)
            },
            ListActionItem(id: "add", content: .icon(AppIcons.addToList), accessibilityLabel: "Add to playlist") { [weak self] in
                self?.perform(.addToPlaylist, episode: episode, at: path)
            },
            ListActionItem(id: "remove", content: .icon(AppIcons.remove), accessibilityLabel: "Remove from inbox") { [weak self] in
                self?.perform(.remove, episode: episode, at: path)
            },
            ListActionItem(id: "details", content: .title("Details"), accessibilityLabel: "Show details") { [weak self] in
                self?.presentDetail(episode: episode)
            },
        ]
    }

    /// Hosts the empty state with the reason the list is empty, or clears it.
    private func applyEmptyState() {
        let displayed = displayedEpisodes
        guard displayed.isEmpty else {
            collectionView.backgroundView = nil
            return
        }
        if didLoadSubscriptions && shows.isEmpty {
            emptyStateView.show(.noSubscriptions)
        } else if let category = selectedCategory {
            emptyStateView.show(.filtered(category: category))
        } else {
            emptyStateView.show(.caughtUp(showCount: shows.count))
        }
        collectionView.backgroundView = emptyStateView
    }

    /// Visible card identities, topmost first. The engine captures the chosen
    /// survivor's presentation position before applying the new snapshot.
    private func visibleAnchors(oldSignature: [String?]) -> [String] {
        let viewportTop = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        return collectionView.indexPathsForVisibleItems
            .filter { sectionKind($0.section) == .cards && oldSignature.indices.contains($0.item) }
            .compactMap { path -> (url: String, minY: CGFloat)? in
                guard let url = oldSignature[path.item],
                      let frame = collectionView.layoutAttributesForItem(at: path)?.frame,
                      frame.maxY > viewportTop else { return nil }
                return (url, frame.minY)
            }
            .sorted { $0.minY < $1.minY }
            .map { $0.url }
    }

    /// Plays the entrance right after the list was applied. A prewarmed page
    /// can apply its data before it is in a window (no layout, nothing to
    /// animate), so that case is retried from `viewDidAppear`.
    private func playEntranceIfNeeded() {
        guard !didPlayEntrance, view.window != nil, !displayedEpisodes.isEmpty else { return }
        didPlayEntrance = true
        CardEntranceAnimator.play(in: collectionView)
    }

    // MARK: - Refresh (feeds.dart:229-249 fetchNewEpisodes)

    private func fireIfPermitted(_ trigger: InboxRefreshTrigger) {
        guard gate.permits(trigger) else { return }
        callRefresh(reveals: trigger.revealsRefreshControl)
    }

    /// callRefresh: runs the SAME fetch path as the pull. `reveals` is true
    /// only for a user-initiated trigger (`InboxRefreshTrigger
    /// .revealsRefreshControl`): it shows the system control and scrolls it
    /// into view. Every other trigger runs silently — no control, no
    /// content-offset change — and reports through the header status line.
    private func callRefresh(reveals: Bool) {
        guard !isRefreshing else { return }
        isRefreshing = true
        if reveals {
            refreshControl.beginRefreshing()
            let controlHeight = refreshControl.bounds.height > 0 ? refreshControl.bounds.height : 80
            let revealY = -(collectionView.adjustedContentInset.top + controlHeight)
            if collectionView.contentOffset.y > revealY {
                collectionView.setContentOffset(CGPoint(x: 0, y: revealY), animated: true)
            }
        } else {
            isSilentRefreshing = true
            refreshChromeStatus()
        }
        performRefresh(userInitiated: reveals)
    }

    @objc private func refreshControlTriggered() {
        guard !isRefreshing else {
            // A silent refresh is already running; the pull has nothing to
            // start, but its spinner must not stay up.
            refreshControl.endRefreshing()
            return
        }
        isRefreshing = true
        performRefresh(userInitiated: true)
    }

    /// The single fetch → settle path every trigger funnels through.
    private func performRefresh(userInitiated: Bool) {
        newRowCount = 0
        Task { [weak self] in
            await self?.fetchNewEpisodes()
            guard let self else { return }
            self.isRefreshing = false
            if self.isSilentRefreshing {
                self.isSilentRefreshing = false
                self.refreshChromeStatus()
            }
            if userInitiated {
                self.refreshControl.endRefreshing()
                // endRefreshing does not undo callRefresh's programmatic
                // reveal when the list was off screen (another tab) while it
                // ran; the list would stay 60 pt low. Settle it back to its
                // top. A silent refresh never moved the list, so it never
                // settles it.
                let top = -self.collectionView.adjustedContentInset.top
                if !self.collectionView.isDragging, self.collectionView.contentOffset.y < top {
                    self.collectionView.setContentOffset(
                        CGPoint(x: 0, y: top), animated: self.view.window != nil
                    )
                }
            }
            if self.needsRefreshAfterImport {
                self.needsRefreshAfterImport = false
                self.callRefresh(reveals: false)
            }
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
        let known = Set(episodes.compactMap(\.enclosureUrl))
        let couldCount = didLoadOnce
        await reload()
        if couldCount {
            newRowCount = InboxHeaderStatus.newRowCount(known: known, current: episodes)
            refreshChromeStatus()
        }
    }

    /// saveNewEpisodes (feeds.dart:293-303): pure merge, then batch writes.
    private func save(batch: [PodcastImportData?], subscriptions: [SubscriptionRow]) async {
        let result = SaveNewEpisodes.compute(fetched: batch, local: subscriptions)
        let repository = context.database
        if !result.subscriptions.isEmpty {
            try? await repository.subscriptionRepository().addMany(result.subscriptions)
            // The shelf reloads (Obx equivalent). Posted with this page as
            // the object so its own observer does not refetch in a loop.
            NotificationCenter.default.post(
                name: ShowsShelfLayout.subscriptionsDidChange,
                object: self
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

    /// Imports and Channel subscribe / unsubscribe write subscriptions
    /// outside this page; the shelf and the strip follow, and a fetch pulls
    /// the new feeds' episodes without the user pulling (`callRefresh`
    /// carries the spinner and the single-flight guard).
    private func observeSubscriptionChanges() {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: ShowsShelfLayout.subscriptionsDidChange,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let sender = note.object.map { ObjectIdentifier($0 as AnyObject) }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // This page's own refresh save, once per 8-feed batch: the
                    // shelf and strip update once, when the refresh finishes
                    // (`fetchNewEpisodes` ends in `reload()`); rebuilding them
                    // per batch made the covers and chips flicker. It must
                    // not refetch either (that would loop).
                    if sender == ObjectIdentifier(self) { return }
                    Task { [weak self] in
                        await self?.reloadCategories()
                        self?.renderList()
                    }
                    // The import writes each feed's first episode rows, so
                    // the reload alone already surfaces content; the fetch
                    // pulls the full backlog for the new subscriptions.
                    if !self.isRefreshing {
                        self.callRefresh(reveals: false)
                    } else {
                        // A refresh already in flight snapshot its
                        // subscription list before the import landed — run
                        // one more pass when it settles.
                        self.needsRefreshAfterImport = true
                    }
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
            // The row pending removal is going away anyway: it neither counts
            // toward the limit nor is a trim candidate.
            let kept = self.episodes.filter { !($0.enclosureUrl.map(self.hiddenRemovalURLs.contains) ?? false) }
            let plan = InboxTrimPlanner.plan(count: kept.count, keeping: settings.maxFeedEpisodes)
            // An import adds episodes the person has not seen the result of
            // yet: the Inbox waits until they tap Done.
            if plan.removesAnything, !InboxTrimHold.isHeld {
                let urls = kept[plan.removedIndices].compactMap(\.enclosureUrl)
                try? await self.context.database.feedRepository().removeByEnclosureUrls(urls)
                let remaining = self.episodes.filter { !($0.enclosureUrl.map(urls.contains) ?? false) }
                self.renderList(allowsDiff: true, incoming: remaining) { self.episodes = remaining }
            }
            // History side: same semantics, SQL-side (history.dart:54-67).
            _ = try? await self.context.database.historyRepository().trim(keeping: settings.maxHistoryEpisodes)
        }
    }

    // MARK: - Card actions (feeds.dart:84-131; ordering in InboxActionPlanner)

    private func perform(_ action: InboxEpisodeAction, episode: FeedEpisodeRow, at indexPath: IndexPath?) {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty,
              actionsInFlight.insert(enclosureURL).inserted else { return }
        if action == .remove {
            Haptics.queueRemoved()
            removeWithUndo(url: enclosureURL)
            actionsInFlight.remove(enclosureURL)
            return
        }
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: playlistId)
        // The full stored row, taken before the Add removes it: Undo restores
        // it field for field.
        let feedSnapshot = episodes.first { $0.enclosureUrl == enclosureURL } ?? episode
        let steps = InboxActionPlanner.steps(
            for: action,
            currentPlaylistId: context.playback.currentPlaylistId,
            currentEnclosureURL: context.playback.currentEpisode?.enclosureUrl,
            episodeEnclosureURL: enclosureURL
        )
        // Capture the Add circle before any await can move or remove its
        // selected card. Context-menu/VoiceOver actions without a group keep
        // the row fallback; Detail supplies nil and never flies.
        let flyInStart = Self.resolvedFlyInStart(
            actionPath: indexPath,
            identityPath: currentIndexPath(of: episode),
            in: collectionView,
            window: view.window,
            addCircle: actionController.selectedID == enclosureURL ? actionController.groupView.button(for: "add") : nil
        )
        Task { [weak self] in
            guard let self else { return }
            defer { self.actionsInFlight.remove(enclosureURL) }
            var insertedRow = row
            var createdRow: PlaylistEpisodeRow?
            for step in steps {
                switch step {
                case .flyInAnimation:
                    await self.runFlyIn(from: flyInStart)
                case .insertIntoPlaylist(let index):
                    let repository = self.context.database.playlistRepository()
                    // Undo deletes only a row this Add created.
                    let existed = (try? await repository.episode(byEnclosureURL: enclosureURL)) != nil
                    try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: index)
                    if let stored = try? await repository.episode(byEnclosureURL: enclosureURL) {
                        insertedRow = stored
                        if !existed { createdRow = stored }
                    }
                case .skipInsertCurrentlyPlaying:
                    break
                case .removeFromInbox:
                    let created = createdRow
                    await self.removeFromInbox(urls: [enclosureURL], keepsGroup: action != .play) {
                        // Play never enters a batch; an Add does.
                        guard action == .addToPlaylist else { return }
                        self.recordAdd(InboxBatchItem(
                            url: enclosureURL, feedRow: feedSnapshot, createdPlaylistRow: created
                        ))
                    }
                case .playInsertedEpisode:
                    await self.context.playback.playByEpisode(insertedRow)
                case .reloadPlaybackQueue:
                    await self.context.playback.reloadQueue()
                }
            }
        }
    }

    /// `perform`'s fly-in decision, whole: only a list-surface action
    /// (non-nil `actionPath`) flies, and only while the row is still
    /// resolvable (`identityPath` — the identity re-resolution of the row
    /// against the CURRENT list). The Detail sheet passes a nil action
    /// path and must never fly; a list action whose row already left the
    /// list drops the flight rather than resolving a stale path. Internal
    /// + static so the regression suite pins the contract at the same
    /// entry `perform` uses.
    static func resolvedFlyInStart(
        actionPath: IndexPath?,
        identityPath: IndexPath?,
        in collectionView: UICollectionView,
        window: UIWindow?,
        addCircle: UIView? = nil
    ) -> CGPoint? {
        guard actionPath != nil, let identityPath else { return nil }
        if let addCircle, let window {
            var center = addCircle.convert(CGPoint(x: addCircle.bounds.midX, y: addCircle.bounds.midY), to: window)
            // Usually the group is stationary. At the top-clamp exception it
            // can still be travelling; launch from the circle the user sees.
            if let group = addCircle.superview, let parent = group.superview,
               let presented = group.layer.presentation() {
                let visible = parent.convert(presented.frame.origin, to: window)
                let model = parent.convert(group.frame.origin, to: window)
                center.x += visible.x - model.x
                center.y += visible.y - model.y
            }
            return center
        }
        return flyInOrigin(in: collectionView, at: identityPath, window: window)
    }

    /// Fallback for a context-menu/VoiceOver Add without an open group.
    /// Group Add supplies its circle center instead; Detail never flies.
    static func flyInOrigin(
        in collectionView: UICollectionView, at indexPath: IndexPath?, window: UIWindow?
    ) -> CGPoint? {
        guard let indexPath, let window else { return nil }
        func pathIsInBounds() -> Bool {
            indexPath.section >= 0
                && indexPath.section < collectionView.numberOfSections
                && indexPath.item >= 0
                && indexPath.item < collectionView.numberOfItems(inSection: indexPath.section)
        }
        let inBounds = pathIsInBounds()
        let restingX = collectionView.convert(collectionView.bounds, to: window).midX
        if inBounds, let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame {
            let midY = collectionView.convert(CGPoint(x: 0, y: frame.midY), to: window).y
            return CGPoint(x: restingX, y: midY)
        }
        if inBounds, let cell = collectionView.cellForItem(at: indexPath) {
            let midY = cell.convert(CGPoint(x: 0, y: cell.bounds.midY), to: window).y
            return CGPoint(x: restingX, y: midY)
        }
        return window.center
    }

    /// Resolve against the applied snapshot, never a configure-time index.
    private func currentIndexPath(of episode: FeedEpisodeRow) -> IndexPath? {
        episode.enclosureUrl.flatMap(currentIndexPath(for:))
    }

    private func currentIndexPath(for url: String) -> IndexPath? {
        dataSource.indexPath(for: .episode(url))
    }

    /// AnimatedPlaylistIndicator — runs AFTER the row's animated removal
    /// (the planner's add-to-playlist order); the insert has already
    /// committed by then.
    private func runFlyIn(from start: CGPoint?) async {
        guard let start, let window = view.window else { return }
        await withCheckedContinuation { continuation in
            context.flyInAnimator.fly(from: start, in: window) {
                continuation.resume()
            }
        }
    }

    /// Durable moves use the same synchronous visual leave as Remove.
    private func removeFromInbox(
        urls: [String], keepsGroup: Bool = true, afterLeave: (() -> Void)? = nil
    ) async {
        try? await context.database.feedRepository().removeByEnclosureUrls(urls)
        while updateGate.isBusy { try? await Task.sleep(nanoseconds: 10_000_000) }
        leaveInbox(urls: urls, hiding: false, keepsGroup: keepsGroup)
        afterLeave?()
        // The fly-in follows the leaving snapshot's travel, without locking
        // the group: the next circle tap can already act on the filler.
        try? await Task.sleep(for: .seconds(ListActionMotion.duration))
    }

    /// Remove with a 5 s Undo, merged with the Removes before it: the card
    /// animates out now, the DB rows go when the window ends (see
    /// `PendingBatch`).
    private func removeWithUndo(url: String) {
        updateGate.submitOrDefer { [weak self] in
            guard let self, self.currentIndexPath(for: url) != nil else { return }
            let repository = self.context.database.feedRepository()
            self.batch.add(InboxBatchItem(url: url), kind: .remove) { [weak self] items in
                let urls = items.map(\.url)
                let deleted = (try? await repository.removeByEnclosureUrls(urls)) != nil
                self?.settleRemoval(urls: urls, deleted: deleted)
            }
            self.leaveInbox(urls: [url], hiding: true)
            self.showBatchCapsule()
        }
    }

    /// An Add already moved its row (the playlist insert and the inbox
    /// delete are durable); the batch only keeps what Undo needs.
    private func recordAdd(_ item: InboxBatchItem) {
        batch.add(item, kind: .add) { _ in }
        showBatchCapsule()
    }

    /// The write finished: the rows are gone from `episodes` too. A failed
    /// write leaves the rows in the DB, so they come back.
    private func settleRemoval(urls: [String], deleted: Bool) {
        // A read begun before this write must not resurrect the committed rows.
        reloadGeneration += 1
        if deleted { episodes.removeAll { $0.enclosureUrl.map(urls.contains) ?? false } }
        hiddenRemovalURLs.subtract(urls)
        renderList(allowsDiff: true)
    }

    private func undoBatch() {
        guard let undone = batch.undo() else { return }
        switch undone.kind {
        case .remove:
            UIAccessibility.post(notification: .announcement, argument: "Restored")
            hiddenRemovalURLs.subtract(undone.items.map(\.url))
            renderList(allowsDiff: true)
        case .add:
            let context = context
            Task { [weak self] in
                do {
                    try await InboxBatchLogic.undoAdd(
                        undone.items,
                        currentEnclosureURL: context.playback.currentEpisode?.enclosureUrl,
                        feedRepository: context.database.feedRepository(),
                        playlistRepository: context.database.playlistRepository()
                    )
                    UIAccessibility.post(notification: .announcement, argument: "Restored")
                } catch {
                    // The episode stays in the playlist (and, if the write
                    // half-failed, in the inbox too) — say so instead of
                    // announcing a restore that did not happen.
                    if let window = self?.view.window {
                        ToastPresenter.shared.show(
                            "Couldn't undo — episodes stayed in your Playlist", in: window, duration: 3
                        )
                    }
                }
                if context.playback.currentPlaylistId == ChannelPlaylistLogic.defaultPlaylistID {
                    await context.playback.reloadQueue()
                }
                await self?.reload()
            }
        }
    }

    private func showBatchCapsule() {
        guard let kind = batch.kind else { return }
        let message = InboxBatchLogic.message(kind: kind, count: batch.count)
        if ToastPresenter.shared.updateAction(message, capsuleIdentifier: "inbox-removal-capsule") { return }
        guard let window = view.window else { return }
        ToastPresenter.shared.showAction(
            message,
            actionTitle: "Undo",
            in: window,
            above: (tabBarController as? MainTabBarController)?.bottomChromeTopAnchor,
            capsuleIdentifier: "inbox-removal-capsule",
            actionIdentifier: "inbox-removal-undo",
            onAction: { [weak self] in self?.undoBatch() },
            // Another toast replaced the capsule: Undo is out of reach.
            onSuperseded: { [weak self] in
                guard let self else { return }
                Task { await self.batch.commitNow() }
            }
        )
    }

    /// The model and the snapshot change synchronously once. FLIP owns all
    /// motion; rapid subsequent actions can use the filler immediately.
    private func leaveInbox(urls: [String], hiding: Bool, keepsGroup: Bool = true) {
        if hiding, !urls.allSatisfy({ url in batch.items.contains { $0.url == url } }) { return }
        let id = urls.first(where: { dataSource.indexPath(for: .episode($0)) != nil })
        let hadCards = !displayedEpisodes.isEmpty
        reloadGeneration += 1
        updateGate.begin()
        let apply = {
            self.dropFromMemory(urls: urls, hiding: hiding)
            self.applySnapshot()
        }
        if let id {
            actionController.performLeave(id: id, keepsGroup: keepsGroup, apply: apply)
        } else {
            actionController.itemsDidChange(apply: apply)
        }
        finishListUpdate()
        if hadCards && displayedEpisodes.isEmpty {
            emptyStateView.alpha = 0
            collectionView.layoutIfNeeded()
            view.layoutIfNeeded()
            UIView.animate(withDuration: Motion.quick, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.emptyStateView.alpha = 1
            }
        }
        updateGate.end()
    }

    private func dropFromMemory(urls: [String], hiding: Bool) {
        if hiding {
            hiddenRemovalURLs.formUnion(urls)
        } else {
            episodes.removeAll { $0.enclosureUrl.map(urls.contains) ?? false }
        }
    }

    /// The cards section's provider index in the current section set.
    private var cardsSectionIndex: Int {
        sections.firstIndex(of: .cards) ?? sections.count
    }

    // MARK: - Shows shelf

    /// A shelf cover or a Shows sheet row: the Channel sheet for that show,
    /// the same way every card opens it (card.dart:330-342).
    private func openChannel(_ show: SubscriptionRow) {
        ChannelViewController.present(
            from: topMostPresented(),
            context: context,
            rssFeedURL: show.rssFeedUrl ?? "",
            seed: show
        )
    }

    private func presentShowsSheet() {
        LibrarySheetViewController.present(from: topMostPresented(), context: context, shows: shows) { [weak self] show in
            self?.openChannel(show)
        }
    }

    // MARK: - Detail (cover, group and menu)

    private func presentDetail(episode: FeedEpisodeRow) {
        guard let enclosureURL = episode.enclosureUrl else { return }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: episode.duration,
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
            isInPlaylist: context.playback.queue.contains(where: { $0.enclosureUrl == enclosureURL }),
            transcript: DetailTranscriptCoordinator(
                context: context,
                episode: detailEpisode,
                prepareEpisode: { [weak self] in
                    await self?.prepareTranscriptEpisode(episode)
                }
            )
        )
    }

    /// Queue preparation for opening a transcript when nothing else is
    /// playing: the episode moves to the top of the playlist and stays in
    /// the inbox. Playback is not started here.
    private func prepareTranscriptEpisode(_ episode: FeedEpisodeRow) async -> PlaylistEpisodeRow? {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return nil }
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        var row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: playlistId)
        let repository = context.database.playlistRepository()
        try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: 0)
        if let stored = try? await repository.episode(byEnclosureURL: enclosureURL) {
            row = stored
        }
        return row
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
        let isAtTop = collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 0.5
        switch TabZeroRetap.action(hasClient: true, isAtTop: isAtTop) {
        case .scrollToTop:
            let top = CGPoint(x: 0, y: -collectionView.adjustedContentInset.top)
            // Plain animated setContentOffset — the old UIView.animate
            // wrapper around setContentOffset(animated: false) +
            // layoutIfNeeded() jumped the offset inside the block before
            // any property animation could run.
            collectionView.setContentOffset(top, animated: true)
        case .refresh:
            callRefresh(reveals: InboxRefreshTrigger.tabRetapAtTop.revealsRefreshControl)
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
        categoriesByFeed: [String: Set<String>],
        excluding hiddenURLs: Set<String> = []
    ) -> [FeedEpisodeRow] {
        let episodes = hiddenURLs.isEmpty
            ? episodes : episodes.filter { !($0.enclosureUrl.map(hiddenURLs.contains) ?? false) }
        guard let selected else { return episodes }
        let wanted = selected.lowercased()
        return episodes.filter { episode in
            guard let feed = episode.rssFeedUrl else { return false }
            return categoriesByFeed[feed]?.contains(wanted) ?? false
        }
    }
}

// MARK: - Data source

extension InboxPageViewController {

    private func cell(in collectionView: UICollectionView, at indexPath: IndexPath, item: Item) -> UICollectionViewCell {
        switch item {
        case .shelf, .strip:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath)
            (cell as? ChromeHostingCell)?.host(item == .shelf ? shelf : categoryStrip)
            return cell
        case .episode, .unidentified:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier, for: indexPath)
            if let card = cell as? InboxEpisodeCardCell, let episode = renderedRows[item] {
                configure(card: card, episode: episode, at: indexPath)
                if case .episode(let id) = item { actionController.reapplyGap(to: card, id: id) }
                else { card.setActionGap(0) }
            }
            return cell
        }
    }

    private func configure(card: InboxEpisodeCardCell, episode: FeedEpisodeRow, at indexPath: IndexPath) {
        let content = InboxCardContent(
            title: episode.title ?? "",
            showName: episode.channelTitle ?? "",
            dateText: episode.pubDate.map { RelativeTimeFormatter.format($0) } ?? "",
            durationText: Self.durationText(for: episode),
            imageURL: episode.imageUrl,
            status: status(for: episode),
            descriptionText: episode.enclosureUrl.flatMap { plainDescriptions[$0]?.plain } ?? ""
        )
        card.configure(content)
        // The same payload feeds the long-press context menu and the
        // VoiceOver custom actions (09 §7a-C1).
        card.menuActions = actions(for: episode, at: indexPath)
        card.onCardTap = { [weak self] in
            guard let id = episode.enclosureUrl else { return }
            self?.actionController.toggle(id: id)
        }
        card.onCoverTap = { [weak self] in self?.presentDetail(episode: episode) }
    }

    /// "44m" — the metadata duration; empty when unknown.
    static func durationText(for episode: FeedEpisodeRow) -> String {
        guard let duration = episode.duration, duration > 0 else { return "" }
        return TimeFormats.formatDuration(duration)
    }

    private func status(for episode: FeedEpisodeRow) -> InboxCardContent.Status {
        guard let url = episode.enclosureUrl else { return .none }
        if context.playback.currentEpisode?.enclosureUrl == url { return .playing }
        if context.playback.queue.contains(where: { $0.enclosureUrl == url }) { return .queued }
        return .none
    }

    private func refreshVisibleCardStatus() {
        for indexPath in collectionView.indexPathsForVisibleItems
        where sectionKind(indexPath.section) == .cards {
            guard displayedEpisodes.indices.contains(indexPath.item),
                  let card = collectionView.cellForItem(at: indexPath) as? InboxEpisodeCardCell
            else { continue }
            card.apply(status: status(for: displayedEpisodes[indexPath.item]))
        }
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
            EpisodeCardAction(icon: AppIcons.info, accessibilityLabel: "Show details") { [weak self] in
                self?.presentDetail(episode: episode)
            },
        ]
    }
}

// MARK: - Long-press context menu

extension InboxPageViewController: UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard sectionKind(indexPath.section) == .cards else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.contextMenu(at: indexPath)
        }
    }

    /// The strip-equivalent menu (Play / Add to playlist / Remove from
    /// inbox) — same handlers the strip buttons ran. Internal so the
    /// in-app regression suite can assert the wiring directly.
    func contextMenu(at indexPath: IndexPath) -> UIMenu? {
        guard sectionKind(indexPath.section) == .cards,
              displayedEpisodes.indices.contains(indexPath.item) else { return nil }
        let episode = displayedEpisodes[indexPath.item]
        let actions = actions(for: episode, at: indexPath)
        var children: [UIMenuElement] = []
        if DetailTranscriptPolicy.current.includeInboxContextMenu {
            children.append(contentsOf: transcriptContextElements(for: episode))
        }
        children.append(contentsOf: actions.map { action in
            UIAction(title: action.accessibilityLabel, image: action.icon) { _ in
                action.handler()
            }
        })
        return UIMenu(children: children)
    }

    /// Same entries as the detail sheet's ••• group. Only built when
    /// `DetailTranscriptPolicy.includeInboxContextMenu` is on.
    private func transcriptContextElements(for episode: FeedEpisodeRow) -> [UIMenuElement] {
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return [] }
        let detailEpisode = DetailViewController.Episode(
            title: episode.title ?? "",
            channelTitle: episode.channelTitle ?? "",
            pubDateMilliseconds: episode.pubDate,
            durationMilliseconds: episode.duration,
            imageURL: episode.imageUrl,
            rssFeedURL: episode.rssFeedUrl ?? "",
            enclosureURL: enclosureURL,
            descriptionHTML: episode.description ?? ""
        )
        let coordinator = DetailTranscriptCoordinator(
            context: context,
            episode: detailEpisode,
            prepareEpisode: { [weak self] in
                await self?.prepareTranscriptEpisode(episode)
            }
        )
        return coordinator.content().menu.map { item in
            UIAction(title: item.title, subtitle: item.subtitle, image: DetailTranscriptMenuImages.image(for: item.action)) { [weak self] _ in
                guard let self else { return }
                coordinator.handle(item.action, from: self)
            }
        }
    }

}

// MARK: - Scroll-flow chrome hosting (批次1: the Figma column scrolls)

/// Hosts one of the shared chrome views (shelf / strip) inside
/// a self-sizing list cell. Exactly one cell per section is ever alive, so
/// re-parenting the shared view on (re)dequeue is safe.
final class ChromeHostingCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxChromeHostingCell"

    /// The previously hosted chrome view, if this recycled cell carried one.
    /// The header and the strip share this cell class; when the strip
    /// section disappears, a cell that hosted the 44 pt-tall strip can be
    /// recycled for the header — leaving the strip behind would layer it
    /// under the transparent header and fight the header's height pins.
    private var hostedView: UIView?

    func host(_ view: UIView, horizontalInset: CGFloat = 0) {
        if hostedView !== view {
            hostedView?.removeFromSuperview()
        }
        hostedView = view
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

// MARK: - Empty state

/// The three reasons the Inbox list can be empty, each with its own words
/// (on the shared `EmptyStateView`): nothing followed yet, everything heard,
/// or a category filter that hides every episode. Hosted as the collection
/// background so the page stays pull-to-refreshable.
final class InboxEmptyStateView: EmptyStateView {

    enum Reason: Equatable {
        case noSubscriptions
        case caughtUp(showCount: Int)
        case filtered(category: String)
    }

    var onFindShow: (() -> Void)?
    var onImport: (() -> Void)?
    var onShowAll: (() -> Void)?
    private(set) var reason: Reason?

    func show(_ reason: Reason) {
        guard reason != self.reason else { return }
        self.reason = reason
        configure(Self.content(for: reason, find: { [weak self] in self?.onFindShow?() },
                               importAction: { [weak self] in self?.onImport?() },
                               showAll: { [weak self] in self?.onShowAll?() }))
    }

    /// "1 show" / "N shows".
    static func showsPhrase(_ count: Int) -> String {
        count == 1 ? "1 show" : "\(count) shows"
    }

    static func copy(for reason: Reason) -> (title: String, message: String?) {
        switch reason {
        case .noSubscriptions:
            return ("New episodes from shows you follow land here.", "Anycast can transcribe and translate them.")
        case .caughtUp(let count):
            return ("All caught up.", "New episodes from your \(showsPhrase(count)) land here.")
        case .filtered(let category):
            return ("No episodes in \(category).", nil)
        }
    }

    private static func content(
        for reason: Reason,
        find: @escaping () -> Void,
        importAction: @escaping () -> Void,
        showAll: @escaping () -> Void
    ) -> Content {
        let text = copy(for: reason)
        var actions: [UIView] = []
        switch reason {
        case .noSubscriptions:
            let findButton = AnycastButton.make(.primary, title: "Find a show")
            findButton.addAction(UIAction { _ in find() }, for: .touchUpInside)
            let link = EmptyStateView.linkButton(title: "Import from another app")
            link.addAction(UIAction { _ in importAction() }, for: .touchUpInside)
            actions = [findButton, link]
        case .caughtUp:
            break
        case .filtered:
            let button = AnycastButton.make(.secondary, title: "Show all")
            button.addAction(UIAction { _ in showAll() }, for: .touchUpInside)
            actions = [button]
        }
        return Content(title: text.title, message: text.message, actions: actions)
    }
}
