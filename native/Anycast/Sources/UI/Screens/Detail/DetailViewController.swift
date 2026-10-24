import UIKit
import Kingfisher
import AnycastKit

/// The episode Detail sheet (design canvas D3, adopted 2026-10-21): it opens
/// at a 460 pt medium detent — on iOS 26 a floating card inset from the
/// screen edges — and drags up to large. Content sits 28 pt in: the cover
/// beside the title, the show (opens the Channel sheet ON TOP — 03 §10.1)
/// and the date · duration line, then the HTML show notes. The actions stay
/// at the bottom in thumb reach over a soft fade: a Play capsule that
/// carries the episode's progress ("Resume · 32m left") and a ••• menu with
/// Add to playlist, Share episode, Copy link and the remaining actions.
/// Preserved v1 behaviors: actions auto-dismiss this sheet after firing
/// (03 §10.1 wrapper quirk), share → shortlink → UIActivityViewController.
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
        /// Enclosure duration; nil or zero hides it from the meta line and
        /// the Play label.
        var durationMilliseconds: Int64?
        /// How much has been played; above zero the Play capsule resumes.
        var playedMilliseconds: Int64?
        var imageURL: String?
        var rssFeedURL: String
        var enclosureURL: String
        var descriptionHTML: String

        init(
            title: String,
            channelTitle: String,
            pubDateMilliseconds: Int64? = nil,
            durationMilliseconds: Int64? = nil,
            playedMilliseconds: Int64? = nil,
            imageURL: String? = nil,
            rssFeedURL: String,
            enclosureURL: String,
            descriptionHTML: String = ""
        ) {
            self.title = title
            self.channelTitle = channelTitle
            self.pubDateMilliseconds = pubDateMilliseconds
            self.durationMilliseconds = durationMilliseconds
            self.playedMilliseconds = playedMilliseconds
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

    /// The Play capsule's label and the share of it filled as progress.
    struct PlayLabel: Equatable {
        var title: String
        var fraction: Double

        /// "Resume · 32m left" once played, "Play · 80m" before, "Play"
        /// without a known duration.
        static func make(durationMilliseconds: Int64?, playedMilliseconds: Int64?) -> PlayLabel {
            let duration = durationMilliseconds ?? 0
            let played = playedMilliseconds ?? 0
            guard duration > 0 else { return PlayLabel(title: "Play", fraction: 0) }
            if played > 0 {
                let left = PlaylistCardDisplay.timeLeft(
                    durationMilliseconds: duration, playedMilliseconds: played
                )
                return PlayLabel(
                    title: "Resume · \(left)",
                    fraction: min(Double(played) / Double(duration), 1)
                )
            }
            return PlayLabel(title: "Play · \(TimeFormats.formatDuration(duration))", fraction: 0)
        }
    }

    var openChannel: ((ChannelReference) -> Void)?
    /// Shortens the share URL through /api/shortlink; nil or a nil result
    /// degrades to the original URL (G12 contract).
    var shortenURL: ((URL) async -> URL?)?

    private let episode: Episode
    /// The episode already sits in the playlist: the menu shows a disabled
    /// "In playlist" in place of the add action.
    private let isInPlaylist: Bool
    private let actions: [EpisodeCardAction]
    private let htmlRenderer: HTMLContentRenderer
    private let now: () -> Date

    private let scrollView = UIScrollView()
    private let descriptionTextView: UITextView
    private let artwork = UIImageView()
    private var artworkSide: NSLayoutConstraint!
    private let titleLabel = UILabel()
    /// Takes the slack below the meta line so the column stays top-aligned
    /// beside the cover at both detents.
    private let trailingSpacer = UIView()
    private let actionRow = UIStackView()
    private let bottomFade = GradientFadeLayerView()

    private enum Layout {
        static let mediumHeight: CGFloat = 460
        static let inset: CGFloat = 28
        static let artworkMedium: CGFloat = 120
        static let artworkLarge: CGFloat = 160
        static let actionHeight: CGFloat = 52
        static let fadeHeight: CGFloat = 40
        /// Clear band between the notes' fade and the action row.
        static let rowGap: CGFloat = Spacing.sm
    }

    static let mediumDetent = UISheetPresentationController.Detent.Identifier("detail-medium")

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
        if let sheet = controller.sheetPresentationController {
            // Medium is the floating 460 pt card; the system draws its inset
            // and corners on iOS 26. Two detents, so the grabber shows.
            sheet.detents = [
                .custom(identifier: mediumDetent) { context in
                    min(Layout.mediumHeight, context.maximumDetentValue)
                },
                .large(),
            ]
            sheet.selectedDetentIdentifier = mediumDetent
            sheet.prefersGrabberVisible = true
            sheet.delegate = controller
        }
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

    // MARK: - Build

    private func build() {
        view.backgroundColor = Theme.surface

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let content = buildContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        // The notes fade out above the actions; the scroll view itself ends
        // there (below), so nothing is ever drawn under or beside the row.
        bottomFade.configure(color: Theme.surface, fromTop: false)
        bottomFade.isUserInteractionEnabled = false
        bottomFade.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomFade)

        buildActionRow()
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionRow)

        // 28 pt from the floating card's bottom; at large the home
        // indicator's safe area wins.
        let rowBottom = actionRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Layout.inset)
        rowBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -Layout.rowGap),

            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            // Vertical-only scrolling: content is exactly as wide as the
            // visible sheet (long text otherwise ran past inset sheets).
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            actionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.inset),
            actionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.inset),
            actionRow.heightAnchor.constraint(equalToConstant: Layout.actionHeight),
            actionRow.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            rowBottom,

            bottomFade.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Layout.fadeHeight),
            bottomFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])

        // The notes also melt away under the sheet's top edge once scrolled
        // (the column rests `Layout.inset` below it, exactly at the strip's
        // bottom).
        ScrollEdgeChrome.attachTopEdge(
            to: scrollView, in: view, height: Layout.inset, fadeColor: Theme.surface, restingGap: 0
        )

        // The last line of the notes scrolls to rest above the fade.
        scrollView.contentInset.bottom = Layout.fadeHeight
        applyDetentLayout()
    }

    private func buildContent() -> UIView {
        let container = UIView()

        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = Radius.artwork
        artwork.layer.cornerCurve = .continuous
        artwork.backgroundColor = Theme.surfaceContainerHighest
        artwork.setArtwork(episode.imageURL.flatMap(URL.init(string:)), title: episode.channelTitle)
        artwork.isAccessibilityElement = true
        artwork.accessibilityLabel = "Episode artwork"
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artworkSide = artwork.widthAnchor.constraint(equalToConstant: Layout.artworkMedium)

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.text = episode.title
        titleLabel.textColor = TypographyV2.emphasis.color
        titleLabel.numberOfLines = 3
        titleLabel.adjustsFontForContentSizeCategory = true

        // The show: a Meta-styled link to the Channel sheet.
        let hostButton = ExpandedHitButton(type: .system)
        var hostConfig = UIButton.Configuration.plain()
        hostConfig.title = episode.channelTitle
        hostConfig.baseForegroundColor = TypographyV2.meta.color
        hostConfig.contentInsets = .zero
        hostConfig.titleLineBreakMode = .byTruncatingTail
        hostConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        hostButton.configuration = hostConfig
        hostButton.contentHorizontalAlignment = .leading
        hostButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        hostButton.addAction(UIAction { [weak self] _ in self?.channelTapped() }, for: .touchUpInside)

        let meta = UILabel()
        meta.font = TypographyV2.meta.font()
        meta.textColor = TypographyV2.meta.color
        meta.adjustsFontForContentSizeCategory = true
        meta.numberOfLines = 1
        meta.text = RelativeTimeFormatter.dateAndDuration(
            pubDateMilliseconds: episode.pubDateMilliseconds,
            durationMilliseconds: episode.durationMilliseconds,
            now: now()
        )

        for label in [titleLabel, meta] as [UIView] {
            label.setContentHuggingPriority(.required, for: .vertical)
        }
        hostButton.setContentHuggingPriority(.required, for: .vertical)
        let info = UIStackView(arrangedSubviews: [titleLabel, hostButton, meta, trailingSpacer])
        info.axis = .vertical
        info.alignment = .leading
        info.spacing = Spacing.xs

        let header = UIStackView(arrangedSubviews: [artwork, info])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = Spacing.pageH

        descriptionTextView.font = TypographyV2.body.font()
        descriptionTextView.textColor = TypographyV2.body.color
        descriptionTextView.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [header, descriptionTextView])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Spacing.cardInner
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.inset),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.inset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.inset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.inset),
            artworkSide,
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor),
            info.heightAnchor.constraint(greaterThanOrEqualTo: artwork.heightAnchor),
        ])
        return container
    }

    /// Large gives the cover 160 pt and the title four lines; medium is
    /// 120 pt and three lines. Both keep the column top-aligned.
    private func applyDetentLayout() {
        let isLarge = sheetPresentationController?.selectedDetentIdentifier == .large
        artworkSide.constant = isLarge ? Layout.artworkLarge : Layout.artworkMedium
        titleLabel.numberOfLines = isLarge ? 4 : 3
    }

    // MARK: - Actions (Play capsule with progress; the rest behind •••)

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
        actionRow.alignment = .fill
        actionRow.spacing = Spacing.md

        let label = PlayLabel.make(
            durationMilliseconds: episode.durationMilliseconds,
            playedMilliseconds: episode.playedMilliseconds
        )
        let play = AnycastButton.make(.primary, title: label.title, image: AppIcons.play)
        var configuration = play.configuration
        configuration?.background.customView = ProgressCapsuleBackground(fraction: label.fraction)
        play.configuration = configuration
        play.accessibilityLabel = label.title
        play.accessibilityIdentifier = "detail-play"
        if let playAction {
            play.addAction(UIAction { [weak self] _ in self?.fire(playAction) }, for: .touchUpInside)
        }
        actionRow.addArrangedSubview(play)

        let more = AnycastIconButton(
            style: .tonal, icon: AppIcons.more, accessibilityLabel: "More episode actions",
            diameter: Layout.actionHeight
        )
        more.menu = UIMenu(children: overflowMenuChildren())
        more.showsMenuAsPrimaryAction = true
        // Keep the written order when the menu opens upward: destructive
        // last, nearest the button.
        more.preferredMenuElementOrder = .fixed
        actionRow.addArrangedSubview(more)
    }

    private func overflowMenuChildren() -> [UIMenuElement] {
        var items: [UIMenuElement] = []
        if let addAction {
            if isInPlaylist {
                items.append(UIAction(title: "In playlist", image: AppIcons.addedToList, attributes: .disabled) { _ in })
            } else {
                items.append(UIAction(title: "Add to playlist", image: AppIcons.addToList) { [weak self] _ in
                    self?.fire(addAction)
                })
            }
        }
        items.append(UIAction(title: "Share episode", image: AppIcons.share) { [weak self] _ in
            self?.shareTapped()
        })
        items.append(UIAction(title: "Copy link", image: AppIcons.copy) { [weak self] _ in
            self?.copyLinkTapped()
        })
        let others = otherActions.map { action in
            UIAction(
                title: action.accessibilityLabel,
                image: action.icon,
                attributes: action.accessibilityLabel.hasPrefix("Remove") ? .destructive : []
            ) { [weak self] _ in self?.fire(action) }
        }
        guard !others.isEmpty else { return items }
        // Destructive and other episode actions sit apart, under a divider.
        return [UIMenu(options: .displayInline, children: items), UIMenu(options: .displayInline, children: others)]
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

    private func channelTapped() {
        // 03 §10.1: present the Channel sheet ON TOP; Detail stays open.
        openChannel?(ChannelReference(rssFeedURL: episode.rssFeedURL, title: episode.channelTitle))
    }

    /// anycast.website/player?rssfeedurl=…&enclosureurl=… (detail.dart:174-204)
    private var playerURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "anycast.website"
        components.path = "/player"
        components.queryItems = [
            URLQueryItem(name: "rssfeedurl", value: episode.rssFeedURL),
            URLQueryItem(name: "enclosureurl", value: episode.enclosureURL),
        ]
        return components.url
    }

    private func shareTapped() {
        guard let url = playerURL else { return }
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

    /// The same shortened player link as Share, straight to the pasteboard.
    private func copyLinkTapped() {
        guard let url = playerURL else { return }
        Task { [weak self] in
            guard let self else { return }
            let short = await self.shortenURL?(url) ?? url
            UIPasteboard.general.string = short.absoluteString
            if let window = self.view.window {
                ToastPresenter.shared.show("Link copied", in: window)
            }
        }
    }
}

