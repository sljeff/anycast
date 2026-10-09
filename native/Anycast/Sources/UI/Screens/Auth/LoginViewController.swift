import UIKit
import SafariServices
import AnycastKit

/// Login sheet (lib/pages/login.dart, 03 §2.14 / §1.3 row 7): presented as
/// a full-height expand sheet by Settings ("Account") and by the global 401
/// coordinator. Logged-out = centered brand column + three auth buttons
/// (Apple/Google run under a full-screen spinner; Email opens the form sheet
/// with no spinner — 2026-09-22 correction). Logged-in = user info card,
/// subscription card, paywall (autoplaying carousel + plans + purchase /
/// restore), privacy links, remove account.
final class LoginViewController: UIViewController {

    private let context: UIContext
    private let store: PaywallStore

    // View state.
    private var planSelection = LoginPageModel.PlanSelection()
    private var availablePlans: [LoginPageModel.PlanCard] = []
    private var userRecord: User?
    private var isSubscribed = false
    private var plusExpiration: Date?
    private var plusIntroExpanded = true
    private var offeringsLoadStarted = false
    private var carouselModel = LoginPageModel.CarouselAutoplay()
    /// Autoplay may only tick while the sheet is on screen (viewDidAppear
    /// ... viewWillDisappear); viewDidLayoutSubviews can still fire while a
    /// presented sheet covers this one.
    private var isViewAppeared = false

    // Logged-out / logged-in subtrees.
    private let switcherView = UIView()
    private let loggedOutStack = UIStackView()
    private let loggedInScrollView = UIScrollView()
    private let loggedInStack = UIStackView()

    // User Info card.
    private let avatarIconView = UIView()
    private let avatarInnerStack = UIStackView()
    private let emailLabel = UILabel()

    // Subscription card.
    private let tierLabel = UILabel()
    private let expiryLabel = UILabel()
    private let remainingCountLabel = UILabel()
    private let remainingSuffixLabel = UILabel()

    // Paywall.
    private var carouselView: UICollectionView?
    private var carouselTimer: Timer?
    private let offeringsContainer = UIStackView()
    private let offeringsSpinner = UIActivityIndicatorView(style: .medium)
    private var planCardViews: [(id: String, view: PlanCardView)] = []
    private var plusIntroTitleLabel: UILabel?
    private var plusIntroContentStack: UIStackView?
    private var plusIntroChevron: UIImageView?
    private var tooltipView: UIView?
    private var tooltipTimer: Timer?

    /// AnycastTheme.dark `error` token — the Dart sign-out/delete copy color
    /// (0xFFFF8B8B); 03 §5.1 carries no error colorset for it.
    static let errorColor = UIColor(red: 1.0, green: 0.545, blue: 0.545, alpha: 1)

    init(context: UIContext) {
        self.context = context
        self.store = PaywallStore(purchases: context.purchases)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        // Teardown runs on the main thread; the timer is not Sendable so the
        // access goes through an isolated assertion (sibling idiom).
        MainActor.assumeIsolated {
            carouselTimer?.invalidate()
            tooltipTimer?.invalidate()
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        buildLoggedOutColumn()
        buildLoggedInList()

        switcherView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(switcherView)
        NSLayoutConstraint.activate([
            switcherView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            switcherView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            switcherView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            switcherView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        refreshState()
    }

    /// Retry a failed offerings fetch on re-appearance: `offeringsLoadStarted`
    /// latches after the first attempt, so without this a fetch failure would
    /// leave the plans empty (spinner only) for the sheet's whole lifetime.
    /// The explicit force-reload path (purchase/restore) is unchanged.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if availablePlans.isEmpty, store.isConfigured {
            reloadOfferings(force: true)
        }
    }

    /// Refresh on re-appearance: the Email form sheet pops itself on success
    /// (states/user.dart:223 Get.back) and this sheet must flip to the
    /// logged-in list — the Obx equivalent.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewAppeared = true
        refreshState()
        startCarouselTimer()
    }

