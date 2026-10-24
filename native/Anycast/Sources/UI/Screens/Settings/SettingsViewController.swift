import UIKit
import SafariServices
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

/// Stepper writes (Auto Refresh / Inbox / History / Cache limits): maps a
/// stepper row to its coordinator mutation. Extracted so tests can verify
/// each row writes through the coordinator.
struct SettingsStepWriter {

    let coordinator: SettingsCoordinator

    func write(_ value: Int64, for row: SettingsPageModel.Row) async {
        switch row {
        case .autoRefreshInterval: await coordinator.updateAutoRefreshInterval(value)
        case .maxFeedEpisodes: await coordinator.updateMaxFeedEpisodes(value)
        case .maxHistoryEpisodes: await coordinator.updateMaxHistoryEpisodes(value)
        case .cacheLimit: await coordinator.updateMaxCacheCount(value)
        default: break
        }
    }
}

/// Settings sheet (lib/pages/settings.dart, 03 §2.13) in the restrained 2.0
/// Settings direction adopted 2026-10-21: grouped plates on the container
/// page, rows with values and chevrons, in-row steppers for the numeric
/// limits instead of the Dart scroll-wheel pickers, and a sand-tinted switch.
/// Presented via AppSheets.presentExpand from the shell's gear button;
/// children (Login/ImportExport/History) are presented from here.
final class SettingsViewController: UIViewController {

    /// Plate corners stay the system inset-grouped radius: the list layout
    /// exposes no corner-radius control short of hand-drawn plates.
    private static let sections = SettingsPageModel.sections()

    private let context: UIContext
    private var languageApplier: SettingsLanguageChangeApplier

    /// Live settings snapshot; writes land through the coordinator, then the
    /// box is re-read (the sheet never mutates the box itself).
    private var settings: AppSettings

    private let collectionView: UICollectionView
    private let titleLabel = UILabel()
    private var dataSource: UICollectionViewDiffableDataSource<Int, SettingsPageModel.Row>?

    private let longPressRecognizer = UILongPressGestureRecognizer()
    private var notificationObservers: [NSObjectProtocol] = []

    init(context: UIContext) {
        self.context = context
        self.settings = context.settingsBox.current
        self.languageApplier = .live(
            translations: context.translations,
            coordinator: context.settingsCoordinator
        )
        self.collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeLayout()
        )

