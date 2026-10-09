import UIKit
import Kingfisher
import AnycastKit

/// The Channel sheet (lib/pages/channel.dart, 03 §2.7): a full-height expand
/// sheet whose pinned header folds while the episode list scrolls under it.
///
/// Fold architecture (07 §2.3, 08 §11.2): compositional layout with a
/// `pinToVisibleBounds` boundary supplementary of the EXPANDED height; the
/// scroll-driven interpolation only touches layer geometry (gradient layer
/// frame, view transforms, opacity) — never per-tick Auto Layout. The
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

        // The v2 capsule mini player (surface 80% pill, round cover, no
        // time row) — the page previously kept the v1 `.standalone`
        // full-bleed bar, clashing with the shell's capsule language.
        let playerBar = context.makePlayerBar(style: .capsule)
        playerBar.translatesAutoresizingMaskIntoConstraints = false
        let height = playerBar.heightAnchor.constraint(equalToConstant: 58)

        return (collectionView, playerBar, height)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        // Custom grabber is drawn inside the header (Detail precedent, A2);
        // the system sheet grabber would double it.
        sheetPresentationController?.prefersGrabberVisible = false

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

        episodeListSpinner.color = Theme.primary
        episodeListSpinner.hidesWhenStopped = true
        episodeListSpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(episodeListSpinner)

        fullPageSpinner.color = Theme.primary
        fullPageSpinner.hidesWhenStopped = true
        fullPageSpinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fullPageSpinner)

        emptyChannelLabel.text = "No channel"
        emptyChannelLabel.textColor = Theme.secondaryText
        emptyChannelLabel.font = Typography.secondaryTitle.font()
        emptyChannelLabel.isHidden = true
        emptyChannelLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyChannelLabel)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: playerBar.topAnchor),

            // Floating capsule: page-grid side margins, 16 pt clear of the
            // safe-area bottom (the standalone bar used to run full-bleed).
            playerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            playerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            playerBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.pageH
            ),
            playerBarHeight,

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
        ChannelFoldGeometry(safeAreaTop: view.safeAreaInsets.top)
    }

    /// The pinned supplementary's absolute height tracks the current safe
    /// area; extents never use fixed status bar numbers.
    private func rebuildForGeometryChange() {
        appliedSafeAreaTop = view.safeAreaInsets.top
        headerView?.updateSafeAreaTop(view.safeAreaInsets.top)
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        applyFold()
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let maxExtent = foldGeometry.maxExtent
        return UICollectionViewCompositionalLayout { [weak self] _, _ in
            guard let self else { return nil }
            // ONE section hosts everything: the pinned boundary supplementary
            // only pins while its host section is on screen, so the header
            // must belong to the section that spans the whole list. Item 0 is
            // the search/order block; the rest are episode cards.
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

    fileprivate func backTapped() {
        // K34: the view model stays cached — no deletion on close.
        dismiss(animated: true)
    }

    fileprivate func subscriptionTapped() {
        guard let viewModel, subscriptionDisplay != .loading else { return }
        Task {
            if viewModel.subscribed {
                await viewModel.unsubscribe()
            } else {
                await viewModel.subscribe()
            }
        }
    }

    /// Copy the RSS URL + 1 s toast (channel.dart:454-474).
    fileprivate func copyDomainTapped() {
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
        spinner.color = Theme.primaryLightMax
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
            cell.onSubmit = { [weak self] text in
                guard let self, let viewModel = self.viewModel else { return }
                // channel.dart:682-690 — the sheet opens on submit (even
                // with the empty string: contains("") matches everything).
                ChannelSearchViewController.present(
                    from: self,
                    context: self.context,
                    rssFeedURL: viewModel.rssFeedURL,
                    searchText: text
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
        view.updateSafeAreaTop(self.view.safeAreaInsets.top)
        view.actions = .init(
            onBack: { [weak self] in self?.backTapped() },
            onShare: { [weak self] sender in self?.shareTapped(sender) },
            onSubscriptionTap: { [weak self] in self?.subscriptionTapped() },
            onCopyDomain: { [weak self] in self?.copyDomainTapped() },
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

// MARK: - Pinned header (channel.dart:248-541)

/// The pinned supplementary: gradient background layer (dominant → page
/// dark), expanded-state Auto Layout content, and a transform/opacity-only
/// fold. Below the current fold height the view is transparent and passes
/// touches through to the list scrolling beneath.
@MainActor
final class ChannelHeaderView: UICollectionReusableView {

    struct Actions {
        var onBack: () -> Void
        var onShare: (UIView) -> Void
        var onSubscriptionTap: () -> Void
        var onCopyDomain: () -> Void
        var onLatestEpisode: () -> Void
    }

    var actions: Actions?

    private let gradientLayer = CAGradientLayer()
    /// Dominant color last applied to the header gradient (re-applied on
    /// trait flips).
    private var headerDominant: UIColor = ChannelViewModel.playerWarmColor
    private let grabber = SheetGrabberView()
    private let backButton = UIButton(type: .custom)
    private let shareButton = UIButton(type: .custom)
    private let subscriptionButton = SubscriptionCapsuleButton()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let fadeGroup = UIStackView()
    private let authorLabel = UILabel()
    private let domainButton = UIButton(type: .system)
    private let descriptionText = ExpandableText(text: "", style: .defaultText, maxLines: 2)
    private let latestButton = UIButton(type: .custom)

    private var passthroughY: CGFloat = .greatestFiniteMagnitude
    /// Last applied fold inputs — replayed on layout passes.
    private var foldShrink: CGFloat = 0
    private var foldGeometryValue = ChannelFoldGeometry(safeAreaTop: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the gradient layer frame in sync with bounds + safe area
        // without touching constraints.
        applyFold(shrink: foldShrink, geo: foldGeometryValue)
    }

    func updateSafeAreaTop(_ safeAreaTop: CGFloat) {
        layoutMargins.top = safeAreaTop
        foldGeometryValue.safeAreaTop = safeAreaTop
        applyFold(shrink: foldShrink, geo: foldGeometryValue)
    }

    // MARK: Build (expanded-state constraints; channel.dart:343-547)

    private func build() {
        layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)

        applyHeaderGradient(dominant: ChannelViewModel.playerWarmColor)
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)

        grabber.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabber)

        configureCircleButton(backButton, icon: AppIcons.back, label: "Close channel")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.addAction(
            UIAction { [weak self] _ in self?.actions?.onBack() }, for: .touchUpInside
        )
        configureCircleButton(shareButton, icon: AppIcons.share, label: "Share channel")
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addAction(
            UIAction { [weak self] _ in self?.actions?.onShare(self?.shareButton ?? UIView()) },
            for: .touchUpInside
        )
        addSubview(backButton)
        addSubview(shareButton)

        subscriptionButton.onToggle = { [weak self] in self?.actions?.onSubscriptionTap() }
        subscriptionButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subscriptionButton)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 16
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.primaryBackground
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Channel artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false

        // 20pt comfortaa bold, white, centered, 2 lines (03 §2.7).
        titleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: UIFont(name: "Comfortaa-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold)
        )
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        authorLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17)
        )
        authorLabel.textColor = Theme.primaryLightMax
        authorLabel.textAlignment = .center
        authorLabel.adjustsFontForContentSizeCategory = true
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        domainButton.setTitleColor(Theme.primary, for: .normal)
        domainButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold)
        )
        domainButton.titleLabel?.adjustsFontForContentSizeCategory = true
        domainButton.translatesAutoresizingMaskIntoConstraints = false
        domainButton.addAction(
            UIAction { [weak self] _ in self?.actions?.onCopyDomain() }, for: .touchUpInside
        )
        domainButton.isAccessibilityElement = true
        domainButton.accessibilityLabel = "Copy RSS URL"

        latestButton.configuration = latestConfiguration(loading: false)
        latestButton.tintColor = Theme.primaryBackgroundDark
        latestButton.backgroundColor = Theme.primaryLightMax
        // Half the 40 pt height — see SubscriptionCapsuleButton for why
        // the Dart 36 literal is not carried over.
        latestButton.layer.cornerRadius = 20
        latestButton.layer.cornerCurve = .continuous
        latestButton.clipsToBounds = true
        latestButton.isAccessibilityElement = true
        latestButton.accessibilityLabel = "Play latest episode"
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.addAction(
            UIAction { [weak self] _ in self?.actions?.onLatestEpisode() }, for: .touchUpInside
        )

        fadeGroup.axis = .vertical
        fadeGroup.alignment = .center
        fadeGroup.spacing = 12
        fadeGroup.translatesAutoresizingMaskIntoConstraints = false
        descriptionText.translatesAutoresizingMaskIntoConstraints = false
        fadeGroup.addArrangedSubview(authorLabel)
        fadeGroup.addArrangedSubview(domainButton)
        fadeGroup.addArrangedSubview(descriptionText)
        fadeGroup.addArrangedSubview(latestButton)

        addSubview(titleLabel)
        addSubview(fadeGroup)
        // Cover LAST — it draws over the title during the fold (the Dart
        // Stack paints the Positioned cover above the column).
        addSubview(coverView)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 42),
            grabber.heightAnchor.constraint(equalToConstant: 6),

            backButton.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: 22),
            backButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),

            shareButton.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor, constant: 22),
            shareButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 40),
            shareButton.heightAnchor.constraint(equalToConstant: 40),

            subscriptionButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            subscriptionButton.trailingAnchor.constraint(
                equalTo: shareButton.leadingAnchor, constant: -12
            ),
            subscriptionButton.heightAnchor.constraint(equalToConstant: 40),

            coverView.topAnchor.constraint(
                equalTo: layoutMarginsGuide.topAnchor,
                constant: ChannelFoldGeometry.handlerHeight + ChannelFoldGeometry.handlerGap
                    + ChannelFoldGeometry.buttonRowHeight + ChannelFoldGeometry.coverTopGap
            ),
            coverView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            coverView.widthAnchor.constraint(equalToConstant: ChannelFoldGeometry.expandedCoverSize),
            coverView.heightAnchor.constraint(equalToConstant: ChannelFoldGeometry.expandedCoverSize),

            titleLabel.topAnchor.constraint(
                equalTo: coverView.bottomAnchor, constant: ChannelFoldGeometry.coverBottomGap
            ),
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: ChannelFoldGeometry.titleBoxHeight),

            fadeGroup.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            fadeGroup.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            fadeGroup.widthAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.widthAnchor),

            latestButton.widthAnchor.constraint(equalToConstant: 184),
            latestButton.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func latestConfiguration(loading: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = Theme.primaryBackgroundDark
        if loading {
            configuration.image = nil
            configuration.attributedTitle = nil
        } else {
            configuration.image = AppIcons.play
            var title = AttributedString("Latest Episode")
            title.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .systemFont(ofSize: 17, weight: .semibold)
            )
            title.foregroundColor = Theme.primaryBackgroundDark
            configuration.attributedTitle = title
        }
        return configuration
    }

    private func configureCircleButton(_ button: UIButton, icon: UIImage, label: String) {
        button.setImage(icon, for: .normal)
        button.tintColor = Theme.primaryLightMax
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        button.isAccessibilityElement = true
        button.accessibilityLabel = label
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
        domainButton.setTitle(TimeFormats.urlToDomain(channel.rssFeedUrl ?? ""), for: .normal)
        descriptionText.text = (channel.description ?? "No description").dartTrimmed()

        subscriptionButton.configure(display: display)
        latestButton.configuration = latestConfiguration(loading: latestEpisodeLoading)

        applyHeaderGradient(dominant: dominant)
    }

    /// The pinned-header gradient. The bottom stop is a DYNAMIC semantic
    /// token: `.cgColor` would freeze whatever traits the caller carries —
    /// built off-window it resolved Light and washed the header into a
    /// pale band with unreadable text (09 §9a). Resolving with explicit
    /// dark traits matches the page's pinned style; the layer is refreshed
    /// on trait flips for the V4 dual-theme flip-over.
    func applyHeaderGradient(dominant: UIColor) {
        headerDominant = dominant
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        gradientLayer.colors = [
            ChannelFoldGeometry.blendOverBackground(dominant).cgColor,
            Theme.primaryBackgroundDark.resolvedColor(with: dark).cgColor,
        ]
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            applyHeaderGradient(dominant: headerDominant)
        }
    }

    // MARK: Fold (transform/opacity only — 08 §11.2)

    func applyFold(shrink: CGFloat, geo: ChannelFoldGeometry) {
        foldShrink = shrink
        foldGeometryValue = geo

        let headerHeight = geo.headerHeight(shrink: shrink)
        gradientLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        passthroughY = headerHeight

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

        // Title: half the leading padding (the centered label shifts right
        // as its container narrows from the left), plus the spacer rise.
        let rise = geo.contentRise(shrink: shrink)
        let padding = geo.titleLeadingPadding(shrink: shrink)
        titleLabel.transform = CGAffineTransform(translationX: padding / 2, y: -rise)

        let opacity = geo.secondaryOpacity(shrink: shrink)
        fadeGroup.transform = CGAffineTransform(translationX: 0, y: -rise)
        fadeGroup.alpha = opacity
        fadeGroup.isUserInteractionEnabled = opacity > 0.01
        fadeGroup.accessibilityElementsHidden = opacity <= 0.01
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The transparent tail below the fold lets taps reach the cells
        // scrolling under the pinned header.
        if point.y > passthroughY { return nil }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Subscription capsule (channel.dart:543-634)

@MainActor
final class SubscriptionCapsuleButton: UIControl {

    var onToggle: (() -> Void)?

    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()
    private let row = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Half the 40 pt height — a true capsule. The Dart literal
        // BorderRadius.circular(36) clamps in Flutter, but CALayer's
        // continuous curve does NOT clamp an oversized radius and renders
        // a pointed lens instead.
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = Theme.primaryLightMax
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isAccessibilityElement = false

        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold)
        )
        label.adjustsFontForContentSizeCategory = true

        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(iconView)
        row.addArrangedSubview(spinner)
        row.addArrangedSubview(label)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        addAction(UIAction { [weak self] _ in self?.onToggle?() }, for: .touchUpInside)
        configure(display: .loading)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(display: ChannelSubscriptionDisplay) {
        switch display {
        case .loading:
            backgroundColor = UIColor.white.withAlphaComponent(0.12)
            iconView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimating()
            label.text = "Loading..."
            label.textColor = Theme.primaryLightMax
            accessibilityLabel = "Subscribing"
        case .subscribe:
            backgroundColor = UIColor.white.withAlphaComponent(0.12)
            iconView.isHidden = false
            spinner.isHidden = true
            spinner.stopAnimating()
            iconView.image = AppIcons.addCircle
            iconView.tintColor = Theme.primaryLightMax
            label.text = "Subscribe"
            label.textColor = Theme.primaryLightMax
            accessibilityLabel = "Subscribe"
        case .unsubscribe:
            backgroundColor = Theme.primaryLightMax
            iconView.isHidden = false
            spinner.isHidden = true
            spinner.stopAnimating()
            iconView.image = AppIcons.remove
            iconView.tintColor = Theme.primaryBackgroundDark
            label.text = "Unsubscribe"
            label.textColor = Theme.primaryBackgroundDark
            accessibilityLabel = "Unsubscribe"
        }
    }
}