    /// The autoplay timer must not keep ticking while this sheet is off
    /// screen (dismissed, or covered by a presented sheet).
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewAppeared = false
        carouselTimer?.invalidate()
        carouselTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startCarouselTimer()
    }

    // MARK: - State refresh

    private func refreshState() {
        let account = AuthAccountSnapshot.current(context: context)
        loggedOutStack.isHidden = account.signedIn
        loggedInScrollView.isHidden = !account.signedIn
        updateUserCard(account)
        // Dart renders the card instantly from cached state (rc isSubscribed
        // Rx + FutureBuilder "..."), before any fetch resolves.
        updateSubscriptionCard()
        reloadSubscriptionData()
        reloadOfferings(force: false)
    }

    // MARK: - Logged-out (login.dart:29-139)

    private func buildLoggedOutColumn() {
        loggedOutStack.axis = .vertical
        loggedOutStack.alignment = .center
        loggedOutStack.translatesAutoresizingMaskIntoConstraints = false
        loggedOutStack.isHidden = true
        switcherView.addSubview(loggedOutStack)
        let width = loggedOutStack.widthAnchor.constraint(equalToConstant: 300)
        width.priority = .defaultHigh
        width.isActive = true
        NSLayoutConstraint.activate([
            loggedOutStack.centerXAnchor.constraint(equalTo: switcherView.centerXAnchor),
            loggedOutStack.centerYAnchor.constraint(equalTo: switcherView.centerYAnchor),
            loggedOutStack.widthAnchor.constraint(lessThanOrEqualTo: switcherView.widthAnchor, constant: -32),
        ])

        let logo = UIImageView(image: Self.brandLogoImage())
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 22
        logo.layer.cornerCurve = .continuous
        logo.layer.masksToBounds = true
        logo.isAccessibilityElement = false

        let headline = UILabel()
        headline.text = LoginPageModel.signUpHeadline
        headline.font = Self.font(17, .semibold, .body)
        headline.textColor = Theme.primaryLightMax
        headline.textAlignment = .center
        headline.numberOfLines = 0
        headline.adjustsFontForContentSizeCategory = true

        loggedOutStack.addArrangedSubview(logo)
        loggedOutStack.addSpacer(50)
        loggedOutStack.addArrangedSubview(headline)
        loggedOutStack.addSpacer(50)

        let apple = Self.authButton(
            title: LoginPageModel.appleButtonTitle,
            background: Theme.primaryLightMax,
            foreground: Theme.primaryBackgroundDark,
            icon: { UIImageView(image: AppIcons.appleLogo) },
            iconSize: 22
        ) { [weak self] in
            self?.runWithSpinner { presenting in
                try await self?.context.auth.signInWithApple(presenting: presenting)
            }
        }

        let google = Self.authButton(
            title: LoginPageModel.googleButtonTitle,
            background: Theme.primaryLightMax,
            foreground: Theme.primaryBackgroundDark,
            icon: { GoogleMarkView() },
            iconSize: 20
        ) { [weak self] in
            self?.runWithSpinner { presenting in
                try await self?.context.auth.signInWithGoogle(presenting: presenting)
            }
        }

        // Email: dark 12% surface, no spinner — opens the form sheet directly.
        let email = Self.authButton(
            title: LoginPageModel.emailButtonTitle,
            background: UIColor.black.withAlphaComponent(0.12),
            foreground: Theme.primaryLightMax,
            icon: { UIImageView(image: AppIcons.email) },
            iconSize: 16
        ) { [weak self] in
            guard let self else { return }
            AppSheets.presentForm(EmailLoginViewController(context: self.context), from: self)
        }

        loggedOutStack.addArrangedSubview(apple)
        loggedOutStack.addSpacer(10)
        loggedOutStack.addArrangedSubview(google)
        loggedOutStack.addSpacer(10)
        loggedOutStack.addArrangedSubview(email)
        // Buttons fill the 300-wide column (login.dart:31, 54-58).
        for button in [apple, google, email] {
            button.widthAnchor.constraint(equalTo: loggedOutStack.widthAnchor).isActive = true
        }

        logo.widthAnchor.constraint(equalToConstant: 100).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 100).isActive = true
    }

    /// `assets/icon/icon.png` is not in the native asset catalog; the app
    /// icon set substitutes when loadable, else a drawn brand tile. T11 gap.
    private static func brandLogoImage() -> UIImage {
        if let icon = UIImage(named: "AppIcon") { return icon }
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 22)
            Theme.primary.setFill()
            path.fill()
            let icon = AppIcons.playerMain.withTintColor(.white, renderingMode: .alwaysOriginal)
            let side: CGFloat = 56
            icon.draw(in: CGRect(
                x: (size.width - side) / 2, y: (size.height - side) / 2,
                width: side, height: side
            ))
        }
    }

    private static func authButton(
        title: String,
        background: UIColor,
        foreground: UIColor,
        icon: @escaping () -> UIView,
        iconSize: CGFloat,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = background
        button.layer.cornerRadius = 24
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.tintColor = foreground

        let iconView = icon()
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Self.font(16, .semibold, .body)
        titleLabel.textColor = foreground
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        let row = UIStackView(arrangedSubviews: [iconView, titleLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Logged-in list (login.dart:142-157)

    private func buildLoggedInList() {
        loggedInScrollView.alwaysBounceVertical = true
        loggedInScrollView.showsVerticalScrollIndicator = false
        loggedInScrollView.translatesAutoresizingMaskIntoConstraints = false
        loggedInScrollView.isHidden = true
        switcherView.addSubview(loggedInScrollView)

        loggedInStack.axis = .vertical
        loggedInStack.alignment = .fill
        loggedInStack.spacing = 0
        loggedInStack.isLayoutMarginsRelativeArrangement = true
        loggedInStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8, leading: 20, bottom: 40, trailing: 20
        )
        loggedInStack.translatesAutoresizingMaskIntoConstraints = false
        loggedInScrollView.addSubview(loggedInStack)

        loggedInStack.addArrangedSubview(buildUserCard())
        loggedInStack.addSpacer(20)
        loggedInStack.addArrangedSubview(buildSubscriptionCard())
        loggedInStack.addSpacer(20)
        loggedInStack.addArrangedSubview(buildPaywallCard())
        loggedInStack.addSpacer(30)
        loggedInStack.addArrangedSubview(buildPrivacyLinks())
        loggedInStack.addSpacer(30)
        loggedInStack.addArrangedSubview(buildRemoveAccountButton())

        NSLayoutConstraint.activate([
            loggedInScrollView.leadingAnchor.constraint(equalTo: switcherView.leadingAnchor),
            loggedInScrollView.trailingAnchor.constraint(equalTo: switcherView.trailingAnchor),
            loggedInScrollView.topAnchor.constraint(equalTo: switcherView.topAnchor),
            loggedInScrollView.bottomAnchor.constraint(equalTo: switcherView.bottomAnchor),
            loggedInStack.leadingAnchor.constraint(equalTo: loggedInScrollView.contentLayoutGuide.leadingAnchor),
            loggedInStack.trailingAnchor.constraint(equalTo: loggedInScrollView.contentLayoutGuide.trailingAnchor),
            loggedInStack.topAnchor.constraint(equalTo: loggedInScrollView.contentLayoutGuide.topAnchor),
            loggedInStack.bottomAnchor.constraint(equalTo: loggedInScrollView.contentLayoutGuide.bottomAnchor),
            loggedInStack.widthAnchor.constraint(equalTo: loggedInScrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    // MARK: User Info card (login.dart:165-307)

    private func buildUserCard() -> UIView {
        let card = Self.card()
        let stack = card.contentStack

        let title = Self.label(LoginPageModel.userInfoTitle, font: Self.font(16, .medium, .body))

        avatarIconView.backgroundColor = Theme.cardBackground
        avatarIconView.layer.cornerRadius = 25
        avatarIconView.layer.cornerCurve = .continuous
        avatarIconView.translatesAutoresizingMaskIntoConstraints = false
        avatarInnerStack.axis = .vertical
        avatarInnerStack.alignment = .center
        avatarInnerStack.isUserInteractionEnabled = false
        avatarInnerStack.translatesAutoresizingMaskIntoConstraints = false
        avatarIconView.addSubview(avatarInnerStack)
        avatarIconView.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            avatarIconView.widthAnchor.constraint(equalToConstant: 50),
            avatarIconView.heightAnchor.constraint(equalToConstant: 50),
            avatarInnerStack.centerXAnchor.constraint(equalTo: avatarIconView.centerXAnchor),
            avatarInnerStack.centerYAnchor.constraint(equalTo: avatarIconView.centerYAnchor),
        ])

        emailLabel.font = Self.font(15, .semibold, .subheadline)
        emailLabel.textColor = Theme.primaryLightMax
        emailLabel.numberOfLines = 2
        emailLabel.adjustsFontForContentSizeCategory = true
        emailLabel.lineBreakMode = .byTruncatingMiddle
        // 750, not required: at accessibility sizes a long address has to be
        // squeezable — required hugging/resistance here would break another
        // required constraint in the row instead.
        emailLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        emailLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let menuButton = UIButton(type: .system)
        menuButton.setImage(AppIcons.more, for: .normal)
        menuButton.tintColor = Theme.secondaryText
        menuButton.accessibilityLabel = "Account menu"
        menuButton.menu = UIMenu(children: [
            UIAction(title: LoginPageModel.copyEmailMenuTitle, image: AppIcons.copy) { [weak self] _ in
                UIPasteboard.general.string = self?.currentEmail ?? ""
            },
            UIAction(
                title: LoginPageModel.signOutMenuTitle,
                image: AppIcons.signInOut
            ) { [weak self] _ in
                self?.presentSignOutConfirmation()
            },
        ])
        menuButton.showsMenuAsPrimaryAction = true

        let row = UIStackView(arrangedSubviews: [avatarIconView, emailLabel, menuButton])
        row.axis = .horizontal
        row.spacing = 15
        row.alignment = .center

        stack.addArrangedSubview(title)
        stack.addSpacer(15)
        stack.addArrangedSubview(row)
        return card.container
    }

    private var currentEmail: String? {
        AuthAccountSnapshot.current(context: context).email
    }

    private func updateUserCard(_ account: LoginPageModel.AccountSnapshot) {
        emailLabel.text = LoginPageModel.emailDisplay(for: account)
        avatarInnerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch LoginPageModel.providerIcon(providerID: account.providerID) {
        case .apple:
            addAvatarIcon(UIImageView(image: AppIcons.appleLogo), pointSize: 24)
        case .google:
            addAvatarIcon(GoogleMarkView(), pointSize: 22)
        case .email:
            addAvatarIcon(UIImageView(image: AppIcons.email), pointSize: 20)
        }
    }

    private func addAvatarIcon(_ iconView: UIView, pointSize: CGFloat) {
        if let imageView = iconView as? UIImageView {
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = Theme.secondaryText
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        avatarInnerStack.addArrangedSubview(iconView)
        iconView.widthAnchor.constraint(equalToConstant: pointSize).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: pointSize).isActive = true
    }

    private func presentSignOutConfirmation() {
        let alert = UIAlertController(
            title: LoginPageModel.signOutAlertTitle,
            message: LoginPageModel.signOutAlertBody,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: LoginPageModel.signOutMenuTitle, style: .destructive) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.context.auth.signOut(purchases: self.context.purchases)
                    self.refreshState()
                }
            }
        )
        alert.addAction(UIAlertAction(title: LoginPageModel.cancelTitle, style: .default))
        present(alert, animated: true)
    }

    // MARK: Subscription card (login.dart:309-396)

    private func buildSubscriptionCard() -> UIView {
        let card = Self.card()
        let stack = card.contentStack

        tierLabel.font = Self.font(16, .semibold, .body)
        tierLabel.textColor = Theme.primaryLightMax
        tierLabel.adjustsFontForContentSizeCategory = true

        expiryLabel.font = Self.font(15, .regular, .subheadline)
        expiryLabel.textColor = Theme.primaryLightMax
        expiryLabel.adjustsFontForContentSizeCategory = true

        remainingCountLabel.font = Self.font(16, .bold, .body)
        remainingCountLabel.textColor = Theme.primary
        remainingCountLabel.adjustsFontForContentSizeCategory = true

        remainingSuffixLabel.font = Self.font(15, .regular, .subheadline)
        remainingSuffixLabel.textColor = Theme.primaryLightMax
        remainingSuffixLabel.adjustsFontForContentSizeCategory = true
        remainingSuffixLabel.numberOfLines = 0

        let remainingRow = UIStackView(arrangedSubviews: [remainingCountLabel, remainingSuffixLabel])
        remainingRow.axis = .horizontal
        remainingRow.alignment = .firstBaseline
        remainingRow.spacing = 0

        stack.addArrangedSubview(tierLabel)
        stack.addSpacer(8)
        stack.addArrangedSubview(expiryLabel)
        stack.addSpacer(8)
        stack.addArrangedSubview(remainingRow)
        return card.container
    }

    private func reloadSubscriptionData() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            async let subscribed = self.context.purchases.isSubscribed()
            async let expiration = self.store.plusExpirationDate()
            self.isSubscribed = await subscribed
            self.plusExpiration = await expiration
            // Tier paints as soon as RevenueCat answers — before /api/user.
            self.updateSubscriptionCard()

            if let result = try? await self.context.api.getUser() {
                switch result {
                case .user(let user):
                    self.userRecord = user
                case .invalidFields:
                    break
                case .error(.loginRequired):
                    // handle401 parity (api/user.dart:36-39); the coordinator
                    // dedupes while this sheet is the presented login.
                    self.context.presentLogin()
                case .error:
                    break
                }
            }
            self.updateSubscriptionCard()
        }
    }

    private func updateSubscriptionCard() {
        let card = LoginPageModel.subscriptionCard(
            isSubscribed: isSubscribed,
            plusExpiration: plusExpiration,
            remaining: userRecord?.remaining,
            plusFlag: userRecord?.plus
        )
        tierLabel.text = card.tierTitle
        expiryLabel.isHidden = !card.showsExpiry
        expiryLabel.text = card.expiryLine.map { "Plan expires on \($0)" }
        if let count = card.remainingCount {
            remainingCountLabel.text = "\(count)"
            remainingSuffixLabel.text = card.remainingSuffix
        } else {
            remainingCountLabel.text = ""
            remainingSuffixLabel.text = "..."
        }
    }

    // MARK: Paywall card (login.dart:398-645)

    private func buildPaywallCard() -> UIView {
        let card = Self.card()
        let stack = card.contentStack

        let title = Self.label(LoginPageModel.paywallTitle, font: Self.font(15, .bold, .subheadline))

        let infoButton = UIButton(type: .system)
        infoButton.setImage(AppIcons.infoOutline, for: .normal)
        infoButton.tintColor = Theme.secondaryText
        infoButton.accessibilityLabel = "Auto renewal information"
        infoButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        infoButton.addAction(UIAction { [weak self, weak infoButton] _ in
            guard let self, let infoButton else { return }
            self.showTooltip(below: infoButton)
        }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), infoButton])
        header.axis = .horizontal
        header.alignment = .center

        stack.addArrangedSubview(header)
        stack.addSpacer(15)
        stack.addArrangedSubview(makeCarousel())

        offeringsSpinner.color = Theme.secondaryText
        offeringsSpinner.startAnimating()
        offeringsContainer.axis = .vertical
        offeringsContainer.alignment = .fill
        offeringsContainer.spacing = 15
        offeringsContainer.addArrangedSubview(offeringsSpinner)

        stack.addSpacer(15)
        stack.addArrangedSubview(offeringsContainer)
        stack.addSpacer(10)

        let restore = UIButton(type: .system)
        restore.setTitle(LoginPageModel.restorePurchasesTitle, for: .normal)
        restore.setTitleColor(Theme.secondaryText, for: .normal)
        restore.titleLabel?.font = Self.font(12, .semibold, .caption1)
        restore.titleLabel?.adjustsFontForContentSizeCategory = true
        restore.addAction(UIAction { [weak self] _ in self?.restoreTapped() }, for: .touchUpInside)
        stack.addArrangedSubview(restore)
        return card.container
    }

    private func makeCarousel() -> UIView {
        // Compositional orthogonal + group paging + a 4 s timer — the mapped
        // carousel equivalent (07 §2.7), aspect 2:1 full-width slides.
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.5)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .groupPaging
            return section
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(
            IntroSlideCell.self, forCellWithReuseIdentifier: IntroSlideCell.reuseIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // A stack view gets no intrinsic height from a collection view — pin
        // the 2:1 aspect explicitly (carousel_slider aspectRatio, 03 §2.14).
        collectionView.heightAnchor.constraint(
            equalTo: collectionView.widthAnchor, multiplier: 0.5
        ).isActive = true
        collectionView.isAccessibilityElement = true
        collectionView.accessibilityLabel = "Subscription introduction"
        carouselView = collectionView
        return collectionView
    }

    private func startCarouselTimer() {
        guard isViewAppeared, carouselTimer == nil else { return }
        carouselTimer = Timer.scheduledTimer(
            withTimeInterval: LoginPageModel.CarouselAutoplay.autoplayInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.carouselTick()
            }
        }
    }

    private func carouselTick() {
        let before = carouselModel.pageIndex
        carouselModel.tick()
        guard
            carouselModel.pageIndex != before,
            let collectionView = carouselView,
            collectionView.window != nil
        else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: carouselModel.pageIndex, section: 0),
            at: .centeredHorizontally,
            animated: true
        )
    }

    private func showTooltip(below anchor: UIView) {
        tooltipTimer?.invalidate()
        tooltipView?.removeFromSuperview()

        // Tooltip copy + 4 s display (login.dart:416-421).
        let bubble = UIView()
        bubble.backgroundColor = Theme.primaryBackgroundDark
        bubble.layer.borderColor = Theme.cardOutline.cgColor
        bubble.layer.borderWidth = 1
        bubble.layer.cornerRadius = 8
        bubble.layer.cornerCurve = .continuous
        bubble.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = LoginPageModel.autoRenewalTooltip
        label.font = Self.font(13, .regular, .footnote)
        label.textColor = Theme.primaryLightMax
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        // Attach inside the scroll content: the bubble is constrained to an
        // anchor in the scrolled tree, and scrolling re-layouts only the
        // scroll view's subtree — a bubble pinned outside it would freeze in
        // place while the anchor moves. Inside the content the constraints
        // track the anchor for free.
        loggedInScrollView.addSubview(bubble)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            bubble.trailingAnchor.constraint(equalTo: anchor.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 8),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])
        tooltipView = bubble
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissTooltip()
            }
        }
    }

    private func dismissTooltip() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
        tooltipView?.removeFromSuperview()
        tooltipView = nil
    }

    // MARK: Offerings / plan cards (login.dart:448-516, 577-645, 648-720)

    private func reloadOfferings(force: Bool) {
        guard force || !offeringsLoadStarted else { return }
        offeringsLoadStarted = true
        offeringsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        offeringsContainer.addArrangedSubview(offeringsSpinner)
        offeringsSpinner.isHidden = false
        offeringsSpinner.startAnimating()

        Task { @MainActor [weak self] in
            guard let self else { return }
            // nil (unconfigured store, fetch failure) → the spinner stays —
            // FutureBuilder parity (login.dart:450-452).
            guard let plans = try? await self.store.availablePlans() else { return }
            self.availablePlans = plans
            self.buildOfferingsContent()
        }
    }

    private func buildOfferingsContent() {
        offeringsSpinner.stopAnimating()
        offeringsSpinner.isHidden = true
        offeringsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        planCardViews.removeAll()

        offeringsContainer.addArrangedSubview(makePlusIntro())

        let cardsRow = UIStackView()
        cardsRow.axis = .horizontal
        cardsRow.distribution = .fillEqually
        cardsRow.spacing = 8
        for plan in availablePlans {
            let cardView = PlanCardView(plan: plan)
            cardView.isSelectedPlan = planSelection.isSelected(plan)
            cardView.onSelect = { [weak self] id in
                self?.selectPlan(id)
            }
            planCardViews.append((plan.productID, cardView))
            cardsRow.addArrangedSubview(cardView.columnWithCaption)
        }
        offeringsContainer.addArrangedSubview(cardsRow)

        let confirm = UIButton(type: .system)
        confirm.backgroundColor = Theme.primaryLightMax
        confirm.setTitleColor(Theme.primaryBackgroundDark, for: .normal)
        confirm.setTitle(LoginPageModel.confirmPurchaseTitle, for: .normal)
        confirm.titleLabel?.font = Self.font(17, .semibold, .body)
        confirm.titleLabel?.adjustsFontForContentSizeCategory = true
        confirm.layer.cornerRadius = 24
        confirm.layer.cornerCurve = .continuous
        confirm.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        confirm.addAction(
            UIAction { [weak self] _ in self?.confirmPurchaseTapped() },
            for: .touchUpInside
        )
        offeringsContainer.addArrangedSubview(confirm)
    }

    private func selectPlan(_ id: String) {
        planSelection.choose(id)
        for (planID, view) in planCardViews {
            view.isSelectedPlan = planSelection.chosenPlanID == planID
        }
        plusIntroTitleLabel?.text = LoginPageModel.plusIntroTitle(chosenPlanID: planSelection.chosenPlanID)
    }

    private func makePlusIntro() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 4

        let title = UILabel()
        title.font = Self.font(15, .bold, .subheadline)
        title.textColor = Theme.primaryLightMax
        title.adjustsFontForContentSizeCategory = true

        let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
        chevron.tintColor = Theme.secondaryText
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),
        ])

        let header = UIStackView(arrangedSubviews: [title, UIView(), chevron])
        header.axis = .horizontal
        header.spacing = 8
        header.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(
            target: self, action: #selector(togglePlusIntroAction)
        )
        header.addGestureRecognizer(tap)

        let bullets = UIStackView()
        bullets.axis = .vertical
        bullets.spacing = 4
        bullets.alignment = .leading
        for bullet in LoginPageModel.plusBenefits {
            let label = UILabel()
            let full = bullet.prefix + bullet.bold + bullet.suffix
            let text = NSMutableAttributedString(
                string: full,
                attributes: [
                    .font: Self.font(13, .regular, .footnote),
                    .foregroundColor: Theme.primaryLightMax,
                ]
            )
            if !bullet.bold.isEmpty {
                text.addAttributes(
                    [.font: Self.font(13, .bold, .footnote)],
                    range: NSRange(location: bullet.prefix.count, length: bullet.bold.count)
                )
            }
            label.attributedText = text
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            bullets.addArrangedSubview(label)
        }

        container.addArrangedSubview(header)
        container.addArrangedSubview(bullets)
        bullets.isHidden = !plusIntroExpanded

        plusIntroTitleLabel = title
        plusIntroContentStack = bullets
        plusIntroChevron = chevron
        title.text = LoginPageModel.plusIntroTitle(chosenPlanID: planSelection.chosenPlanID)
        return container
    }

    @objc private func togglePlusIntroAction() {
        plusIntroExpanded.toggle()
        plusIntroContentStack?.isHidden = !plusIntroExpanded
        UIView.animate(withDuration: 0.25) { [weak self] in
            self?.plusIntroChevron?.transform = (self?.plusIntroExpanded ?? false)
                ? .identity
                : CGAffineTransform(rotationAngle: -.pi / 2)
        }
    }

    private func confirmPurchaseTapped() {
        guard let card = planSelection.selectedCard(available: availablePlans) else {
            // login.dart:489-502 — "Invalid plan" dialog.
            presentAlert(
                title: LoginPageModel.invalidPlanAlertTitle,
                message: LoginPageModel.invalidPlanAlertBody
            )
            return
        }
        let spinner = FullScreenSpinnerViewController.present(over: self)
        Task { @MainActor [weak self] in
            do {
                try await self?.store.purchase(card)
            } catch {
                // A failed purchase must not pass silently — the Confirm
                // button would look dead. (User cancellation is already
                // folded away inside the store.)
                spinner.dismissSpinner { [weak self] in
                    self?.presentAlert(
                        title: LoginPageModel.purchaseErrorAlertTitle,
                        message: error.localizedDescription
                    )
                    self?.refreshState()
                    self?.reloadOfferings(force: true)
                }
                return
            }
            spinner.dismissSpinner { [weak self] in
                self?.refreshState()
                self?.reloadOfferings(force: true)
            }
        }
    }

    private func restoreTapped() {
        let spinner = FullScreenSpinnerViewController.present(over: self)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await self.store.restorePurchases()
            spinner.dismissSpinner {
                // login.dart:532-559 — error/success dialogs after restore.
                if success {
                    self.presentAlert(
                        title: LoginPageModel.restoreSuccessAlertTitle,
                        message: LoginPageModel.restoreSuccessAlertBody
                    )
                } else {
                    self.presentAlert(
                        title: LoginPageModel.restoreErrorAlertTitle,
                        message: LoginPageModel.restoreErrorAlertBody
                    )
                }
                self.refreshState()
            }
        }
    }

    // MARK: Privacy + Remove account (privacy.dart, login.dart:722-794)

    private func buildPrivacyLinks() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center

        func link(_ title: String, url: URL) -> UIButton {
            let button = UIButton(type: .system)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font(12, .semibold, .caption1),
                .foregroundColor: Theme.primary,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            button.setAttributedTitle(
                NSAttributedString(string: title, attributes: attributes), for: .normal
            )
            button.addAction(UIAction { [weak self] _ in
                // inAppBrowserView parity — SFSafariViewController.
                self?.present(SFSafariViewController(url: url), animated: true)
            }, for: .touchUpInside)
            return button
        }

        stack.addArrangedSubview(link(LoginPageModel.privacyPolicyTitle, url: LoginPageModel.privacyPolicyURL))
        stack.addArrangedSubview(link(LoginPageModel.termsOfUseTitle, url: LoginPageModel.termsOfUseURL))
        return stack
    }

    private func buildRemoveAccountButton() -> UIView {
        let button = UIButton(type: .system)
        button.backgroundColor = Self.errorColor.withAlphaComponent(0.10)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        config.baseForegroundColor = Self.errorColor
        config.title = LoginPageModel.deleteButtonTitle
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = Self.font(17, .bold, .body)
            return outgoing
        }
        button.configuration = config
        button.addAction(
            UIAction { [weak self] _ in self?.presentDeleteConfirmation() },
            for: .touchUpInside
        )
        return button
    }

    private func presentDeleteConfirmation() {
        let alert = UIAlertController(
            title: LoginPageModel.deleteAlertTitle,
            message: LoginPageModel.deleteAlertBody,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LoginPageModel.cancelTitle, style: .default))
        alert.addAction(
            UIAlertAction(title: LoginPageModel.deleteConfirmTitle, style: .destructive) { [weak self] _ in
                guard let self else { return }
                // The Dart stacked a spinner over the dialog before the
                // DELETE (login.dart:749-764); presenting before this alert
                // finishes dismissing is swallowed, so run the flow from the
                // dismissal completion instead of a timed delay.
                self.dismiss(animated: true) { self.performDelete() }
            }
        )
        present(alert, animated: true)
    }

    private func performDelete() {
        guard presentedViewController == nil else { return }
        let spinner = FullScreenSpinnerViewController.present(over: self)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.context.api.deleteUser()
                spinner.dismissSpinner {
                    switch result {
                    case .deleted:
                        // DELETE 200 → sign out (login.dart:760-763); backend
                        // cascade removes Firebase + RevenueCat records.
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            await self.context.auth.signOut(purchases: self.context.purchases)
                            self.refreshState()
                        }
                    case .error(let signal):
                        self.presentErrorSignal(signal)
                    }
                }
            } catch {
                // Transport failure: the Dart left this as an unhandled
                // async error (no dialog).
                spinner.dismissSpinner()
            }
        }
    }

    private func presentErrorSignal(_ signal: APIClient.ErrorSignal) {
        switch signal {
        case .loginRequired:
            context.presentLogin()
        case .errorMessage(let text):
            presentAlert(title: "Error", message: text)
        case .errorBody(let status, let body):
            presentAlert(title: "Error \(status)", message: body)
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Spinner flow (login.dart:72-81, 103-113)

    private func runWithSpinner(_ flow: @escaping (UIViewController) async throws -> Void) {
        let spinner = FullScreenSpinnerViewController.present(over: self)
        Task { @MainActor [weak self] in
            defer { spinner.dismissSpinner { [weak self] in self?.refreshState() } }
            do {
                try await flow(spinner)
            } catch {
                // Dart prints and stays signed out (states/user.dart:130-138).
            }
        }
    }

    // MARK: - Shared helpers

    /// Shared Dynamic Type helper for the auth screens (app font tokens carry
    /// no Material-scale equivalent for these labels).
    static func font(
        _ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle
    ) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(
            for: UIFont.systemFont(ofSize: size, weight: weight)
        )
    }

    private static func label(_ text: String, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = Theme.primaryLightMax
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    /// Dart `Card` (anycast_theme cardTheme): surface fill, hairline outline,
    /// 24 pt continuous radius, 15 pt content inset.
    private static func card() -> (container: UIView, contentStack: UIStackView) {
        let container = UIView()
        container.backgroundColor = Theme.cardBackground
        container.layer.borderColor = Theme.cardOutline.cgColor
        container.layer.borderWidth = 1
        container.layer.cornerRadius = 24
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 15, leading: 15, bottom: 15, trailing: 15
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return (container, stack)
    }
}

// MARK: - Carousel data source / scroll feedback

extension LoginViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        LoginPageModel.CarouselAutoplay.slideCount
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: IntroSlideCell.reuseIdentifier, for: indexPath
        )
        (cell as? IntroSlideCell)?.configure(index: indexPath.item)
        return cell
    }

    // carousel_slider pauses autoplay while touched and resumes on release.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        carouselModel.pause()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        syncCarouselPageFromScroll(scrollView)
        carouselModel.resume()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // A drag released with ~zero velocity exactly at a page boundary
        // never decelerates — without this settle the model stays paused
        // (autoplay stalled) and the page index never re-syncs (the
        // DiscoverPagingContainer settle precedent).
        guard !decelerate else { return }
        syncCarouselPageFromScroll(scrollView)
        carouselModel.resume()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        syncCarouselPageFromScroll(scrollView)
    }

    private func syncCarouselPageFromScroll(_ scrollView: UIScrollView) {
        // The forwarded callbacks carry the orthogonal section scroller;
        // the page follows from its offset/bounds directly. An
        // indexPathForItem(at:) probe is unreliable at page boundaries —
        // the probe point can land between items. setUserPage wraps any
        // out-of-range result.
        guard scrollView.bounds.width > 0 else { return }
        let index = Int(
            (scrollView.contentOffset.x + scrollView.bounds.width / 2)
                / scrollView.bounds.width
        )
        carouselModel.setUserPage(index)
    }
}

