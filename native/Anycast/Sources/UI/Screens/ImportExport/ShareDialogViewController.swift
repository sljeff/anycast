import UIKit
import AnycastKit

/// Share-handoff dialog (lib/widgets/share.dart, 03 §2.15): the Get.dialog
/// AlertDialog over the share-extension handoff — the importable channel
/// list from the shared OPML, Close + Import actions, and the share-style
/// progress ring (strokeWidth 2) during import. The empty state carries the
/// shipped "no valid links" copy.
final class ShareDialogViewController: DialogBaseViewController {

    private let context: UIContext
    private let entries: [OPMLParser.Entry]
    private lazy var importer = PodcastImporter(database: context.database)

    private let listView = UITableView(frame: .zero, style: .plain)
    private var progressOverlay: ImportProgressOverlayController?

    /// Stub-era entry point (kept: the coordinator constructs by name).
    convenience init(context: UIContext) {
        self.init(context: context, entries: [])
    }

    init(context: UIContext, entries: [OPMLParser.Entry]) {
        self.context = context
        self.entries = entries
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // width: Get.width * 0.8 — kept relative to the presented container.
        constrainCardWidth(fraction: 0.8)

        let titleLabel = UILabel()
        titleLabel.text = "Import Podcasts"
        titleLabel.font = Typography.secondaryTitle.font()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(column)

        if entries.isEmpty {
            // share.dart:13-35 — the empty/invalid payload state.
            let message = UILabel()
            message.text = "Oh no! Seems like there is no valid links in the file."
            message.font = Typography.htmlBody.font()
            message.textColor = Theme.primaryLightMax
            message.adjustsFontForContentSizeCategory = true
            message.numberOfLines = 0

            let ok = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = "OK"
            configuration.baseForegroundColor = Theme.primary
            ok.configuration = configuration
            ok.titleLabel?.font = Typography.mainText.font()
            ok.addAction(
                UIAction { [weak self] _ in self?.dismiss(animated: true) },
                for: .touchUpInside
            )
            column.addArrangedSubview(message)
            column.addArrangedSubview(ok)
            column.alignment = .center
        } else {
            let list = makeListView()
            let actions = makeActionRow()
            column.addArrangedSubview(list)
            column.addArrangedSubview(actions)
            column.alignment = .fill
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -24),

            column.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            column.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            column.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    /// ListView.separated of Card>ListTile rows (titleMedium, one line,
    /// ellipsis; Divider(height: 1)), height 300 (share.dart:40-65).
    private func makeListView() -> UIView {
        listView.register(ShareEntryCell.self, forCellReuseIdentifier: ShareEntryCell.reuseIdentifier)
        listView.dataSource = self
        listView.delegate = self
        listView.backgroundColor = .clear
        listView.separatorColor = Theme.cardOutline
        listView.rowHeight = UITableView.automaticDimension
        listView.estimatedRowHeight = 56
        listView.isAccessibilityElement = true
        listView.accessibilityLabel = "Importable podcasts"
        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.heightAnchor.constraint(equalToConstant: 300).isActive = true
        return listView
    }

    /// Close (secondary) + Import (filled inverseSurface) — share.dart:67-117.
    private func makeActionRow() -> UIView {
        let close = UIButton(type: .system)
        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.title = "Close"
        closeConfiguration.baseForegroundColor = Theme.secondaryText
        close.configuration = closeConfiguration
        close.titleLabel?.font = Typography.mainText.font()
        close.addAction(
            UIAction { [weak self] _ in self?.dismiss(animated: true) },
            for: .touchUpInside
        )

        let confirm = UIButton(type: .system)
        var confirmConfiguration = UIButton.Configuration.filled()
        confirmConfiguration.title = "Import"
        confirmConfiguration.baseBackgroundColor = Theme.primaryLightMax
        confirmConfiguration.baseForegroundColor = Theme.primaryBackgroundDark
        confirmConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 24, bottom: 10, trailing: 24
        )
        confirm.configuration = confirmConfiguration
        confirm.titleLabel?.font = Typography.mainText.font()
        confirm.addAction(
            UIAction { [weak self] _ in self?.startImport() },
            for: .touchUpInside
        )

        let row = UIStackView(arrangedSubviews: [close, confirm])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    // MARK: - Import (share.dart:77-105)

    private func startImport() {
        guard !isBusy else { return }
        isBusy = true

        let overlay = ImportProgressOverlayController.shareStyle()
        progressOverlay = overlay
        present(overlay, animated: true)

        Task { [weak self] in
            guard let self else { return }
            self.importer.onPhaseChange = { [weak self] phase in
                guard case .importing(let progress?) = phase else { return }
                self?.progressOverlay?.setProgress(progress)
            }
            await self.importer.importByURLs(
                self.entries.map(\.xmlURL), reportsProgress: true
            )
            self.isBusy = false

            var titles: [String] = []
            if case .finished(let result) = self.importer.phase {
                titles = result.titles
            }
            // Get.back() x2, progress reset, then the truncated-titles
            // snackbar — same batch text as the OPML flow. Dismissing self
            // cascades to the progress overlay above it.
            let window = self.view.window
            let text = ImportResultText.batchFlow(titles: titles)
            self.progressOverlay = nil
            self.dismiss(animated: true)
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let window {
                ToastPresenter.shared.show(text, in: window, duration: 3.0)
            }
        }
    }
}

// MARK: - List

extension ShareDialogViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ShareEntryCell.reuseIdentifier, for: indexPath
        )
        if let shareCell = cell as? ShareEntryCell, entries.indices.contains(indexPath.row) {
            shareCell.configure(title: entries[indexPath.row].title)
        }
        return cell
    }
}

/// A Card > ListTile row: titleMedium, single line, tail-ellipsis.
final class ShareEntryCell: UITableViewCell {

    static let reuseIdentifier = "ShareEntryCell"

    private let card = UIView()
    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        card.backgroundColor = Theme.loginCardBackground
        card.layer.cornerRadius = 8
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        titleLabel.font = Typography.cardTitleBold.font()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String) {
        titleLabel.text = title
        isAccessibilityElement = true
        accessibilityLabel = title
    }
}
