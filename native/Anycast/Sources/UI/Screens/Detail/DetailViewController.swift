import UIKit
import Kingfisher

/// The episode Detail sheet (lib/widgets/detail.dart, 03 §1.3 + §3.4):
/// a standard sheet with custom detents 0.7/0.6 (largest first — the
/// DraggableScrollableSheet initialChildSize/minChildSize), scroll-linked
/// shrink provided by UISheetPresentationController, custom grabber whose
/// area TAPS to close (the system grabber is not tappable — A2), HTML
/// description via HTMLContentRenderer, channel-name tap presenting the
/// Channel ON TOP (03 §10.1: Detail does NOT close), share → shortlink →
/// UIActivityViewController with a spinner, and action buttons that
/// auto-dismiss this sheet after firing (03 §10.1 wrapper quirk).
///
/// Presenters inject behavior: `openChannel`, `shortenURL`, and the action
/// closures inside `EpisodeCardAction`. No other screen type is referenced
/// here (ChannelViewController etc. arrive in later M3 tasks).
@MainActor
final class DetailViewController: UIViewController {

    /// The minimal episode facts Detail renders (03 §1.3); screens map from
    /// their own row types.
    struct Episode {
        var title: String
        var channelTitle: String
        var pubDateMilliseconds: Int64?
        var imageURL: String?
        var rssFeedURL: String
        var enclosureURL: String
        var descriptionHTML: String

