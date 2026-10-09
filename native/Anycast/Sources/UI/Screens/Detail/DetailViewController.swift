import UIKit
import Kingfisher
import AnycastKit

/// The episode Detail sheet — v2 form (09 §10 批次1, Figma `507:14681` set,
/// open state `1784:7538` re-measured 2026-10-02): a near-full sheet
/// (`.large` + `.medium`, corner radius 48) with a full-bleed hero artwork
/// that fades into a frosted content panel — 32pt semibold title, metadata
/// row, status tag pills, channel host, HTML description — and a pinned
/// bottom blur bar carrying the two v2 actions: a gold "ADD TO QUEUE" pill
/// and a dark play button. The v1 remove action retired from the bar (the
/// lists own removal through swipe/context menu now, 09 §7a-C1); the other
/// v1 behaviors are preserved: custom grabber whose area TAPS to close
/// (A2), channel tap presenting the Channel sheet ON TOP (03 §10.1),
/// actions auto-dismiss this sheet after firing (03 §10.1 wrapper quirk),
/// share → shortlink → UIActivityViewController with a spinner.
///
/// Presenters inject behavior: `openChannel`, `shortenURL`, the action
/// closures inside `EpisodeCardAction`, and optional status tags.
@MainActor
final class DetailViewController: UIViewController {

    /// The minimal episode facts Detail renders (03 §1.3); screens map from
    /// their own row types.
    struct Episode {
        var title: String
        var channelTitle: String
        var pubDateMilliseconds: Int64?
        /// Enclosure duration for the metadata row (the v2 "164minutes"
        /// slot); nil or zero hides the term.
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
    /// Status tag pills ("inbox" / "queued", Figma tag row); empty hides
    /// the row.
    private let tags: [String]
    private let actions: [EpisodeCardAction]
    private let htmlRenderer: HTMLContentRenderer
    private let now: () -> Date

    private let scrollView = UIScrollView()
    private let descriptionTextView: UITextView
    private let shareSpinner = UIActivityIndicatorView(style: .medium)
    private let playButton = UIButton(type: .custom)
    private let addButton = UIButton(type: .custom)

