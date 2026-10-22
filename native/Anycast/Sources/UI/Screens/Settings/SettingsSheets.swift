import UIKit
import AnycastKit

/// Picker sheet for the country and language choices: a title over a plain
/// list of options, drawn directly on the sheet (restrained 2.0 Settings
/// direction, 2026-10-21). No close button and no grabber — swiping down
/// dismisses without a change. The presenter sizes the sheet with
/// `customDetent()`.
final class SettingsOptionSheetViewController: UIViewController {

    /// Called with the chosen option's code when a row is tapped; the sheet
    /// dismisses itself.
    var onSelect: ((String) -> Void)?

    static let contentInset: CGFloat = 28
    static let titleGap: CGFloat = 12
    static let rowHeight: CGFloat = 52
    static let minimumDetentHeight: CGFloat = 350
    static let maximumDetentFraction: CGFloat = 0.72

    private let titleText: String
    private let options: [(name: String, code: String)]
    private let selectedCode: String?
    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>?
    private let titleLabel = UILabel()

    init(title: String, options: [(name: String, code: String)], selectedCode: String?) {
        self.titleText = title
        self.options = options
        self.selectedCode = selectedCode

        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = .clear
        let lastItem = options.count - 1
        config.itemSeparatorHandler = { indexPath, proposed in
            var separator = proposed
            separator.color = AnycastColor.sandAlpha4
            separator.topSeparatorInsets = .zero
            separator.bottomSeparatorInsets = .zero
            if indexPath.item == lastItem {
                separator.bottomSeparatorVisibility = .hidden
            }
            return separator
        }
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Title block + rows, clamped to 350 pt at least and 72% of the
    /// available detent height at most.
    static func detentHeight(rowCount: Int, maximum: CGFloat) -> CGFloat {
        let titleBlock = contentInset + TypographyV2.emphasis.font().lineHeight
            + titleGap + contentInset
        let content = titleBlock + CGFloat(rowCount) * rowHeight
        return min(max(content, minimumDetentHeight), maximum * maximumDetentFraction)
    }

    /// The single detent that fits this sheet's content.
    func customDetent() -> UISheetPresentationController.Detent {
        let rowCount = options.count
        return .custom(identifier: .init("settings.options")) { context in
            Self.detentHeight(rowCount: rowCount, maximum: context.maximumDetentValue)
        }
    }

    /// Page sheet with the one content-fitting detent and no grabber; a
    /// swipe down dismisses without a change.
    func present(from presenter: UIViewController) {
        modalPresentationStyle = .pageSheet
        if let presentation = sheetPresentationController {
            presentation.detents = [customDetent()]
            presentation.prefersGrabberVisible = false
        }
        presenter.present(self, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? AnycastColor.sandDark4 : AnycastColor.sand1
        }

        titleLabel.text = titleText
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let registration = UICollectionView.CellRegistration<SettingsOptionRowCell, Int> {
            [options, selectedCode] cell, _, index in
            let option = options[index]
            cell.configure(title: option.name, isSelected: option.code == selectedCode)
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
        collectionView.backgroundColor = .clear
        collectionView.contentInset.bottom = Self.contentInset
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.contentInset),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.contentInset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.contentInset),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.contentInset),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.contentInset),
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Self.titleGap),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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

/// One option row of the picker sheet: the name, plus a primary-tinted
/// checkmark and primary text on the selected option.
final class SettingsOptionRowCell: UICollectionViewListCell {