extension DetailViewController: UISheetPresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        Motion.animate { [weak self] in
            self?.applyDetentLayout()
            self?.view.layoutIfNeeded()
        }
    }
}

/// The Play capsule's fill: the primary ink with the played share washed
/// lighter from the leading edge (`onPrimary` at 18 %).
private final class ProgressCapsuleBackground: UIView {

    private let fill = UIView()
    private let fraction: Double

    init(fraction: Double) {
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = Theme.onSurface
        clipsToBounds = true
        fill.backgroundColor = Theme.surface.withAlphaComponent(0.18)
        addSubview(fill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(fraction), height: bounds.height)
    }
}

/// A text-sized link whose touch area still reaches the 44 pt minimum.
private final class ExpandedHitButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let grow = max(0, (AnycastIconButton.standardDiameter - bounds.height) / 2)
        return bounds.insetBy(dx: 0, dy: -grow).contains(point)
    }
}

/// A vertical surface-color fade (fully opaque at one edge, clear at the
/// other) for chrome that needs a soft edge without a blur view. The color
/// is re-resolved on appearance changes and when the view joins a window
/// (09 §9a); the opaque end is exactly 1.0 so content behind it never
/// ghosts through.
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The first resolve ran detached (default traits).
        applyColors()
    }

    private func applyColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let resolved = color.resolvedColor(with: traitCollection)
        let opaque = resolved.cgColor
        let clear = resolved.withAlphaComponent(0).cgColor
        gradient.colors = fromTop ? [opaque, clear] : [clear, opaque]
    }
}