    /// CAGradientLayers have no autolayout — frames sync in
    /// viewDidLayoutSubviews and colors re-resolve per trait (§9a
    /// CGColor-freeze discipline).
    private var heroFadeLayer: CAGradientLayer!
    private var panelGradientLayer: CAGradientLayer!
    private var barGradientLayer: CAGradientLayer!

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
        tags: [String] = [],
        now: @escaping () -> Date = { Date() }
    ) {
        let controller = DetailViewController(
            episode: episode,
            actions: actions,
            htmlRenderer: htmlRenderer,
            openChannel: openChannel,
            shortenURL: shortenURL,
            tags: tags,
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
        tags: [String] = [],
        now: @escaping () -> Date = { Date() }
    ) {
        self.episode = episode
        self.actions = actions
        self.htmlRenderer = htmlRenderer
        self.openChannel = openChannel
        self.shortenURL = shortenURL
        self.tags = tags
        self.now = now
        self.descriptionTextView = HTMLContentRenderer.makeTextView()
        super.init(nibName: nil, bundle: nil)
        // VC-level: the sheet's system chrome (plate, corner treatment)
        // is created before viewDidLoad's view-level override lands.
        overrideUserInterfaceStyle = .dark
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
        // Hero fade: bottom 140pt of the artwork. Panel tint: the frosted
        // gradient spans the whole panel. Bar tint: the full play bar.
        heroFadeLayer.frame = CGRect(
            x: 0, y: (heroFadeLayer.superlayer?.bounds.height ?? 140) - 140,
            width: heroFadeLayer.superlayer?.bounds.width ?? 0, height: 140
        )
        panelGradientLayer.frame = panelGradientLayer.superlayer?.bounds ?? .zero
        barGradientLayer.frame = barGradientLayer.superlayer?.bounds ?? .zero
        // Resolve HERE, not at build time: the dark override lives on the
        // view, so the VC's traitCollection is still light during
        // viewDidLoad and build()-time cgColors froze light values (§9a).
        applyGradientColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true {
            applyGradientColors()
        }
    }

    // MARK: - Build

    private func build() {
        view.backgroundColor = Theme.surface

        // Grabber 36×5 sandAlpha4 (Figma 1784:7561) — the tap-to-close
        // band covering it stays ≤32pt (A2 adaptation, detail.dart:53-58).
        let grabber = UIView()
        grabber.backgroundColor = AnycastColor.sandAlpha4
        grabber.layer.cornerRadius = 2.5
        grabber.layer.cornerCurve = .continuous
        grabber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grabber)
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        view.addGestureRecognizer(headerTap)
        headerTap.delegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Hero: full-bleed artwork (≈ half the sheet, Figma 440×440 on a
        // 894-tall modal) fading out at the bottom into the panel.
        let hero = UIImageView()
        hero.contentMode = .scaleAspectFill
        hero.clipsToBounds = true
        hero.backgroundColor = Theme.surfaceContainerHighest
        hero.kf.setImage(with: episode.imageURL.flatMap(URL.init(string:)))
        hero.isAccessibilityElement = true
        hero.accessibilityLabel = "Episode artwork"
        hero.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hero)

        heroFadeLayer = CAGradientLayer()
        hero.layer.addSublayer(heroFadeLayer)

        // Frosted content panel (Figma: backdrop blur 50 + sand1 gradient
        // 0→50%→100%). NO UIVisualEffectView: blur materials ignore
        // overrideUserInterfaceStyle, so under the app's forced dark the
        // frost renders light (measured white block, §9a). The gradient
        // scrim alone carries the design until the V4 trait flip restores
        // real blur.
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panelGradientLayer = CAGradientLayer()
        panel.layer.addSublayer(panelGradientLayer)
        scrollView.addSubview(panel)

        let titleMetrics = UIFontMetrics(forTextStyle: .title2)
        let titleLabel = UILabel()
        // 32pt Semibold 590 (open-state header, 1784:7542). The frame paints
        // it white over the dark hero tail; without the design's 50pt blur
        // the panel is translucent there, so onSurface keeps it readable
        // (deviation noted in 09 §10).
        titleLabel.font = titleMetrics.scaledFont(
            for: .systemFont(ofSize: 32, weight: .semibold)
        )
        titleLabel.text = episode.title
        titleLabel.textColor = Theme.onSurface
        titleLabel.numberOfLines = 3
        titleLabel.adjustsFontForContentSizeCategory = true

        let metaMetrics = UIFontMetrics(forTextStyle: .subheadline)
        func metaLabel(_ text: String) -> UILabel {
            let label = UILabel()
            label.text = text
            label.font = metaMetrics.scaledFont(for: .systemFont(ofSize: 14, weight: .regular))
            label.textColor = Theme.onSurface
            label.adjustsFontForContentSizeCategory = true
            return label
        }
        let dateText = episode.pubDateMilliseconds.map {
            RelativeTimeFormatter.formatDate($0, now: now())
        } ?? ""
        var metaLabels = [metaLabel(dateText)]
        if let duration = episode.durationSeconds, duration > 0 {
            metaLabels.append(metaLabel("\(TimeFormats.formatDuration(duration)) MIN"))
        }
        let metaRow = UIStackView(arrangedSubviews: metaLabels)
        metaRow.axis = .horizontal
        metaRow.spacing = 16

        // Status tag pills (Figma tag row: h22, padding 2/12, sandAlpha4,
        // 12/18 TITLE).
        let tagRow = UIStackView()
        tagRow.axis = .horizontal
        tagRow.spacing = 8
        tagRow.isHidden = tags.isEmpty
        for tag in tags {
            let pill = UILabel()
            pill.text = tag.localizedUppercase
            pill.font = UIFontMetrics(forTextStyle: .caption1)
                .scaledFont(for: .systemFont(ofSize: 12, weight: .regular))
            pill.textColor = Theme.onSurface
            pill.backgroundColor = AnycastColor.sandAlpha4
            pill.layer.cornerRadius = 11
            pill.layer.cornerCurve = .continuous
            pill.layer.masksToBounds = true
            pill.textAlignment = .center
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.heightAnchor.constraint(equalToConstant: 22).isActive = true
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            tagRow.addArrangedSubview(pill)
        }

        // Channel host (16/28) — tap opens the Channel sheet ON TOP.
        let hostButton = UIButton(type: .system)
        var hostConfig = UIButton.Configuration.plain()
        hostConfig.baseForegroundColor = Theme.onSurface
        hostConfig.title = episode.channelTitle
        hostConfig.contentInsets = .zero
        hostButton.configuration = hostConfig
        hostButton.titleLabel?.font = UIFontMetrics(forTextStyle: .callout)
            .scaledFont(for: .systemFont(ofSize: 16, weight: .regular))
        hostButton.contentHorizontalAlignment = .leading
        hostButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        hostButton.addAction(
            UIAction { [weak self] _ in self?.channelTapped() },
            for: .touchUpInside
        )

        descriptionTextView.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 14, weight: .regular))
        descriptionTextView.textColor = Theme.onSurface
        descriptionTextView.adjustsFontForContentSizeCategory = true

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel, metaRow, tagRow, hostButton, descriptionTextView,
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12, leading: 24, bottom: 24, trailing: 24
        )
        panel.addSubview(contentStack)

        // Pinned bottom bar (Figma play zone: blur 25 + bottom-radius 56;
        // flattened to the surface-gradient band — same blur/override
        // caveat as the panel): gold ADD TO QUEUE pill (fills) + dark
        // play pill.
        let playBar = UIView()
        playBar.translatesAutoresizingMaskIntoConstraints = false
        barGradientLayer = CAGradientLayer()
        playBar.layer.addSublayer(barGradientLayer)
        view.addSubview(playBar)

        buildActionButtons(into: playBar)

        // Share: 44×44 floating circle pinned over the hero's top right
        // (the Figma header share slot, kept reachable at rest).
        let shareButton = UIButton(type: .custom)
        shareButton.setImage(AppIcons.share, for: .normal)
        shareButton.tintColor = Theme.onSurface
        shareButton.backgroundColor = Theme.surface
        shareButton.layer.cornerRadius = 22
        shareButton.layer.cornerCurve = .continuous
        shareButton.layer.shadowColor = UIColor.black.cgColor
        shareButton.layer.shadowOpacity = 0.1
        shareButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        shareButton.layer.shadowRadius = 10
        shareButton.isAccessibilityElement = true
        shareButton.accessibilityLabel = "Share episode"
        shareButton.addAction(UIAction { [weak self] _ in self?.shareTapped() }, for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareButton)

        shareSpinner.color = Theme.onSurface
        shareSpinner.hidesWhenStopped = true
        shareSpinner.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addSubview(shareSpinner)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            hero.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hero.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hero.heightAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.heightAnchor, multiplier: 0.5
            ),

            // The panel starts 24pt inside the hero tail (Figma content
            // column y416 vs artwork bottom 440) and closes the scroll
            // content (plus the play-bar clearance inset below).
            panel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            panel.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: -24),
            panel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: panel.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            playBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playBar.heightAnchor.constraint(equalToConstant: 132),

            shareButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            shareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            shareSpinner.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            shareSpinner.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),
        ])

        // The scroll content clears the pinned play bar.
        scrollView.contentInset.bottom = 140
        applyGradientColors()
    }

    /// Gold "ADD TO QUEUE" (fills) + dark play pill, mapped from the
    /// injected action payload by accessibility label (09 §10 批次1: remove
    /// retired from the bar — the lists own it via swipe/context menu).
    private func buildActionButtons(into playBar: UIView) {
        let addAction = actions.first { $0.accessibilityLabel == "Add to playlist" }
        let playAction = actions.first { $0.accessibilityLabel == "Play" }

        var addConfig = UIButton.Configuration.filled()
        if addAction != nil {
            addConfig.title = "add to queue".localizedUppercase
        }
        addConfig.baseBackgroundColor = AnycastColor.gold9
        addConfig.baseForegroundColor = AnycastColor.sand1
        addConfig.cornerStyle = .capsule
        addButton.configuration = addConfig
        addButton.accessibilityLabel = "Add to playlist"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        playBar.addSubview(addButton)
        if let addAction {
            addButton.addAction(
                UIAction { [weak self] _ in self?.fire(addAction) }, for: .touchUpInside
            )
        }

        playButton.setImage(AppIcons.play, for: .normal)
        playButton.tintColor = AnycastColor.sand1
        playButton.backgroundColor = AnycastColor.sand12
        playButton.layer.cornerRadius = 28
        playButton.layer.cornerCurve = .continuous
        playButton.accessibilityLabel = "Play"
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playBar.addSubview(playButton)
        if let playAction {
            playButton.addAction(
                UIAction { [weak self] _ in self?.fire(playAction) }, for: .touchUpInside
            )
        }

        let barRow = UIStackView(arrangedSubviews: [addButton, playButton])
        barRow.axis = .horizontal
        barRow.spacing = 12
        barRow.alignment = .center
        barRow.translatesAutoresizingMaskIntoConstraints = false
        playBar.addSubview(barRow)

        NSLayoutConstraint.activate([
            barRow.leadingAnchor.constraint(equalTo: playBar.leadingAnchor, constant: 24),
            barRow.trailingAnchor.constraint(equalTo: playBar.trailingAnchor, constant: -24),
            barRow.bottomAnchor.constraint(
                equalTo: playBar.safeAreaLayoutGuide.bottomAnchor, constant: -16
            ),
            barRow.heightAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56),
            playButton.widthAnchor.constraint(equalToConstant: 56),
            playButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    // MARK: - Gradients (§9a: re-resolve on trait change)

    private func applyGradientColors() {
        // view.traitCollection — carries the dark override (self's does not
        // until the view joins the window).
        let surface = Theme.surface.resolvedColor(with: view.traitCollection)
        heroFadeLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor,
        ]
        panelGradientLayer.locations = [0, 0.35, 0.7]
        panelGradientLayer.colors = [
            surface.withAlphaComponent(0).cgColor,
            surface.withAlphaComponent(0.55).cgColor,
            surface.withAlphaComponent(1).cgColor,
        ]
        barGradientLayer.colors = [
            surface.withAlphaComponent(0).cgColor,
            surface.withAlphaComponent(0.92).cgColor,
        ]
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

        shareSpinner.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            let short = await self.shortenURL?(url) ?? url
            self.shareSpinner.stopAnimating()
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
