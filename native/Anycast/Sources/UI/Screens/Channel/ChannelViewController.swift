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
    /// The page's actions, in thumb reach above the mini player:
    /// Latest Episode, subscribe, share (long press: Copy RSS URL).
    private let actionRow = UIStackView()
    private let latestButton = UIButton(type: .custom)
    private let subscribeButton = AnycastIconButton(
        style: .glass, icon: AppIcons.subscribe, accessibilityLabel: "Subscribe",
        diameter: AnycastIconButton.largeDiameter, glyphSize: 20
    )
    private let shareButton = AnycastIconButton(
        style: .glass, icon: AppIcons.share, accessibilityLabel: "Share",
        diameter: AnycastIconButton.largeDiameter, glyphSize: 20
    )
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
    }

    // MARK: - Build

    private func buildViewHierarchy() {
        view.addSubview(collectionView)
        view.addSubview(playerBar)
        buildActionRow()
        view.addSubview(actionRow)

        // Scrim behind the bottom row and capsule so rows are not hard-cut
        // by them (G-7).
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

            // The action row sits 8 pt above the capsule (or the home
            // indicator when nothing plays and the capsule collapses).
            actionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            actionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            actionRow.bottomAnchor.constraint(equalTo: playerBar.topAnchor, constant: -Spacing.md),
            actionRow.heightAnchor.constraint(equalToConstant: AnycastIconButton.largeDiameter),

            bottomFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomFade.topAnchor.constraint(
                equalTo: actionRow.topAnchor, constant: -ScrollEdgeFade.fadeLength
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
        collectionView.register(
            ChannelEpisodeRowCell.self, forCellWithReuseIdentifier: ChannelEpisodeRowCell.reuseIdentifier
        )
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
        let layout = UICollectionViewCompositionalLayout { [weak self] _, _ in
            guard let self else { return nil }
            // ONE section hosts everything: the pinned boundary supplementary
            // only pins while its host section is on screen, so the header
            // must belong to the section that spans the whole list. Item 0 is
            // the order/search row; the rest are rows on one grouped plate.
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(ChannelEpisodeRowCell.minimumHeight)
                )
            )
            // Horizontal margins live on the ITEM — section content insets
            // would also inset the pinned supplementary.
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            // The plate starts under the header and the order row.
            if !(self.viewModel?.showEpisodes.isEmpty ?? true) {
                let plate = NSCollectionLayoutDecorationItem.background(elementKind: GroupedPlateView.elementKind)
                plate.contentInsets = NSDirectionalEdgeInsets(
                    top: maxExtent + ChannelBodyHeaderCell.fixedHeight, leading: 16, bottom: 0, trailing: 16
                )
                section.decorationItems = [plate]
            }
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
        layout.register(GroupedPlateView.self, forDecorationViewOfKind: GroupedPlateView.elementKind)
        return layout
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

        headerView?.configure(channel: viewModel.channel, dominant: viewModel.dominantColor)
        renderActionRow()

        // Plain no-animation rebuild (08 §7.2 — the Flutter Obx rebuild).
        let signature = viewModel.showEpisodes.map(\.enclosureUrl)
        if signature != lastEpisodeSignature {
            lastEpisodeSignature = signature
            UIView.performWithoutAnimation {
                collectionView.reloadData()
            }
            refreshVisibleCards()
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
        let row = AnycastIconButton.largeDiameter + Spacing.md
        let clearance = playerVisible
            ? PlayerBarView.barHeight + Spacing.xs + row + Spacing.pageH
            : row + Spacing.pageH
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
                      let cell = collectionView.cellForItem(at: path) as? ChannelEpisodeRowCell {
                configureRow(cell, at: path.item - 1)
            }
        }
    }

    // MARK: - Bottom action row

    private func buildActionRow() {
        latestButton.configuration = latestConfiguration(loading: false)
        latestButton.addPressFeedback(scale: Motion.pressScaleSubtle)
        latestButton.accessibilityLabel = "Play latest episode"
        latestButton.addAction(UIAction { [weak self] _ in self?.latestEpisodeTapped() }, for: .touchUpInside)

        subscribeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.subscriptionTapped(self.subscribeButton)
        }, for: .touchUpInside)

        shareButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.shareTapped(self.shareButton)
        }, for: .touchUpInside)
        // Long press keeps the old domain button's job: copy the RSS URL.
        shareButton.menu = UIMenu(children: [
            UIAction(title: "Copy RSS URL", image: AppIcons.copy) { [weak self] _ in self?.copyRSSTapped() },
        ])
        shareButton.showsMenuAsPrimaryAction = false
        shareButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Copy RSS URL") { [weak self] _ in
                self?.copyRSSTapped()
                return true
            },
        ]

        actionRow.axis = .horizontal
        actionRow.alignment = .fill
        actionRow.spacing = Spacing.md
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        for button in [latestButton, subscribeButton, shareButton] as [UIView] {
            actionRow.addArrangedSubview(button)
        }
    }

    /// The shared primary capsule; while the feed loads it shows the
    /// configuration's own activity indicator in place of the glyph.
    private func latestConfiguration(loading: Bool) -> UIButton.Configuration {
        var configuration = AnycastButton.configuration(.primary, title: "Latest Episode", image: AppIcons.play)
        configuration.showsActivityIndicator = loading
        return configuration
    }

    private func renderActionRow() {
        let display = subscriptionDisplay
        subscribeButton.setIcon(display.toggleIcon)
        subscribeButton.configuration?.baseForegroundColor =
            display == .unsubscribe ? Theme.primary : Theme.onSurface
        subscribeButton.accessibilityLabel = display.toggleAccessibilityLabel
        subscribeButton.isEnabled = display != .loading
        subscribeButton.alpha = display == .loading ? 0.5 : 1
        latestButton.configuration = latestConfiguration(loading: viewModel?.isLoading ?? false)
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
            cell.onOrderSelect = { [weak self] reversed in
                guard let self, let viewModel = self.viewModel else { return }
                guard viewModel.isReversed != reversed else { return }
                viewModel.isReversed = reversed
            }
            cell.setOrder(reversed: viewModel?.isReversed ?? false)
            return cell
        }

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ChannelEpisodeRowCell.reuseIdentifier, for: indexPath
        ) as! ChannelEpisodeRowCell
        configureRow(cell, at: indexPath.item - 1)
        return cell
    }

    private func configureRow(_ cell: ChannelEpisodeRowCell, at index: Int) {
        guard let viewModel, viewModel.showEpisodes.indices.contains(index) else { return }
        binder?.configure(row: cell, episode: viewModel.showEpisodes[index])
        cell.setPosition(isFirst: index == 0, isLast: index == viewModel.showEpisodes.count - 1)
    }

    // Row tap opens Detail (it carries Play and the ••• menu); the order
    // row is not selectable.

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        indexPath.item > 0
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let viewModel, viewModel.showEpisodes.indices.contains(indexPath.item - 1) else { return }
        binder?.presentDetail(episode: viewModel.showEpisodes[indexPath.item - 1])
    }

    /// Long press: Play / Add to playlist (the Inbox native-first pattern).
    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let path = indexPaths.first, path.item > 0,
              let viewModel, viewModel.showEpisodes.indices.contains(path.item - 1),
              let binder else { return nil }
        let episode = viewModel.showEpisodes[path.item - 1]
        return UIContextMenuConfiguration(actionProvider: { _ in binder.menu(for: episode) })
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
        if let viewModel {
            view.configure(channel: viewModel.channel, dominant: viewModel.dominantColor)
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
/// background), the cover with the title and author beside it that shrink
/// into a compact bar, and the description that scrolls up under that bar
/// inside a clipping container. The fold only touches frames, transforms
/// and the clip — never per-tick Auto Layout. Below the current fold height
/// the view is transparent and passes touches through to the list scrolling
/// beneath. The page's actions live in the bottom row, not here.
@MainActor
final class ChannelHeaderView: UICollectionReusableView {

    /// Reports the measured height of the description block so the
    /// controller can size the pinned supplementary to it.
    var onContentHeightChange: ((CGFloat) -> Void)?

    private let gradientLayer = CAGradientLayer()
    /// Hangs below the gradient's bottom edge so scrolled rows fade in under
    /// the pinned header instead of being hard-cut (G-7); positioned by a
    /// transform in `applyFold` like the rest of the fold.
    private let bottomFade = ScrollEdgeFade(edge: .top)
    /// Dominant color last applied to the header gradient (re-applied on
    /// trait flips).
    private var headerDominant: UIColor = ChannelViewModel.playerWarmColor
    private let coverView = UIImageView()
    private let titleBlock = UIStackView()
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    /// Clips the description at the compact bar's bottom line; its top
    /// 16 pt fade out through the mask.
    private let contentClip = UIView()
    private let contentFadeMask = CAGradientLayer()
    /// Body-sized description (the v1 expandable label takes a v1 style).
    private let descriptionText = ExpandableText(
        text: "",
        style: Typography.Style(
            postScriptName: "SFPro-Regular", size: 15, kern: 0,
            color: Theme.onSurface, scalingTextStyle: .subheadline
        ),
        maxLines: 2
    )

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
        layoutMargins = UIEdgeInsets(top: 0, left: Spacing.pageH, bottom: 0, right: Spacing.pageH)

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
        coverView.applyArtworkHairline()
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Channel artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false

        // Emphasis title and Meta author, one line each, beside the cover.
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true
        authorLabel.font = TypographyV2.meta.font()
        authorLabel.textColor = TypographyV2.meta.color
        authorLabel.numberOfLines = 1
        authorLabel.adjustsFontForContentSizeCategory = true
        titleBlock.axis = .vertical
        titleBlock.spacing = Spacing.xs
        titleBlock.alignment = .fill
        titleBlock.addArrangedSubview(titleLabel)
        titleBlock.addArrangedSubview(authorLabel)

        // The description sits directly on the header — no tinted plate.
        descriptionText.showsTruncatedPlate = false
        descriptionText.layoutMargins = .zero

        contentClip.clipsToBounds = true
        contentFadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        contentFadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        contentFadeMask.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
        contentClip.layer.mask = contentFadeMask
        contentClip.addSubview(descriptionText)

        addSubview(titleBlock)
        addSubview(contentClip)
        addSubview(coverView)

        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(
                equalTo: layoutMarginsGuide.topAnchor, constant: ChannelFoldGeometry.coverTopGap
            ),
            coverView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            coverView.widthAnchor.constraint(equalToConstant: ChannelFoldGeometry.expandedCoverSize),
            coverView.heightAnchor.constraint(equalToConstant: ChannelFoldGeometry.expandedCoverSize),
        ])
    }

    // MARK: Configure

    func configure(channel: SubscriptionRow, dominant: UIColor) {
        coverView.kf.cancelDownloadTask()
        let imageURL = channel.imageUrl.flatMap(URL.init(string:))
            ?? URL(string: "https://placeholder.co/120.png?text=Waiting")
        coverView.kf.setImage(with: imageURL, placeholder: nil, options: [.transition(.none)])

        titleLabel.text = channel.title ?? ""
        authorLabel.text = channel.author
        authorLabel.isHidden = (channel.author ?? "").isEmpty
        descriptionText.text = DisplayText.plainText(fromHTML: channel.description ?? "No description")

        applyHeaderGradient(dominant: dominant)
        measureContentIfNeeded()
        setNeedsLayout()
    }

    /// Measures the description at the header width and reports changes;
    /// the key keeps per-layout-pass calls cheap.
    private func measureContentIfNeeded() {
        let width = bounds.width - layoutMargins.left - layoutMargins.right
        guard width > 0 else { return }
        let key = "\(width)|\(descriptionText.text)"
            + "|\(traitCollection.preferredContentSizeCategory.rawValue)"
        guard key != contentMeasureKey else { return }
        contentMeasureKey = key
        let size = descriptionText.systemLayoutSizeFitting(
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
        // A pull past the top drags the header down with the list; the
        // gradient reaches up over the exposed band.
        let overscroll = max(-shrink, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(
            x: 0, y: -overscroll, width: bounds.width, height: headerHeight + overscroll
        )
        CATransaction.commit()
        passthroughY = headerHeight
        bottomFade.transform = CGAffineTransform(translationX: 0, y: headerHeight)

        // Cover: shrinks around its top-leading corner, which stays put.
        let size = geo.coverSize(shrink: shrink)
        let scale = size / ChannelFoldGeometry.expandedCoverSize
        let offset = (ChannelFoldGeometry.expandedCoverSize - size) / 2
        coverView.transform = CGAffineTransform(translationX: -offset, y: -offset)
            .scaledBy(x: scale, y: scale)

        // Title block: beside the cover, centered on it; the author fades
        // out as the bar compacts.
        let paddedWidth = bounds.width - layoutMargins.left - layoutMargins.right
        let leading = geo.titleLeading(shrink: shrink)
        authorLabel.alpha = 1 - geo.compactProgress(shrink: shrink)
        let hasAuthor = !authorLabel.isHidden
        titleBlock.frame = CGRect(
            x: layoutMargins.left + leading,
            y: geo.titleTop(shrink: shrink, hasAuthor: hasAuthor),
            width: max(paddedWidth - leading, 0),
            height: hasAuthor ? ChannelFoldGeometry.titleBlockHeight : ChannelFoldGeometry.titleLineHeight
        )

        // Description: 1:1 with the scroll, clipped at the compact bar.
        let clipHeight = max(bounds.height - geo.clipLine, 0)
        contentClip.frame = CGRect(x: 0, y: geo.clipLine, width: bounds.width, height: clipHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentFadeMask.frame = contentClip.bounds
        let fade = clipHeight > 0 ? min(ScrollEdgeFade.fadeLength / clipHeight, 1) : 1
        contentFadeMask.locations = [0, NSNumber(value: Double(fade)), 1]
        CATransaction.commit()
        let contentHeight = measuredContentHeight ?? geo.contentHeight
        let contentY = geo.contentTop - geo.clipLine + geo.contentTranslation(shrink: shrink)
        descriptionText.frame = CGRect(
            x: layoutMargins.left, y: contentY, width: max(paddedWidth, 0), height: contentHeight
        )
        // Tappable (expand) only while it is still visible below the clip.
        let visible = contentY + contentHeight > ScrollEdgeFade.fadeLength
        contentClip.isUserInteractionEnabled = visible
        contentClip.accessibilityElementsHidden = !visible
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The transparent tail below the fold lets taps reach the cells
        // scrolling under the pinned header.
        if point.y > passthroughY { return nil }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Sort and search row (channel.dart:62-100 / 636-748)

/// "Newest ⇅" — a quiet menu button choosing the order — and the search
/// glyph opening ChannelSearch. The row ends 12 pt above the episode plate.
@MainActor
final class ChannelBodyHeaderCell: UICollectionViewCell {

    static let reuseIdentifier = "ChannelBodyHeaderCell"
    /// 44 (the row) + 12 (gap to the plate).
    static let fixedHeight: CGFloat = 56

    var onSearch: (() -> Void)?
    /// true = oldest first.
    var onOrderSelect: ((Bool) -> Void)?

    private let orderButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private var reversed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        orderButton.showsMenuAsPrimaryAction = true
        orderButton.accessibilityIdentifier = "channel-order"
        orderButton.translatesAutoresizingMaskIntoConstraints = false
        orderButton.addPressFeedback()

        var search = UIButton.Configuration.plain()
        search.image = AppIcons.search
        search.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        search.baseForegroundColor = Theme.onSurfaceVariant
        searchButton.configuration = search
        searchButton.accessibilityLabel = "Search episodes"
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)

        contentView.addSubview(orderButton)
        contentView.addSubview(searchButton)

        // The item is inset 16; the order button's own 12 pt padding hangs
        // into that margin so its label lines up with the page text.
        NSLayoutConstraint.activate([
            orderButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: -Spacing.gap),
            orderButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            orderButton.heightAnchor.constraint(equalToConstant: 36),

            searchButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 4),
            searchButton.centerYAnchor.constraint(equalTo: orderButton.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
            searchButton.heightAnchor.constraint(equalToConstant: AnycastIconButton.standardDiameter),
        ])
        setOrder(reversed: false)
    }

    /// The row height is fixed; the plate below starts at this edge.
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.frame.size.height = Self.fixedHeight
        return attributes
    }

    func setOrder(reversed: Bool) {
        self.reversed = reversed
        var configuration = UIButton.Configuration.plain()
        configuration.title = reversed ? "Oldest" : "Newest"
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = Spacing.sm
        configuration.baseForegroundColor = TypographyV2.emphasis.color
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: Spacing.gap, bottom: 0, trailing: Spacing.gap)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.emphasis.font()
            return outgoing
        }
        orderButton.configuration = configuration
        orderButton.accessibilityLabel = "Sort order: \(reversed ? "Oldest" : "Newest")"
        orderButton.menu = UIMenu(children: [
            UIAction(title: "Newest", state: reversed ? .off : .on) { [weak self] _ in self?.onOrderSelect?(false) },
            UIAction(title: "Oldest", state: reversed ? .on : .off) { [weak self] _ in self?.onOrderSelect?(true) },
        ])
    }
}

