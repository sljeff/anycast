import UIKit
import Kingfisher
import AnycastKit

/// The episode Detail sheet in the Anycast 2.0 UI kit form
/// (`EpisodeDetailViewController`): the artwork opens large under the
/// grabber and, as the notes scroll, shrinks along one continuous track into
/// a small sticky tile (its corners tightening with it) over a frosted top
/// edge; below it the title, the show (opens the Channel sheet ON TOP —
/// 03 §10.1), the date and duration, the action row — Play, Add to playlist,
/// and an overflow menu with Share and the remaining actions — and the HTML
/// show notes. When the action row scrolls away a bottom bar takes over
/// (only one set of actions is ever live). Preserved v1 behaviors: the
/// custom grabber whose area TAPS to close (A2), actions auto-dismiss this
/// sheet after firing (03 §10.1 wrapper quirk), share → shortlink →
/// UIActivityViewController.
///
/// Presenters inject behavior: `openChannel`, `shortenURL`, the action
/// closures inside `EpisodeCardAction`, and whether the episode is already
/// in the playlist.
@MainActor
final class DetailViewController: UIViewController {

    struct Episode {
        var title: String
        var channelTitle: String
        var pubDateMilliseconds: Int64?
        /// Enclosure duration for the metadata line; nil or zero hides it.
        var durationSeconds: Int64?
        var imageURL: String?
        var rssFeedURL: String
        var enclosureURL: String
        var descriptionHTML: String

        init(
            title: String,
            channelTitle: String,
            pubDateMilliseconds: Int64? = nil,
            durationSeconds: Int64? = nil,
            imageURL: String? = nil,
            rssFeedURL: String,
            enclosureURL: String,
            descriptionHTML: String = ""
        ) {
            self.title = title
            self.channelTitle = channelTitle
            self.pubDateMilliseconds = pubDateMilliseconds
            self.durationSeconds = durationSeconds
            self.imageURL = imageURL
            self.rssFeedURL = rssFeedURL
            self.enclosureURL = enclosureURL
            self.descriptionHTML = descriptionHTML
        }
    }

    /// Identifies the channel to open on top of this sheet
    /// (Detail does not close — 03 §10.1).
    struct ChannelReference {
        var rssFeedURL: String
        var title: String
    }

    var openChannel: ((ChannelReference) -> Void)?
    /// Shortens the share URL through /api/shortlink; nil or a nil result
    /// degrades to the original URL (G12 contract).
    var shortenURL: ((URL) async -> URL?)?

    private let episode: Episode
    /// The episode already sits in the playlist: the add control shows a
    /// check and does nothing.
    private let isInPlaylist: Bool
    private let actions: [EpisodeCardAction]
    private let htmlRenderer: HTMLContentRenderer
    private let now: () -> Date

    private let scrollView = UIScrollView()
    private let descriptionTextView: UITextView
    private let artwork = UIImageView()
    private let artworkPlaceholder = UIView()
    private var artworkPlaceholderHeight: NSLayoutConstraint!
    private var contentTop: NSLayoutConstraint!
    private let topScrim = GradientFadeLayerView()
    private let actionRow = UIStackView()
    private let bottomBar = UIStackView()
    private let bottomScrim = GradientFadeLayerView()
    private var bottomBarVisible = false

    private enum Layout {
        /// UI kit `detailArtworkDefault`: the open artwork never exceeds
        /// 256 pt, the inset width, or the upper half of the sheet.
        static let artworkDefaultMax: CGFloat = 256
        static let artworkSticky: CGFloat = 56
        static let actionHeight: CGFloat = 52
    }

