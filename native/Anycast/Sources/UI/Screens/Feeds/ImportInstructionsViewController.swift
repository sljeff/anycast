import UIKit

/// ImportInstructions content (lib/widgets/import_export.dart:251-333),
/// extracted verbatim — five ExpansionTile sections; the XiaoYuzhou
/// (小宇宙) entry is
/// the one Chinese-copy exception (03 §8).
enum ImportInstructionsContent {

    struct Section: Equatable {
        let title: String
        /// The exact Dart description string ("\n"-joined numbered steps).
        let text: String

        var lines: [String] { text.components(separatedBy: "\n") }
    }

    static let headerTitle = "Import OPML from"

    static let sections: [Section] = [
        Section(
            title: "Castro",
            text: "1. Open Castro.\n"
                + "2. Tap the Settings icon on the top left.\n"
                + "3. Scroll down to \"User Data\" and tap it.\n"
                + "4. Click \"Export Subscriptions\"\n"
                + "5. Share to \"Anycast\""
        ),
        Section(
            title: "Overcast",
            text: "1. Open Overcast.\n"
                + "2. Tap the Settings icon on the top left.\n"
                + "3. Scroll down to \"Export OPML\" and tap it.\n"
                + "4. Share to \"Anycast\""
        ),
        Section(
            title: "Pocket Casts",
            text: "1. Open Pocket Casts -> Profile\n"
                + "2. Tap Settings icon on the top right\n"
                + "3. Scroll down to \"Export Podcasts\"\n"
                + "4. Click \"Export Podcasts\"\n"
                + "5. Share to \"Anycast\""
        ),
        Section(
            title: "小宇宙",
            text: "1. 打开小宇宙 -> 订阅\n"
                + "2. 点击右上角 \"我的订阅\"\n"
                + "3. 点击右上角的分享按钮\n"
                + "4. 选中所有想要导入的频道\n"
                + "5. 点击 \"导出 OPML\"\n"
                + "6. 分享到 \"Anycast\""
        ),
        Section(
            title: "Other Apps using OPML",
            text: "1. Find your OPML file\n"
                + "2. Share to \"Anycast\""
        ),
    ]
}

/// The import-instructions sheet (import_export.dart:249-343, 03 §2.15 /
/// §3.4): a DraggableScrollableSheet at 0.7 initial / 0.6 min — custom
/// fraction detents, scroll-linked shrink — with the system
/// grabber. The five instruction sections render as
/// disclosure rows; several may stay open at once (ExpansionTile keeps no
/// exclusivity).
final class ImportInstructionsViewController: UIViewController {

    /// Sheet content inset: the title, the rows and the chevrons share it.
    private static let contentInset: CGFloat = 28

    private enum SectionKind {
        static let header = "ImportInstructionsHeader"
        static let steps = "ImportInstructionsSteps"
    }

    private let collectionView: UICollectionView
    private var expandedSections: Set<Int> = []

    // MARK: - Present (showModalBottomSheet + DraggableScrollableSheet 0.7/0.6)

    static func present(from presenter: UIViewController) {
        let controller = ImportInstructionsViewController()
        controller.modalPresentationStyle = .pageSheet
        let sheet = controller.sheetPresentationController
        // SDK 27 removed Detent.fraction; the custom resolver reproduces it
        // (height = maximumDetentValue × fraction). Largest detent first:
        // the sheet opens at 0.7 and shrinks to 0.6 while scrolling.
        func fractionDetent(_ fraction: CGFloat) -> UISheetPresentationController.Detent {
            UISheetPresentationController.Detent.custom(
                identifier: .init("import-instructions-\(fraction)")
            ) { context in
                context.maximumDetentValue * fraction
            }
        }
        sheet?.detents = [fractionDetent(0.7), fractionDetent(0.6)]
        sheet?.prefersGrabberVisible = true
        presenter.present(controller, animated: true)
    }

    init() {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let item = NSCollectionLayoutItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(48)
                )
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: item.layoutSize, subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: Self.contentInset, bottom: 16, trailing: Self.contentInset
            )
            _ = environment
            return section
        }
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        // Fixed title over the scrolling list — the Dart
        // Column[Handler, title, Expanded(ListView)].
        let titleLabel = UILabel()
        titleLabel.text = ImportInstructionsContent.headerTitle
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.register(
            ImportSectionHeaderCell.self,
            forCellWithReuseIdentifier: SectionKind.header
        )
        collectionView.register(
            ImportSectionStepsCell.self,
            forCellWithReuseIdentifier: SectionKind.steps
        )

        view.addSubview(collectionView)
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.contentInset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.contentInset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Self.contentInset),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// MARK: - Data source

extension ImportInstructionsViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        ImportInstructionsContent.sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        expandedSections.contains(section) ? 2 : 1   // header (+ steps when open)
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let section = ImportInstructionsContent.sections[indexPath.section]
        if indexPath.item == 0 {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SectionKind.header, for: indexPath
            )
            if let header = cell as? ImportSectionHeaderCell {
                header.configure(title: section.title, expanded: expandedSections.contains(indexPath.section))
                header.onToggle = { [weak self] in
                    self?.toggleSection(indexPath.section)
                }
            }
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SectionKind.steps, for: indexPath
        )
        if let steps = cell as? ImportSectionStepsCell {
            steps.configure(text: section.text)
        }
        return cell
    }

    private func toggleSection(_ section: Int) {
        // ExpansionTile: independent tiles, several may stay open.
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
        // Plain no-animation rebuild (08 §7.2); the chevron rotates with the
        // cell's own animation.
        UIView.performWithoutAnimation {
            collectionView.reloadSections(IndexSet(integer: section))
        }
    }
}

// MARK: - Cells

/// Disclosure header row: app title + rotating chevron. Collapsed icon is
/// secondary, expanded is primary (ExpansionTile collapsedIconColor/iconColor).
final class ImportSectionHeaderCell: UICollectionViewCell {

    static let preferredHeight: CGFloat = 48

    var onToggle: (() -> Void)?

    private let titleLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = TypographyV2.body.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        chevron.image = UIImage(systemName: "chevron.down")
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(chevron)

        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityTraits = [.button]

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 16),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.preferredHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggle = nil
    }

    func configure(title: String, expanded: Bool) {
        titleLabel.text = title
        accessibilityLabel = title
        accessibilityValue = expanded ? "expanded" : "collapsed"
        chevron.tintColor = expanded ? Theme.primary : Theme.onSurfaceVariant
        let transform = CGAffineTransform(rotationAngle: expanded ? .pi : 0)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
            self.chevron.transform = transform
        }
    }

    @objc private func tapped() {
        onToggle?()
    }
}

/// The numbered steps block under an open section (ExpansionTile children):
/// secondary text on the rows' leading edge.
final class ImportSectionStepsCell: UICollectionViewCell {

    private let stepsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stepsLabel.font = TypographyV2.meta.font()
        stepsLabel.textColor = Theme.onSurfaceVariant
        stepsLabel.numberOfLines = 0
        stepsLabel.adjustsFontForContentSizeCategory = true
        stepsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stepsLabel)
        NSLayoutConstraint.activate([
            stepsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stepsLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            stepsLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stepsLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(text: String) {
        stepsLabel.text = text
    }
}
