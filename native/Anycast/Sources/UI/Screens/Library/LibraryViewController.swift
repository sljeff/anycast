import UIKit
import AnycastKit

/// The v2 library tab (Figma `library` 86:2814 — 09 §3.3, V2 wrap scope):
/// the v2 header over a membership placeholder block and the existing
/// Subscriptions page, which moves here from the retired inner tab. The
/// Figma `library block` chrome (pill row + surface card, cover strip,
/// `recent` block) is the V3 batch-2 deepening — this pass only lands the
/// IA move plus the membership placeholder (upgrade row: goldAlpha2 fill +
/// sandAlpha4 hairline + radius 16, Figma 628:6365/366:5127).
@MainActor
final class LibraryViewController: UIViewController {

    private let context: UIContext

    private let header = HeaderView()
    private let subscriptions: SubscriptionsPageViewController
    private var notificationObserver: NSObjectProtocol?

    init(context: UIContext) {
        self.context = context
        self.subscriptions = SubscriptionsPageViewController(context: context)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

        header.configure(HeaderView.Configuration(title: "library"))
        header.onSettings = { [weak self] in
            guard let self else { return }
            AppSheets.presentExpand(SettingsViewController(context: self.context), from: self.topMostPresented())
        }
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let membership = buildMembershipCard()
        membership.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(membership)

        let blockRow = buildBlockRow()
        blockRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blockRow)

        // The wrapped Subscriptions list shares the 16 pt page grid with the
        // chrome above it; hosting it full-bleed preserves the v1 list rhythm
        // under the new chrome (the surface-card block visual is V3 batch-2
        // scope).
        addChild(subscriptions)
        subscriptions.view.backgroundColor = .clear
        subscriptions.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subscriptions.view)
        subscriptions.didMove(toParent: self)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            membership.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            membership.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            membership.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Spacing.chip),

            blockRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Spacing.pageH),
            blockRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Spacing.pageH),
            blockRow.topAnchor.constraint(equalTo: membership.bottomAnchor, constant: Spacing.chip),

            subscriptions.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subscriptions.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subscriptions.view.topAnchor.constraint(equalTo: blockRow.bottomAnchor, constant: Spacing.xs),
            subscriptions.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        notificationObserver = NotificationCenter.default.addObserver(
            forName: SubscriptionsPageViewController.subscriptionsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        refreshStatus()
    }

    // MARK: - Status line ("100 episodes remain" placeholder → live count)

    private func refreshStatus() {
        Task { [weak self] in
            guard let self else { return }
            let count = (try? await self.context.database.subscriptionRepository().listAll())?.count ?? 0
            self.header.configure(HeaderView.Configuration(
                title: "library",
                statusText: Self.statusText(showCount: count)
            ))
        }
    }

    /// Pure status text derivation (testable without the view).
    static func statusText(showCount: Int) -> String {
        "\(showCount) show\(showCount == 1 ? "" : "s")"
    }

    // MARK: - Membership placeholder (V3 batch-5 wires the paywall action)

    private func buildMembershipCard() -> UIView {
        let card = UIControl()
        card.backgroundColor = AnycastColor.goldAlpha2
        card.layer.borderColor = AnycastColor.sandAlpha4.cgColor
        card.layer.borderWidth = 0.5
        card.layer.cornerRadius = Radius.md
        card.layer.cornerCurve = .continuous
        card.accessibilityIdentifier = "library-membership"

        let iconContainer = UIView()
        iconContainer.backgroundColor = AnycastColor.goldAlpha3
        iconContainer.layer.cornerRadius = Spacing.large / 2
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "wand.and.stars"))
        icon.tintColor = Theme.primary
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = "anycast membership"
        titleLabel.font = TypographyV2.titleMedium.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.onSurface

        let messageLabel = UILabel()
        messageLabel.text = "Upgrade for AI transcripts and chat"
        messageLabel.font = TypographyV2.bodySmall.font()
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = Theme.onSurfaceVariant

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        textColumn.axis = .vertical
        textColumn.spacing = Spacing.xxs
        textColumn.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Theme.onSurfaceVariant
        chevron.contentMode = .center
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconContainer)
        card.addSubview(textColumn)
        card.addSubview(chevron)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Spacing.pageH),
            iconContainer.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Spacing.large),
            iconContainer.heightAnchor.constraint(equalToConstant: Spacing.large),
            card.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            // The text column spans the card vertically (20 pt inner
            // padding) — a centerY-only pin left the card height ambiguous
            // and Auto Layout stretched it over the whole page, crushing
            // the embedded Subscriptions list to zero height.
            textColumn.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: Spacing.gap),
            textColumn.topAnchor.constraint(equalTo: card.topAnchor, constant: Spacing.cardInner),
            textColumn.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Spacing.cardInner),
            textColumn.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -Spacing.md),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Spacing.pageH),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: Spacing.row),
        ])
        return card
    }

    // MARK: - "all shows" block row (Figma library block 628:6406)

    private func buildBlockRow() -> UIView {
        let pill = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "chevron.right")
        config.imagePlacement = .trailing
        config.imagePadding = Spacing.xs
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 14, weight: .semibold
        )
        config.baseForegroundColor = Theme.onSurfaceVariant
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.xs, bottom: 0, trailing: Spacing.xs
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .systemFont(ofSize: 16, weight: .semibold)
            )
            return outgoing
        }
        config.title = "all shows"
        pill.configuration = config
        pill.accessibilityIdentifier = "library-all-shows"
        pill.translatesAutoresizingMaskIntoConstraints = false

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(pill)
        NSLayoutConstraint.activate([
            // Page-grid alignment (16): the row must line up with the
            // membership card and the list cards below, not float at the
            // pill's own 6 pt content inset.
            pill.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Spacing.pageH),
            pill.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pill.topAnchor.constraint(equalTo: row.topAnchor),
            pill.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }
}