    /// Present factory. v2 detents (09 §10 批次1): `.large` reproduces the
    /// design's open frame (modal top y62 ≈ system large on the design
    /// device); `.medium` replaces the v1 0.6 shrink stop.
    static func present(
        from presenter: UIViewController,
        episode: Episode,
        actions: [EpisodeCardAction],
        htmlRenderer: HTMLContentRenderer,
        openChannel: ((ChannelReference) -> Void)? = nil,
        shortenURL: ((URL) async -> URL?)? = nil,
        isInPlaylist: Bool = false,
        now: @escaping () -> Date = { Date() }
    ) {
        let controller = DetailViewController(
            episode: episode,
            actions: actions,
            htmlRenderer: htmlRenderer,
            openChannel: openChannel,
            shortenURL: shortenURL,
            isInPlaylist: isInPlaylist,
            now: now
        )
        controller.modalPresentationStyle = .pageSheet
        let sheet = controller.sheetPresentationController
        // Single near-full detent (the v2 open frame, modal top y62 ≈ 0.93
        // on the design device). NO .medium: iOS 26+ renders medium detents
        // as inset system CARDS (9pt sides, own light plate that ignores
        // the dark override) — measured as the white card plate, 2026-10-02.
        // SDK 27 removed Detent.fraction; the custom resolver reproduces it
        // (the v1 Detail precedent).
        func fractionDetent(_ fraction: CGFloat) -> UISheetPresentationController.Detent {
            UISheetPresentationController.Detent.custom(
                identifier: .init("detail-v2-\(fraction)")
            ) { context in
                context.maximumDetentValue * fraction
            }
        }
        sheet?.detents = [fractionDetent(0.93)]
        sheet?.prefersGrabberVisible = false
        presenter.present(controller, animated: true)
    }

