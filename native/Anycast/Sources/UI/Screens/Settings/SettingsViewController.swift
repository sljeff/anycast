import UIKit
import SafariServices
import MessageUI
import AnycastKit

/// Language-change side effects (Dart `setTargetLanguage`, states/player.dart
/// :558-564): clear the translation poller's in-memory map, then persist +
/// notify. Extracted so tests can verify the wiring with spies.
struct SettingsLanguageChangeApplier {

    var resetTranslations: () -> Void
    var persist: (_ language: String) async -> Void

    func apply(_ language: String) async {
        resetTranslations()
        await persist(language)
    }

    static func live(
        translations: TranslationPollController?,
        coordinator: SettingsCoordinator?
    ) -> SettingsLanguageChangeApplier {
        SettingsLanguageChangeApplier(
            resetTranslations: { [weak translations] in
                translations?.resetForLanguageChange()
            },
            persist: { [weak coordinator] language in
                await coordinator?.updateTargetLanguage(language)
            }
        )
    }
}

/// Stepper writes (Inbox / History / Cache limits): maps a
/// stepper row to its coordinator mutation. Extracted so tests can verify
/// each row writes through the coordinator.
struct SettingsStepWriter {

    let coordinator: SettingsCoordinator

    func write(_ value: Int64, for row: SettingsPageModel.Row) async {
        switch row {
        case .maxFeedEpisodes: await coordinator.updateMaxFeedEpisodes(value)
        case .maxHistoryEpisodes: await coordinator.updateMaxHistoryEpisodes(value)
        case .cacheLimit: await coordinator.updateMaxCacheCount(value)
        default: break
        }
    }
}

/// Commits a held History Limit when Settings closes: persist through the
/// coordinator, then trim History to it. The trim runs only if the new limit
/// actually landed, so a failed write never deletes rows under the old
/// setting. Returns the remaining history count (nil if the read failed).
struct SettingsHistoryLimitCommit {

    let coordinator: SettingsCoordinator
    let settingsBox: SettingsBox
    let history: HistoryRepository

    func run(_ limit: Int64) async -> Int? {
        await coordinator.updateMaxHistoryEpisodes(limit)
        guard settingsBox.current.maxHistoryEpisodes == limit else { return nil }
        _ = try? await history.trim(keeping: limit)
        return try? await history.count()
    }
}

/// Settings sheet (lib/pages/settings.dart, 03 §2.13) in the restrained 2.0
/// Settings direction adopted 2026-10-21: grouped plates on the container
/// page, rows with values and chevrons, and in-row steppers for the numeric
/// limits instead of the Dart scroll-wheel pickers.
/// Presented via AppSheets.presentExpand from the shell's gear button;
/// children (Login/ImportExport) are presented from here.
final class SettingsViewController: UIViewController {

    /// What the account rows render from. Signed-in vs signed-out is read
    /// synchronously; the subscription, entitlement and quota fields fill in
    /// as their async sources answer.
    private struct AccountInfo {
        var snapshot = LoginPageModel.AccountSnapshot(uid: nil, email: nil, providerID: nil)
        /// Nil until RevenueCat has answered, so a Plus user never flashes
        /// the free state.
        var isSubscribed: Bool?
        var plus: AccountPageModel.PlusStatus?
        var remaining: Int?

        var tier: AccountPageModel.Tier {
            AccountPageModel.tier(signedIn: snapshot.signedIn, isSubscribed: isSubscribed ?? false)
        }

        /// Tier that drives the section list: the Plus row waits for a
        /// definite free answer.
        var sectionTier: AccountPageModel.Tier {
            snapshot.signedIn && isSubscribed == nil ? .plus : tier
        }
    }

    /// The layout provider is built before `self` exists and must always see
    /// the current sections, so it reads them through this box.
    private final class SectionStore {
        var sections: [SettingsPageModel.Section] = []
        /// The text under "Keep on this iPhone".
        var keepFooter = SettingsPageModel.keepNote
    }

    private let sectionStore: SectionStore
    private var accountInfo = AccountInfo()
    private var accountTask: Task<Void, Never>?

    private var sections: [SettingsPageModel.Section] { sectionStore.sections }

    private let context: UIContext
    private var languageApplier: SettingsLanguageChangeApplier

    /// Live settings snapshot; writes land through the coordinator, then the
    /// box is re-read (the sheet never mutates the box itself).
    private var settings: AppSettings

