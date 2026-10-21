import UIKit
import Kingfisher
import AnycastKit

/// The Channel sheet (lib/pages/channel.dart, 03 §2.7): a full-height expand
/// sheet whose pinned header folds while the episode list scrolls under it.
///
/// Fold architecture (07 §2.3, 08 §11.2): compositional layout with a
/// `pinToVisibleBounds` boundary supplementary of the EXPANDED height; the
/// scroll-driven interpolation only touches layer geometry (gradient layer
/// frame, view frames/transforms, the content clip) — never per-tick Auto Layout. The
/// supplementary's transparent tail below the current fold height passes
/// touches through to the cells scrolling beneath it.
///
/// Data: the view model is cached per rssFeedURL in `ChannelSessionStore`
/// for the whole session — same-session reopen reuses it without refetch
/// (K34, 05 §11). The default `init(context:)` resolves the channel of the
/// CURRENT episode (the player's jumpToChannel path, player.dart:401-410).
@MainActor
final class ChannelViewController: UIViewController {

    static let headerElementKind = "ChannelPinnedHeader"

    private let context: UIContext
    private let configuredRSSFeedURL: String?
    private let configuredSeed: SubscriptionRow?

    private var viewModel: ChannelViewModel?

    private let collectionView: UICollectionView
    private let playerBar: PlayerBarView
    private let playerBarHeight: NSLayoutConstraint
    private let episodeListSpinner = UIActivityIndicatorView(style: .large)
    private let fullPageSpinner = UIActivityIndicatorView(style: .large)
    private let emptyChannelLabel = UILabel()

    private let expandCoordinator = CardExpandCoordinator()
    private var binder: ChannelEpisodeListBinder?
    private let htmlRenderer = HTMLContentRenderer()

    private var headerView: ChannelHeaderView?
    private var appliedSafeAreaTop: CGFloat = -1
    /// Measured height of the header's content block (see
    /// `ChannelHeaderView.onContentHeightChange`).
    private var contentBlockHeight = ChannelFoldGeometry.fallbackContentHeight
    private var lastEpisodeSignature: [String?] = []

    private let modelObservation = ObservationLoop()
    private let playbackObservation = ObservationLoop()

    // MARK: - Construction (presenters keep the `init(context:)` name)

