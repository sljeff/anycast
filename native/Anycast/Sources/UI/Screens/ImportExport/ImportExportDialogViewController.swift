import UIKit
import UniformTypeIdentifiers
import AnycastKit

/// Import/export sheet (lib/widgets/import_export.dart:22-264, 03 §2.15):
/// Import (document picker → parse → progress ring → toast), Export (OPML
/// from subscriptions → UIActivityViewController), a manual RSS-URL field
/// (invalid → red "Invalid RSS Feed URL" alert), and the title-row help
/// button opening Feeds' ImportInstructions sheet. The Dart AlertDialog is a
/// floating fit-content sheet here (one custom detent, no grabber; the
/// system draws the 8 pt inset and the corners on iOS 26): content sits 28 pt
/// in, the primary Import and tonal Export capsules rest at the bottom in
/// thumb reach and ride above the keyboard while it is up. Settings and the
/// Inbox empty state present this controller by name.
final class ImportExportDialogViewController: UIViewController,
    UIDocumentPickerDelegate {

    private enum Layout {
        static let inset: CGFloat = 28
        static let minimumDetentHeight: CGFloat = 350
        static let controlHeight: CGFloat = 52
        static let titleRowHeight: CGFloat = 44
        static let fieldHeight: CGFloat = 48
        static let titleGap: CGFloat = 16
        static let minimumGroupGap: CGFloat = 24
        static let buttonGap: CGFloat = 12
    }

    private let context: UIContext
    private lazy var importer = PodcastImporter(database: context.database)

    private let urlField = UITextField()
    private var progressOverlay: ImportProgressOverlayController?

    /// While an import runs the sheet cannot be swiped away (the Dart
    /// barrier technically stayed dismissible, but dismissing mid-import
    /// desynced the Get.back pairing — closed as a crash-family fix).
    var isBusy = false {
        didSet { isModalInPresentation = isBusy }
    }

    static func present(from presenter: UIViewController, context: UIContext) {
        presenter.present(ImportExportDialogViewController(context: context), animated: true)
    }

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // One fit-content detent (the content is fixed-height and
            // shorter than the 350 pt floor); no grabber, swiping down
            // dismisses.
            sheet.detents = [
                .custom(identifier: .init("import-export.fit")) { context in
                    min(Layout.minimumDetentHeight, context.maximumDetentValue)
                }
            ]
            sheet.prefersGrabberVisible = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface
        buildContent()
    }

    // MARK: - Layout

    private func buildContent() {
        // Title row: 'Import & Export' + help IconButton (help_outline_rounded).
        let titleLabel = UILabel()
        titleLabel.text = "Import & Export"
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits = .header

        let helpButton = UIButton(type: .system)
        helpButton.setImage(AppIcons.help, for: .normal)
        helpButton.tintColor = Theme.onSurfaceVariant
        helpButton.isAccessibilityElement = true
        helpButton.accessibilityLabel = "Import help"
        helpButton.widthAnchor.constraint(equalToConstant: Layout.titleRowHeight).isActive = true
        helpButton.heightAnchor.constraint(equalToConstant: Layout.titleRowHeight).isActive = true
        helpButton.addAction(
            UIAction { [weak self] _ in
                // showModalBottomSheet(ImportInstructions) over the dialog
                // (Feeds' implementation, 03 §1.3).
                guard let self else { return }
                ImportInstructionsViewController.present(from: self)
            },
            for: .touchUpInside
        )

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, helpButton])
        titleRow.axis = .horizontal
        titleRow.alignment = .center   // Row default (center) — the Dart icon centered against the title
        titleRow.spacing = 8
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Import: primary capsule; Export: secondary (tonal) capsule.
        let importButton = AnycastButton.make(.primary, title: "Import")
        importButton.addAction(
            UIAction { [weak self] _ in self?.pickOPMLFile() },
            for: .touchUpInside
        )
        let exportButton = AnycastButton.make(.secondary, title: "Export")
        exportButton.addAction(
            UIAction { [weak self] _ in self?.exportSubscriptions() },
            for: .touchUpInside
        )

        // Manual RSS URL field (hint 'RSS Feed URL', URL keyboard). Custom
        // surface instead of `.roundedRect` — the system style paints pure
        // black, which is not a palette value and sat as a void on the
        // surface card (09 audit).
        urlField.clearButtonMode = .whileEditing
        urlField.applyAnycastStyle(placeholder: "RSS Feed URL")
        urlField.keyboardType = .URL
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.returnKeyType = .go
        urlField.delegate = self
        urlField.isAccessibilityElement = true
        urlField.accessibilityLabel = "RSS Feed URL"

        for item in [titleRow, urlField, importButton, exportButton] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }

        // The buttons rest 28 pt above the sheet bottom (the safe area wins
        // when larger, Detail's rule) or above the keyboard while it is up:
        // the system lifts the sheet only partway, so the content rides the
        // keyboard guide. The guide ignores the bottom safe area, so its top
        // is the sheet bottom while the keyboard is hidden.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        let exportBottom = exportButton.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor, constant: -Layout.inset
        )
        exportBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleRow.topAnchor.constraint(equalTo: view.topAnchor, constant: Layout.inset),
            titleRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Layout.inset),
            titleRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Layout.inset),
            titleRow.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.titleRowHeight),

            urlField.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: Layout.titleGap),
            urlField.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            urlField.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.fieldHeight),

            importButton.topAnchor.constraint(
                greaterThanOrEqualTo: urlField.bottomAnchor, constant: Layout.minimumGroupGap
            ),
            importButton.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            importButton.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            importButton.heightAnchor.constraint(equalToConstant: Layout.controlHeight),

            exportButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: Layout.buttonGap),
            exportButton.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            exportButton.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            exportButton.heightAnchor.constraint(equalToConstant: Layout.controlHeight),
            exportButton.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            exportBottom,
        ])
    }

    // MARK: - Import (file_picker → parseOPML → importPodcastsByUrls)

    private func pickOPMLFile() {
        let types: [UTType] = [
            UTType.xml,
            UTType(filenameExtension: "opml") ?? UTType.xml,
            UTType.plainText,
        ]
        let picker = UIDocumentPickerViewController(
            // asCopy: file_picker handed the app a tmp copy, not a
            // security-scoped original.
            forOpeningContentTypes: types, asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first else { return }
        // Get.dialog(ImportIndicator) before parsing (import_export.dart:85-86)
        // — the picker is still dismissing here, so wait for a free window.
        let overlay = ImportProgressOverlayController.determinate()
        progressOverlay = overlay
        Task { [weak self] in
            await self?.presentWhenPossible(overlay)
            guard let self else { return }

            // File read + XML parse off the main actor.
            let entries = await Task.detached(priority: .userInitiated) {
                (try? OPMLParser.parse(fileURL: fileURL)) ?? []
            }.value

            if entries.isEmpty {
                // Dart's parse error left the indicator hanging (crash family
                // K4); the port surfaces the shipped "no valid links" copy.
                overlay.dismiss(animated: true) {
                    self.progressOverlay = nil
                    self.showSimpleErrorAlert(message: ImportCopy.unparsableOPMLMessage)
                }
                return
            }
            await self.runImport(
                urls: entries.map(\.xmlURL),
                reportsProgress: true,
                completionText: { ImportResultText.batchFlow(titles: $0.titles) }
            )
        }
    }

    /// Presents once the receiver has nothing presented above it (the
    /// document picker's automatic dismissal is still animating when the
    /// pick callback fires).
    private func presentWhenPossible(_ controller: UIViewController) async {
        for _ in 0..<20 {
            if presentedViewController == nil, view.window != nil {
                present(controller, animated: true)
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}

    // MARK: - Manual URL import (import_export.dart:187-239)

    private func submitURLField() {
        let url = urlField.text ?? ""
        guard !url.isEmpty else { return }
        urlField.resignFirstResponder()
        let overlay = ImportProgressOverlayController.indeterminate()
        progressOverlay = overlay
        present(overlay, animated: true)
        Task { [weak self] in
            await self?.runImport(
                urls: [url],
                reportsProgress: false,
                completionText: { ImportResultText.manualURLFlow(title: $0.titles.first) }
            )
        }
    }

    // MARK: - Shared import pipeline

    private func runImport(
        urls: [String],
        reportsProgress: Bool,
        completionText: @escaping (PodcastImporter.Result) -> String
    ) async {
        isBusy = true
        importer.onPhaseChange = { [weak self] phase in
            guard case .importing(let progress?) = phase else { return }
            self?.progressOverlay?.setProgress(progress)
        }
        await importer.importByURLs(urls, reportsProgress: reportsProgress)
        isBusy = false

        let window = view.window
        let result: PodcastImporter.Result
        if case .finished(let finished) = importer.phase {
            result = finished
        } else {
            result = PodcastImporter.Result(requestedURLCount: urls.count, importedSubscriptions: [])
        }

        if result.writeFailed {
            // Nothing was persisted — alert instead of a success toast for
            // BOTH flows (the empty-titles toast parity below covers failed
            // fetches, not failed writes).
            let overlay = progressOverlay
            progressOverlay = nil
            overlay?.dismiss(animated: true) {
                self.showSimpleErrorAlert(message: ImportCopy.importWriteFailedMessage)
            }
            return
        }

        if !reportsProgress, ImportCopy.needsInvalidFeedAlert(result) {
            // Only the manual-URL flow alerts on empty results
            // (import_export.dart:196-226); the OPML flow toasts regardless
            // — an all-failed import still "succeeds" with empty titles.
            let overlay = progressOverlay
            progressOverlay = nil
            overlay?.dismiss(animated: true) {
                self.showSimpleErrorAlert(message: ImportCopy.invalidFeedURLMessage)
            }
            return
        }

        // Get.back() x2 — overlay, then this dialog — then the snackbar.
        let text = completionText(result)
        await dismissOverlays()
        if let window {
            ToastPresenter.shared.show(text, in: window, duration: 3.0)
        }
    }

    private func dismissOverlays() async {
        progressOverlay = nil
        // Dismissing self cascades to the progress overlay it presented
        // (the Dart Get.back() x2 pair).
        dismiss(animated: true)
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    /// The red "Invalid RSS Feed URL" alert (import_export.dart:198-225):
    /// red headline + red body, single OK action.
    private func showSimpleErrorAlert(message: String) {
        let alert = UIAlertController(
            title: ImportCopy.invalidFeedURLTitle, message: nil, preferredStyle: .alert
        )
        let title = NSAttributedString(string: ImportCopy.invalidFeedURLTitle, attributes: [
            .font: TypographyV2.emphasis.font(),
            .foregroundColor: UIColor.systemRed,
        ])
        let body = NSAttributedString(string: message, attributes: [
            .font: TypographyV2.body.font(),
            .foregroundColor: UIColor.systemRed,
        ])
        // Isolated KVC: UIAlertController exposes no public attributed
        // title/message API, and the red headline + red body are Dart parity
        // (import_export.dart:198-225) — this private key path is the only
        // way to color a system alert's text without a hand-rolled dialog.
        alert.setValue(title, forKey: "attributedTitle")
        alert.setValue(body, forKey: "attributedMessage")
        alert.addAction(UIAlertAction(title: ImportCopy.okButton, style: .default))
        present(alert, animated: true)
    }

    // MARK: - Export (import_export.dart:139-159)

    private func exportSubscriptions() {
        isBusy = true
        Task { [weak self] in
            guard let self else { return }
            // A read failure must degrade to an alert, not to an empty
            // list — sharing an empty OPML looks like a valid backup.
            guard let subscriptions = try? await self.context.database.subscriptionRepository().listAll() else {
                self.isBusy = false
                self.showSimpleErrorAlert(message: ImportCopy.exportWriteFailedMessage)
                return
            }
            // Dart wrote Documents/anycast_subscriptions.xml then shared it
            // (share_plus); the file path is kept so previous exports remain
            // discoverable in Files. The write runs off the main actor like
            // the import's parse leg.
            let fileURL = self.context.paths.documents
                .appendingPathComponent("anycast_subscriptions.xml")
            let written = await Task.detached(priority: .userInitiated) { () -> Bool in
                let opml = OPMLWriter.document(subscriptions: subscriptions)
                do {
                    try opml.data(using: .utf8)?.write(to: fileURL, options: .atomic)
                    return true
                } catch {
                    return false
                }
            }.value
            self.isBusy = false
            guard written else {
                self.showSimpleErrorAlert(message: ImportCopy.exportWriteFailedMessage)
                return
            }

            let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = self.view
            self.present(activity, animated: true)
        }
    }
}

extension ImportExportDialogViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitURLField()
        return true
    }
}