// MARK: - Placeholder intro slides

/// The Dart ships `assets/images/subscription_intro{,_2}.png`; those images
/// are not in the native asset catalog yet, so slides render a gradient +
/// brand glyph placeholder. T11 asset gap.
final class IntroSlideCell: UICollectionViewCell {

    static let reuseIdentifier = "IntroSlide"

    private let gradientLayer = CAGradientLayer()
    private let iconView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        contentView.layer.addSublayer(gradientLayer)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.white.withAlphaComponent(0.92)
        iconView.isAccessibilityElement = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(index: Int) {
        if index == 0 {
            gradientLayer.colors = [Theme.primaryDark.cgColor, Theme.primary.cgColor]
            iconView.image = AppIcons.aiTranscript
        } else {
            gradientLayer.colors = [
                UIColor(red: 0.85, green: 0.45, blue: 0.05, alpha: 1).cgColor,
                Theme.accent.cgColor,
            ]
            iconView.image = AppIcons.newDoc
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }
}

// MARK: - Plan card (login.dart:577-645)

/// Selectable plan tile plus the auto-renewal caption below it (the Dart
/// renders card + caption as one column per Expanded slot).
final class PlanCardView: UIControl {

    var onSelect: ((String) -> Void)?

    private let plan: LoginPageModel.PlanCard
    private let captionLabel = UILabel()