    init(context: UIContext) {
        self.context = context
        self.configuredRSSFeedURL = nil
        self.configuredSeed = nil
        (collectionView, playerBar, playerBarHeight) = Self.makeCoreViews(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    init(context: UIContext, rssFeedURL: String, seed: SubscriptionRow? = nil) {
        self.context = context
        self.configuredRSSFeedURL = rssFeedURL
        self.configuredSeed = seed
        (collectionView, playerBar, playerBarHeight) = Self.makeCoreViews(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Present factory used by the card/detail paths (card.dart:311-318).
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        rssFeedURL: String,
        seed: SubscriptionRow? = nil
    ) {
        let controller = ChannelViewController(context: context, rssFeedURL: rssFeedURL, seed: seed)
        AppSheets.presentExpand(controller, from: presenter)
    }

    private static func makeCoreViews(context: UIContext) -> (UICollectionView, PlayerBarView, NSLayoutConstraint) {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive
        if #available(iOS 26.0, *) {
            // The pinned header automatically gets a progressive-blur scroll
            // edge effect on iOS 26+ — the Dart design scrolls cells under
            // the transparent tail plainly, so disable it.
            collectionView.topEdgeEffect.isHidden = true
        }
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        // The v2 capsule mini player (sand pill, round cover, single title
        // line) — the same chrome as the shell's capsule language.
        let playerBar = context.makePlayerBar(style: .capsule)
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        let height = playerBar.heightAnchor.constraint(equalToConstant: 58)

        return (collectionView, playerBar, height)
    }

    /// The first non-empty episode list rises in once per instance
    /// (`CardEntranceAnimator`); later reloads never replay it.
    private var didPlayEntrance = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        sheetPresentationController?.prefersGrabberVisible = true

        buildViewHierarchy()
        resolveChannel()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)

        modelObservation.track(
            read: { [weak self] in
                guard let self, let viewModel = self.viewModel else { return }
                _ = viewModel.channel
                _ = viewModel.episodes
                _ = viewModel.isLoading
                _ = viewModel.subscribed
                _ = viewModel.subscriptionChecked
                _ = viewModel.dominantColor
                _ = viewModel.isReversed
            },
            onChange: { [weak self] in self?.render() }
        )
        playbackObservation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.context.playback.currentEpisode
            },
            onChange: { [weak self] in self?.renderPlayerBar() }
        )
        // Initial frame for the cached-VM (K34) path — ObservationLoop does
        // not fire for an unchanged read, so without this the player bar
        // kept its default-visible state until the first playback change.
        render()
        renderPlayerBar()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateListBottomInset()
        rebuildForGeometryChange()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.safeAreaInsets.top != appliedSafeAreaTop {
            rebuildForGeometryChange()
        }
        applyFold()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        binder?.refreshPlaylistMembership()
        playEntranceIfNeeded()
    }

    // MARK: - Build

    private func buildViewHierarchy() {
        view.addSubview(collectionView)
        view.addSubview(playerBar)

        // Scrim behind the capsule so rows are not hard-cut by it (G-7).
        let bottomFade = ScrollEdgeFade(edge: .bottom)
        view.insertSubview(bottomFade, belowSubview: playerBar)

        episodeListSpinner.color = Theme.primary
        episodeListSpinner.hidesWhenStopped = true
        episodeListSpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodeListSpinner)

        fullPageSpinner.color = Theme.primary
        fullPageSpinner.hidesWhenStopped = true
        fullPageSpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fullPageSpinner)

        emptyChannelLabel.text = "No channel"
        emptyChannelLabel.textColor = Theme.onSurfaceVariant
        emptyChannelLabel.font = TypographyV2.headlineSmall.font()
        emptyChannelLabel.isHidden = true
        emptyChannelLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyChannelLabel)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            // Runs under the floating capsule; `updateListBottomInset()`
            // keeps the last row clear of it.
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Floating capsule: page-grid side margins, 16 pt clear of the
            // safe-area bottom.
            playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            playerBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.xs
            ),
            playerBarHeight,

            bottomFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomFade.topAnchor.constraint(
                equalTo: playerBar.topAnchor, constant: -ScrollEdgeFade.fadeLength
            ),

            episodeListSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            episodeListSpinner.centerYAnchor.constraint(
                equalTo: collectionView.centerYAnchor, constant: 100
            ),

            fullPageSpinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fullPageSpinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyChannelLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyChannelLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EpisodeCardCell.self, forCellWithReuseIdentifier: EpisodeCardCell.reuseIdentifier)
        collectionView.register(
            ChannelBodyHeaderCell.self,
            forCellWithReuseIdentifier: ChannelBodyHeaderCell.reuseIdentifier
        )
        collectionView.register(
            ChannelHeaderView.self,
            forSupplementaryViewOfKind: Self.headerElementKind,
            withReuseIdentifier: Self.headerElementKind
        )
    }

    /// Resolves the channel input: explicit URL, else the current episode's
    /// channel (the player path — player.dart jumpToChannel seeds a minimal
    /// subscription when the DB has none).
    private func resolveChannel() {
        let rssFeedURL: String
        if let configured = configuredRSSFeedURL {
            rssFeedURL = configured
        } else if let episode = context.playback.currentEpisode,
                  let rss = episode.rssFeedUrl, !rss.isEmpty {
            rssFeedURL = rss
        } else {
            emptyChannelLabel.isHidden = false
            return
        }

        var seed = configuredSeed
        if seed == nil, let episode = context.playback.currentEpisode, episode.rssFeedUrl == rssFeedURL {
            seed = SubscriptionRow(
                rssFeedUrl: rssFeedURL,
                title: episode.channelTitle,
                imageUrl: episode.imageUrl
            )
        }

        let entry = ChannelSessionStore.shared.entry(context: context, rssFeedURL: rssFeedURL, seed: seed)
        viewModel = entry.model
        let binder = ChannelEpisodeListBinder(
            owner: self,
            context: context,
            viewModel: entry.model,
            htmlRenderer: htmlRenderer,
            expandCoordinator: expandCoordinator
        )
        binder.onListContentChanged = { [weak self] in self?.refreshVisibleCards() }
        binder.collectionView = collectionView
        binder.startObservingPlayback()
        self.binder = binder

        if entry.isNew {
            let model = entry.model
            Task { await model.prepare() }
        }
    }

    // MARK: - Geometry (safe-area driven; any window size)

    private var foldGeometry: ChannelFoldGeometry {
        ChannelFoldGeometry(safeAreaTop: view.safeAreaInsets.top, contentHeight: contentBlockHeight)
    }

    /// The pinned supplementary's absolute height tracks the current safe
    /// area and the measured content block; extents never use fixed status
    /// bar numbers.
    private func rebuildForGeometryChange() {
        appliedSafeAreaTop = view.safeAreaInsets.top
        headerView?.updateGeometry(foldGeometry)
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        applyFold()
    }

    /// Called from the header's layout pass, so the layout rebuild is
    /// deferred; a stable measurement stops the loop.
    private func contentHeightMeasured(_ height: CGFloat) {
        guard abs(height - contentBlockHeight) > 0.5 else { return }
        contentBlockHeight = height
        DispatchQueue.main.async { [weak self] in self?.rebuildForGeometryChange() }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let maxExtent = foldGeometry.maxExtent
        return UICollectionViewCompositionalLayout { [weak self] _, _ in
            guard let self else { return nil }
            // ONE section hosts everything: the pinned boundary supplementary
            // only pins while its host section is on screen, so the header
            // must belong to the section that spans the whole list. Item 0 is
            // the order/search row; the rest are episode cards.
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(EpisodeCardCell.cardRowHeight)
                )
            )
            // Horizontal margins live on the ITEM — section content insets
            // would also inset the pinned supplementary.
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = EpisodeCardCell.spacing
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(maxExtent)
                ),
                elementKind: Self.headerElementKind,
                alignment: .top
            )
            header.pinToVisibleBounds = true
            section.boundarySupplementaryItems = [header]
            return section
        }
    }

    // MARK: - Rendering

    private func render() {
        guard let viewModel else { return }

        // Full-page spinner gate (channel.dart:47-49).
        if viewModel.hasTitle {
            fullPageSpinner.stopAnimating()
        } else {
            fullPageSpinner.startAnimating()
        }

        headerView?.configure(
            channel: viewModel.channel,
            display: subscriptionDisplay,
            latestEpisodeLoading: viewModel.isLoading,
            dominant: viewModel.dominantColor
        )

        // Plain no-animation rebuild (08 §7.2 — the Flutter Obx rebuild).
        let signature = viewModel.showEpisodes.map(\.enclosureUrl)
        if signature != lastEpisodeSignature {
            lastEpisodeSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
            refreshVisibleCards()
            playEntranceIfNeeded()
        }

        // Dart gates the whole page on the title (channel.dart:47-49): while
        // the full-page spinner shows, the list spinner must not — one
        // loading affordance at a time.
        let showListSpinner = viewModel.episodes.isEmpty && viewModel.isLoading && viewModel.hasTitle
        episodeListSpinner.isHidden = !showListSpinner
        if showListSpinner {
            episodeListSpinner.startAnimating()
        } else {
            episodeListSpinner.stopAnimating()
        }

        renderPlayerBar()
    }

    /// Plays the entrance right after the list was applied. A sheet applies
    /// cached data in `viewDidLoad`, before it is in a window (no layout,
    /// nothing to animate), so that case is retried from `viewDidAppear`.
    private func playEntranceIfNeeded() {
        guard !didPlayEntrance, view.window != nil,
              let viewModel, !viewModel.showEpisodes.isEmpty else { return }
        didPlayEntrance = true
        CardEntranceAnimator.play(in: collectionView)
    }

    private var subscriptionDisplay: ChannelSubscriptionDisplay {
        guard let viewModel else { return .loading }
        return ChannelSubscriptionDisplay.display(
            subscribed: viewModel.subscribed,
            subscriptionChecked: viewModel.subscriptionChecked,
            hasTitle: viewModel.hasTitle
        )
    }

    /// PlayerBar(bottomSafe: true) — a shrink when nothing plays
    /// (bottom_nav_bar.dart:86-88).
    private func renderPlayerBar() {
        let visible = context.playback.currentEpisode != nil
        playerBar.isHidden = !visible
        playerBarHeight.constant = visible ? 58 : 0
        updateListBottomInset()
    }

    /// The list runs under the floating capsule (and the home indicator),
    /// so the last row needs the bar's footprint as bottom content inset.
    /// Only the bottom changes — the pinned header and fold geometry key off
    /// the top.
    private func updateListBottomInset() {
        let playerVisible = context.playback.currentEpisode != nil
        let clearance = playerVisible
            ? PlayerBarView.barHeight + Spacing.xs + Spacing.pageH
            : Spacing.pageH
        let bottom = view.safeAreaInsets.bottom + clearance
        collectionView.contentInset.bottom = bottom
        collectionView.verticalScrollIndicatorInsets.bottom = bottom
    }

    private func refreshVisibleCards() {
        guard let viewModel else { return }
        for path in collectionView.indexPathsForVisibleItems {
            if path.item == 0 {
                if let cell = collectionView.cellForItem(at: path) as? ChannelBodyHeaderCell {
                    cell.setOrder(reversed: viewModel.isReversed)
                }
            } else if viewModel.showEpisodes.indices.contains(path.item - 1),
                      let cell = collectionView.cellForItem(at: path) as? EpisodeCardCell {
                binder?.configure(
                    cell: cell,
                    episode: viewModel.showEpisodes[path.item - 1],
                    at: path,
                    in: collectionView
                )
            }
        }
    }

    // MARK: - Fold

    private func applyFold() {
        headerView?.applyFold(shrink: collectionView.contentOffset.y, geo: foldGeometry)
    }

    // MARK: - Actions

    /// Subscribe applies immediately; unsubscribing asks first.
    fileprivate func subscriptionTapped(_ sender: UIView) {
        guard let viewModel else { return }
        switch subscriptionDisplay {
        case .loading:
            return
        case .subscribe:
            Task { await viewModel.subscribe() }
        case .unsubscribe:
            let alert = UIAlertController(
                title: "Unsubscribe from \(viewModel.channel.title ?? "this show")?",
                message: nil,
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "Unsubscribe", style: .destructive) { _ in
                Task { await viewModel.unsubscribe() }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.popoverPresentationController?.sourceView = sender
            alert.popoverPresentationController?.sourceRect = sender.bounds
            present(alert, animated: true)
        }
    }

    /// Copy the RSS URL + 1 s toast (channel.dart:454-474).
    fileprivate func copyRSSTapped() {
        guard let viewModel else { return }
        UIPasteboard.general.string = viewModel.rssFeedURL
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let window = view.window {
            ToastPresenter.shared.show("Copied", in: window, duration: 1.0)
        }
    }

    /// Play episodes[0] — the un-reversed first episode; guarded against
    /// the empty list (the Dart `episodes[0]` crash, K4 family).
    fileprivate func latestEpisodeTapped() {
        guard let viewModel, !viewModel.isLoading, let first = viewModel.episodes.first else { return }
        Task { [weak binder] in
            guard let row = await binder?.addToTop(first) else { return }
            await self.context.playback.playByEpisode(row)
        }
    }

    /// Spinner → /api/shortlink → system share panel with "title\nurl"
    /// (channel.dart:376-411; shortlink failure degrades to the long URL).
    fileprivate func shareTapped(_ sender: UIView) {
        guard let viewModel,
              let shareURL = URL(string: ShareURL.channel(rssFeedURL: viewModel.rssFeedURL))
        else { return }
        let title = viewModel.channel.title ?? ""

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = Theme.onSurface
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        sender.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: sender.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sender.centerYAnchor),
        ])

        Task { [weak self] in
            let short = await self?.context.api.getShortURL(for: shareURL) ?? shareURL
            spinner.stopAnimating()
            spinner.removeFromSuperview()
            guard let self else { return }
            let activity = UIActivityViewController(
                activityItems: ["\(title)\n\(short.absoluteString)"],
                applicationActivities: nil
            )
            self.present(activity, animated: true)
        }
    }
}

