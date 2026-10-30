import UIKit
import SafariServices

/// The standalone paywall (variants A and C), presented as a large page
/// sheet. Restore and a glass close button sit in the top bar from the first
/// frame; the plans, the CTA and the disclosure are pinned to the bottom
/// thumb zone while the content above scrolls when it has to.
///
/// - A (`.standard`): one screen, no swipe layer. The headline over a dark
///   transcript card whose translation cycles through four language chips
///   every 3 s until a chip is tapped, then a feature line and a
///   "What's in Plus" link that opens `PaywallDetailsViewController`.
/// - C (`.quota`): shown at the quota limit. The episode the user just tried
///   is the hero, with their language preselected and no cycling, followed
///   by the "50" and "≈4¢" figures.
///
/// Prices, the Save badge and trial eligibility come from RevenueCat via
/// `PaywallStore`; while they load, or when they fail, the plans area shows a
/// quiet state instead of numbers. Signed out, the CTA opens the login sheet
/// (`.paywall`) and the purchase continues as soon as it reports success.
final class PaywallViewController: UIViewController {

    private static let topBarHeight: CGFloat = 76
    private static let inset = Spacing.sheetContent

    private let context: UIContext
    private let store: PaywallStore
    private(set) var model: PaywallModel
    private var demo: PaywallModel.Demo

    /// Called after the sheet has dismissed itself following a purchase or
    /// a restore that left an active entitlement.
    var onPurchased: (() -> Void)?

    /// Internal seam for snapshot renders and tests: set to false before the
    /// view loads and inject plans with `setPlans(_:)`, so no RevenueCat
    /// offering fetch runs.
    var loadsPlansOnLoad = true

    private var loadTask: Task<Void, Never>?
    private var cycleTask: Task<Void, Never>?
    private var isBusy = false

    // Views.
    private let scrollView = UIScrollView()
    private var card: PaywallCardView!
    private let plansContainer = UIView()
    private let statusView = PaywallPlansStatusView()
    private var rowViews: [PaywallPlanRowView] = []
    private let ctaButton = LoginSheetPrimaryButton()
    private let disclosureLabel = UILabel()
    private var buyColumn: UIStackView!
    private lazy var figuresView = PaywallFiguresView(figures: model.figures)

