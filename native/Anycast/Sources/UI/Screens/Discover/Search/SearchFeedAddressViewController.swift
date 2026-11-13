import UIKit
import AnycastKit

/// A pasted feed address in Search. When the submitted text is a web
/// address, Search does not run a text search: it reads that feed and shows
/// one row with the show's title and host. Tapping the row opens the show's
/// page; Follow subscribes right here.
nonisolated enum FeedAddress {

    /// The address to fetch when `text` is a web address (a scheme and a
    /// host, no spaces); nil for anything that should be searched by name.
    /// `feed://`, `itpc://` and `pcast://` are the podcast apps' own
    /// schemes for the same http address.
    static func parse(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let schemeEnd = trimmed.range(of: "://")
        else { return nil }
        let scheme = trimmed[..<schemeEnd.lowerBound].lowercased()
        let rest = String(trimmed[schemeEnd.upperBound...])
        let normalized: String
        switch scheme {
        case "http", "https": normalized = trimmed
        case "feed", "itpc", "pcast": normalized = "http://" + rest
        default: return nil
        }
        guard let host = URLComponents(string: normalized)?.host, !host.isEmpty else { return nil }
        return normalized
    }

    /// The host shown under the title.
    static func host(of address: String) -> String {
        URLComponents(string: address)?.host ?? address
    }
}

/// What the feed-address page is showing.
nonisolated enum FeedAddressPhase: Equatable {
    case loading
    case loaded(PodcastImportData)
    case notAFeed
}

@MainActor
final class SearchFeedAddressViewController: UIViewController {

    static let notAFeedText = "That address isn\u{2019}t a podcast feed."

    /// Reads the feed (newest episode only); nil when nothing that parses
    /// as a feed came back.
    typealias Fetch = @Sendable (String) async -> PodcastImportData?

    private let context: UIContext?
    private let fetch: Fetch
    private let followed: () async -> [String]
    private let subscribe: (PodcastImportData) async -> Bool

    private(set) var phase: FeedAddressPhase = .loading
    private(set) var address = ""
    private(set) var isFollowing = false
    private var loadTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    /// Where the content starts, under the header (and the field on iOS 18).
    var topInset: CGFloat = 0 {
        didSet { topConstraint?.constant = topInset + Spacing.gap }
    }
    private var topConstraint: NSLayoutConstraint?

    private let plate = UIControl()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let followButton = UIButton(type: .system)
    private let messageLabel = UILabel()