// MARK: - UICollectionViewDataSource / Delegate

extension ChannelViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        1 + (viewModel?.showEpisodes.count ?? 0)
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if indexPath.item == 0 {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ChannelBodyHeaderCell.reuseIdentifier, for: indexPath
            ) as! ChannelBodyHeaderCell
            cell.onSearch = { [weak self] in
                guard let self, let viewModel = self.viewModel else { return }
                // The search sheet owns the query field; it opens empty.
                ChannelSearchViewController.present(
                    from: self,
                    context: self.context,
                    rssFeedURL: viewModel.rssFeedURL,
                    searchText: ""
                )
            }
            cell.onOrderSelect = { [weak self] index in
                guard let self, let viewModel = self.viewModel else { return }
                let reversed = ChannelOrderMapping.isReversed(selectedIndex: index)
                guard viewModel.isReversed != reversed else { return }
                viewModel.isReversed = reversed
            }
            cell.setOrder(reversed: viewModel?.isReversed ?? false)
            return cell
        }

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: EpisodeCardCell.reuseIdentifier, for: indexPath
        ) as! EpisodeCardCell
        if let viewModel, viewModel.showEpisodes.indices.contains(indexPath.item - 1) {
            binder?.configure(
                cell: cell,
                episode: viewModel.showEpisodes[indexPath.item - 1],
                at: indexPath,
                in: collectionView
            )
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: elementKind,
            withReuseIdentifier: Self.headerElementKind,
            for: indexPath
        ) as! ChannelHeaderView
        headerView = view
        view.updateGeometry(foldGeometry)
        view.onContentHeightChange = { [weak self] height in self?.contentHeightMeasured(height) }
        view.actions = .init(
            onShare: { [weak self] sender in self?.shareTapped(sender) },
            onSubscriptionTap: { [weak self] sender in self?.subscriptionTapped(sender) },
            onCopyRSS: { [weak self] in self?.copyRSSTapped() },
            onLatestEpisode: { [weak self] in self?.latestEpisodeTapped() }
        )
        if let viewModel {
            view.configure(
                channel: viewModel.channel,
                display: subscriptionDisplay,
                latestEpisodeLoading: viewModel.isLoading,
                dominant: viewModel.dominantColor
            )
        }
        applyFold()
        return view
    }

    // MARK: UIScrollViewDelegate (the fold driver — 08 §11.2)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        applyFold()
    }
}