    private let titleLabel = UILabel()
    private let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark"))

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = TypographyV2.body.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        checkmarkView.tintColor = Theme.primary
        checkmarkView.setContentHuggingPriority(.required, for: .horizontal)
        checkmarkView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, checkmarkView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Spacing.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let minimumHeight = contentView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: SettingsOptionSheetViewController.rowHeight
        )
        minimumHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.gap),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.gap),
            minimumHeight,
        ])

        automaticallyUpdatesBackgroundConfiguration = false
        configurationUpdateHandler = { [unowned self] _, state in
            var background = UIBackgroundConfiguration.clear()
            if state.isHighlighted || state.isSelected {
                background.backgroundColor = AnycastColor.sandAlpha5
            }
            self.backgroundConfiguration = background
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(title: String, isSelected: Bool) {
        titleLabel.text = title
        titleLabel.textColor = isSelected ? Theme.primary : Theme.onSurface
        checkmarkView.isHidden = !isSelected
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}

/// Settings list row (restrained 2.0 Settings direction, 2026-10-21): a
/// title with an optional one-line subtitle, an optional trailing value,
/// an optional control (switch / stepper) and an optional chevron, inset 24
/// with 12 above and below and a 56 pt minimum height. The plate fill
/// comes from the cell background; pressing fills `sandAlpha5` over it.
/// Self-drawn rather than a content configuration so the trailing controls
/// stay real, touchable views.
class SettingsRowCell: UICollectionViewListCell {

    static let horizontalInset: CGFloat = 24
    static let minimumHeight: CGFloat = 56
    /// Rows whose trailing control is taller than the text block shrink the
    /// outer inset and pad the text block instead (see `SettingsStepperRowCell`).
    class var verticalInset: CGFloat { 12 }

    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let valueLabel = UILabel()
    let textStack = UIStackView()
    private let chevronView = UIImageView(
        image: UIImage(systemName: "chevron.forward")?.applyingSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
    )
    private let rowStack = UIStackView()
    private var usesPlate = true

    /// Dimmed rows keep their layout but read as inert.
    private(set) var isDimmed = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Labels truncate rather than wrap (restrained Settings copy rule).
        titleLabel.font = TypographyV2.body.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1
        valueLabel.font = TypographyV2.meta.font()
        valueLabel.textColor = Theme.onSurfaceVariant
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.numberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail
        chevronView.tintColor = Theme.onSurfaceVariant
        chevronView.contentMode = .center

        textStack.axis = .vertical
        textStack.spacing = Spacing.xxs
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        let textPadding = 12 - Self.verticalInset
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: textPadding, leading: 0, bottom: textPadding, trailing: 0
        )

        // The text block takes the slack; the value truncates before the
        // title wraps.
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(UILayoutPriority(740), for: .horizontal)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = Spacing.gap
        rowStack.addArrangedSubview(textStack)
        rowStack.addArrangedSubview(valueLabel)
        rowStack.addArrangedSubview(chevronView)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rowStack)

        let minimumHeight = contentView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Self.minimumHeight
        )
        minimumHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Self.horizontalInset
            ),
            rowStack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Self.horizontalInset
            ),
            rowStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalInset),
            rowStack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Self.verticalInset
            ),
            minimumHeight,
        ])

        // Fill-only press feedback: the plate fill with sandAlpha5 over it;
        // nothing scales and nothing stays selected.
        automaticallyUpdatesBackgroundConfiguration = false
        configurationUpdateHandler = { [unowned self] _, state in
            var background = UIBackgroundConfiguration.clear()
            let pressed = state.isHighlighted || state.isSelected
            if self.usesPlate {
                background.backgroundColor = pressed ? Self.pressedPlateFill : Theme.surface
            } else if pressed {
                background.backgroundColor = AnycastColor.sandAlpha5
            }
            self.backgroundConfiguration = background
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// `sandAlpha5` composited over the plate, resolved per appearance.
    private static let pressedPlateFill = UIColor { traits in
        let overlay = AnycastColor.sandAlpha5.resolvedColor(with: traits)
        let plate = Theme.surface.resolvedColor(with: traits)
        var (or, og, ob, oa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (pr, pg, pb, pa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard overlay.getRed(&or, green: &og, blue: &ob, alpha: &oa),
              plate.getRed(&pr, green: &pg, blue: &pb, alpha: &pa) else { return overlay }
        return UIColor(
            red: or * oa + pr * (1 - oa),
            green: og * oa + pg * (1 - oa),
            blue: ob * oa + pb * (1 - oa),
            alpha: 1
        )
    }

    /// Standard plate row. Resets every field, so a reused cell never keeps
    /// the previous row's look.
    func configure(
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        showsChevron: Bool = false,
        isDimmed: Bool = false
    ) {
        usesPlate = true
        self.isDimmed = isDimmed
        titleLabel.attributedText = nil
        titleLabel.text = title
        titleLabel.textColor = isDimmed ? Theme.onSurfaceVariant : Theme.onSurface
        titleLabel.textAlignment = .natural
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        valueLabel.text = value
        valueLabel.isHidden = value == nil
        chevronView.isHidden = !showsChevron
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityValue = value
        setNeedsUpdateConfiguration()
    }

    /// Plain centered underlined link (Privacy / Terms), no plate.
    func configureLink(title: String) {
        configure(title: title)
        usesPlate = false
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [
            .font: TypographyV2.meta.font(),
            .foregroundColor: Theme.onSurfaceVariant,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        titleLabel.textAlignment = .center
        accessibilityTraits = .link
        setNeedsUpdateConfiguration()
    }

    /// Installs a control between the value and the chevron.
    func setTrailingView(_ view: UIView) {
        rowStack.insertArrangedSubview(view, at: rowStack.arrangedSubviews.count - 1)
    }
}

/// Switch row cell: the label and caption left, a sand-tinted UISwitch
/// right. A tap anywhere on the row toggles the switch (`toggle()`), the
/// same path VoiceOver activation takes.
final class SettingsSwitchListCell: SettingsRowCell {

    var onSwitchChanged: ((Bool) -> Void)?

    private let switchView = UISwitch()

    override init(frame: CGRect) {
        super.init(frame: frame)
        switchView.onTintColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? AnycastColor.sandDark9 : AnycastColor.sand12
        }
        switchView.thumbTintColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? AnycastColor.sandDark1 : AnycastColor.sand1
        }
        switchView.setContentHuggingPriority(.required, for: .horizontal)
        switchView.setContentCompressionResistancePriority(.required, for: .horizontal)
        switchView.addTarget(self, action: #selector(switchToggled), for: .valueChanged)
        setTrailingView(switchView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setOn(_ on: Bool, animated: Bool) {
        switchView.setOn(on, animated: animated)
    }

    var isOn: Bool { switchView.isOn }

    /// Flips the switch with animation and reports the change like a real
    /// toggle. The cell is the row's single accessibility element (the real
    /// switch is folded into it), so row taps and VoiceOver/Switch Control
    /// activation both route here.
    func toggle() {
        switchView.setOn(!switchView.isOn, animated: true)
        onSwitchChanged?(switchView.isOn)
    }

    override func accessibilityActivate() -> Bool {
        toggle()
        return true
    }

    @objc private func switchToggled() {
        onSwitchChanged?(switchView.isOn)
    }
}

/// Stepper row cell: the title, then the value, then the − | + capsule.
/// The capsule's halves are separate accessibility elements next to the
/// row's text, so the cell itself is not one element.
final class SettingsStepperRowCell: SettingsRowCell {

    /// Fires on a tap of either half; the owner applies the step.
    var onStep: ((SettingsPageModel.StepDirection) -> Void)?

    override class var verticalInset: CGFloat { 6 }

    private lazy var stepper = AnycastStepperView(
        minusLabel: "",
        plusLabel: "",
        onMinus: { [weak self] in self?.onStep?(.decrease) },
        onPlus: { [weak self] in self?.onStep?(.increase) }
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        stepper.setContentHuggingPriority(.required, for: .horizontal)
        stepper.setContentCompressionResistancePriority(.required, for: .horizontal)
        setTrailingView(stepper)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(
        title: String,
        value: String,
        labels: (decrease: String, increase: String),
        canDecrease: Bool,
        canIncrease: Bool
    ) {
        configure(title: title, value: value)
        stepper.minusButton.accessibilityLabel = labels.decrease
        stepper.plusButton.accessibilityLabel = labels.increase
        stepper.setEnabled(minus: canDecrease, plus: canIncrease)

        isAccessibilityElement = false
        textStack.isAccessibilityElement = true
        textStack.accessibilityLabel = title
        textStack.accessibilityValue = value
        accessibilityElements = [textStack, stepper.minusButton, stepper.plusButton]
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
        label.font = TypographyV2.body.font()
        // Inverse pair: readable over any page in both appearances.
        label.textColor = Theme.surface
        label.numberOfLines = 0
        label.textAlignment = .natural
        label.adjustsFontForContentSizeCategory = true

        let pill = UIView()
        pill.backgroundColor = Theme.inverseSurface
        pill.layer.cornerRadius = Radius.md
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