    init(
        context: UIContext?,
        fetch: Fetch? = nil,
        followed: (() async -> [String])? = nil,
        subscribe: ((PodcastImportData) async -> Bool)? = nil
    ) {
        self.context = context
        let userAgent = AppConfiguration.rssUserAgent
        self.fetch = fetch ?? { address in
            let fetcher = RSSFetcher(client: HTTPClient(), userAgent: userAgent)
            return await fetcher.fetchPodcasts(urls: [address], onlyFirstEpisode: true).first
        }
        self.followed = followed ?? {
            guard let context else { return [] }
            return ((try? await context.database.subscriptionRepository().listAll()) ?? []).compactMap(\.rssFeedUrl)
        }
        self.subscribe = subscribe ?? { data in
            guard let context else { return false }
            // The same writes as Follow on the show page: the newest
            // episode enters the Inbox, then the subscription.
            var channel = data.subscription
            if let newest = data.feedEpisodes.first {
                guard (try? await context.database.feedRepository().insertMany([newest])) != nil else { return false }
                channel.lastUpdated = newest.pubDate
            }
            guard (try? await context.database.subscriptionRepository().addMany([channel])) != nil else { return false }
            NotificationCenter.default.post(name: ShowsShelfLayout.subscriptionsDidChange, object: nil)
            return true
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        MainActor.assumeIsolated {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        build()
        render()
        observer = NotificationCenter.default.addObserver(
            forName: ShowsShelfLayout.subscriptionsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFollowing() }
        }
    }

    /// Reads `address` and shows what came of it.
    func load(address: String) {
        loadTask?.cancel()
        self.address = address
        phase = .loading
        isFollowing = false
        if isViewLoaded { render() }
        loadTask = Task { [weak self] in
            guard let self else { return }
            let fetched = await self.fetch(address)
            guard !Task.isCancelled, self.address == address else { return }
            if let fetched {
                let key = ImportPlan.feedKey(address)
                self.isFollowing = await self.followed().contains { ImportPlan.feedKey($0) == key }
                guard !Task.isCancelled, self.address == address else { return }
                self.phase = .loaded(fetched)
            } else {
                self.phase = .notAFeed
            }
            if self.isViewLoaded { self.render() }
        }
    }

    private func refreshFollowing() {
        guard case .loaded = phase else { return }
        let key = ImportPlan.feedKey(address)
        Task { [weak self] in
            guard let self else { return }
            let now = await self.followed().contains { ImportPlan.feedKey($0) == key }
            guard now != self.isFollowing else { return }
            self.isFollowing = now
            self.render()
        }
    }

    // MARK: - Build

    private func build() {
        plate.backgroundColor = Theme.surface
        plate.layer.cornerRadius = Radius.card
        plate.layer.cornerCurve = .continuous
        plate.accessibilityIdentifier = "search-feed-row"
        plate.addAction(UIAction { [weak self] _ in self?.openShow() }, for: .touchUpInside)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.artwork
        coverView.layer.cornerCurve = .continuous

        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        hostLabel.font = TypographyV2.meta.font()
        hostLabel.textColor = Theme.onSurfaceVariant
        hostLabel.adjustsFontForContentSizeCategory = true
        hostLabel.numberOfLines = 1

        followButton.accessibilityIdentifier = "search-feed-follow"
        followButton.setContentHuggingPriority(.required, for: .horizontal)
        followButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        followButton.addAction(UIAction { [weak self] _ in self?.followTapped() }, for: .touchUpInside)

        let texts = UIStackView(arrangedSubviews: [titleLabel, hostLabel])
        texts.axis = .vertical
        texts.spacing = Spacing.xxs
        let row = UIStackView(arrangedSubviews: [coverView, texts, followButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.gap
        row.isUserInteractionEnabled = true
        row.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(row)
        // Touches on the labels fall through to the plate; the button keeps its own.
        for item in [coverView, texts] { item.isUserInteractionEnabled = false }

        messageLabel.text = Self.notAFeedText
        messageLabel.font = TypographyV2.body.font()
        messageLabel.textColor = Theme.onSurfaceVariant
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "search-feed-message"

        for item in [plate, messageLabel] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        let top = plate.topAnchor.constraint(equalTo: view.topAnchor, constant: topInset + Spacing.gap)
        topConstraint = top
        NSLayoutConstraint.activate([
            top,
            plate.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            plate.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),

            coverView.widthAnchor.constraint(equalToConstant: PodcastCardCell.coverSide),
            coverView.heightAnchor.constraint(equalToConstant: PodcastCardCell.coverSide),
            row.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.gap),
            row.bottomAnchor.constraint(equalTo: plate.bottomAnchor, constant: -Spacing.gap),
            row.leadingAnchor.constraint(equalTo: plate.leadingAnchor, constant: Spacing.gap),
            row.trailingAnchor.constraint(equalTo: plate.trailingAnchor, constant: -Spacing.gap),

            messageLabel.topAnchor.constraint(equalTo: plate.topAnchor, constant: Spacing.gap),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH + Spacing.gap),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(Spacing.pageH + Spacing.gap)),
        ])
    }

    // MARK: - Render

    private func render() {
        switch phase {
        case .loading:
            plate.isHidden = false
            messageLabel.isHidden = true
            plate.isUserInteractionEnabled = false
            followButton.isHidden = true
            coverView.kf.cancelDownloadTask()
            coverView.image = nil
            coverView.backgroundColor = AnycastColor.sandAlpha4
            func bar(_ text: String, _ font: UIFont) -> NSAttributedString {
                NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: UIColor.clear, .backgroundColor: AnycastColor.sandAlpha4,
                ])
            }
            titleLabel.attributedText = bar("Placeholder show title", titleLabel.font)
            hostLabel.attributedText = bar("placeholder.example", hostLabel.font)
            plate.isAccessibilityElement = true
            plate.accessibilityLabel = "Loading"
        case .notAFeed:
            plate.isHidden = true
            messageLabel.isHidden = false
            UIAccessibility.post(notification: .announcement, argument: Self.notAFeedText)
        case .loaded(let data):
            plate.isHidden = false
            messageLabel.isHidden = true
            plate.isUserInteractionEnabled = true
            coverView.backgroundColor = nil
            let title = data.subscription.title ?? ""
            titleLabel.attributedText = nil
            titleLabel.text = title
            hostLabel.attributedText = nil
            hostLabel.text = FeedAddress.host(of: address)
            coverView.setArtwork(
                data.subscription.imageUrl.flatMap(URL.init(string:)), title: title, side: PodcastCardCell.coverSide
            )
            followButton.isHidden = false
            var configuration = AnycastButton.configuration(isFollowing ? .secondary : .primary, title: isFollowing ? "Following" : "Follow")
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: Spacing.md, leading: Spacing.cardInner, bottom: Spacing.md, trailing: Spacing.cardInner
            )
            followButton.configuration = configuration
            followButton.isEnabled = !isFollowing
            plate.isAccessibilityElement = true
            plate.accessibilityLabel = "\(title), \(FeedAddress.host(of: address))"
            plate.accessibilityTraits = .button
            plate.accessibilityHint = "Opens the show"
            plate.accessibilityCustomActions = isFollowing ? [] : [
                UIAccessibilityCustomAction(name: "Follow") { [weak self] _ in
                    self?.followTapped()
                    return true
                },
            ]
        }
    }

    // MARK: - Actions

    private func openShow() {
        guard case .loaded(let data) = phase, let context else { return }
        ChannelViewController.present(
            from: self, context: context, rssFeedURL: address, seed: data.subscription
        )
    }

    private func followTapped() {
        guard case .loaded(let data) = phase, !isFollowing else { return }
        isFollowing = true
        render()
        Task { [weak self] in
            guard let self else { return }
            let ok = await self.subscribe(data)
            if !ok {
                self.isFollowing = false
                self.render()
                if let window = self.view.window {
                    ToastPresenter.shared.show("Couldn\u{2019}t save. Try again.", in: window, duration: 3)
                }
            }
        }
    }
}
