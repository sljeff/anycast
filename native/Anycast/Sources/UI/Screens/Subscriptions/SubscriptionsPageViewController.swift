import UIKit
import AnycastKit

/// Tab0 Subscriptions page (lib/pages/subscriptions.dart, 03 §2.4): the
/// PodcastCard list of subscriptions; tapping any card opens the Channel
/// sheet (card.dart:330-342). No pull-to-refresh (03 §3.3). The four visual
/// states (loading / error / empty / content) follow the Dart
/// anycastCollectionVisualState mapping.
final class SubscriptionsPageViewController: UIViewController {

    /// Posted by the Inbox refresh after subscription batch writes — the
    /// resident page reloads (the Obx reactivity equivalent).
    static let subscriptionsDidChange = Notification.Name("AnycastSubscriptionsDidChange")

    private let context: UIContext

    private var subscriptions: [SubscriptionRow] = []
    private var isLoading = true
    private var loadError: String?
    private var lastSignature: [String] = []

    private let collectionView: UICollectionView
    private let stateView = CollectionStateView()
    private var notificationObserver: NSObjectProtocol?

    init(context: UIContext) {
        self.context = context
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(PodcastCardCell.cardHeight)
                )
            )
            // v2 page margin (16) — same correction as the Inbox list: the
            // v1 24 pt inset clashed with the 16 pt grid the header and
            // membership card use above this embedded list.
            item.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: Spacing.pageH, bottom: 0, trailing: Spacing.pageH
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: item.layoutSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = PodcastCardCell.spacing
            // Zero bottom inset (09 §10 决策⑥): same double-counted v1
            // clearance as the Inbox list — the shell's
            // additionalSafeAreaInsets owns the chrome avoidance now.
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)
            return section
        }
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // No deinit observer removal: the observer closure holds self weakly and
    // the page is resident for the whole session (the shell prewarms it).

    // MARK: - Lifecycle

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.alignBackgroundViewMargins()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.register(
            PodcastCardCell.self,
            forCellWithReuseIdentifier: PodcastCardCell.reuseIdentifier
        )
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        notificationObserver = NotificationCenter.default.addObserver(
            forName: Self.subscriptionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startLoad() }
        }

        startLoad()
    }

    /// Returning from a Channel sheet (subscribe/unsubscribe writes the
    /// repository directly) refreshes the list — quietly: rows are already
    /// on screen, so the reload must not bounce through the loading state
    /// (which clears the list and loses the scroll position even when the
    /// rows come back identical).
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !isLoading else { return }   // first appear already loading
        startLoad(keepingContent: true)
    }

    // MARK: - Load (states/subscription.dart:52-67)

    /// Monotonic: an older overlapping DB read must never overwrite a newer
    /// reload's rows (same ruling as
    /// PlaylistEpisodeListViewController.reloadEpisodes).
    private var loadGeneration = 0

    /// `keepingContent`: skip the initial loading-state render — used by the
    /// appear-refresh, where flipping to `.loading` would clear the shown
    /// list (flicker + scroll reset) only to redraw the same rows.
    private func startLoad(keepingContent: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        Task { [weak self] in
            guard let self else { return }
            if !keepingContent {
                self.isLoading = true
                self.loadError = nil
                self.render()
            }
            do {
                let subscriptions = try await self.context.database.subscriptionRepository().listAll()
                guard generation == self.loadGeneration else { return }
                self.subscriptions = subscriptions
                // The quiet path skips the initial reset — a successful read
                // must still retire a stale error from an earlier load.
                self.loadError = nil
            } catch {
                guard generation == self.loadGeneration else { return }
                self.loadError = "Unable to load subscriptions."
                self.subscriptions = []
            }
            self.isLoading = false
            self.render()
        }
    }

    private var visualState: SubscriptionsVisualState {
        SubscriptionsVisualState.state(
            isLoading: isLoading,
            hasError: loadError != nil,
            isEmpty: subscriptions.isEmpty
        )
    }

    /// Plain no-animation rebuild (08 §7.2 — the Flutter Obx rebuild). The
    /// collection background renders BEHIND cells, so non-content states
    /// also empty the data source (the state block fully replaces the list,
    /// like the Dart switch).
    private func render() {
        switch visualState {
        case .loading:
            stateView.configure(kind: .loading)
            collectionView.backgroundView = stateView
            clearListIfShown()
            return
        case .error:
            stateView.configure(kind: .error) { [weak self] in
                self?.startLoad()   // "Try again" (controller.load)
            }
            collectionView.backgroundView = stateView
            clearListIfShown()
            return
        case .empty:
            stateView.configure(kind: .empty)
            collectionView.backgroundView = stateView
            clearListIfShown()
            return
        case .content:
            break
        }

        collectionView.backgroundView = nil
        let signature = Self.renderSignature(subscriptions)
        if signature != lastSignature {
            lastSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
        }
    }

    /// Metadata-aware reload gate: an inbox refresh INSERT-OR-REPLACEs
    /// existing rows in place — same URL list, new title/cover/lastUpdated —
    /// so a URL-only signature would keep stale cards on screen.
    static func renderSignature(_ rows: [SubscriptionRow]) -> [String] {
        rows.map {
            "\($0.rssFeedUrl ?? "")|\($0.title ?? "")|\($0.description ?? "")|\($0.imageUrl ?? "")|\($0.lastUpdated.map(String.init) ?? "")"
        }
    }

    private func clearListIfShown() {
        guard lastSignature != [] else { return }
        lastSignature = []
        UIView.performWithoutAnimation {
            collectionView.reloadData()
        }
    }
}