        super.init(nibName: nil, bundle: nil)
    }

    /// Per-section list layout: inset-grouped plates 16 from the screen
    /// edges with 24-inset `sandAlpha4` separators; the trailing Privacy
    /// links sit outside any plate — plain appearance, no separators.
    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            let section = sections.indices.contains(sectionIndex) ? sections[sectionIndex] : nil
            if section?.plainStyle == true {
                var config = UICollectionLayoutListConfiguration(appearance: .plain)
                config.backgroundColor = .clear
                config.showsSeparators = false
                let layoutSection = NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
                layoutSection.contentInsets = NSDirectionalEdgeInsets(
                    top: Spacing.pageHeader, leading: Spacing.pageH,
                    bottom: Spacing.pageHeader, trailing: Spacing.pageH
                )
                return layoutSection
            }
            var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            // The page paints the container base; the list default would lay
            // the system grouped gray over it.
            config.backgroundColor = .clear
            config.headerMode = section?.header == nil ? .none : .supplementary
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

        longPressRecognizer.minimumPressDuration = 0.5
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))
        collectionView.addGestureRecognizer(longPressRecognizer)

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

    deinit {
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
        let switchRegistration = UICollectionView.CellRegistration<SettingsSwitchListCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configureSwitchCell(cell, for: row)
        }
        let stepperRegistration = UICollectionView.CellRegistration<SettingsStepperRowCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configureStepperCell(cell, for: row)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            guard Self.sections.indices.contains(indexPath.section),
                  let title = Self.sections[indexPath.section].header else { return }
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

        let dataSource = UICollectionViewDiffableDataSource<Int, SettingsPageModel.Row>(
            collectionView: collectionView
        ) { collectionView, indexPath, row in
            switch row {
            case .enableTranslation:
                return collectionView.dequeueConfiguredReusableCell(
                    using: switchRegistration, for: indexPath, item: row
                )
            case .cacheLimit, .autoRefreshInterval, .maxFeedEpisodes, .maxHistoryEpisodes:
                return collectionView.dequeueConfiguredReusableCell(
                    using: stepperRegistration, for: indexPath, item: row
                )
            default:
                return collectionView.dequeueConfiguredReusableCell(
                    using: rowRegistration, for: indexPath, item: row
                )
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration, for: indexPath
            )
        }
        self.dataSource = dataSource
        applySnapshot()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, SettingsPageModel.Row>()
        for (index, section) in Self.sections.enumerated() {
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

    private var translationIsOn: Bool {
        SettingsPageModel.showsTargetLanguage(targetLanguage: settings.targetLanguage)
    }

    private func configure(_ cell: SettingsRowCell, for row: SettingsPageModel.Row) {
        let title = SettingsPageModel.title(for: row)
        switch row {
        case .privacyPolicy, .termsOfUse:
            cell.configureLink(title: title)
        default:
            // Target Language is inert while translation is off.
            let isDimmed = row == .targetLanguage && !translationIsOn
            let opensSomething: Set<SettingsPageModel.Row> = [
                .account, .targetLanguage, .country, .importExport, .history,
            ]
            cell.configure(
                title: title,
                subtitle: SettingsPageModel.subtitle(for: row),
                value: SettingsPageModel.value(for: row, settings: settings),
                showsChevron: opensSomething.contains(row) && !isDimmed,
                isDimmed: isDimmed
            )
            cell.accessibilityTraits = isDimmed ? [.button, .notEnabled] : .button
        }
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
        if let tooltip = SettingsPageModel.tooltip(for: row) {
            cell.accessibilityHint = tooltip
        }
    }

    /// The translation switch row.
    private func configureSwitchCell(_ cell: SettingsSwitchListCell, for row: SettingsPageModel.Row) {
        let enabled = translationIsOn
        cell.configure(
            title: SettingsPageModel.title(for: row),
            subtitle: SettingsPageModel.subtitle(for: row)
        )
        cell.setOn(enabled, animated: false)
        cell.onSwitchChanged = { [weak self] isOn in
            self?.translationSwitchToggled(isOn: isOn)
        }
        cell.accessibilityTraits = .button
        // Spoken words, not the stored encoding ("1"/"0" read as "one"/"zero").
        cell.accessibilityValue = enabled ? "On" : "Off"
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
    }

    /// A numeric-limit row: title, value, and the − | + stepper.
    private func configureStepperCell(_ cell: SettingsStepperRowCell, for row: SettingsPageModel.Row) {
        guard let choices = SettingsPageModel.stepperChoices(for: row),
              let current = SettingsPageModel.stepperValue(for: row, settings: settings),
              let labels = SettingsPageModel.stepperAccessibilityLabels(for: row) else { return }
        cell.configure(
            title: SettingsPageModel.title(for: row),
            value: SettingsPageModel.value(for: row, settings: settings) ?? "",
            labels: labels,
            canDecrease: SettingsPageModel.canDecrease(from: current, in: choices),
            canIncrease: SettingsPageModel.canIncrease(from: current, in: choices)
        )
        cell.onStep = { [weak self] direction in
            self?.step(row, direction)
        }
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
        if let tooltip = SettingsPageModel.tooltip(for: row) {
            cell.accessibilityHint = tooltip
        }
    }

    // MARK: - Actions

    /// One stepper tap: write the neighbouring choice immediately, then
    /// re-render the row.
    private func step(_ row: SettingsPageModel.Row, _ direction: SettingsPageModel.StepDirection) {
        let latest = context.settingsBox.current
        guard let choices = SettingsPageModel.stepperChoices(for: row),
              let current = SettingsPageModel.stepperValue(for: row, settings: latest) else { return }
        let next = SettingsPageModel.steppedValue(from: current, direction, in: choices)
        guard next != current else { return }
        let writer = SettingsStepWriter(coordinator: context.settingsCoordinator)
        Task {
            await writer.write(next, for: row)
            refreshFromBox()
        }
    }

    private func translationSwitchToggled(isOn: Bool) {
        // Dart settings.dart:216-229: off writes '', on derives the system
        // language (G9 locale split: first segment).
        let language = isOn
            ? SettingsPageModel.defaultTargetLanguage(
                localeIdentifier: Locale.preferredLanguages.first ?? "en"
            )
            : ""
        Task { await applyLanguageChange(language) }
    }

    private func applyLanguageChange(_ language: String) async {
        await languageApplier.apply(language)
        refreshFromBox()
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let location = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: location),
              let row = dataSource?.itemIdentifier(for: indexPath),
              let tooltip = SettingsPageModel.tooltip(for: row),
              let cell = collectionView.cellForItem(at: indexPath) else { return }
        SettingsTooltipOverlay.show(message: tooltip, above: cell, in: view)
    }

    // MARK: - Child presentations

    private func presentAccount() {
        AppSheets.presentExpand(LoginViewController(context: context), from: self)
    }

    private func presentImportExport() {
        ImportExportDialogViewController.present(from: self, context: context)
    }

    private func presentHistory() {
        HistoryDialogViewController.present(from: self, context: context)
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
                self.refreshFromBox()
            }
        }
        sheet.present(from: self)
    }

    private func presentLanguageSheet() {
        let sheet = SettingsOptionSheetViewController(
            title: SettingsPageModel.title(for: .targetLanguage),
            options: SettingsPageModel.languages.map { ($0.name, $0.code) },
            selectedCode: settings.targetLanguage
        )
        sheet.onSelect = { [weak self] code in
            guard let self else { return }
            Task { await self.applyLanguageChange(code) }
        }
        sheet.present(from: self)
    }

    private func openFeedbackMail() {
        // The shipped app's mailto recipient lacks the dot shown on the row
        // (settings.dart:451-461) — mirrored byte-for-byte.
        UIApplication.shared.open(SettingsPageModel.feedbackMailtoURL)
    }

    private func presentSafari(_ url: URL) {
        // privacy.dart used inAppBrowserView — SFSafariViewController parity.
        let controller = SFSafariViewController(url: url)
        present(controller, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension SettingsViewController: UICollectionViewDelegate {

    /// Stepper rows (their controls own the taps) and the inert Target
    /// Language row neither highlight nor select.
    private func isInteractive(_ row: SettingsPageModel.Row) -> Bool {
        switch row {
        case .cacheLimit, .autoRefreshInterval, .maxFeedEpisodes, .maxHistoryEpisodes:
            return false
        case .targetLanguage:
            return translationIsOn
        default:
            return true
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
        case .country: presentCountrySheet()
        case .enableTranslation:
            (collectionView.cellForItem(at: indexPath) as? SettingsSwitchListCell)?.toggle()
        case .targetLanguage: presentLanguageSheet()
        case .importExport: presentImportExport()
        case .history: presentHistory()
        case .cacheLimit, .autoRefreshInterval, .maxFeedEpisodes, .maxHistoryEpisodes: break
        case .contactEmail: openFeedbackMail()
        case .privacyPolicy: presentSafari(SettingsPageModel.privacyPolicyURL)
        case .termsOfUse: presentSafari(SettingsPageModel.termsOfUseURL)
        }
    }
}