// MARK: - Subscribe toggle presentation

extension ChannelSubscriptionDisplay {

    /// Outline bookmark = not subscribed, filled = subscribed; the loading
    /// state keeps the outline (dimmed and disabled by the button).
    var toggleIcon: UIImage {
        self == .unsubscribe ? AppIcons.subscribed : AppIcons.subscribe
    }

    /// "Subscribing" while the state is unknown keeps the loading state
    /// addressable for UI tests.
    var toggleAccessibilityLabel: String {
        switch self {
        case .loading: "Subscribing"
        case .subscribe: "Subscribe"
        case .unsubscribe: "Unsubscribe"
        }
    }
}

// MARK: - Pinned header (channel.dart:248-541)

/// The pinned supplementary: gradient background layer (dominant → page
/// dark), the cover/title that collapse into a compact bar, and the content
/// block (author, description, action row) that scrolls up under that bar
/// inside a clipping container. The fold only touches frames, transforms and
/// the clip — never per-tick Auto Layout. Below the current fold height the
/// view is transparent and passes touches through to the list scrolling
/// beneath.
@MainActor
final class ChannelHeaderView: UICollectionReusableView {

    struct Actions {
        var onShare: (UIView) -> Void
        var onSubscriptionTap: (UIView) -> Void
        var onCopyRSS: () -> Void
        var onLatestEpisode: () -> Void
    }