// MARK: - Body header (search + Newest/Oldest, channel.dart:62-100 / 636-748)

@MainActor
final class ChannelBodyHeaderCell: UICollectionViewCell {

    static let reuseIdentifier = "ChannelBodyHeaderCell"
    /// 56 (search bar) + 36 (order strip) + 1 (separator).
    static let fixedHeight: CGFloat = 93

    var onSubmit: ((String) -> Void)?
    var onOrderSelect: ((Int) -> Void)?

    private let searchField = UITextField()
    private let clearButton = UIButton(type: .system)
    private let orderStrip: UnderlineTabBarView
    private let separator = UIView()

    override init(frame: CGRect) {
        // headlineMedium: the Dart theme pins it at 22 pt w600 on the
        // system face (anycast_theme.dart:279-284).
        let font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        orderStrip = UnderlineTabBarView(
            titles: ["Newest", "Oldest"],
            selectedFont: font,
            unselectedFont: font
        )
        super.init(frame: frame)

        contentView.backgroundColor = .clear
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        let icon = UIImageView(image: AppIcons.search)
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        let iconBox = UIView()
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(icon)
        NSLayoutConstraint.activate([
            // Explicit box size — UITextField measures the leftView via
            // systemLayoutSizeFitting; an unsized box collapses to 0×0 and
            // the icon floats at the field's top edge (same fix as the
            // shared AppBar search field).
            iconBox.widthAnchor.constraint(equalToConstant: 42),
            iconBox.heightAnchor.constraint(equalToConstant: 24),

            icon.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        searchField.leftView = iconBox
        searchField.leftViewMode = .always
        searchField.placeholder = "Search episodes"
        searchField.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17))
        searchField.adjustsFontForContentSizeCategory = true
        searchField.textColor = Theme.primaryLightMax
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search episodes",
            attributes: [.foregroundColor: Theme.hintGray]
        )
        searchField.backgroundColor = Theme.cardBackground
        searchField.layer.cornerRadius = 12
        searchField.layer.cornerCurve = .continuous
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.clearButtonMode = .never
        searchField.isAccessibilityElement = true
        searchField.accessibilityLabel = "Search episodes"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.heightAnchor.constraint(equalToConstant: 56).isActive = true
        searchField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        searchField.addTarget(self, action: #selector(submitted), for: .primaryActionTriggered)

        clearButton.setTitle("Clear", for: .normal)
        clearButton.setTitleColor(Theme.primary, for: .normal)
        clearButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold)
        )
        clearButton.titleLabel?.adjustsFontForContentSizeCategory = true
        clearButton.isHidden = true
        clearButton.addAction(UIAction { [weak self] _ in
            // channel.dart:727-730 — clear and unfocus.
            self?.searchField.text = nil
            self?.editingChanged()
            self?.searchField.resignFirstResponder()
        }, for: .touchUpInside)

        let searchRow = UIStackView(arrangedSubviews: [searchField, clearButton])
        searchRow.axis = .horizontal
        searchRow.alignment = .center
        searchRow.spacing = 16

        orderStrip.onSelect = { [weak self] index in self?.onOrderSelect?(index) }

        separator.backgroundColor = Theme.cardBackground
        separator.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [searchRow, orderStrip])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The layout item already insets 16; the Dart page pads this block
        // by 24 (AnycastSpacing.pageHeader) — the remaining 8 lives here.
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        contentView.addSubview(stack)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: separator.topAnchor),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            orderStrip.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @objc private func editingChanged() {
        clearButton.isHidden = (searchField.text ?? "").isEmpty
    }

    @objc private func submitted() {
        onSubmit?(searchField.text ?? "")
    }

    /// The cell embeds UnderlineTabBarView's scroll view; self-sizing must
    /// never consult it (a scroll view inside a self-sizing item explodes
    /// the content size). The height is fixed and the search/order block
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