// MARK: - Data source

extension SubscriptionsPageViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visualState == .content ? subscriptions.count : 0
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PodcastCardCell.reuseIdentifier,
            for: indexPath
        )
        if let card = cell as? PodcastCardCell, subscriptions.indices.contains(indexPath.item) {
            let subscription = subscriptions[indexPath.item]
            card.configure(PodcastCardContent(
                rssFeedURL: subscription.rssFeedUrl ?? "",
                title: subscription.title ?? "",
                description: subscription.description ?? "",
                imageURL: subscription.imageUrl
            ))
            card.onTap = { [weak self] content in
                guard let self else { return }
                ChannelViewController.present(
                    from: self,
                    context: self.context,
                    rssFeedURL: content.rssFeedURL,
                    seed: subscription
                )
            }
        }
        return cell
    }
}

// MARK: - Visual state mapping (anycastCollectionVisualState port)

/// Loading wins over error wins over empty (anycast_components.dart:146-161).
enum SubscriptionsVisualState: Equatable {
    case loading
    case error
    case empty
    case content

    static func state(isLoading: Bool, hasError: Bool, isEmpty: Bool) -> SubscriptionsVisualState {
        if isLoading { return .loading }
        if hasError { return .error }
        if isEmpty { return .empty }
        return .content
    }
}

// MARK: - State views (AnycastLoadingState / AnycastEmptyState)

/// The Subscriptions loading / error / empty block on the shared
/// `EmptyStateView`, hosted as the collection background.
final class CollectionStateView: EmptyStateView {

    enum Kind {
        case loading
        case error
        case empty
    }

    private var onAction: (() -> Void)?

    func configure(kind: Kind, action: (() -> Void)? = nil) {
        onAction = action
        switch kind {
        case .loading:
            configure(Content(showsSpinner: true, message: "Loading subscriptions…"))
        case .error:
            var actions: [UIView] = []
            if action != nil {
                let retry = AnycastButton.make(.secondary, title: "Try again", image: UIImage(systemName: "arrow.clockwise"))
                retry.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
                actions.append(retry)
            }
            configure(Content(
                icon: UIImage(systemName: "icloud.slash"),
                title: "Couldn’t load subscriptions",
                message: "Check the local library and try again.",
                actions: actions
            ))
        case .empty:
            configure(Content(
                icon: UIImage(systemName: "music.note.list"),
                title: "No subscriptions yet",
                message: "Follow a podcast to keep it close at hand."
            ))
        }
    }
}
