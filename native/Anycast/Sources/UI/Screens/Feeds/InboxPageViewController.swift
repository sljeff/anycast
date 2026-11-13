import UIKit
import os
import Kingfisher
import AnycastKit

/// Tab0 Inbox page (lib/pages/feeds.dart, 03 §2.3; v2 per 09 §3.2/§3.8 and
/// the Anycast 2.0 UI kit Inbox) and the Podcast tab's root: the header is
/// pinned above the list like the other tab headers, while the shows shelf
/// and the category strip scroll WITH the card list (Figma 1787:7899 scroll
/// column) over the feedEpisode table, with the full refresh trigger set — pull-to-refresh
/// (UIRefreshControl, A4 adaptation), refreshOnStart, a 2 s-after-creation
/// auto fetch, a periodic auto fetch every `autoRefreshInterval` seconds
/// (DB default 300, restarted on settings change, K36), and the Tab0
/// re-tap path. Every 60 s the inbox/history overage trim runs
/// (states/player.dart:344-349). The episodes are rows of ONE grouped plate
/// (InboxEpisodeCardCell on `GroupedPlateView`); actions follow
/// `InboxActionPlanner` exactly (play / add-with-fly-in / remove) through
/// the native-first surfaces: whole-row tap opens Detail, long-press opens
/// the context menu, a leading swipe adds to the playlist and a trailing
/// swipe removes (09 §7a-C1; 05 §6.3 P0). Row badges follow the playing
/// episode and the playlist.
final class InboxPageViewController: UIViewController, TabZeroTopRefresh {

    /// Scroll-column sections (Figma column order). The shelf shows only
    /// with subscriptions, the strip only with categories beyond "All", the
    /// history tail only with cards. An empty inbox keeps a weak
    /// "Listening history" link at the page bottom instead. The header is
    /// not a section: it is pinned outside the list, so it stays on the
    /// empty inbox and Settings remains reachable, with the empty state
    /// beneath it.
    enum Section {
        case shelf
        case strip
        case cards
        case tail
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
    private let shelf = ShowsShelfView()
    private let categoryStrip = CategoryStripView()
    private let playbackObservation = ObservationLoop()
    private let collectionView: UICollectionView
    private let refreshControl = UIRefreshControl()
    private let emptyStateView = InboxEmptyStateView()
    /// Empty-inbox link, shown only when History has rows. Hidden once the
    /// inbox has cards; those use the tail.
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
    /// A diff batch or a row removal is animating; a render that lands now
    /// waits for it (its diff would start from rows that are mid-removal).
    private let updateGate = UpdateGate()

    /// An import landed while a refresh was already running; that refresh
    /// predates the new subscriptions, so one more pass must follow it.
    private var needsRefreshAfterImport = false