// MARK: - Episode row (one grouped plate)

/// One episode on the Channel page's grouped plate: the Emphasis title on
/// up to two lines and the Meta "date · duration" line. No cover — the
/// show's artwork already heads the page, and per-episode art is usually
/// the same picture. Rows after the first draw a hairline from the text on; touching fills the
/// row (no scale). Tap opens Detail; long press offers Play / Add to
/// playlist — both wired by the list.
@MainActor
final class ChannelEpisodeRowCell: UICollectionViewCell {

    static let reuseIdentifier = "ChannelEpisodeRowCell"
    /// 12 + one-line title (22) + 4 + meta (20) + 12.
    static let minimumHeight: CGFloat = 70

    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, meta: String) {
        titleLabel.text = title
        metaLabel.text = meta
        contentView.accessibilityLabel = title
        contentView.accessibilityValue = meta
    }

    /// Where the row sits on its plate: the first row has no hairline, and
    /// the first and last rows round their press fill into the plate.
    func setPosition(isFirst: Bool, isLast: Bool) {
        separator.isHidden = isFirst
        var corners: CACornerMask = []
        if isFirst { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if isLast { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        contentView.layer.maskedCorners = corners
        contentView.layer.cornerRadius = corners.isEmpty ? 0 : Radius.card
    }

    override var isHighlighted: Bool {
        didSet {
            let fill = isHighlighted ? AnycastColor.sandAlpha5 : .clear
            UIView.animate(withDuration: isHighlighted ? 0.1 : Motion.quick) {
                self.contentView.backgroundColor = fill
            }
        }
    }

    private func build() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerCurve = .continuous
        contentView.isAccessibilityElement = true
        contentView.accessibilityTraits = [.button]
        contentView.accessibilityHint = "Opens episode details"

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        metaLabel.font = TypographyV2.meta.font().monospacedDigits()
        metaLabel.textColor = TypographyV2.meta.color
        metaLabel.numberOfLines = 1
        metaLabel.adjustsFontForContentSizeCategory = true

        let text = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        text.axis = .vertical
        text.spacing = Spacing.xs
        text.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(text)

        separator.backgroundColor = Theme.outline
        separator.isUserInteractionEnabled = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),

            text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.gap),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.gap),
            text.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.gap),
            text.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.gap),
            text.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.topAnchor.constraint(equalTo: contentView.topAnchor),
            separator.leadingAnchor.constraint(equalTo: text.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.gap),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }
}