    var actions: Actions?
    /// Reports the measured height of the content block so the controller
    /// can size the pinned supplementary to it.
    var onContentHeightChange: ((CGFloat) -> Void)?

    private let gradientLayer = CAGradientLayer()
    /// Hangs below the gradient's bottom edge so scrolled rows fade in under
    /// the pinned header instead of being hard-cut (G-7); positioned by a
    /// transform in `applyFold` like the rest of the fold.
    private let bottomFade = ScrollEdgeFade(edge: .top)
    /// Dominant color last applied to the header gradient (re-applied on
    /// trait flips).
    private var headerDominant: UIColor = ChannelViewModel.playerWarmColor
    private let subscribeButton = AnycastIconButton(
        style: .tonal, icon: AppIcons.subscribe, accessibilityLabel: "Subscribe"
    )
    private let shareButton = AnycastIconButton(
        style: .tonal, icon: AppIcons.share, accessibilityLabel: "Share"
    )
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    /// Clips the content block at the compact bar's bottom line; its top
    /// 16 pt fade out through the mask.
    private let contentClip = UIView()
    private let contentFadeMask = CAGradientLayer()
    private let contentStack = UIStackView()
    private let authorLabel = UILabel()
    private let descriptionText = ExpandableText(text: "", style: .defaultText, maxLines: 2)
    private let latestButton = UIButton(type: .custom)

