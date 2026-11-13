import UIKit
import UniformTypeIdentifiers
import AnycastKit

/// The one import sheet. A picked file, a file shared to Anycast, the Inbox's
/// "Import from another app" and Settings' "Import subscriptions" all end
/// here, and the buttons change in place through three stages:
///
/// - Confirm: how many shows, from which file, how many are already
///   followed; the list of titles; one primary button.
/// - Progress: the button becomes a bar, "X of N" and Cancel; rows tick as
///   they finish. Nothing is written until every fetch is done, so Cancel
///   imports nothing.
/// - Result: stays until Done. Shows imported, the ones that failed with a
///   reason, whether the Inbox will drop older episodes, and Try again for
///   the failed ones only.
@MainActor
final class ImportSheetViewController: UIViewController {

    enum Stage: Equatable {
        case confirm
        case progress
        case result
    }

    private enum RowState: Equatable {
        case waiting
        case done
        case failed(String)
    }

    private enum Layout {
        static let inset: CGFloat = 28
        static let controlHeight: CGFloat = 52
        static let rowHeight: CGFloat = 44
        static let minimumDetentHeight: CGFloat = 380
        static let maximumDetentFraction: CGFloat = 0.8
        static let visibleRowsInDetent = 6
    }

    // MARK: - Inputs

    private let importer: PodcastImporter
    private let context: UIContext?
    /// How many episodes the Inbox keeps, and how many it holds now. Both
    /// are injected so tests do not need a settings box.
    private let inboxLimit: () -> Int
    private let inboxCount: () async -> Int?

    private(set) var filename: String?
    private(set) var plan: ImportPlan
    /// Runs when Done is tapped (or the sheet has nothing to do). Defaults to
    /// dismissing the sheet; the Inbox's instructions flow dismisses both.
    var onDone: (() -> Void)?

    // MARK: - State

    private(set) var stage: Stage = .confirm
    private var states: [RowState]
    /// Indices into `plan.entries` the current run covers.
    private var runIndices: [Int] = []
    private var finishedCount = 0
    private var importedTotal = 0
    private var writeFailed = false
    private var inboxNote: String?
    private var importTask: Task<Void, Never>?
    private var holdsTrim = false
    private var picker: ImportFilePicker?
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    // MARK: - Views

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let noteLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let progressCountLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let progressRow = UIStackView()
    private var primaryButton = AnycastButton.make(.primary, title: " ")
    private var secondaryButton = AnycastButton.make(.secondary, title: " ")
    private let footer = UIStackView()

    // MARK: - Init