        init(
            title: String,
            channelTitle: String,
            pubDateMilliseconds: Int64? = nil,
            imageURL: String? = nil,
            rssFeedURL: String,
            enclosureURL: String,
            descriptionHTML: String = ""
        ) {
            self.title = title
            self.channelTitle = channelTitle
            self.pubDateMilliseconds = pubDateMilliseconds
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
    private let actions: [EpisodeCardAction]
    private let htmlRenderer: HTMLContentRenderer
    private let now: () -> Date

    private let scrollView = UIScrollView()
    private let descriptionTextView: UITextView
    private let shareSpinner = UIActivityIndicatorView(style: .medium)

    /// Present factory matching the Dart showModalBottomSheet +
    /// DraggableScrollableSheet 0.7/0.6 (03 §1.3). Largest detent is first,
    /// so the sheet opens at 0.70 and can shrink to 0.60 while scrolling.
    static func present(
        from presenter: UIViewController,
        episode: Episode,
        actions: [EpisodeCardAction],
        htmlRenderer: HTMLContentRenderer,
        openChannel: ((ChannelReference) -> Void)? = nil,
        shortenURL: ((URL) async -> URL?)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        let controller = DetailViewController(
            episode: episode,
            actions: actions,
            htmlRenderer: htmlRenderer,
            openChannel: openChannel,
            shortenURL: shortenURL,
            now: now
        )
        controller.modalPresentationStyle = .pageSheet
        let sheet = controller.sheetPresentationController
        // SDK 27 removed Detent.fraction; the custom resolver reproduces it
        // exactly (height = maximumDetentValue × fraction).
        func fractionDetent(_ fraction: CGFloat) -> UISheetPresentationController.Detent {
            UISheetPresentationController.Detent.custom(
                identifier: .init("detail-\(fraction)")
            ) { context in
                context.maximumDetentValue * fraction
            }
        }
        sheet?.detents = [fractionDetent(0.7), fractionDetent(0.6)]
        sheet?.prefersGrabberVisible = false
        sheet?.preferredCornerRadius = 20
        presenter.present(controller, animated: true)
    }

    init(
        episode: Episode,
        actions: [EpisodeCardAction],
        htmlRenderer: HTMLContentRenderer,
        openChannel: ((ChannelReference) -> Void)? = nil,
        shortenURL: ((URL) async -> URL?)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.episode = episode
        self.actions = actions
        self.htmlRenderer = htmlRenderer
        self.openChannel = openChannel
        self.shortenURL = shortenURL
        self.now = now
        self.descriptionTextView = HTMLContentRenderer.makeTextView()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
        build()
        renderDescription()
    }

    // MARK: - Build

    private func build() {
        let grabber = SheetGrabberView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        // Grabber-area tap closes (detail.dart:53-58).
        let headerTap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        view.addGestureRecognizer(headerTap)
        headerTap.delegate = self
        view.addSubview(grabber)

        let cover = UIImageView()
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 16
        cover.layer.cornerCurve = .continuous
        cover.backgroundColor = Theme.primaryBackground
        cover.kf.setImage(with: episode.imageURL.flatMap(URL.init(string:)))
        cover.isAccessibilityElement = true
        cover.accessibilityLabel = "Episode artwork"

        let titleLabel = UILabel()
        // headlineMedium mapping (22pt w600, 03 §2.11 detail header row).
        titleLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 22, weight: .semibold)
        )
        titleLabel.text = episode.title
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        let channelButton = UIButton(type: .system)
        var channelConfig = UIButton.Configuration.plain()
        channelConfig.baseForegroundColor = Theme.tabSelectedGreen
        var channelTitle = AttributedString(episode.channelTitle)
        channelTitle.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold)
        )
        channelTitle.underlineStyle = .single
        channelConfig.attributedTitle = channelTitle
        // Dart row: Expanded(channel name) + unconstrained date — under
        // pressure the CHANNEL truncates and the date always shows whole
        // (detail.dart). The native row used to invert that, squeezing the
        // date down to "9-…".
        channelConfig.titleLineBreakMode = .byTruncatingTail
        channelButton.configuration = channelConfig
        channelButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        channelButton.accessibilityLabel = "Open channel \(episode.channelTitle)"
        channelButton.addAction(
            UIAction { [weak self] _ in self?.channelTapped() },
            for: .touchUpInside
        )

        let dateLabel = UILabel()
        dateLabel.text = episode.pubDateMilliseconds.map {
            RelativeTimeFormatter.formatDate($0, now: now())
        } ?? ""
        dateLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        )
        dateLabel.textColor = Theme.secondaryText
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.numberOfLines = 1
        dateLabel.adjustsFontSizeToFitWidth = false
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let metaRow = UIStackView(arrangedSubviews: [channelButton])
        metaRow.axis = .horizontal
        metaRow.spacing = 12
        metaRow.alignment = .center
        metaRow.addArrangedSubview(dateLabel)

        let shareButton = UIButton(type: .custom)
        shareButton.setImage(AppIcons.share, for: .normal)
        shareButton.tintColor = Theme.primaryLightMax
        shareButton.backgroundColor = Theme.primaryBackground
        shareButton.layer.cornerRadius = 20
        shareButton.layer.cornerCurve = .continuous
        shareButton.isAccessibilityElement = true
        shareButton.accessibilityLabel = "Share episode"
        shareButton.addAction(UIAction { [weak self] _ in self?.shareTapped() }, for: .touchUpInside)

        shareSpinner.color = Theme.primaryLightMax
        shareSpinner.hidesWhenStopped = true
        shareSpinner.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addSubview(shareSpinner)

        let headerRow = UIStackView(arrangedSubviews: [cover])
        headerRow.axis = .horizontal
        headerRow.spacing = 12
        headerRow.alignment = .top
        let titleColumn = UIStackView(arrangedSubviews: [titleLabel])
        titleColumn.axis = .vertical
        titleColumn.spacing = 4
        titleColumn.addArrangedSubview(metaRow)
        headerRow.addArrangedSubview(titleColumn)
        headerRow.addArrangedSubview(shareButton)

        descriptionTextView.font = Typography.htmlBody.font()
        descriptionTextView.textColor = Typography.htmlBody.color
        descriptionTextView.adjustsFontForContentSizeCategory = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let contentStack = UIStackView(arrangedSubviews: [headerRow])
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16)
        contentStack.addArrangedSubview(descriptionTextView)
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        // Action row pinned below the scroll area (spaceEvenly, 03 §1.3).
        let actionRow = UIStackView()
        actionRow.axis = .horizontal
        actionRow.distribution = .equalSpacing
        actionRow.alignment = .center
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, action) in actions.enumerated() {
            let button = UIButton(type: .custom)
            button.setImage(action.icon, for: .normal)
            button.tintColor = Theme.primaryBackgroundDark
            button.backgroundColor = Theme.primaryLightMax
            button.layer.cornerRadius = 20
            button.layer.cornerCurve = .continuous
            button.accessibilityLabel = action.accessibilityLabel
            button.addAction(UIAction { [weak self] _ in self?.actionTapped(at: index) }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 40).isActive = true
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            actionRow.addArrangedSubview(button)
        }
        view.addSubview(actionRow)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 42),
            grabber.heightAnchor.constraint(equalToConstant: 6),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionRow.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            cover.widthAnchor.constraint(equalToConstant: 80),
            cover.heightAnchor.constraint(equalToConstant: 80),

            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            shareSpinner.centerXAnchor.constraint(equalTo: shareButton.centerXAnchor),
            shareSpinner.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),

            actionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            actionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actionRow.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8
            ),
            actionRow.heightAnchor.constraint(equalToConstant: 60),
        ])
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

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func channelTapped() {
        // 03 §10.1: present the Channel sheet ON TOP; Detail stays open.
        openChannel?(ChannelReference(rssFeedURL: episode.rssFeedURL, title: episode.channelTitle))
    }

    private func actionTapped(at index: Int) {
        guard actions.indices.contains(index) else { return }
        actions[index].handler()
        // 03 §10.1 wrapper quirk: the Detail pops itself after firing.
        dismiss(animated: true)
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