    init(
        episode: Episode,
        actions: [EpisodeCardAction],
        htmlRenderer: HTMLContentRenderer,
        openChannel: ((ChannelReference) -> Void)? = nil,
        shortenURL: ((URL) async -> URL?)? = nil,
        isInPlaylist: Bool = false,
        now: @escaping () -> Date = { Date() }
    ) {
        self.episode = episode
        self.actions = actions
        self.htmlRenderer = htmlRenderer
        self.openChannel = openChannel
        self.shortenURL = shortenURL
        self.isInPlaylist = isInPlaylist
        self.now = now
        self.descriptionTextView = HTMLContentRenderer.makeTextView()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)
        build()
        renderDescription()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let side = defaultArtworkSide
        if artworkPlaceholderHeight.constant != side {
            artworkPlaceholderHeight.constant = side
        }
        if contentTop.constant != artworkOriginY {
            contentTop.constant = artworkOriginY
        }
        updateScrollMorph(animated: false)
    }

    // MARK: - Build

    private func build() {
        view.backgroundColor = Theme.surface

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let content = buildContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        // The one artwork view: the scroll content only reserves its open
        // footprint; the view itself moves along default → sticky.
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerCurve = .continuous
        artwork.backgroundColor = Theme.surfaceContainerHighest
        artwork.setArtwork(episode.imageURL.flatMap(URL.init(string:)), title: episode.channelTitle)
        artwork.isAccessibilityElement = true
        artwork.accessibilityLabel = "Episode artwork"

        // Frosted top edge under the sticky tile, and the bottom bar's
        // backing — opacity-ramped surface gradients (a masked blur view
        // renders nothing, 09 §9a).
        topScrim.configure(color: Theme.surface, fromTop: true)
        topScrim.alpha = 0
        bottomScrim.configure(color: Theme.surface, fromTop: false)
        bottomScrim.alpha = 0
        for chrome in [topScrim, bottomScrim] as [UIView] {
            chrome.isUserInteractionEnabled = false
            chrome.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(chrome)
        }
        view.addSubview(artwork)

        buildBottomBar()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        // Grabber 36×5 — the tap-to-close band covering it stays ≤32 pt
        // (A2 adaptation, detail.dart:53-58).
        let grabber = UIView()
        grabber.backgroundColor = AnycastColor.sandAlpha4
        grabber.layer.cornerRadius = 2.5
        grabber.layer.cornerCurve = .continuous
        grabber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grabber)
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        view.addGestureRecognizer(headerTap)
        headerTap.delegate = self

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.md),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            // Vertical-only scrolling: content is exactly as wide as the
            // visible sheet (long text otherwise ran past inset sheets).
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            topScrim.topAnchor.constraint(equalTo: view.topAnchor),
            topScrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topScrim.heightAnchor.constraint(equalToConstant: Spacing.pageHeader * 2 + Layout.artworkSticky + Spacing.xl),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageHeader),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageHeader),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.gap),
            bottomBar.heightAnchor.constraint(equalToConstant: Layout.actionHeight),

            bottomScrim.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -Spacing.xl),
            bottomScrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomScrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // The notes clear the bottom bar when it takes over.
        scrollView.contentInset.bottom = Layout.actionHeight + Spacing.sectionGap + Spacing.xl
        applyBottomBarVisibility()
    }

    private func buildContent() -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.font = TypographyV2.headlineMedium.font()
        titleLabel.text = episode.title
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        // The show: a quiet gold text link (UI kit host entry), 44 pt tall.
        let hostButton = UIButton(type: .system)
        var hostConfig = UIButton.Configuration.plain()
        hostConfig.title = episode.channelTitle
        hostConfig.baseForegroundColor = AnycastColor.gold10
        hostConfig.contentInsets = .zero
        hostConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.titleSmall.font()
            return outgoing
        }
        hostButton.configuration = hostConfig
        hostButton.contentHorizontalAlignment = .leading
        hostButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        hostButton.heightAnchor.constraint(greaterThanOrEqualToConstant: AnycastIconButton.standardDiameter).isActive = true
        hostButton.addAction(UIAction { [weak self] _ in self?.channelTapped() }, for: .touchUpInside)

        let meta = UILabel()
        meta.font = TypographyV2.bodySmall.font()
        meta.textColor = Theme.onSurfaceVariant
        meta.adjustsFontForContentSizeCategory = true
        meta.numberOfLines = 0
        var metaParts: [String] = []
        if let date = episode.pubDateMilliseconds {
            metaParts.append(RelativeTimeFormatter.formatDate(date, now: now()))
        }
        if let duration = episode.durationSeconds, duration > 0 {
            metaParts.append(TimeFormats.formatDuration(duration))
        }
        meta.text = metaParts.joined(separator: "  ·  ")

        buildActionRow()

        descriptionTextView.font = TypographyV2.bodyLarge.font()
        descriptionTextView.textColor = Theme.onSurface
        descriptionTextView.adjustsFontForContentSizeCategory = true

        let info = UIStackView(arrangedSubviews: [titleLabel, hostButton, meta])
        info.axis = .vertical
        info.alignment = .leading
        info.spacing = Spacing.xs

        let stack = UIStackView(arrangedSubviews: [artworkPlaceholder, info, actionRow, descriptionTextView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Spacing.pageHeader
        stack.setCustomSpacing(Spacing.sectionGap, after: actionRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        artworkPlaceholderHeight = artworkPlaceholder.heightAnchor.constraint(equalToConstant: Layout.artworkDefaultMax)
        contentTop = stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Spacing.pageHeader)
        NSLayoutConstraint.activate([
            contentTop,
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Spacing.pageHeader),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Spacing.pageHeader),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Spacing.pageHeader),
            artworkPlaceholderHeight,
        ])
        return container
    }

    // MARK: - Actions (UI kit: Play primary, add as a tonal disc, the rest
    // behind the overflow menu; mirrored by the bottom bar)

    private var playAction: EpisodeCardAction? {
        actions.first { $0.accessibilityLabel == "Play" }
    }

    private var addAction: EpisodeCardAction? {
        actions.first { $0.accessibilityLabel == "Add to playlist" }
    }

    private var otherActions: [EpisodeCardAction] {
        actions.filter { $0.accessibilityLabel != "Play" && $0.accessibilityLabel != "Add to playlist" }
    }

    private func buildActionRow() {
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = Spacing.gap

        let play = AnycastButton.make(.primary, title: "Play", image: AppIcons.play)
        play.accessibilityLabel = "Play"
        if let playAction {
            play.addAction(UIAction { [weak self] _ in self?.fire(playAction) }, for: .touchUpInside)
        }
        actionRow.addArrangedSubview(play)

        if addAction != nil {
            actionRow.addArrangedSubview(makeAddDisc())
        }

        let more = AnycastIconButton(style: .tonal, icon: AppIcons.more, accessibilityLabel: "More episode actions")
        more.menu = UIMenu(children: overflowMenuChildren())
        more.showsMenuAsPrimaryAction = true
        actionRow.addArrangedSubview(more)
        actionRow.addArrangedSubview(UIView())
    }

    private func makeAddDisc() -> UIButton {
        let disc = AnycastIconButton(
            style: .tonal,
            icon: isInPlaylist ? AppIcons.check : UIImage(systemName: "plus"),
            accessibilityLabel: isInPlaylist ? "In playlist" : "Add to playlist"
        )
        disc.isEnabled = !isInPlaylist
        if let addAction, !isInPlaylist {
            disc.addAction(UIAction { [weak self] _ in self?.fire(addAction) }, for: .touchUpInside)
        }
        return disc
    }

    private func overflowMenuChildren() -> [UIMenuElement] {
        let share = UIAction(title: "Share episode", image: AppIcons.share) { [weak self] _ in
            self?.shareTapped()
        }
        let others = otherActions.map { action in
            UIAction(
                title: action.accessibilityLabel,
                image: action.icon,
                attributes: action.accessibilityLabel.hasPrefix("Remove") ? .destructive : []
            ) { [weak self] _ in self?.fire(action) }
        }
        return [share] + others
    }

    /// The bottom bar (UI kit idle state): Add to playlist capsule + Play
    /// disc, or a single Play capsule when the presenter offers no add.
    private func buildBottomBar() {
        bottomBar.axis = .horizontal
        bottomBar.alignment = .fill
        bottomBar.spacing = Spacing.gap
        if let addAction {
            let add = AnycastButton.make(
                .secondary,
                title: isInPlaylist ? "In playlist" : "Add to playlist",
                image: isInPlaylist ? AppIcons.check : UIImage(systemName: "plus")
            )
            add.isEnabled = !isInPlaylist
            add.addAction(UIAction { [weak self] _ in self?.fire(addAction) }, for: .touchUpInside)
            let play = AnycastIconButton(
                style: .inverse, icon: AppIcons.play, accessibilityLabel: "Play", diameter: Layout.actionHeight
            )
            if let playAction {
                play.addAction(UIAction { [weak self] _ in self?.fire(playAction) }, for: .touchUpInside)
            }
            bottomBar.addArrangedSubview(add)
            bottomBar.addArrangedSubview(play)
        } else {
            let play = AnycastButton.make(.primary, title: "Play", image: AppIcons.play)
            play.accessibilityLabel = "Play"
            if let playAction {
                play.addAction(UIAction { [weak self] _ in self?.fire(playAction) }, for: .touchUpInside)
            }
            bottomBar.addArrangedSubview(play)
        }
    }

    // MARK: - Scroll morph (UI kit `DetailArtworkMotion` / `DetailActionHandoff`)

    private var artworkOriginY: CGFloat { view.safeAreaInsets.top + Spacing.pageHeader }

    private var defaultArtworkSide: CGFloat {
        max(0, min(
            Layout.artworkDefaultMax,
            view.bounds.width - Spacing.pageHeader * 2,
            view.bounds.height / 2 - artworkOriginY
        ))
    }

    /// One scroll progress drives the artwork's position, size and corner
    /// radius together along a monotonic track, so scrolling back and forth
    /// retraces the same path; pulling down past the top moves it with the
    /// content instead.
    private func updateScrollMorph(animated: Bool) {
        guard view.bounds.width > 0 else { return }
        let defaultSide = defaultArtworkSide
        let defaultFrame = CGRect(x: Spacing.pageHeader, y: artworkOriginY, width: defaultSide, height: defaultSide)
        let stickyFrame = CGRect(
            x: Spacing.pageHeader, y: artworkOriginY, width: Layout.artworkSticky, height: Layout.artworkSticky
        )
        let offset = scrollView.contentOffset.y
        let travel = max(defaultSide - Layout.artworkSticky, Spacing.xs)
        let progress = min(max(offset / travel, 0), 1)

        if offset < 0 || Motion.reduceMotion {
            artwork.frame = defaultFrame.offsetBy(dx: 0, dy: -offset)
            artwork.layer.cornerRadius = Radius.artwork
        } else {
            artwork.frame = CGRect(
                x: defaultFrame.minX + (stickyFrame.minX - defaultFrame.minX) * progress,
                y: defaultFrame.minY + (stickyFrame.minY - defaultFrame.minY) * progress,
                width: defaultFrame.width + (stickyFrame.width - defaultFrame.width) * progress,
                height: defaultFrame.height + (stickyFrame.height - defaultFrame.height) * progress
            )
            artwork.layer.cornerRadius = Radius.artwork + (Radius.sm - Radius.artwork) * progress
        }
        topScrim.alpha = Motion.reduceMotion ? 0 : progress

        // The bottom bar takes over only once the action row has fully left
        // under the sticky tile — never both, never neither.
        let rowFrame = actionRow.convert(actionRow.bounds, to: view)
        let handoffLine = stickyFrame.maxY
        let usesBottom = rowFrame.height > 0 && rowFrame.maxY <= handoffLine
        setBottomBar(visible: usesBottom, animated: animated)
    }

    private func setBottomBar(visible: Bool, animated: Bool) {
        guard visible != bottomBarVisible else { return }
        bottomBarVisible = visible
        actionRow.alpha = visible ? 0 : 1
        actionRow.isUserInteractionEnabled = !visible
        actionRow.accessibilityElementsHidden = visible
        guard animated, !Motion.reduceMotion else {
            applyBottomBarVisibility()
            return
        }
        UIView.animate(
            withDuration: Motion.standard, delay: 0,
            usingSpringWithDamping: 1, initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: applyBottomBarVisibility
        )
    }

    private func applyBottomBarVisibility() {
        bottomScrim.alpha = bottomBarVisible ? 1 : 0
        bottomBar.isUserInteractionEnabled = bottomBarVisible
        bottomBar.accessibilityElementsHidden = !bottomBarVisible
        bottomBar.alpha = bottomBarVisible ? 1 : 0
        if Motion.reduceMotion {
            bottomBar.transform = .identity
        } else {
            let hiddenOffset = Layout.actionHeight + view.safeAreaInsets.bottom + Spacing.gap
            bottomBar.transform = CGAffineTransform(translationX: 0, y: bottomBarVisible ? 0 : hiddenOffset)
        }
    }

    // MARK: - Behavior

    private func renderDescription() {
        Task {
            await htmlRenderer.render(
                episode.descriptionHTML,
                cacheKey: episode.enclosureURL,
                into: descriptionTextView
            )
        }
    }

    /// 03 §10.1 wrapper quirk: the Detail pops itself after firing.
    private func fire(_ action: EpisodeCardAction) {
        action.handler()
        dismiss(animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func channelTapped() {
        // 03 §10.1: present the Channel sheet ON TOP; Detail stays open.
        openChannel?(ChannelReference(rssFeedURL: episode.rssFeedURL, title: episode.channelTitle))
    }

    private func shareTapped() {
        // anycast.website/player?rssfeedurl=…&enclosureurl=… (detail.dart:174-204)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "anycast.website"
        components.path = "/player"
        components.queryItems = [
            URLQueryItem(name: "rssfeedurl", value: episode.rssFeedURL),
            URLQueryItem(name: "enclosureurl", value: episode.enclosureURL),
        ]
        guard let url = components.url else { return }

        Task { [weak self] in
            guard let self else { return }
            let short = await self.shortenURL?(url) ?? url
            let activity = UIActivityViewController(
                activityItems: ["\(self.episode.title)\n\n\(short.absoluteString)"],
                applicationActivities: nil
            )
            // The shortlink await can complete while this sheet is already
            // dismissing — present from a presenter that is still attached to
            // the window (the share-handoff precedent) instead of from self.
            let presenter = self.view.window?.rootViewController?.topMostPresented() ?? self
            presenter.present(activity, animated: true)
        }
    }
}

extension DetailViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateScrollMorph(animated: scrollView.isDragging || scrollView.isDecelerating)
    }
}

/// The grabber-area tap closes; taps elsewhere scroll normally.
extension DetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Only the top grabber band acts as the close affordance.
        touch.location(in: view).y <= 32
    }
}

/// A vertical surface-color fade (opaque at one edge, clear at the other)
/// for chrome that needs a soft edge without a blur view. The color is
/// re-resolved on appearance changes (09 §9a).
final class GradientFadeLayerView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var color: UIColor = .clear
    private var fromTop = true

    func configure(color: UIColor, fromTop: Bool) {
        self.color = color
        self.fromTop = fromTop
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.applyColors()
        }
    }

    private func applyColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let resolved = color.resolvedColor(with: traitCollection)
        let opaque = resolved.withAlphaComponent(0.96).cgColor
        let clear = resolved.withAlphaComponent(0).cgColor
        gradient.colors = fromTop ? [opaque, opaque, clear] : [clear, opaque, opaque]
        gradient.locations = fromTop ? [0, 0.6, 1] : [0, 0.4, 1]
    }
}
