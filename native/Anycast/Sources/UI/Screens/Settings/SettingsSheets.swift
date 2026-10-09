import UIKit
import AnycastKit

/// Country/language option sheet (A8 adaptation of the country_code_picker
/// dialog): a plain list page sheet — the Flutter dialog had no search and
/// no flags, so the closest sanctioned form is a simple name list. 07 §2.7
/// permits either a list sheet or a UIPickerView; the list matches the
/// 49-row scrollable dialog more closely.
final class SettingsOptionSheetViewController: UIViewController {

    /// Called with the chosen option's code when a row is tapped; the sheet
    /// dismisses itself.
    var onSelect: ((String) -> Void)?

    private let titleText: String
    private let options: [(name: String, code: String)]
    private let selectedCode: String?
    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>?
    private let headerLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    init(title: String, options: [(name: String, code: String)], selectedCode: String?) {
        self.titleText = title
        self.options = options
        self.selectedCode = selectedCode

        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .none
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        // Header row: title + close icon, like the picker dialog's top bar.
        headerLabel.text = titleText
        headerLabel.font = Typography.secondaryTitle.font()
        headerLabel.textColor = Theme.primaryLightMax
        headerLabel.adjustsFontForContentSizeCategory = true
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(AppIcons.close, for: .normal)
        closeButton.tintColor = Theme.secondaryText
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.isPointerInteractionEnabled = true
        closeButton.accessibilityLabel = "Close"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> {
            [options, selectedCode] cell, _, index in
            let option = options[index]
            var config = cell.defaultContentConfiguration()
            config.text = option.name
            config.textProperties.color = Theme.primaryLightMax
            config.textProperties.font = Typography.mainText.font()
            cell.contentConfiguration = config
            cell.accessories = option.code == selectedCode ? [.checkmark()] : []
            // v2 surface token instead of the system insetGrouped gray
            // (09 audit — same treatment as the settings main list).
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = Theme.surfaceContainer
            cell.backgroundConfiguration = background
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) {
            collectionView, indexPath, index in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: index)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(options.indices))
        dataSource.apply(snapshot, animatingDifferences: false)
        self.dataSource = dataSource

        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)
        view.addSubview(closeButton)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(
                equalTo: view.readableContentGuide.leadingAnchor, constant: 20
            ),
            headerLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12
            ),
            closeButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(
                equalTo: view.readableContentGuide.trailingAnchor, constant: -20
            ),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(
                equalTo: headerLabel.bottomAnchor, constant: 8
            ),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

extension SettingsOptionSheetViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard options.indices.contains(indexPath.item) else { return }
        let code = options[indexPath.item].code
        onSelect?(code)
        dismiss(animated: true)
    }
}

/// Switch row cell (settings.dart:205-235: a plain Row with the label left
/// and the Material Switch right). The row is self-drawn — label + UISwitch
/// with plain constraints — because driving it through a content
/// configuration on a UICollectionViewListCell buried the switch under the
/// system-managed content view (present in AX, invisible and untouchable).
final class SettingsSwitchListCell: UICollectionViewListCell {

    var onSwitchChanged: ((Bool) -> Void)?

    private let titleLabel = UILabel()
    private let switchView = UISwitch()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = Typography.mainText.font()
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        switchView.addTarget(self, action: #selector(switchToggled), for: .valueChanged)
        switchView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(switchView)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.leadingAnchor
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: switchView.leadingAnchor, constant: -8
            ),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            switchView.trailingAnchor.constraint(
                equalTo: contentView.layoutMarginsGuide.trailingAnchor
            ),
            switchView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    func setOn(_ on: Bool, animated: Bool) {
        switchView.setOn(on, animated: animated)
    }

    var isOn: Bool { switchView.isOn }

    /// The cell is the row's single accessibility element (the real
    /// switch is folded into it), so VoiceOver/Switch Control activation
    /// must drive the switch — didSelectItemAt deliberately ignores this
    /// row, so without this override the toggle is unreachable without
    /// direct touch.
    override func accessibilityActivate() -> Bool {
        switchView.setOn(!switchView.isOn, animated: true)
        onSwitchChanged?(switchView.isOn)
        return true
    }

    @objc private func switchToggled() {
        onSwitchChanged?(switchView.isOn)
    }
}

/// The 200 pt picker sheet (Dart `SettingsBottomContainer` + CupertinoPicker,
/// settings.dart:603-633, 07 §2.7 maps it to UIPickerView).
final class SettingsValuePickerSheetViewController: UIViewController {

    /// Fires on every row change while scrolling, like CupertinoPicker's
    /// `onSelectedItemChanged` — each change is persisted.
    var onSelect: ((Int) -> Void)?

    private let picker = UIPickerView()
    private let choices: [String]
    private let initialIndex: Int

    init(choices: [String], initialIndex: Int) {
        self.choices = choices
        self.initialIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func preferredSheetHeight() -> CGFloat { 200 }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        picker.dataSource = self
        picker.delegate = self
        picker.selectRow(initialIndex, inComponent: 0, animated: false)
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            picker.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

extension SettingsValuePickerSheetViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        choices.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        choices[row]
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        onSelect?(row)
    }
}

/// Long-press info caption (07 §2.7): a small dark floating overlay shown
/// ~2 s — the Dart `Tooltip(showDuration: 2000ms)` messages.
enum SettingsTooltipOverlay {

    static let displayDuration: TimeInterval = 2.0

    private static weak var overlay: UIView?
    private static var dismissalTask: Task<Void, Never>?

    /// Shows `message` above `anchor` inside `container`, clamped to the
    /// container's bounds (any window size; no screen-math).
    @MainActor
    static func show(message: String, above anchor: UIView, in container: UIView) {
        overlay?.removeFromSuperview()
        dismissalTask?.cancel()

        let label = UILabel()
        label.text = message
        label.font = Typography.defaultText.font()
        label.textColor = Theme.primaryLightMax
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.adjustsFontForContentSizeCategory = true

        let pill = UIView()
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.87)
        pill.layer.cornerRadius = 12
        pill.layer.cornerCurve = .continuous
        pill.alpha = 0
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        container.addSubview(pill)

        let anchorTop = anchor.convert(anchor.bounds, to: container).minY
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -8),
            pill.leadingAnchor.constraint(
                equalTo: container.readableContentGuide.leadingAnchor
            ),
            pill.trailingAnchor.constraint(
                lessThanOrEqualTo: container.readableContentGuide.trailingAnchor
            ),
            pill.bottomAnchor.constraint(
                equalTo: container.topAnchor,
                constant: max(8, anchorTop - 8)
            ),
        ])

        overlay = pill
        UIView.animate(withDuration: 0.15) { pill.alpha = 1 }

        dismissalTask = Task {
            try? await Task.sleep(for: .seconds(displayDuration))
            guard !Task.isCancelled else { return }
            UIView.animate(withDuration: 0.2, animations: { pill.alpha = 0 }) { _ in
                pill.removeFromSuperview()
            }
        }
    }
}