    /// Column the caller embeds: [card, caption] (login.dart:598-642).
    lazy var columnWithCaption: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [self, captionLabel])
        stack.axis = .vertical
        stack.spacing = 5
        stack.alignment = .center
        return stack
    }()

    var isSelectedPlan = false {
        didSet { applySelection() }
    }

    init(plan: LoginPageModel.PlanCard) {
        self.plan = plan
        super.init(frame: .zero)

        layer.borderColor = Theme.cardOutline.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous

        let title = UILabel()
        title.text = plan.title
        title.font = LoginViewController.font(15, .bold, .subheadline)
        title.textColor = Theme.primaryLightMax
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true

        let price = UILabel()
        price.text = plan.priceLine
        price.font = LoginViewController.font(12, .semibold, .caption1)
        price.textColor = Theme.primaryLightMax
        price.textAlignment = .center
        price.adjustsFontForContentSizeCategory = true

        let inner = UIStackView(arrangedSubviews: [title, price])
        inner.axis = .vertical
        inner.spacing = 5
        inner.alignment = .center
        inner.isLayoutMarginsRelativeArrangement = true
        inner.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12, leading: 8, bottom: 12, trailing: 8
        )
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: trailingAnchor),
            inner.topAnchor.constraint(equalTo: topAnchor),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        captionLabel.text = plan.autoRenewalCaption
        captionLabel.font = LoginViewController.font(11, .medium, .caption2)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        captionLabel.adjustsFontForContentSizeCategory = true

        accessibilityLabel = "\(plan.title), \(plan.priceLine)"
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applySelection() {
        // Tap-selected card takes the green container tone (03 §2.14).
        backgroundColor = isSelectedPlan
            ? Theme.primary.withAlphaComponent(0.16)
            : Theme.cardBackground
        layer.borderColor = isSelectedPlan ? Theme.primary.cgColor : Theme.cardOutline.cgColor
        captionLabel.textColor = isSelectedPlan ? Theme.primary : Theme.secondaryText
    }

    @objc private func tapped() {
        onSelect?(plan.productID)
    }
}

private extension UIStackView {

    /// Fixed spacer subview (the Dart SizedBox gaps).
    func addSpacer(_ height: CGFloat) {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(spacer)
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
    }
}