    init(
        context: UIContext?,
        importer: PodcastImporter,
        plan: ImportPlan,
        filename: String?,
        inboxLimit: @escaping () -> Int,
        inboxCount: @escaping () async -> Int?
    ) {
        self.context = context
        self.importer = importer
        self.plan = plan
        self.filename = filename
        self.inboxLimit = inboxLimit
        self.inboxCount = inboxCount
        self.states = Array(repeating: .waiting, count: plan.entries.count)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [detent()]
            sheet.prefersGrabberVisible = false
        }
    }

    /// The production sheet over the app's database and settings.
    convenience init(context: UIContext, plan: ImportPlan, filename: String?) {
        self.init(
            context: context,
            importer: PodcastImporter(database: context.database),
            plan: plan,
            filename: filename,
            inboxLimit: { Int(context.settingsBox.current.maxFeedEpisodes) },
            inboxCount: { try? await context.database.feedRepository().count() }
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Detent

    /// One detent for all three stages, so the sheet never resizes under the
    /// buttons: the header, up to six rows, and the footer.
    static func detentHeight(rowCount: Int, maximum: CGFloat) -> CGFloat {
        let header = Layout.inset + TypographyV2.emphasis.font().lineHeight
            + 4 + TypographyV2.meta.font().lineHeight + 16
        let rows = CGFloat(min(max(rowCount, 1), Layout.visibleRowsInDetent)) * Layout.rowHeight
        let footer: CGFloat = 16 + 3 * 20 + Layout.controlHeight * 2 + 12 + Layout.inset
        return min(max(header + rows + footer, Layout.minimumDetentHeight), maximum * Layout.maximumDetentFraction)
    }

    private func detent() -> UISheetPresentationController.Detent {
        .custom(identifier: .init("import.sheet")) { [weak self] context in
            Self.detentHeight(rowCount: self?.plan.entries.count ?? 0, maximum: context.maximumDetentValue)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? AnycastColor.sandDark4 : AnycastColor.sand1
        }
        buildViews()
        render()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        importTask?.cancel()
        endTrimHold()
    }

    // MARK: - Build

    private func buildViews() {
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        titleLabel.accessibilityIdentifier = "import-title"

        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        subtitleLabel.accessibilityIdentifier = "import-subtitle"

        tableView.register(ImportRowCell.self, forCellReuseIdentifier: ImportRowCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = Layout.rowHeight
        tableView.allowsSelection = false
        tableView.showsVerticalScrollIndicator = true
        tableView.accessibilityIdentifier = "import-list"

        noteLabel.font = TypographyV2.meta.font()
        noteLabel.textColor = Theme.onSurfaceVariant
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.numberOfLines = 0
        noteLabel.accessibilityIdentifier = "import-note"

        progressBar.progressTintColor = Theme.primary
        progressBar.trackTintColor = AnycastColor.sandAlpha4
        progressBar.accessibilityIdentifier = "import-progress-bar"
        progressCountLabel.font = TypographyV2.meta.font()
        progressCountLabel.textColor = Theme.onSurfaceVariant
        progressCountLabel.adjustsFontForContentSizeCategory = true
        progressCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressCountLabel.accessibilityIdentifier = "import-progress-count"
        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = ImportCopy.cancel
        cancelConfiguration.baseForegroundColor = Theme.onSurface
        cancelConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.emphasis.font()
            return outgoing
        }
        cancelButton.configuration = cancelConfiguration
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelButton.accessibilityIdentifier = "import-cancel"
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancelTapped() }, for: .touchUpInside)

        progressRow.axis = .horizontal
        progressRow.alignment = .center
        progressRow.spacing = 12
        progressRow.addArrangedSubview(progressBar)
        progressRow.addArrangedSubview(progressCountLabel)
        progressRow.addArrangedSubview(cancelButton)
        progressRow.heightAnchor.constraint(equalToConstant: Layout.controlHeight).isActive = true

        primaryButton.accessibilityIdentifier = "import-primary"
        secondaryButton.accessibilityIdentifier = "import-secondary"
        primaryButton.addAction(UIAction { [weak self] _ in self?.primaryAction?() }, for: .touchUpInside)
        secondaryButton.addAction(UIAction { [weak self] _ in self?.secondaryAction?() }, for: .touchUpInside)
        for button in [primaryButton, secondaryButton] {
            button.heightAnchor.constraint(equalToConstant: Layout.controlHeight).isActive = true
        }

        footer.axis = .vertical
        footer.spacing = 12
        footer.alignment = .fill
        for item in [noteLabel, progressRow, primaryButton, secondaryButton] {
            footer.addArrangedSubview(item)
        }

        for item in [titleLabel, subtitleLabel, tableView, footer] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }

        let footerBottom = footer.bottomAnchor.constraint(
            equalTo: view.bottomAnchor, constant: -Layout.inset
        )
        footerBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.inset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.inset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.inset),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),

            footer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            footer.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            footerBottom,
        ])
    }

    // MARK: - Rendering

    /// Plan indices of the rows the list shows in the current stage.
    private var visibleIndices: [Int] {
        switch stage {
        case .confirm:
            return Array(plan.entries.indices)
        case .progress:
            return runIndices
        case .result:
            let failed = plan.entries.indices.filter {
                if case .failed = states[$0] { return true } else { return false }
            }
            return failed.isEmpty ? runIndices : failed
        }
    }

    private var failedIndices: [Int] {
        plan.entries.indices.filter {
            if case .failed = states[$0] { return true } else { return false }
        }
    }

    private func setButton(
        _ button: UIButton, _ kind: AnycastButton.Kind, title: String?
    ) {
        guard let title else {
            button.isHidden = true
            return
        }
        button.isHidden = false
        button.configuration = AnycastButton.configuration(kind, title: title)
    }

    private func render() {
        isModalInPresentation = stage != .confirm
        noteLabel.isHidden = true
        progressRow.isHidden = true
        tableView.isHidden = false
        subtitleLabel.isHidden = false
        var primary: (String, () -> Void)?
        var secondary: (String, () -> Void)?

        switch stage {
        case .confirm:
            if plan.isEmptyFile {
                titleLabel.text = ImportCopy.noFeedsTitle
                subtitleLabel.isHidden = true
                tableView.isHidden = true
                primary = (ImportCopy.chooseAnotherFile, { [weak self] in self?.chooseAnotherFile() })
            } else if plan.isAllFollowed {
                titleLabel.text = ImportCopy.allFollowedTitle(total: plan.alreadyFollowed)
                subtitleLabel.text = ImportCopy.confirmSubtitle(filename: filename, alreadyFollowed: 0)
                tableView.isHidden = true
                primary = (ImportCopy.done, { [weak self] in self?.doneTapped() })
            } else {
                titleLabel.text = ImportCopy.confirmTitle(count: plan.entries.count)
                subtitleLabel.text = ImportCopy.confirmSubtitle(
                    filename: filename, alreadyFollowed: plan.alreadyFollowed
                )
                primary = (ImportCopy.confirmButton(count: plan.entries.count), { [weak self] in
                    self?.startImport(of: Array(self?.plan.entries.indices ?? 0..<0))
                })
            }
        case .progress:
            titleLabel.text = ImportCopy.confirmTitle(count: runIndices.count)
            subtitleLabel.text = ImportCopy.confirmSubtitle(
                filename: filename, alreadyFollowed: plan.alreadyFollowed
            )
            progressRow.isHidden = false
            updateProgressViews()
        case .result:
            if writeFailed {
                titleLabel.text = ImportCopy.writeFailedTitle
                subtitleLabel.isHidden = true
                tableView.isHidden = true
            } else {
                titleLabel.text = ImportCopy.resultTitle(imported: importedTotal)
                let failed = failedIndices.count
                subtitleLabel.text = failed > 0 ? ImportCopy.failedSummary(count: failed) : nil
                subtitleLabel.isHidden = failed == 0
                tableView.isHidden = visibleIndices.isEmpty
            }
            if let inboxNote {
                noteLabel.text = inboxNote
                noteLabel.isHidden = false
            }
            primary = (ImportCopy.done, { [weak self] in self?.doneTapped() })
            let retryCount = writeFailed ? runIndices.count : failedIndices.count
            if retryCount > 0 {
                secondary = (ImportCopy.retryButton(count: retryCount), { [weak self] in
                    guard let self else { return }
                    self.startImport(of: self.writeFailed ? self.runIndices : self.failedIndices)
                })
            }
        }

        primaryAction = primary?.1
        secondaryAction = secondary?.1
        setButton(primaryButton, .primary, title: primary?.0)
        setButton(secondaryButton, .secondary, title: secondary?.0)
        tableView.reloadData()
        sheetPresentationController?.invalidateDetents()
        UIAccessibility.post(notification: .layoutChanged, argument: titleLabel)
    }

    private func updateProgressViews() {
        let total = max(runIndices.count, 1)
        progressBar.setProgress(Float(finishedCount) / Float(total), animated: !Motion.reduceMotion)
        progressCountLabel.text = ImportCopy.progressCount(finished: finishedCount, total: runIndices.count)
        // Once every address has answered the write is under way: too late
        // to cancel, and it takes a moment.
        cancelButton.isEnabled = finishedCount < runIndices.count
    }

    // MARK: - Running

    private func startImport(of indices: [Int]) {
        guard stage != .progress, !indices.isEmpty else { return }
        beginTrimHold()
        runIndices = indices
        for index in indices { states[index] = .waiting }
        finishedCount = 0
        writeFailed = false
        inboxNote = nil
        stage = .progress
        render()

        let entries = indices.map { plan.entries[$0] }
        importTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.importer.run(entries) { [weak self] finished, answered in
                guard let self, self.stage == .progress else { return }
                self.finishedCount = max(self.finishedCount, finished)
                for (offset, ok) in answered where self.runIndices.indices.contains(offset) {
                    let index = self.runIndices[offset]
                    // A failure's reason is filled in with the outcome; the
                    // tick is final the moment the feed came back.
                    if ok { self.states[index] = .done }
                }
                self.updateProgressViews()
                self.reloadVisibleRows()
            }
            await self.finish(with: outcome)
        }
    }

    private func finish(with outcome: ImportOutcome) async {
        importTask = nil
        if outcome.cancelled {
            // Nothing was written.
            for index in runIndices { states[index] = .waiting }
            runIndices = []
            stage = .confirm
            endTrimHold()
            render()
            return
        }

        writeFailed = outcome.writeFailed
        if outcome.writeFailed {
            for index in runIndices { states[index] = .waiting }
        } else {
            let failureByURL = Dictionary(
                outcome.failures.map { ($0.entry.xmlURL, $0.reason) },
                uniquingKeysWith: { first, _ in first }
            )
            for index in runIndices {
                if let reason = failureByURL[plan.entries[index].xmlURL] {
                    states[index] = .failed(reason.text)
                } else {
                    states[index] = .done
                }
            }
            importedTotal += outcome.imported.count
            if !outcome.imported.isEmpty, let count = await inboxCount() {
                inboxNote = ImportCopy.inboxLimitNote(inboxCount: count, limit: inboxLimit())
            }
        }
        stage = .result
        render()
        // The trim stays held: it is released by Done.
    }

    private func cancelTapped() {
        guard stage == .progress else { return }
        cancelButton.isEnabled = false
        importTask?.cancel()
    }

    private func doneTapped() {
        endTrimHold()
        if let onDone {
            onDone()
        } else {
            dismiss(animated: true)
        }
    }

    private func beginTrimHold() {
        guard !holdsTrim else { return }
        holdsTrim = true
        InboxTrimHold.acquire()
    }

    private func endTrimHold() {
        guard holdsTrim else { return }
        holdsTrim = false
        InboxTrimHold.release()
    }

    private func reloadVisibleRows() {
        tableView.reloadData()
    }

    // MARK: - Choose another file

    private func chooseAnotherFile() {
        let picker = ImportFilePicker { [weak self] url in
            self?.picker = nil
            guard let url else { return }
            Task { await self?.load(fileURL: url) }
        }
        self.picker = picker
        picker.present(from: self)
    }

    /// Replaces the file this sheet is about, in place.
    func load(fileURL: URL) async {
        let entries = await ImportFlow.parse(fileURL: fileURL)
        let newPlan = await importer.plan(entries: entries)
        apply(plan: newPlan, filename: fileURL.lastPathComponent)
    }

    func apply(plan: ImportPlan, filename: String?) {
        self.plan = plan
        self.filename = filename
        states = Array(repeating: .waiting, count: plan.entries.count)
        runIndices = []
        importedTotal = 0
        stage = .confirm
        render()
    }
}