    private let collectionView: UICollectionView
    private let titleLabel = UILabel()
    private var dataSource: UICollectionViewDiffableDataSource<Int, SettingsPageModel.Row>?

    private var notificationObservers: [NSObjectProtocol] = []
    /// Inbox and History row counts, once read; they size the removal notices.
    private var keptCounts: [SettingsPageModel.Row: Int] = [:]
    /// Inbox / History limits stepped in this sheet, held until Settings
    /// closes (a row is absent when its stepper shows the stored value).
    private var pendingLimits: [SettingsPageModel.Row: Int64] = [:]

    init(context: UIContext) {
        self.context = context
        self.settings = context.settingsBox.current
        self.languageApplier = .live(
            translations: context.translations,
            coordinator: context.settingsCoordinator
        )
        let store = SectionStore()
        store.sections = SettingsPageModel.sections(tier: .signedOut)
        self.sectionStore = store
        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeLayout(store: store)
        )

        super.init(nibName: nil, bundle: nil)
    }

    /// Per-section list layout: inset-grouped plates 16 from the screen
    /// edges with 24-inset `sandAlpha4` separators.
    private static func makeLayout(store: SectionStore) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            let sections = store.sections
            let section = sections.indices.contains(sectionIndex) ? sections[sectionIndex] : nil
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            // The page paints the container base; the list default would lay
            // the system grouped gray over it.
            config.backgroundColor = .clear
            config.headerMode = section?.header == nil ? .none : .supplementary
            config.footerMode = section?.footer == nil ? .none : .supplementary
            config.headerTopPadding = sectionIndex == 0 ? Spacing.md : Spacing.pageHeader
            config.itemSeparatorHandler = { _, proposed in
                var separator = proposed
                separator.color = AnycastColor.sandAlpha4
                let insets = NSDirectionalEdgeInsets(
                    top: 0, leading: SettingsRowCell.horizontalInset,
                    bottom: 0, trailing: SettingsRowCell.horizontalInset
                )
                separator.topSeparatorInsets = insets
                separator.bottomSeparatorInsets = insets
                return separator
            }
            let layoutSection = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
            layoutSection.contentInsets.leading = Spacing.pageH
            layoutSection.contentInsets.trailing = Spacing.pageH
            return layoutSection
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surfaceContainer

        refreshAccount()
        configureDataSource()

        titleLabel.text = "Settings"
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.contentInset.bottom = Spacing.pageHeader
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        // The title lines up with the row text: plate inset + row inset.
        let textInset = Spacing.pageH + SettingsRowCell.horizontalInset
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: textInset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -textInset),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Runs under the title row and the sheet's bottom edge, fading
            // out behind both; `viewDidLayoutSubviews` keeps the resting
            // layout of a list that started below the title.
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        ScrollEdgeChrome.attachTopBand(
            to: collectionView, in: view, below: titleLabel.bottomAnchor,
            fadeColor: Theme.surfaceContainer, restingGap: Spacing.xs
        )
        ScrollEdgeChrome.attachBottomEdge(to: collectionView, in: view, fadeColor: Theme.surfaceContainer)
        view.bringSubviewToFront(titleLabel)

        // Dynamic Type: re-render visible cells when the content size moves.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            [weak self] (_: SettingsViewController, _: UITraitCollection) in
            self?.reconfigureVisible()
        }

        // Obx reactivity parity: any settings change (even one made outside
        // this sheet) re-renders the page.
        let center = NotificationCenter.default
        for name in [
            SettingsCoordinator.countryCodeDidChange,
            SettingsCoordinator.targetLanguageDidChange,
            SettingsCoordinator.limitsDidChange,
        ] {
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                self.refreshFromBox()
            })
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ScrollEdgeChrome.clearTop(of: collectionView, to: titleLabel.frame.maxY + Spacing.xs)
    }

    /// Settings closing for real (not a cancelled interactive swipe, which
    /// never reaches here, and not a child presented over it) commits the
    /// held limits. The task keeps this controller alive until the writes
    /// finish.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !pendingLimits.isEmpty, presentedViewController == nil,
              isBeingDismissed || presentingViewController == nil else { return }
        Task { await commitHeldLimits() }
    }

    deinit {
        accountTask?.cancel()
        // UI teardown runs on the main thread; the observer tokens are not
        // Sendable so the access goes through an isolated assertion.
        MainActor.assumeIsolated {
            for observer in notificationObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - Data source

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<SettingsRowCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configure(cell, for: row)
        }
        let stepperRegistration = UICollectionView.CellRegistration<SettingsStepperRowCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configureStepperCell(cell, for: row)
        }

        let identityRegistration = UICollectionView.CellRegistration<SettingsIdentityRowCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configureIdentityCell(cell, for: row)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let sections = self?.sections, sections.indices.contains(indexPath.section),
                  let title = sections[indexPath.section].header else { return }
            var config = header.defaultContentConfiguration()
            config.text = title
            config.textProperties.color = Theme.onSurfaceVariant
            config.textProperties.font = TypographyV2.meta.font()
            config.textProperties.adjustsFontForContentSizeCategory = true
            // Text lines up with the row text, 8 above the plate.
            config.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: 0, leading: SettingsRowCell.horizontalInset,
                bottom: Spacing.md, trailing: SettingsRowCell.horizontalInset
            )
            header.contentConfiguration = config
            header.backgroundConfiguration = .clear()
        }

        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { [weak self] footer, _, indexPath in
            self?.configureFooter(footer, section: indexPath.section)
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, SettingsPageModel.Row>(
            collectionView: collectionView
        ) { collectionView, indexPath, row in
            switch row {
            case .account, .plusUpgrade:
                return collectionView.dequeueConfiguredReusableCell(
                    using: identityRegistration, for: indexPath, item: row
                )
            case .cacheLimit, .maxFeedEpisodes, .maxHistoryEpisodes:
                return collectionView.dequeueConfiguredReusableCell(
                    using: stepperRegistration, for: indexPath, item: row
                )
            default:
                return collectionView.dequeueConfiguredReusableCell(
                    using: rowRegistration, for: indexPath, item: row
                )
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: kind == UICollectionView.elementKindSectionFooter ? footerRegistration : headerRegistration,
                for: indexPath
            )
        }
        self.dataSource = dataSource
        applySnapshot()
        reloadKeptCounts()
    }

    /// Inbox and History counts, read when the sheet loads (it is created
    /// per presentation); they size the removal notices.
    private func reloadKeptCounts() {
        Task { [weak self] in
            guard let self else { return }
            let database = context.database
            if let count = try? await database.feedRepository().count() {
                keptCounts[.maxFeedEpisodes] = count
            }
            if let count = try? await database.historyRepository().count() {
                keptCounts[.maxHistoryEpisodes] = count
            }
            updateKeepFooter()
        }
    }

    // MARK: - Held Inbox / History limits

    /// The settings the rows render: the stored ones with the held limits
    /// laid over them.
    private var displayedSettings: AppSettings {
        var shown = settings
        if let feed = pendingLimits[.maxFeedEpisodes] { shown.maxFeedEpisodes = feed }
        if let history = pendingLimits[.maxHistoryEpisodes] { shown.maxHistoryEpisodes = history }
        return shown
    }

    private func configureFooter(_ footer: UICollectionViewListCell, section: Int) {
        guard sections.indices.contains(section) else { return }
        var config = footer.defaultContentConfiguration()
        switch sections[section].footer {
        case .keep: config.text = sectionStore.keepFooter
        case .version:
            config.text = SettingsPageModel.versionLine(appVersion: Self.bundleValue("CFBundleShortVersionString"),
                                                        build: Self.bundleValue("CFBundleVersion"))
            config.textProperties.alignment = .center
        case nil: break
        }
        config.textProperties.color = Theme.onSurfaceVariant
        config.textProperties.font = TypographyV2.meta.font()
        config.textProperties.adjustsFontForContentSizeCategory = true
        // Text lines up with the row text, 8 under the plate.
        config.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.md, leading: SettingsRowCell.horizontalInset,
            bottom: 0, trailing: SettingsRowCell.horizontalInset
        )
        footer.contentConfiguration = config
        footer.backgroundConfiguration = .clear()
    }

    private static func bundleValue(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "?"
    }

    /// Rewrites the "Keep on this iPhone" footer from the held limits and
    /// the stored counts, resizing it when the line count changes.
    private func updateKeepFooter() {
        let text = SettingsPageModel.keepFooter(pendingLimits: pendingLimits, counts: keptCounts)
        guard text != sectionStore.keepFooter else { return }
        sectionStore.keepFooter = text
        if let index = sections.firstIndex(where: { $0.footer == .keep }),
           let footer = collectionView.supplementaryView(
               forElementKind: UICollectionView.elementKindSectionFooter,
               at: IndexPath(item: 0, section: index)
           ) as? UICollectionViewListCell {
            configureFooter(footer, section: index)
        }
        UIView.animate(withDuration: Motion.reduceMotion ? 0 : 0.25) {
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
        }
    }

    /// Writes the held limits once. Inbox: the limit only; the Inbox's own
    /// 60 s trim applies it. History: the limit, then trim History to it.
    /// A limit is only cleared after its write, so the row never flips back.
    private func commitHeldLimits() async {
        if let limit = pendingLimits[.maxFeedEpisodes] {
            await context.settingsCoordinator.updateMaxFeedEpisodes(limit)
        }
        if let limit = pendingLimits[.maxHistoryEpisodes] {
            let commit = SettingsHistoryLimitCommit(
                coordinator: context.settingsCoordinator,
                settingsBox: context.settingsBox,
                history: context.database.historyRepository()
            )
            if let remaining = await commit.run(limit) { keptCounts[.maxHistoryEpisodes] = remaining }
        }
        pendingLimits = [:]
        refreshFromBox()
        updateKeepFooter()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, SettingsPageModel.Row>()
        for (index, section) in sections.enumerated() {
            snapshot.appendSections([index])
            snapshot.appendItems(section.rows, toSection: index)
        }
        // The old page rebuilt without animation on every Obx change — keep
        // the same no-animation semantics (07 §2.2).
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func reconfigureVisible() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        let visible = snapshot.itemIdentifiers
        guard !visible.isEmpty else { return }
        snapshot.reconfigureItems(visible)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func refreshFromBox() {
        settings = context.settingsBox.current
        applySnapshot()
        // A plain apply leaves cells untouched when their identifiers did not
        // change, so a picker write would leave the row showing the old value
        // until the sheet reopened (the Dart Obx rebuild updates immediately).
        reconfigureVisible()
    }

    // MARK: - Cell configuration

    private func configure(_ cell: SettingsRowCell, for row: SettingsPageModel.Row) {
        let opensSomething: Set<SettingsPageModel.Row> = [.targetLanguage, .country, .importExport, .contactEmail]
        let opensExternally = row == .privacyPolicy || row == .termsOfUse
        cell.configure(
            title: SettingsPageModel.title(for: row),
            value: SettingsPageModel.value(for: row, settings: settings),
            showsChevron: opensSomething.contains(row),
            opensExternally: opensExternally
        )
        cell.accessibilityTraits = opensExternally ? .link : .button
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
        cell.accessibilityHint = SettingsPageModel.accessibilityHint(for: row)
    }

    /// The identity row and the Plus row.
    private func configureIdentityCell(_ cell: SettingsIdentityRowCell, for row: SettingsPageModel.Row) {
        if row == .plusUpgrade {
            cell.configureUpgrade(
                subtitle: AccountPageModel.upgradePlateSubtitle(
                    tier: accountInfo.tier, remaining: accountInfo.remaining
                ),
                action: SettingsPageModel.plusActionTitle(tier: accountInfo.tier)
            )
        } else {
            var content = AccountPageModel.identity(
                tier: accountInfo.tier,
                email: accountInfo.snapshot.email,
                remaining: accountInfo.remaining,
                plus: accountInfo.plus
            )
            // Hold the subtitle back until the tier is certain.
            if accountInfo.snapshot.signedIn, accountInfo.isSubscribed == nil {
                content.subtitle = ""
            }
            cell.configure(identity: content)
        }
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
    }

    /// A numeric-limit row: title, value, and the − | + stepper.
    private func configureStepperCell(_ cell: SettingsStepperRowCell, for row: SettingsPageModel.Row) {
        let shown = displayedSettings
        guard let choices = SettingsPageModel.stepperChoices(for: row),
              let current = SettingsPageModel.stepperValue(for: row, settings: shown),
              let labels = SettingsPageModel.stepperAccessibilityLabels(for: row) else { return }
        cell.configure(
            title: SettingsPageModel.title(for: row),
            value: SettingsPageModel.value(for: row, settings: shown) ?? "",
            labels: labels,
            canDecrease: SettingsPageModel.canDecrease(from: current, in: choices),
            canIncrease: SettingsPageModel.canIncrease(from: current, in: choices)
        )
        cell.onStep = { [weak self] direction in
            self?.step(row, direction)
        }
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
        cell.accessibilityHint = SettingsPageModel.accessibilityHint(for: row)
    }

    // MARK: - Actions

    /// One stepper tap. Inbox and History steps are held until Settings
    /// closes; the cache limit is written at once. (The stepper itself
    /// fires the selection haptic on touch-down.)
    private func step(_ row: SettingsPageModel.Row, _ direction: SettingsPageModel.StepDirection) {
        if row == .maxFeedEpisodes || row == .maxHistoryEpisodes {
            stepHeldLimit(row, direction)
            return
        }
        let latest = context.settingsBox.current
        guard let choices = SettingsPageModel.stepperChoices(for: row),
              let current = SettingsPageModel.stepperValue(for: row, settings: latest) else { return }
        let next = SettingsPageModel.steppedValue(from: current, direction, in: choices)
        guard next != current else { return }
        let writer = SettingsStepWriter(coordinator: context.settingsCoordinator)
        Task {
            await writer.write(next, for: row)
            finishWrite(landed: SettingsPageModel.stepperValue(for: row, settings: context.settingsBox.current) == next)
        }
    }

    private func applyLanguageChange(_ language: String) async {
        await languageApplier.apply(language)
        finishWrite(landed: context.settingsBox.current.targetLanguage == language)
    }

    /// Re-renders the rows from the box; a write that did not land leaves
    /// the old value there, so the row reverts, and the user is told.
    private func finishWrite(landed: Bool) {
        refreshFromBox()
        guard !landed, let window = view.window else { return }
        ToastPresenter.shared.show("Couldn't save. Try again.", in: window, duration: 3)
    }

    // MARK: - Child presentations

    // MARK: Account

    /// Re-reads the account rows' inputs: sign-in state synchronously, then
    /// subscription, entitlement and quota asynchronously. Called on load
    /// and whenever a child account sheet goes away (page sheets do not
    /// trigger this page's `viewWillAppear`).
    private func refreshAccount() {
        accountTask?.cancel()
        let snapshot = AuthAccountSnapshot.current(context: context)
        let sameUser = snapshot.signedIn && snapshot.uid == accountInfo.snapshot.uid
        accountInfo = sameUser
            ? AccountInfo(snapshot: snapshot, isSubscribed: accountInfo.isSubscribed,
                          plus: accountInfo.plus, remaining: accountInfo.remaining)
            : AccountInfo(snapshot: snapshot)
        applyAccountInfo()
        guard snapshot.signedIn else { return }

        let store = PaywallStore(purchases: context.purchases)
        accountTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let subscribed = self.context.purchases.isSubscribed()
            async let plus = store.plusStatus()
            let isSubscribed = await subscribed
            let status = await plus
            guard !Task.isCancelled else { return }
            self.accountInfo.isSubscribed = isSubscribed
            self.accountInfo.plus = status
            self.applyAccountInfo()

            // A login-required answer is not escalated from Settings; the
            // quota just stays unknown.
            let remaining = await AccountRemaining.fetch(context: self.context)
            guard !Task.isCancelled else { return }
            self.accountInfo.remaining = remaining
            self.applyAccountInfo()
        }
    }

    private func applyAccountInfo() {
        sectionStore.sections = SettingsPageModel.sections(tier: accountInfo.sectionTier)
        guard dataSource != nil else { return }
        applySnapshot()
        reconfigureVisible()
    }

    private func presentAccount() {
        if accountInfo.snapshot.signedIn {
            let membership = MembershipViewController(
                context: context,
                isSubscribed: accountInfo.isSubscribed ?? false,
                plus: accountInfo.plus,
                remaining: accountInfo.remaining
            )
            membership.onAccountChanged = { [weak self] in self?.refreshAccount() }
            presentAccountSheet(membership)
        } else {
            let login = LoginSheetViewController.present(
                from: self, context: context, source: .settings
            ) { [weak self] in self?.refreshAccount() }
            login.presentationController?.delegate = self
        }
    }

    private func presentUpgrade() {
        let paywall = PaywallViewController.present(
            from: self, context: context, variant: .standard
        ) { [weak self] in self?.refreshAccount() }
        paywall.presentationController?.delegate = self
    }

    private func presentAccountSheet(_ controller: UIViewController) {
        AppSheets.presentExpand(controller, from: self)
        controller.presentationController?.delegate = self
    }

    private func presentImportExport() {
        ImportExportDialogViewController.present(from: self, context: context)
    }

    /// Inbox / History steps are held, not written: lowering below the
    /// stored count removes nothing until Settings closes, and stepping back
    /// up cancels it.
    private func stepHeldLimit(_ row: SettingsPageModel.Row, _ direction: SettingsPageModel.StepDirection) {
        guard let choices = SettingsPageModel.stepperChoices(for: row),
              let stored = SettingsPageModel.stepperValue(for: row, settings: context.settingsBox.current)
        else { return }
        var draft = SettingsPageModel.LimitDraft(stored: stored, pending: pendingLimits[row])
        draft.step(direction, in: choices)
        guard draft.pending != pendingLimits[row] else { return }
        pendingLimits[row] = draft.pending
        reconfigureVisible()
        updateKeepFooter()
    }

    private func presentCountrySheet() {
        let sheet = SettingsOptionSheetViewController(
            title: SettingsPageModel.title(for: .country),
            options: SettingsPageModel.sortedCountries.map { ($0.name, $0.code) },
            selectedCode: settings.countryCode
        )
        sheet.onSelect = { [weak self] code in
            guard let self else { return }
            Task {
                await self.context.settingsCoordinator.updateCountryCode(code)
                self.finishWrite(landed: self.context.settingsBox.current.countryCode == code)
            }
        }
        sheet.present(from: self)
    }

    private func presentLanguageSheet() {
        let sheet = SettingsOptionSheetViewController(
            title: SettingsPageModel.title(for: .targetLanguage),
            options: SettingsPageModel.languageOptions.map { ($0.name, $0.code) },
            selectedCode: settings.targetLanguage
        )
        sheet.onSelect = { [weak self] code in
            guard let self else { return }
            Task { await self.applyLanguageChange(code) }
        }
        sheet.present(from: self)
    }

    /// Mail composer with a diagnostics block; without a mail account, an
    /// alert with the address to copy.
    private func openFeedbackMail() {
        let address = SettingsPageModel.feedbackAddress
        guard MFMailComposeViewController.canSendMail() else {
            let alert = UIAlertController(title: "Send Feedback", message: address, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
                UIPasteboard.general.string = address
            })
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            present(alert, animated: true)
            return
        }
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = self
        composer.setToRecipients([address])
        composer.setSubject(SettingsPageModel.feedbackSubject)
        composer.setMessageBody(SettingsPageModel.feedbackBody(
            appVersion: Self.bundleValue("CFBundleShortVersionString"),
            build: Self.bundleValue("CFBundleVersion"),
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: Self.deviceModelIdentifier
        ), isHTML: false)
        present(composer, animated: true)
    }

    /// Hardware identifier such as "iPhone17,1" (the simulator reports its host's).
    private static var deviceModelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private func presentSafari(_ url: URL) {
        // privacy.dart used inAppBrowserView — SFSafariViewController parity.
        let controller = SFSafariViewController(url: url)
        present(controller, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension SettingsViewController: UICollectionViewDelegate {

    /// Stepper rows: their controls own the taps.
    private func isInteractive(_ row: SettingsPageModel.Row) -> Bool {
        switch row {
        case .cacheLimit, .maxFeedEpisodes, .maxHistoryEpisodes: return false
        default: return true
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        dataSource?.itemIdentifier(for: indexPath).map(isInteractive) ?? false
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource?.itemIdentifier(for: indexPath).map(isInteractive) ?? false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource?.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .account: presentAccount()
        case .plusUpgrade: presentUpgrade()
        case .country: presentCountrySheet()
        case .targetLanguage: presentLanguageSheet()
        case .importExport: presentImportExport()
        case .cacheLimit, .maxFeedEpisodes, .maxHistoryEpisodes: break
        case .contactEmail: openFeedbackMail()
        case .privacyPolicy: presentSafari(SettingsPageModel.privacyPolicyURL)
        case .termsOfUse: presentSafari(SettingsPageModel.termsOfUseURL)
        }
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension SettingsViewController: UIAdaptivePresentationControllerDelegate {

    /// A swipe-dismissed Login or Membership sheet may have changed the
    /// account: re-read it.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        refreshAccount()
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension SettingsViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}