    /// The category-filtered projection the list renders.
    private var displayedEpisodes: [FeedEpisodeRow] {
        InboxCategoryFilter.displayed(
            episodes: episodes, selected: selectedCategory, categoriesByFeed: categoriesByFeed
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
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        self.collectionView = collection
        super.init(nibName: nil, bundle: nil)
        // Scroll-flow chrome (09 §10 批次1): shelf/strip are list
        // cells now, the card section is a list section so it can carry
        // native swipe actions, and the history pill closes the column.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.makeSection(index: index, environment: environment)
        }
        layout.register(GroupedPlateView.self, forDecorationViewOfKind: GroupedPlateView.elementKind)
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
            episodeCount: episodes.count
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
        if hasCards { kinds.append(.tail) }
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
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.showsSeparators = false
            config.backgroundColor = .clear
            // The config-level provider (not the UICollectionViewDelegate
            // method) — measured on iOS 27 the delegate selector never
            // fires for a list section nested in a compositional section
            // provider, the swipe surface never engages.
            config.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.leadingSwipeActions(at: indexPath)
            }
            config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                self?.trailingSwipeActions(at: indexPath)
            }
            return Self.rowsSection(
                config: config, environment: environment, hasRows: !displayedEpisodes.isEmpty
            )
        case .tail:
            return Self.chromeSection(height: nil, bottomInset: Spacing.gap)
        }
    }

    /// The episode rows as one list section (swipe actions come with the
    /// list configuration) on a grouped plate inset 16 from the edges — the
    /// same `GroupedPlateView` decoration Discover and Channel lists use.
    static func rowsSection(
        config: UICollectionLayoutListConfiguration, environment: NSCollectionLayoutEnvironment,
        hasRows: Bool = true
    ) -> NSCollectionLayoutSection {
        let section = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: Spacing.sm, trailing: Spacing.pageH
        )
        let plate = NSCollectionLayoutDecorationItem.background(elementKind: GroupedPlateView.elementKind)
        plate.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: 0, trailing: Spacing.pageH
        )
        // An empty section would draw an empty plate, a stray white strip.
        section.decorationItems = hasRows ? [plate] : []
        return section
    }

    /// One chrome row (shelf / strip / history pill). The shelf and the
    /// strip are fixed-height controls, so they get their real height here:
    /// an estimate stays in force until the next `reloadData` and left the
    /// shelf 64 pt too tall (cards sat 64 pt low on a cold start). Only the
    /// history pill, which nothing sits below, keeps an estimate.
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

    private func reload() async {
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
        // The rows commit inside the render (inside the batch update when
        // the list is diffed), never ahead of it.
        renderList(allowsDiff: true, incoming: rows, generation: generation) { [weak self] in
            guard let self else { return }
            self.episodes = rows
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

    /// Plain no-animation rebuild (08 §7.2 — the Flutter Obx rebuild).
    /// Renders the list. `incoming` are the rows the list is about to show
    /// and `commit` makes them the page's data; both are optional, and
    /// without them the current rows are re-rendered. With a diff the commit
    /// runs inside `performBatchUpdates`; every other path commits at once.
    /// A render that lands while an update animates waits for it
    /// (`generation` drops a parked reload that a newer one has replaced).
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
                episodes: $0, selected: selectedCategory, categoriesByFeed: categoriesByFeed
            )
        } ?? displayedEpisodes
        let signature = displayed.map(\.enclosureUrl)
        let newSections = Self.sections(
            hasShelf: !shows.isEmpty, hasStrip: categoryStrip.hasFilters, hasCards: !displayed.isEmpty
        )
        var committed = false
        func commitNow() {
            guard !committed else { return }
            committed = true
            commit?()
        }
        // Cover changes reach the shelf in place; only a different card
        // list or a different section set needs an update.
        if signature != lastSignature || newSections != sections {
            let plan = allowsDiff && view.window != nil
                ? InboxListDiff.plan(old: lastSignature, new: signature, sectionsUnchanged: newSections == sections)
                : .reload
            switch plan {
            case .unchanged:
                commitNow()
                lastSignature = signature
            case .reload:
                commitNow()
                lastSignature = signature
                sections = newSections
                UIView.performWithoutAnimation {
                    collectionView.reloadData()
                }
            case .batch(let removes, let inserts):
                committed = true
                applyDiff(
                    removes: removes, inserts: inserts,
                    oldSignature: lastSignature, signature: signature, commit: commit ?? {}
                )
            }
        }
        commitNow()
        applyEmptyState()
        historyFooterButton.refresh(pageIsEmpty: displayedEpisodes.isEmpty, database: context.database)
        refreshChromeStatus()
        refreshVisibleRowPositions()
        playEntranceIfNeeded()
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

    /// Applies rows that appeared or left as a batch update; the cards that
    /// stayed are neither reconfigured nor moved relative to each other.
    /// Scrolled away from the top: no animation and the first visible card
    /// keeps its exact place in the viewport. Resting at the top: the new
    /// cards come in and the rest shift down as one block (not with Reduce
    /// Motion).
    private func applyDiff(
        removes: [Int], inserts: [Int], oldSignature: [String?], signature: [String?],
        commit: @escaping () -> Void
    ) {
        let topY = -collectionView.adjustedContentInset.top
        let restingAtTop = collectionView.contentOffset.y <= topY + 0.5
        // Resolved against the OLD rows: the collection view still shows them.
        let anchors = restingAtTop ? [] : visibleAnchors(oldSignature: oldSignature)
        let animated = restingAtTop && !Motion.reduceMotion

        updateGate.begin()
        InboxBatchUpdate.apply(
            to: collectionView, section: cardsSectionIndex,
            removes: removes, inserts: inserts, animated: animated,
            commit: { [weak self] in
                commit()
                self?.lastSignature = signature
            },
            completion: { [weak self] in
                guard let self else { return }
                if !animated { self.restore(anchors, signature: signature) }
                self.refreshVisibleRowPositions()
                self.updateGate.end()
            }
        )
        if !animated { restore(anchors, signature: signature) }
    }

    /// Visible cards, topmost first, each with its distance from the top of
    /// the visible area.
    private func visibleAnchors(oldSignature: [String?]) -> [(url: String, offset: CGFloat)] {
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
            .map { ($0.url, $0.minY - collectionView.contentOffset.y) }
    }

    /// Puts the first anchor that survived back at its recorded place.
    private func restore(_ anchors: [(url: String, offset: CGFloat)], signature: [String?]) {
        guard !anchors.isEmpty else { return }
        collectionView.layoutIfNeeded()
        for anchor in anchors {
            guard let item = signature.firstIndex(where: { $0 == anchor.url }),
                  let frame = collectionView.layoutAttributesForItem(
                      at: IndexPath(item: item, section: cardsSectionIndex)
                  )?.frame
            else { continue }
            collectionView.contentOffset.y = frame.minY - anchor.offset
            return
        }
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
            let plan = InboxTrimPlanner.plan(count: self.episodes.count, keeping: settings.maxFeedEpisodes)
            // An import adds episodes the person has not seen the result of
            // yet: the Inbox waits until they tap Done.
            if plan.removesAnything, !InboxTrimHold.isHeld {
                let urls = self.episodes[plan.removedIndices].compactMap(\.enclosureUrl)
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
        guard let enclosureURL = episode.enclosureUrl, !enclosureURL.isEmpty else { return }
        let playlistId = ChannelPlaylistLogic.defaultPlaylistID
        let row = ChannelPlaylistLogic.playlistRow(from: episode, playlistId: playlistId)
        let steps = InboxActionPlanner.steps(
            for: action,
            currentPlaylistId: context.playback.currentPlaylistId,
            currentEnclosureURL: context.playback.currentEpisode?.enclosureUrl,
            episodeEnclosureURL: enclosureURL
        )
        // The fly-in origin must be captured from the tapped cell BEFORE
        // any step runs: the removal step deletes the row, so resolving the
        // cell at fly-in time would miss it — the ball leaves from where
        // the row was. The row's position is re-resolved by identity here,
        // too: the action closures capture configure-time index paths,
        // which go stale once an earlier animated removal shifts surviving
        // rows without reconfiguring them. The re-resolution TIGHTENS only
        // a list-surface caller's path: the Detail sheet passes nil, and
        // nil must come out nil — its add runs without the flight (the
        // landed Detail-action precedent,
        // ChannelEpisodeListBinder.detailActions). A list action whose row
        // vanished before firing (trim/refresh) also drops the flight —
        // the configure-time fallback would feed the layout a stale,
        // possibly out-of-range path.
        let flyInStart = Self.resolvedFlyInStart(
            actionPath: indexPath,
            identityPath: currentIndexPath(of: episode),
            in: collectionView,
            window: view.window
        )
        Task { [weak self] in
            var insertedRow = row
            for step in steps {
                guard let self else { return }
                switch step {
                case .flyInAnimation:
                    await self.runFlyIn(from: flyInStart)
                case .insertIntoPlaylist(let index):
                    let repository = self.context.database.playlistRepository()
                    try? await repository.insertOrUpdateByIndex(row, playlistId: playlistId, index: index)
                    if let stored = try? await repository.episode(byEnclosureURL: enclosureURL) {
                        insertedRow = stored
                    }
                case .skipInsertCurrentlyPlaying:
                    break
                case .removeFromInbox:
                    if steps == [.removeFromInbox] { Haptics.queueRemoved() }
                    await self.removeFromInbox(urls: [enclosureURL])
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
        window: UIWindow?
    ) -> CGPoint? {
        guard let actionPath, let identityPath else { return nil }
        return flyInOrigin(in: collectionView, at: identityPath, window: window)
    }

    /// The resolution core. The origin's X never comes from the item: a
    /// full leading swipe displaces the row toward the trailing edge, and
    /// at action time BOTH lookup layers report the displaced position
    /// (observed on device with the cell-center and the
    /// layout-attributes strategies). The resting X of a full-width row
    /// is the collection view's horizontal center, so the origin is the
    /// item's Y (list swipes translate horizontally only — Y is
    /// trustworthy) at the collection's center X. The path is guarded
    /// against the collection view's CURRENT counts before touching the
    /// layout: `layoutAttributesForItem` on a compositional section with
    /// an out-of-range index can assert where `cellForItem` would return
    /// nil.
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

    /// The row's CURRENT index path, resolved by identity (enclosure URL).
    /// Animated removals shift surviving rows without reconfiguring them,
    /// so the configure-time index paths captured in the action closures
    /// drift; every action funnels through `perform`, which re-resolves
    /// here — the context menu, the more pull-down, the swipe surfaces,
    /// and VoiceOver custom actions all stay consistent.
    private func currentIndexPath(of episode: FeedEpisodeRow) -> IndexPath? {
        guard let url = episode.enclosureUrl,
              let index = displayedEpisodes.firstIndex(where: { $0.enclosureUrl == url })
        else { return nil }
        return IndexPath(item: index, section: cardsSectionIndex)
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

    /// The removal side of every card action: database delete, in-memory
    /// removal, and an ANIMATED row deletion. `performBatchUpdates` keeps
    /// the surviving rows' measured attributes — the old no-animation
    /// `reloadData()` re-estimated every self-sizing card and the
    /// neighbors snapped. `renderList()` stays the bulk/full-refresh path
    /// (fetch, trim, category reselect); this list is strip-less, so no
    /// CardExpandCoordinator index needs closing before the mutation.
    private func removeFromInbox(urls: [String]) async {
        try? await context.database.feedRepository().removeByEnclosureUrls(urls)
        // One update at a time: wait out a diff or removal still animating.
        while updateGate.isBusy {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Everything is derived from the CURRENT data before any mutation:
        // the in-memory removal happens INSIDE the batch closure, right
        // before deleteItems — mutating the data source ahead of the batch
        // makes its counts report post-removal numbers, and a layout pass
        // in between (rotation, sheet dismissal, a pending reload) then
        // trips UIKit's item-count consistency check.
        let displayed = displayedEpisodes
        let cardsSection = cardsSectionIndex
        let removedPaths = displayed.indices.compactMap { index -> IndexPath? in
            guard let url = displayed[index].enclosureUrl, urls.contains(url) else { return nil }
            return IndexPath(item: index, section: cardsSection)
        }
        let displayedAfterRemoval = displayed.filter { row in
            guard let url = row.enclosureUrl else { return true }
            return !urls.contains(url)
        }
        // Animated deletion applies only while the rows were on screen AND
        // the column keeps its structure: emptying the displayed list
        // collapses every section into the ImportBlock empty state — that
        // structural rebuild goes through the plain path.
        guard view.window != nil, !removedPaths.isEmpty, !displayedAfterRemoval.isEmpty else {
            let remaining = episodes.filter { !($0.enclosureUrl.map(urls.contains) ?? false) }
            renderList(incoming: remaining) { self.episodes = remaining }
            return
        }
        updateGate.begin()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            collectionView.performBatchUpdates {
                self.episodes.removeAll { $0.enclosureUrl.map(urls.contains) ?? false }
                self.lastSignature = self.displayedEpisodes.map(\.enclosureUrl)
                self.collectionView.deleteItems(at: removedPaths)
            } completion: { _ in
                continuation.resume()
            }
        }
        // Post-completion state, not a cached one: a concurrent refresh may
        // have emptied the list while the delete animation ran.
        applyEmptyState()
        historyFooterButton.refresh(pageIsEmpty: displayedEpisodes.isEmpty, database: context.database)
        refreshChromeStatus()
        refreshVisibleRowPositions()
        updateGate.end()
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

    // MARK: - Detail (whole-card and cover tap, card.dart:129-138 + 09 §7a-C1)

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
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let kind = sectionKind(section) else { return 0 }
        switch kind {
        case .shelf, .strip, .tail:
            return 1
        case .cards:
            return displayedEpisodes.count
        }
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        switch sectionKind(indexPath.section) {
        case .shelf:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
            (cell as? ChromeHostingCell)?.host(shelf)
            return cell
        case .strip:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
            (cell as? ChromeHostingCell)?.host(categoryStrip)
            return cell
        case .cards:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: InboxEpisodeCardCell.reuseIdentifier,
                for: indexPath
            )
            if let card = cell as? InboxEpisodeCardCell,
               displayedEpisodes.indices.contains(indexPath.item) {
                configure(card: card, episode: displayedEpisodes[indexPath.item], at: indexPath)
            }
            return cell
        case .tail:
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HistoryTailCell.reuseIdentifier, for: indexPath
            )
            (cell as? HistoryTailCell)?.onOpenHistory = { [weak self] in
                self?.presentHistory()
            }
            return cell
        case nil:
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: ChromeHostingCell.reuseIdentifier, for: indexPath
            )
        }
    }

    private func configure(card: InboxEpisodeCardCell, episode: FeedEpisodeRow, at indexPath: IndexPath) {
        let content = InboxCardContent(
            title: episode.title ?? "",
            showName: episode.channelTitle ?? "",
            dateText: episode.pubDate.map { RelativeTimeFormatter.format($0) } ?? "",
            durationText: Self.durationText(for: episode),
            imageURL: episode.imageUrl,
            status: status(for: episode)
        )
        card.configure(content)
        card.setPosition(
            isFirst: indexPath.item == 0,
            isLast: indexPath.item == displayedEpisodes.count - 1
        )
        // The same payload feeds the long-press context menu and the
        // VoiceOver custom actions (09 §7a-C1).
        card.menuActions = actions(for: episode, at: indexPath)
        card.onCardTap = { [weak self] in
            self?.presentDetail(episode: episode)
        }
    }

    /// "44m" — the row's trailing duration; empty when unknown.
    static func durationText(for episode: FeedEpisodeRow) -> String {
        guard let duration = episode.duration, duration > 0 else { return "" }
        return TimeFormats.formatDuration(duration)
    }

    /// The first and last rows round the plate's corners and the first has
    /// no hairline, so rows that stayed through an insert or a removal
    /// re-resolve their place.
    private func refreshVisibleRowPositions() {
        let count = displayedEpisodes.count
        for indexPath in collectionView.indexPathsForVisibleItems
        where sectionKind(indexPath.section) == .cards {
            (collectionView.cellForItem(at: indexPath) as? InboxEpisodeCardCell)?
                .setPosition(isFirst: indexPath.item == 0, isLast: indexPath.item == count - 1)
        }
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

    /// The leading swipe surface (UI kit Inbox: swipe right to queue): Add
    /// to playlist through the same planner path as the menu entry.
    func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard sectionKind(indexPath.section) == .cards,
              displayedEpisodes.indices.contains(indexPath.item) else { return nil }
        let episode = displayedEpisodes[indexPath.item]
        let add = UIContextualAction(
            style: .normal, title: "Add to playlist",
            handler: { [weak self] _, _, completion in
                self?.perform(.addToPlaylist, episode: episode, at: indexPath)
                completion(true)
            }
        )
        add.image = AppIcons.addToList
        add.backgroundColor = AnycastColor.grass9
        return UISwipeActionsConfiguration(actions: [add])
    }

    /// The trailing swipe surface (09 §7a-C1 批次1): a single destructive
    /// Remove running the same planner path as the menu entry. Internal so
    /// the in-app regression suite can assert the wiring directly.
    func trailingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard sectionKind(indexPath.section) == .cards,
              displayedEpisodes.indices.contains(indexPath.item) else { return nil }
        let episode = displayedEpisodes[indexPath.item]
        let remove = UIContextualAction(
            style: .destructive, title: "Remove",
            handler: { [weak self] _, _, completion in
                // A list surface: pass the path (nil is reserved for the
                // Detail sheet's no-fly contract; remove has no flight
                // today, but the marker must stay truthful).
                self?.perform(.remove, episode: episode, at: indexPath)
                completion(true)
            }
        )
        remove.image = AppIcons.remove
        return UISwipeActionsConfiguration(actions: [remove])
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

/// The weak "history ›" capsule that closes the scroll column when the
/// inbox has cards. Not chrome: it sits in the list, after the cards.
final class HistoryTailCell: UICollectionViewCell {

    static let reuseIdentifier = "InboxHistoryTailCell"

    var onOpenHistory: (() -> Void)?

    private let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "history"
        configuration.image = AppIcons.disclosure
        configuration.imagePlacement = .trailing
        configuration.imagePadding = Spacing.xs
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            textStyle: TypographyV2.meta.scalingTextStyle
        )
        configuration.baseBackgroundColor = Theme.surfaceContainer
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.row, leading: Spacing.cardInner, bottom: Spacing.row, trailing: Spacing.cardInner
        )
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        button.configuration = configuration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "inbox-history-tail"
        button.accessibilityLabel = "history"
        button.addAction(
            UIAction { [weak self] _ in self?.onOpenHistory?() },
            for: .touchUpInside
        )
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.leadingAnchor, constant: Spacing.pageH
            ),
            button.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor, constant: -Spacing.pageH
            ),
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.gap),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: IconMetrics.minimumHit),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
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
