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

/// Settings sheet (lib/pages/settings.dart, 03 §2.13): inset-grouped list
/// mirroring the Dart groups. Presented via AppSheets.presentExpand from the
/// shell's gear button; children (Login/ImportExport/History) are presented
/// from here. iOS 26 glass comes free with the system list appearance — no
/// custom background painting (07 §2.7).
final class SettingsViewController: UIViewController {

    private let context: UIContext
    private var languageApplier: SettingsLanguageChangeApplier

    /// Live settings snapshot; writes land through the coordinator, then the
    /// box is re-read (the sheet never mutates the box itself).
    private var settings: AppSettings

    private let collectionView: UICollectionView
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
            collectionViewLayout: Self.makeLayout(box: context.settingsBox)
        )

        super.init(nibName: nil, bundle: nil)
    }

    /// Per-section list layout: inset-grouped everywhere except the trailing
    /// Privacy links, which sit outside any group card in Dart (a centered
    /// column, settings.dart privacy.dart) — plain appearance, no separators.
    private static func makeLayout(box: SettingsBox) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            let sections = SettingsPageModel.sections(
                includeTargetLanguage: SettingsPageModel.showsTargetLanguage(
                    targetLanguage: box.current.targetLanguage
                )
            )
            let plain = sections.indices.contains(sectionIndex) && sections[sectionIndex].plainStyle
            var config = UICollectionLayoutListConfiguration(
                appearance: plain ? .plain : .insetGrouped
            )
            if sections.indices.contains(sectionIndex) {
                config.headerMode = sections[sectionIndex].header == nil ? .none : .supplementary
                if plain {
                    config.showsSeparators = false
                }
            }
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

        configureDataSource()

        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

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
        let rowRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configure(cell, for: row)
        }
        let switchRegistration = UICollectionView.CellRegistration<SettingsSwitchListCell, SettingsPageModel.Row> {
            [weak self] cell, _, row in
            self?.configureSwitchCell(cell, for: row)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            let sections = SettingsPageModel.sections(includeTargetLanguage: true)
            guard sections.indices.contains(indexPath.section),
                  let title = sections[indexPath.section].header else { return }
            var config = header.defaultContentConfiguration()
            config.text = title
            config.textProperties.color = Theme.secondaryText
            config.textProperties.font = Typography.mainText.font()
            header.contentConfiguration = config
            header.backgroundConfiguration = .clear()
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, SettingsPageModel.Row>(
            collectionView: collectionView
        ) { collectionView, indexPath, row in
            let cell: UICollectionViewListCell
            if row == .enableTranslation {
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: switchRegistration, for: indexPath, item: row
                )
            } else {
                cell = collectionView.dequeueConfiguredReusableCell(
                    using: rowRegistration, for: indexPath, item: row
                )
            }
            // v2 surface token instead of the system insetGrouped gray —
            // the default material is not part of the palette and halved
            // the card/background contrast step (09 audit).
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = Theme.surfaceContainer
            cell.backgroundConfiguration = background
            return cell
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
        let sections = SettingsPageModel.sections(
            includeTargetLanguage: SettingsPageModel.showsTargetLanguage(
                targetLanguage: settings.targetLanguage
            )
        )
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

    /// Underlined link text (privacy.dart / the contact row keep the Dart
    /// `TextDecoration.underline` treatment).
    private static func underlined(_ title: String, color: UIColor, font: UIFont) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
    }

    private func configure(_ cell: UICollectionViewListCell, for row: SettingsPageModel.Row) {
        var config = cell.defaultContentConfiguration()
        config.textProperties.color = Theme.primaryLightMax
        config.textProperties.font = Typography.mainText.font()
        config.textProperties.adjustsFontForContentSizeCategory = true
        config.secondaryTextProperties.color = Theme.secondaryText
        config.secondaryTextProperties.font = Typography.cardTextLight.font()
        config.secondaryTextProperties.adjustsFontForContentSizeCategory = true

        var accessibilityValue: String?
        cell.accessories = []

        switch row {
        case .account:
            config.image = AppIcons.person
            config.imageProperties.tintColor = Theme.secondaryText
            config.text = SettingsPageModel.title(for: row)
        case .country:
            config.text = SettingsPageModel.title(for: row)
            config.secondaryText = SettingsPageModel.countryName(forCode: settings.countryCode)
            accessibilityValue = config.secondaryText
        case .enableTranslation:
            // Handled by configureSwitchCell (SettingsSwitchListCell).
            break
        case .targetLanguage:
            // Indented sub-row: the Dart `arrow_elbow_down_right_bold` prefix
            // (settings.dart:511-519) becomes a leading elbow icon + indent.
            config.image = AppIcons.elbowIndent
            config.imageProperties.tintColor = Theme.secondaryText
            config.text = SettingsPageModel.title(for: row)
            config.secondaryText = SettingsPageModel.languageName(forCode: settings.targetLanguage)
            accessibilityValue = config.secondaryText
            cell.indentationLevel = 1
        case .importExport, .history:
            config.text = SettingsPageModel.title(for: row)
        case .autoRefreshInterval:
            config.text = SettingsPageModel.title(for: row)
            config.secondaryText = SettingsPageModel.autoRefreshDisplay(
                seconds: settings.autoRefreshInterval
            )
            accessibilityValue = config.secondaryText
        case .maxFeedEpisodes:
            config.text = SettingsPageModel.title(for: row)
            config.secondaryText = SettingsPageModel.maxEpisodesDisplay(count: settings.maxFeedEpisodes)
            accessibilityValue = config.secondaryText
        case .maxHistoryEpisodes:
            config.text = SettingsPageModel.title(for: row)
            config.secondaryText = SettingsPageModel.maxEpisodesDisplay(count: settings.maxHistoryEpisodes)
            accessibilityValue = config.secondaryText
        case .contactEmail:
            config.attributedText = Self.underlined(
                SettingsPageModel.title(for: row),
                color: Theme.accent,
                font: Typography.cardTextLight.font()
            )
        case .privacyPolicy, .termsOfUse:
            config.attributedText = Self.underlined(
                SettingsPageModel.title(for: row),
                color: Theme.brandGreen,
                font: Typography.cardTextLight.font()
            )
        }

        cell.contentConfiguration = config
        cell.isAccessibilityElement = true
        cell.accessibilityLabel = SettingsPageModel.title(for: row)
        cell.accessibilityValue = accessibilityValue
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
        if let tooltip = SettingsPageModel.tooltip(for: row) {
            cell.accessibilityHint = tooltip
        }
    }

    /// The translation switch row (settings.dart:205-235).
    private func configureSwitchCell(_ cell: SettingsSwitchListCell, for row: SettingsPageModel.Row) {
        let enabled = SettingsPageModel.showsTargetLanguage(targetLanguage: settings.targetLanguage)
        cell.setTitle(SettingsPageModel.title(for: row))
        cell.setOn(enabled, animated: false)
        cell.onSwitchChanged = { [weak self] isOn in
            self?.translationSwitchToggled(isOn: isOn)
        }
        cell.isAccessibilityElement = true
        cell.accessibilityTraits = .button
        cell.accessibilityLabel = SettingsPageModel.title(for: row)
        // Spoken words, not the stored encoding ("1"/"0" read as "one"/"zero").
        cell.accessibilityValue = enabled ? "On" : "Off"
        cell.accessibilityIdentifier = SettingsPageModel.identifier(for: row)
    }

    // MARK: - Actions

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
            title: SettingsPageModel.optionSheetTitle,
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
        AppSheets.presentForm(sheet, from: self)
    }

    private func presentLanguageSheet() {
        let sheet = SettingsOptionSheetViewController(
            title: SettingsPageModel.optionSheetTitle,
            options: SettingsPageModel.languages.map { ($0.name, $0.code) },
            selectedCode: settings.targetLanguage
        )
        sheet.onSelect = { [weak self] code in
            guard let self else { return }
            Task { await self.applyLanguageChange(code) }
        }
        AppSheets.presentForm(sheet, from: self)
    }

    private func presentValuePicker(
        choices: [String],
        initialIndex: Int,
        onIndex: @escaping (Int) async -> Void
    ) {
        let sheet = SettingsValuePickerSheetViewController(choices: choices, initialIndex: initialIndex)
        sheet.onSelect = { index in Task { await onIndex(index) } }
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [
                .custom { _ in SettingsValuePickerSheetViewController.preferredSheetHeight() }
            ]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    private func presentAutoRefreshPicker() {
        presentValuePicker(
            choices: SettingsCodec.autoRefreshChoicesSeconds.indices.map(SettingsPageModel.autoRefreshLabel),
            initialIndex: SettingsPageModel.autoRefreshPickerIndex(seconds: settings.autoRefreshInterval),
            onIndex: { [weak self] index in
                guard let self else { return }
                await self.context.settingsCoordinator.updateAutoRefreshInterval(
                    SettingsPageModel.autoRefreshSeconds(at: index)
                )
                self.refreshFromBox()
            }
        )
    }

    private func presentMaxEpisodesPicker(current: Int64, update: @escaping (Int64) async -> Void) {
        presentValuePicker(
            choices: SettingsCodec.maxEpisodesChoices.indices.map(SettingsPageModel.maxEpisodesLabel),
            initialIndex: SettingsPageModel.maxEpisodesPickerIndex(count: current),
            onIndex: { [weak self] index in
                guard let self else { return }
                await update(SettingsPageModel.maxEpisodesCount(at: index))
                self.refreshFromBox()
            }
        )
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

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource?.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .account: presentAccount()
        case .country: presentCountrySheet()
        case .enableTranslation: break // The switch accessory handles it.
        case .targetLanguage: presentLanguageSheet()
        case .importExport: presentImportExport()
        case .history: presentHistory()
        case .autoRefreshInterval: presentAutoRefreshPicker()
        case .maxFeedEpisodes:
            presentMaxEpisodesPicker(current: settings.maxFeedEpisodes) { [weak self] value in
                await self?.context.settingsCoordinator.updateMaxFeedEpisodes(value)
            }
        case .maxHistoryEpisodes:
            presentMaxEpisodesPicker(current: settings.maxHistoryEpisodes) { [weak self] value in
                await self?.context.settingsCoordinator.updateMaxHistoryEpisodes(value)
            }
        case .contactEmail: openFeedbackMail()
        case .privacyPolicy: presentSafari(SettingsPageModel.privacyPolicyURL)
        case .termsOfUse: presentSafari(SettingsPageModel.termsOfUseURL)
        }
    }
}