    private var passthroughY: CGFloat = .greatestFiniteMagnitude
    /// Last applied fold inputs — replayed on layout passes.
    private var foldShrink: CGFloat = 0
    private var foldGeometryValue = ChannelFoldGeometry(safeAreaTop: 0)
    private var measuredContentHeight: CGFloat?
    private var contentMeasureKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        measureContentIfNeeded()
        // Keep the gradient layer frame in sync with bounds + safe area
        // without touching constraints.
        applyFold(shrink: foldShrink, geo: foldGeometryValue)
    }

    func updateGeometry(_ geo: ChannelFoldGeometry) {
        layoutMargins.top = geo.safeAreaTop
        foldGeometryValue = geo
        applyFold(shrink: foldShrink, geo: foldGeometryValue)
    }

    // MARK: Build (channel.dart:343-547)

    private func build() {
        layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)

        applyHeaderGradient(dominant: ChannelViewModel.playerWarmColor)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)

        addSubview(bottomFade)
        NSLayoutConstraint.activate([
            bottomFade.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomFade.topAnchor.constraint(equalTo: topAnchor),
            bottomFade.heightAnchor.constraint(equalToConstant: ScrollEdgeFade.fadeLength),
        ])

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Channel artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false

        // titleLarge, 2 lines (03 §2.7). Frame-driven by `applyFold`: it
        // starts centered under the cover and ends left-aligned beside it.
        titleLabel.font = TypographyV2.titleLarge.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        authorLabel.font = TypographyV2.bodyLarge.font()
        authorLabel.textColor = Theme.onSurface
        authorLabel.textAlignment = .center
        authorLabel.adjustsFontForContentSizeCategory = true

        // The description sits directly on the header — no tinted plate.
        descriptionText.showsTruncatedPlate = false
        descriptionText.layoutMargins = .zero

        subscribeButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.actions?.onSubscriptionTap(self.subscribeButton)
            },
            for: .touchUpInside
        )

        latestButton.configuration = latestConfiguration(loading: false)
        latestButton.addPressFeedback(scale: Motion.pressScaleSubtle)
        latestButton.isAccessibilityElement = true
        latestButton.accessibilityLabel = "Play latest episode"
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.addAction(
            UIAction { [weak self] _ in self?.actions?.onLatestEpisode() }, for: .touchUpInside
        )

        shareButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                self.actions?.onShare(self.shareButton)
            },
            for: .touchUpInside
        )
        // Long press keeps the old domain button's job: copy the RSS URL.
        shareButton.menu = UIMenu(children: [
            UIAction(title: "Copy RSS URL", image: AppIcons.copy) { [weak self] _ in
                self?.actions?.onCopyRSS()
            },
        ])
        shareButton.showsMenuAsPrimaryAction = false
        shareButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Copy RSS URL") { [weak self] _ in
                self?.actions?.onCopyRSS()
                return true
            },
        ]

        let actionRow = UIStackView(arrangedSubviews: [subscribeButton, latestButton, shareButton])
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = Spacing.gap
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        let actionHost = UIView()
        actionHost.addSubview(actionRow)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 12
        contentStack.addArrangedSubview(authorLabel)
        contentStack.addArrangedSubview(descriptionText)
        contentStack.addArrangedSubview(actionHost)

        contentClip.clipsToBounds = true
        contentFadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        contentFadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        contentFadeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        contentClip.layer.mask = contentFadeMask
        contentClip.addSubview(contentStack)

        addSubview(titleLabel)
        addSubview(contentClip)
        // Cover LAST — it draws over the title during the fold (the Dart
        // Stack paints the Positioned cover above the column).
        addSubview(coverView)

        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(
                equalTo: layoutMarginsGuide.topAnchor, constant: ChannelFoldGeometry.coverTopGap
            ),
            coverView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            coverView.widthAnchor.constraint(equalToConstant: ChannelFoldGeometry.expandedCoverSize),
            coverView.heightAnchor.constraint(equalToConstant: ChannelFoldGeometry.expandedCoverSize),

            actionRow.topAnchor.constraint(equalTo: actionHost.topAnchor),
            actionRow.bottomAnchor.constraint(equalTo: actionHost.bottomAnchor),
            actionRow.centerXAnchor.constraint(equalTo: actionHost.centerXAnchor),
            actionRow.leadingAnchor.constraint(greaterThanOrEqualTo: actionHost.leadingAnchor),

            latestButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AnycastIconButton.standardDiameter),
        ])
    }

    /// The shared primary capsule; while the feed loads it shows the
    /// configuration's own activity indicator in place of the glyph.
    private func latestConfiguration(loading: Bool) -> UIButton.Configuration {
        var configuration = AnycastButton.configuration(.primary, title: "Latest Episode", image: AppIcons.play)
        configuration.showsActivityIndicator = loading
        return configuration
    }

    // MARK: Configure

    func configure(
        channel: SubscriptionRow,
        display: ChannelSubscriptionDisplay,
        latestEpisodeLoading: Bool,
        dominant: UIColor
    ) {
        coverView.kf.cancelDownloadTask()
        let imageURL = channel.imageUrl.flatMap(URL.init(string:))
            ?? URL(string: "https://placeholder.co/120.png?text=Waiting")
        coverView.kf.setImage(with: imageURL, placeholder: nil, options: [.transition(.none)])

        titleLabel.text = channel.title ?? ""
        authorLabel.text = channel.author ?? "Unknown"
        descriptionText.text = DisplayText.plainText(fromHTML: channel.description ?? "No description")

        subscribeButton.setIcon(display.toggleIcon)
        subscribeButton.configuration?.baseForegroundColor =
            display == .unsubscribe ? Theme.primary : Theme.onSurface
        subscribeButton.accessibilityLabel = display.toggleAccessibilityLabel
        subscribeButton.isEnabled = display != .loading
        subscribeButton.alpha = display == .loading ? 0.5 : 1
        latestButton.configuration = latestConfiguration(loading: latestEpisodeLoading)

        applyHeaderGradient(dominant: dominant)
        measureContentIfNeeded()
        setNeedsLayout()
    }

    /// Measures the content block at the header width and reports changes;
    /// the key keeps per-layout-pass calls cheap.
    private func measureContentIfNeeded() {
        let width = bounds.width - layoutMargins.left - layoutMargins.right
        guard width > 0 else { return }
        let key = "\(width)|\(authorLabel.text ?? "")|\(descriptionText.text)"
            + "|\(traitCollection.preferredContentSizeCategory.rawValue)"
        guard key != contentMeasureKey else { return }
        contentMeasureKey = key
        let size = contentStack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = ceil(size.height)
        guard height != measuredContentHeight else { return }
        measuredContentHeight = height
        onContentHeightChange?(height)
    }

    /// The pinned-header gradient: 30% artwork tint over the page
    /// background, fading into the background, resolved against this
    /// view's traits so the header matches the page in light and dark and
    /// the dynamic header ink stays readable. CGColors freeze at
    /// assignment (09 §9a), so the layer is rebuilt on appearance changes.
    func applyHeaderGradient(dominant: UIColor) {
        headerDominant = dominant
        gradientLayer.colors = [
            ChannelFoldGeometry.blendOverBackground(dominant, traits: traitCollection).cgColor,
            Theme.background.resolvedColor(with: traitCollection).cgColor,
        ]
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            applyHeaderGradient(dominant: headerDominant)
        }
    }

    // MARK: Fold (frames/transforms only — 08 §11.2)

    func applyFold(shrink: CGFloat, geo: ChannelFoldGeometry) {
        foldShrink = shrink
        foldGeometryValue = geo

        let headerHeight = geo.headerHeight(shrink: shrink)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        passthroughY = headerHeight
        bottomFade.transform = CGAffineTransform(translationX: 0, y: headerHeight)

        // Cover: scale around its (center-anchored) expanded position, then
        // translate — position stays a transform product, not a constraint.
        let paddedWidth = bounds.width - layoutMargins.left - layoutMargins.right
        let size = geo.coverSize(shrink: shrink)
        let scale = size / ChannelFoldGeometry.expandedCoverSize
        let expandedLeading = paddedWidth / 2 - ChannelFoldGeometry.expandedCoverSize / 2
        let leading = geo.coverLeading(shrink: shrink, paddedWidth: paddedWidth)
        let expandedCenter = CGPoint(
            x: layoutMargins.left + expandedLeading + ChannelFoldGeometry.expandedCoverSize / 2,
            y: geo.coverTop + ChannelFoldGeometry.expandedCoverSize / 2
        )
        let targetCenter = CGPoint(
            x: layoutMargins.left + leading + size / 2,
            y: geo.coverTop + size / 2
        )
        coverView.transform = CGAffineTransform(
            translationX: targetCenter.x - expandedCenter.x,
            y: targetCenter.y - expandedCenter.y
        ).scaledBy(x: scale, y: scale)

        applyTitle(shrink: shrink, geo: geo, paddedWidth: paddedWidth)

        // Content block: 1:1 with the scroll, clipped at the compact bar.
        let clipHeight = max(bounds.height - geo.clipLine, 0)
        contentClip.frame = CGRect(x: 0, y: geo.clipLine, width: bounds.width, height: clipHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentFadeMask.frame = contentClip.bounds
        let fade = clipHeight > 0 ? min(ScrollEdgeFade.fadeLength / clipHeight, 1) : 1
        contentFadeMask.locations = [0, NSNumber(value: Double(fade)), 1]
        CATransaction.commit()
        let contentHeight = measuredContentHeight ?? geo.contentHeight
        let translation = geo.contentTranslation(shrink: shrink)
        let contentY = geo.contentTop - geo.clipLine + translation
        contentStack.frame = CGRect(
            x: layoutMargins.left, y: contentY, width: max(paddedWidth, 0), height: contentHeight
        )
        // Tappable only while the action row is still visible below the
        // clip line (the content bottom is the action row's bottom edge).
        let rowVisible = contentY + contentHeight > ScrollEdgeFade.fadeLength
        contentClip.isUserInteractionEnabled = rowVisible
        contentClip.accessibilityElementsHidden = !rowVisible
    }

    /// Title: a frame-driven label — rises with the cover, starts centered
    /// under it and ends left-aligned beside it, truncating before the
    /// trailing margin.
    private func applyTitle(shrink: CGFloat, geo: ChannelFoldGeometry, paddedWidth: CGFloat) {
        guard paddedWidth > 0 else { return }
        func tightWidth(in available: CGFloat) -> CGFloat {
            let fitted = titleLabel.sizeThatFits(
                CGSize(width: available, height: .greatestFiniteMagnitude)
            ).width
            return min(ceil(fitted), available)
        }
        let expandedWidth = tightWidth(in: paddedWidth)
        let leading = geo.titleLeading(
            shrink: shrink, paddedWidth: paddedWidth,
            expandedLeading: (paddedWidth - expandedWidth) / 2
        )
        let width = tightWidth(in: max(paddedWidth - leading, 0))
        // Centered while it sits under the cover; left-aligned once it
        // shares rows with the collapsed cover.
        titleLabel.textAlignment = geo.clampedShrink(shrink)
            < ChannelFoldGeometry.expandedCoverSize - ChannelFoldGeometry.collapsedCoverSize
            ? .center : .left
        titleLabel.frame = CGRect(
            x: layoutMargins.left + leading,
            y: geo.titleTop(shrink: shrink),
            width: width,
            height: ChannelFoldGeometry.titleBoxHeight
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The transparent tail below the fold lets taps reach the cells
        // scrolling under the pinned header.
        if point.y > passthroughY { return nil }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Body header (Newest/Oldest + search, channel.dart:62-100 / 636-748)

@MainActor
final class ChannelBodyHeaderCell: UICollectionViewCell {

    static let reuseIdentifier = "ChannelBodyHeaderCell"
    /// 44 (order strip + search button row) + 1 (separator).
    static let fixedHeight: CGFloat = 45

    var onSearch: (() -> Void)?
    var onOrderSelect: ((Int) -> Void)?

    private let orderStrip: ChipTabBarView
    private let searchButton = UIButton(type: .system)
    private let separator = UIView()

    override init(frame: CGRect) {
        orderStrip = ChipTabBarView(titles: ["Newest", "Oldest"])
        super.init(frame: frame)

        contentView.backgroundColor = .clear
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        orderStrip.onSelect = { [weak self] index in self?.onOrderSelect?(index) }
        orderStrip.translatesAutoresizingMaskIntoConstraints = false

        // A plain glyph with the full 44 pt tap target; opens the search sheet.
        var configuration = UIButton.Configuration.plain()
        configuration.image = AppIcons.search
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        searchButton.configuration = configuration
        searchButton.accessibilityLabel = "Search episodes"
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)

        separator.backgroundColor = Theme.surface
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(orderStrip)
        contentView.addSubview(searchButton)
        contentView.addSubview(separator)

        // The layout item already insets 16; the Dart page pads this block
        // by 24 (AnycastSpacing.pageHeader) — the remaining 8 lives here.
        NSLayoutConstraint.activate([
            orderStrip.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            orderStrip.trailingAnchor.constraint(equalTo: searchButton.leadingAnchor),
            orderStrip.centerYAnchor.constraint(equalTo: searchButton.centerYAnchor),
            orderStrip.heightAnchor.constraint(equalToConstant: 36),

            searchButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            searchButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
            searchButton.heightAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    /// The cell embeds ChipTabBarView's scroll view; self-sizing must
    /// never consult it (a scroll view inside a self-sizing item explodes
    /// the content size). The height is fixed and the order/search row
    /// owns its own layout.
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.frame.size.height = Self.fixedHeight
        return attributes
    }

    func setOrder(reversed: Bool) {
        orderStrip.select(ChannelOrderMapping.selectedIndex(isReversed: reversed), animated: false)
    }
}