    /// Presents the paywall from `presenter` as a large sheet and returns it
    /// so the caller can attach a presentation delegate.
    @discardableResult
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        variant: PaywallModel.Variant,
        onPurchased: (() -> Void)? = nil
    ) -> PaywallViewController {
        let paywall = PaywallViewController(context: context, variant: variant, onPurchased: onPurchased)
        AppSheets.presentExpand(paywall, from: presenter)
        return paywall
    }

    init(context: UIContext, variant: PaywallModel.Variant, onPurchased: (() -> Void)? = nil) {
        self.context = context
        self.store = PaywallStore(purchases: context.purchases)
        self.model = PaywallModel(variant: variant)
        self.onPurchased = onPurchased
        switch variant {
        case .standard:
            demo = PaywallModel.Demo(cycles: true)
        case .quota:
            let index = PaywallModel.preselectedLanguageIndex(
                settingsTarget: context.settingsBox.current.targetLanguage,
                deviceLanguage: Locale.preferredLanguages.first
            )
            demo = PaywallModel.Demo(cycles: false, index: index)
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        loadTask?.cancel()
        cycleTask?.cancel()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let topBar = buildTopBar()
        let body = buildBody()
        let buyPanel = buildBuyPanel()
        let fade = ScrollEdgeFade(edge: .bottom)

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        buyPanel.translatesAutoresizingMaskIntoConstraints = false
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        view.addSubview(fade)
        view.addSubview(buyPanel)
        view.addSubview(topBar)
        scrollView.addSubview(body)

        // 34 pt below on a home-indicator phone (the safe area).
        let safeBottom = buyColumn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        safeBottom.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            safeBottom,
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: Self.topBarHeight),

            buyPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buyPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buyPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buyPanel.topAnchor),

            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: buyPanel.topAnchor),
            fade.heightAnchor.constraint(equalToConstant: ScrollEdgeFade.fadeLength),

            body.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            // The fade over the plans stays drawn; the content ends above it
            // so the details link never rests half-faded.
            body.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -ScrollEdgeFade.fadeLength
            ),
            body.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            body.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            // Short content still fills the viewport, so the details link
            // rests at the bottom of the area above the plans.
            body.heightAnchor.constraint(
                greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor, constant: -ScrollEdgeFade.fadeLength
            ),
        ])

        applyModel()
        if loadsPlansOnLoad { loadPlans() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCycling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cycleTask?.cancel()
        cycleTask = nil
    }

    // MARK: - Build

    private func buildTopBar() -> UIView {
        let bar = UIView()

        var configuration = UIButton.Configuration.plain()
        configuration.title = PaywallModel.restoreTitle
        configuration.baseForegroundColor = Theme.onSurface
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.gap, leading: 0, bottom: Spacing.gap, trailing: Spacing.gap
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        let restore = UIButton(configuration: configuration)
        restore.titleLabel?.adjustsFontForContentSizeCategory = true
        restore.accessibilityIdentifier = "paywall-restore"
        restore.addAction(UIAction { [weak self] _ in self?.restoreTapped() }, for: .touchUpInside)
        restore.translatesAutoresizingMaskIntoConstraints = false

        let close = AnycastIconButton(style: .glass, icon: AppIcons.close, accessibilityLabel: "Close")
        close.accessibilityIdentifier = "paywall-close"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        bar.addSubview(restore)
        bar.addSubview(close)
        NSLayoutConstraint.activate([
            restore.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: Self.inset),
            restore.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -Spacing.pageH),
            close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func buildBody() -> UIView {
        let selectedIndex = demo.index
        let cardContent: PaywallCardView.Content
        if let episode = model.episode {
            cardContent = .episode(episode)
        } else {
            cardContent = .demo
        }
        card = PaywallCardView(content: cardContent, selectedIndex: selectedIndex)
        card.onPick = { [weak self] index in self?.languagePicked(index) }

        let headline = UILabel()
        headline.attributedText = NSAttributedString(
            string: model.headline, attributes: TypographyV2.displaySmall.attributes()
        )
        headline.numberOfLines = 0
        headline.adjustsFontForContentSizeCategory = true
        headline.accessibilityTraits = .header

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Spacing.gap
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let context = model.contextLine {
            stack.addArrangedSubview(metaLabel(context))
        }
        stack.addArrangedSubview(headline)
        stack.addArrangedSubview(card)
        if model.isQuota {
            stack.addArrangedSubview(figuresView)
        } else {
            stack.addArrangedSubview(metaLabel(PaywallModel.featureLine))
        }

        // Absorbs spare height so the link below rests at the bottom.
        let spacer = UIView()
        spacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        stack.addArrangedSubview(spacer)
        if !model.isQuota {
            stack.addArrangedSubview(makeDetailsLink())
        }

        let body = UIView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: body.topAnchor, constant: Spacing.xs),
            stack.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: Self.inset),
            stack.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -Self.inset),
            stack.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -Spacing.pageH),
        ])
        return body
    }

    private func metaLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = TypographyV2.meta.font()
        label.textColor = Theme.onSurfaceVariant
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    private func makeDetailsLink() -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.title = PaywallModel.detailsLinkTitle
        configuration.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = Spacing.sm
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.gap, bottom: 0, trailing: Spacing.gap
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "paywall-details"
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: AnycastIconButton.standardDiameter).isActive = true
        button.addAction(UIAction { [weak self] _ in self?.detailsTapped() }, for: .touchUpInside)

        let wrapper = UIStackView(arrangedSubviews: [UIView(), button, UIView()])
        wrapper.distribution = .equalCentering
        return wrapper
    }

    private func buildBuyPanel() -> UIView {
        let panel = UIView()
        panel.backgroundColor = Theme.background

        plansContainer.translatesAutoresizingMaskIntoConstraints = false
        statusView.onRetry = { [weak self] in self?.loadPlans() }

        ctaButton.accessibilityIdentifier = "paywall-cta"
        ctaButton.addAction(UIAction { [weak self] _ in self?.ctaTapped() }, for: .touchUpInside)

        disclosureLabel.font = TypographyV2.meta.font().monospacedDigits()
        disclosureLabel.textColor = Theme.onSurfaceVariant
        disclosureLabel.textAlignment = .center
        disclosureLabel.numberOfLines = 0
        disclosureLabel.adjustsFontForContentSizeCategory = true
        disclosureLabel.accessibilityIdentifier = "paywall-disclosure"
        disclosureLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 20).isActive = true

        let links = PaywallLinksView.make(
            presenter: self, terms: PaywallModel.termsTitle, privacy: PaywallModel.privacyTitle
        )

        let footer = UIStackView(arrangedSubviews: [disclosureLabel, links])
        footer.axis = .vertical
        footer.spacing = 0

        let column = UIStackView(arrangedSubviews: [plansContainer, ctaButton, footer])
        column.axis = .vertical
        column.spacing = Spacing.chip
        column.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(column)

        buyColumn = column
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: panel.topAnchor, constant: Spacing.xs),
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: Self.inset),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -Self.inset),
            // Never closer than 16 pt to the bottom edge.
            column.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -Spacing.pageH),
        ])
        return panel
    }

    // MARK: - Render

    /// Rebuilds the plans area for the current availability and refreshes
    /// the CTA and disclosure.
    private func applyModel() {
        plansContainer.subviews.forEach { $0.removeFromSuperview() }
        rowViews = []
        let plate: AccountPlateView
        switch model.availability {
        case .ready:
            rowViews = model.planRows.map { row in
                let view = PaywallPlanRowView(row: row)
                view.accessibilityIdentifier = "paywall-plan-\(row.period == .yearly ? "yearly" : "monthly")"
                view.addAction(UIAction { [weak self] _ in self?.select(row.period) }, for: .touchUpInside)
                return view
            }
            plate = AccountPlateView(fill: Theme.surface, rows: rowViews)
        case .loading:
            statusView.setLoading(true)
            plate = AccountPlateView(fill: Theme.surface, rows: [statusView])
        case .unavailable:
            statusView.setLoading(false)
            plate = AccountPlateView(fill: Theme.surface, rows: [statusView])
        }
        plate.translatesAutoresizingMaskIntoConstraints = false
        plansContainer.addSubview(plate)
        NSLayoutConstraint.activate([
            plate.topAnchor.constraint(equalTo: plansContainer.topAnchor),
            plate.leadingAnchor.constraint(equalTo: plansContainer.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: plansContainer.trailingAnchor),
            plate.bottomAnchor.constraint(equalTo: plansContainer.bottomAnchor),
        ])
        if model.isQuota { figuresView.update(model.figures) }
        refreshSelection()
    }

    private func refreshSelection() {
        for (view, row) in zip(rowViews, model.planRows) { view.configure(row) }
        ctaButton.setTitle(model.ctaTitle)
        ctaButton.isEnabled = model.ctaEnabled
        disclosureLabel.text = model.disclosure
    }

    // MARK: - Plans

    /// Injects fetched plans (nil = unavailable). Internal so snapshot
    /// renders and tests can drive the plans area without RevenueCat.
    func setPlans(_ plans: PaywallModel.Plans?) {
        if let plans { model.setPlans(plans) } else { model.setUnavailable() }
        if isViewLoaded { applyModel() }
    }

    /// Selects a plan row (taps and tests).
    func select(_ period: PaywallModel.Period) {
        guard model.selected != period else { return }
        model.select(period)
        if isViewLoaded { refreshSelection() }
    }

    private func loadPlans() {
        loadTask?.cancel()
        model.setLoading()
        if isViewLoaded { applyModel() }
        let store = store
        loadTask = Task { @MainActor [weak self] in
            let plans = try? await store.loadPlans()
            guard !Task.isCancelled, let self else { return }
            self.setPlans(plans)
        }
    }

    // MARK: - Demo

    private func languagePicked(_ index: Int) {
        demo.pick(index)
        cycleTask?.cancel()
        cycleTask = nil
        card.setLanguage(index: index, animated: true)
    }

    private func startCycling() {
        guard demo.cycles, !demo.isPinned, cycleTask == nil else { return }
        cycleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(PaywallModel.Demo.cycleInterval))
                guard !Task.isCancelled, let self else { return }
                self.cycleTick()
            }
        }
    }

    private func cycleTick() {
        guard !Motion.reduceMotion, view.window != nil, presentedViewController == nil else { return }
        demo.tick()
        card.setLanguage(index: demo.index, animated: true)
    }

    // MARK: - Actions

    private func detailsTapped() {
        present(PaywallDetailsViewController(model: model), animated: true)
    }

    private func ctaTapped() {
        guard !isBusy, model.selectedPlan != nil else { return }
        // Signed out: sign in first; the purchase continues from the
        // sheet's success, with no second tap.
        guard AuthAccountSnapshot.current(context: context).signedIn else {
            LoginSheetViewController.present(
                from: self, context: context, source: .paywall
            ) { [weak self] in self?.continueAfterSignIn() }
            return
        }
        startPurchase()
    }

    /// The account just signed into may already have Plus: close instead of
    /// starting a second purchase.
    private func continueAfterSignIn() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await self.context.purchases.isSubscribed() {
                self.finishPurchased()
            } else {
                self.startPurchase()
            }
        }
    }

    private func startPurchase() {
        guard !isBusy, let plan = model.selectedPlan else { return }
        isBusy = true
        let spinner = FullScreenSpinnerViewController.present(over: self)
        let store = store
        Task { @MainActor [weak self] in
            var outcome: PaywallStore.PurchaseOutcome?
            var failure: Error?
            do {
                outcome = try await store.purchase(productID: plan.productID)
            } catch {
                failure = error
            }
            spinner.dismissSpinner { [weak self] in
                guard let self else { return }
                self.isBusy = false
                if let failure {
                    self.presentAlert(
                        title: LoginPageModel.purchaseErrorAlertTitle,
                        message: failure.localizedDescription
                    )
                } else if outcome == .purchased {
                    self.finishPurchased()
                }
            }
        }
    }

    private func restoreTapped() {
        guard !isBusy else { return }
        isBusy = true
        let spinner = FullScreenSpinnerViewController.present(over: self)
        let store = store
        Task { @MainActor [weak self] in
            let restored = await store.restorePurchases()
            spinner.dismissSpinner { [weak self] in
                guard let self else { return }
                self.isBusy = false
                self.presentAlert(
                    title: restored ? LoginPageModel.restoreSuccessAlertTitle : LoginPageModel.restoreErrorAlertTitle,
                    message: restored ? LoginPageModel.restoreSuccessAlertBody : LoginPageModel.restoreErrorAlertBody
                ) { if restored { self.finishPurchased() } }
            }
        }
    }

    /// An entitlement is active: close the sheet, then tell the presenter.
    private func finishPurchased() {
        let callback = onPurchased
        dismiss(animated: true) { callback?() }
    }

    private func presentAlert(title: String, message: String, onOK: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in onOK?() })
        present(alert, animated: true)
    }
}