// MARK: - List

extension ImportSheetViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleIndices.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ImportRowCell.reuseIdentifier, for: indexPath
        ) as! ImportRowCell
        let indices = visibleIndices
        guard indices.indices.contains(indexPath.row) else { return cell }
        let index = indices[indexPath.row]
        let title = plan.entries[index].title
        switch states[index] {
        case .waiting: cell.configure(title: title, status: .none)
        case .done: cell.configure(title: title, status: stage == .confirm ? .none : .done)
        case .failed(let reason): cell.configure(title: title, status: .failed(reason))
        }
        return cell
    }
}

/// One show: its title, and once it has finished a tick or the reason it
/// failed.
final class ImportRowCell: UITableViewCell {

    enum Status: Equatable {
        case none
        case done
        case failed(String)
    }

    static let reuseIdentifier = "ImportRowCell"

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let tick = UIImageView(image: UIImage(systemName: "checkmark"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.font = TypographyV2.meta.font()
        statusLabel.textColor = Theme.onSurfaceVariant
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        tick.tintColor = Theme.primary
        tick.setContentHuggingPriority(.required, for: .horizontal)
        tick.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, statusLabel, tick])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, status: Status) {
        titleLabel.text = title
        statusLabel.isHidden = true
        tick.isHidden = true
        var spoken = title
        switch status {
        case .none: break
        case .done:
            tick.isHidden = false
            spoken += ", imported"
        case .failed(let reason):
            statusLabel.text = reason
            statusLabel.isHidden = false
            spoken += ", \(reason)"
        }
        isAccessibilityElement = true
        accessibilityLabel = spoken
    }
}

