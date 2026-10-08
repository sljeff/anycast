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

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

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

/// The centered spinner-or-empty-state block hosted as the collection
/// background: 64 pt circle icon + title + message (+ optional action).
final class CollectionStateView: UIView {

    enum Kind {
        case loading
        case error
        case empty
    }

    private let iconCircle = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    init() {
        super.init(frame: .zero)
        iconCircle.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        iconCircle.layer.cornerRadius = 32
        iconCircle.layer.cornerCurve = .continuous
        iconCircle.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.addSubview(iconView)
        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        spinner.color = Theme.primary
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        iconCircle.addSubview(spinner)

        titleLabel.font = Typography.secondaryTitle.font()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        messageLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16))
        messageLabel.textColor = Theme.secondaryText
        messageLabel.textAlignment = .center
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        var actionConfiguration = UIButton.Configuration.plain()
        actionConfiguration.imagePadding = 8
        actionConfiguration.baseForegroundColor = Theme.primary
        actionConfiguration.contentInsets = .zero
        actionButton.configuration = actionConfiguration
        actionButton.titleLabel?.font = Typography.mainText.font()
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)

        let column = UIStackView(arrangedSubviews: [iconCircle, titleLabel, messageLabel, actionButton])
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
            iconView.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor),

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

    private var onAction: (() -> Void)?

    func configure(kind: Kind, action: (() -> Void)? = nil) {
        onAction = action
        switch kind {
        case .loading:
            iconView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimating()
            titleLabel.text = nil
            messageLabel.text = "Loading subscriptions…"
            actionButton.isHidden = true
        case .error:
            iconView.isHidden = false
            spinner.stopAnimating()
            iconView.tintColor = Theme.primary
            iconView.image = UIImage(systemName: "icloud.slash")
            titleLabel.text = "Couldn’t load subscriptions"
            messageLabel.text = "Check the local library and try again."
            if action != nil {
                actionButton.isHidden = false
                actionButton.setImage(
                    UIImage(systemName: "arrow.clockwise"), for: .normal
                )
                actionButton.setTitle("Try again", for: .normal)
            } else {
                actionButton.isHidden = true
            }
        case .empty:
            iconView.isHidden = false
            spinner.stopAnimating()
            iconView.tintColor = Theme.primary
            iconView.image = UIImage(systemName: "music.note.list")
            titleLabel.text = "No subscriptions yet"
            messageLabel.text = "Follow a podcast to keep it close at hand."
            actionButton.isHidden = true
        }
    }
}