// MARK: - File picker

/// The system document picker with a closure, retained by its owner until
/// it answers. xml, opml and plain text, as a copy (no security scope).
@MainActor
final class ImportFilePicker: NSObject, UIDocumentPickerDelegate {

    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func present(from presenter: UIViewController) {
        let types: [UTType] = [
            UTType.xml,
            UTType(filenameExtension: "opml") ?? UTType.xml,
            UTType.plainText,
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}

// MARK: - Entry points

/// The doors into the import sheet.
@MainActor
enum ImportFlow {

    /// Retains a picker that has no other owner until it answers.
    private static var activePicker: ImportFilePicker?

    /// Reads the OPML off the main actor; an unreadable file is an empty one.
    nonisolated static func parse(fileURL: URL) async -> [OPMLParser.Entry] {
        await Task.detached(priority: .userInitiated) {
            (try? OPMLParser.parse(fileURL: fileURL)) ?? []
        }.value
    }

    /// Settings' "Import subscriptions" and the instructions' "Choose a file":
    /// the file picker, then the sheet. `onDone` replaces the sheet's own
    /// dismissal (the instructions flow closes both).
    static func chooseFile(
        from presenter: UIViewController, context: UIContext, onDone: (() -> Void)? = nil
    ) {
        let picker = ImportFilePicker { url in
            activePicker = nil
            guard let url else { return }
            Task {
                await present(from: presenter, context: context, fileURL: url, onDone: onDone)
            }
        }
        activePicker = picker
        picker.present(from: presenter)
    }

    /// A file already in hand (picked, or shared to Anycast): parse, split
    /// into new and already followed, and present the sheet.
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        fileURL: URL,
        onDone: (() -> Void)? = nil
    ) async {
        let entries = await parse(fileURL: fileURL)
        let plan = await PodcastImporter(database: context.database).plan(entries: entries)
        let sheet = ImportSheetViewController(context: context, plan: plan, filename: fileURL.lastPathComponent)
        sheet.onDone = onDone
        await presentWhenFree(sheet, from: presenter)
    }

    /// The picker's own dismissal may still be animating when it answers.
    static func presentWhenFree(_ sheet: UIViewController, from presenter: UIViewController) async {
        for _ in 0..<20 {
            let top = presenter.topMostPresented()
            if !(top is UIDocumentPickerViewController), top.view.window != nil {
                top.present(sheet, animated: true)
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
