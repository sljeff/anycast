import UIKit

/// The v2 Inbox category strip (Figma `inbox category` 637:9506 +
/// `category capsule item` 599:30274 — 09 §3.2): a horizontal row of capsule
/// chips (icon + label) derived from `subscription.categories`. The SELECTED
/// chip is the `state=selected` variant (599:30269): `goldAlpha7` fill +
/// `sandAlpha4` 1 pt stroke + pill, icon/label in `sand1`; UNSELECTED chips
/// are `sandAlpha2` pills with `onSurfaceVariant` content. Data mapping
/// lives in `CategoryStripModel` so the pure dedupe/sort logic is testable
/// without the view.
@MainActor
final class CategoryStripView: UIView {

    struct Chip {
        let label: String
        let icon: UIImage?
        /// The raw category value this chip filters on (`nil` = all).
        let value: String?
    }

    /// Fires with the selected chip's value (`nil` = the "all" chip).
    var onSelect: ((String?) -> Void)?

    private let scrollView = UIScrollView()
    private var chips: [Chip] = []
    private var buttons: [UIButton] = []
    private var selectedValue: String?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInset = UIEdgeInsets(top: 0, left: Spacing.pageH, bottom: 0, right: Spacing.pageH)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.chipHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static let chipHeight: CGFloat = 44
    private var previousChip: UIButton?

    /// Reloads the strip. `selected` not present in `categories` resets to all.
    func configure(categories: [String], selected: String?) {
        chips = CategoryStripModel.chips(categories: categories)
        selectedValue = chips.contains { $0.value == selected } ? selected : nil

        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        previousChip = nil

        for (index, chip) in chips.enumerated() {
            var config = UIButton.Configuration.plain()
            config.image = chip.icon?.withRenderingMode(.alwaysTemplate)
            config.imagePadding = Spacing.xxs
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: Spacing.row, bottom: 0, trailing: Spacing.row
            )
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                // Figma selected variant: SF Pro 590 (semibold) 16/21.
                outgoing.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: .systemFont(ofSize: 16, weight: .semibold)
                )
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(chip.label, for: .normal)
            button.layer.cornerRadius = Self.chipHeight / 2
            button.layer.cornerCurve = .continuous
            button.clipsToBounds = true
            button.accessibilityIdentifier = chip.value.map { "category-\($0)" } ?? "category-all"
            button.accessibilityLabel = chip.label
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.select(chip.value, animated: true)
                self.onSelect?(chip.value)
            }, for: .touchUpInside)
            scrollView.addSubview(button)
            buttons.append(button)

            let leading: NSLayoutConstraint
            if let previous = previousChip {
                leading = button.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: Spacing.sm)
            } else {
                leading = button.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor)
            }
            NSLayoutConstraint.activate([
                leading,
                button.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
                button.heightAnchor.constraint(equalToConstant: Self.chipHeight),
            ])
            if index == chips.count - 1 {
                button.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor).isActive = true
            }
            previousChip = button
        }
        applySelection()
        setNeedsLayout()
    }

    var currentSelection: String? { selectedValue }

    /// Silent selection update (programmatic moves).
    func select(_ value: String?, animated: Bool) {
        selectedValue = chips.contains { $0.value == value } ? value : nil
        applySelection()
    }

    private func applySelection() {
        for (index, button) in buttons.enumerated() {
            let active = chips[index].value == selectedValue
            // 09 §3.2 selected variant: goldAlpha7 fill + sandAlpha4 1 pt
            // stroke + sand1 content; unselected: sandAlpha2 fill only,
            // onSurfaceVariant content.
            button.backgroundColor = active ? AnycastColor.goldAlpha7 : AnycastColor.sandAlpha2
            button.layer.borderColor = AnycastColor.sandAlpha4.cgColor
            button.layer.borderWidth = active ? Spacing.hairline : 0
            button.tintColor = active ? AnycastColor.sand1 : Theme.onSurfaceVariant
            button.setTitleColor(active ? AnycastColor.sand1 : Theme.onSurfaceVariant, for: .normal)
            button.accessibilityTraits = active ? [.button, .selected] : [.button]
        }
    }

    /// Re-resolves the chip stroke colors on appearance flips — the border
    /// runs through `layer.borderColor` (CGColor freeze, 09 §9a).
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            applySelection()
        }
    }
}

/// Pure chip derivation for `CategoryStripView` (09 §3.2): the "all" chip
/// plus one chip per distinct category from the comma-separated
/// `subscription.categories` column, case-insensitively deduped, sorted, and
/// title-cased for display.
nonisolated enum CategoryStripModel {

    static func chips(categories: [String]) -> [CategoryStripView.Chip] {
        var seen = Set<String>()
        let distinct = categories
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.lowercased() < $1.lowercased() }
        let all = CategoryStripView.Chip(label: "all", icon: AppIcons.subscriptions, value: nil)
        let rest = distinct.map { category in
            CategoryStripView.Chip(label: displayLabel(category), icon: nil, value: category)
        }
        return [all] + rest
    }

    /// First letter uppercased, rest as-is (categories arrive lowercase from
    /// the RSS pipeline).
    static func displayLabel(_ category: String) -> String {
        guard let first = category.first else { return category }
        return first.uppercased() + category.dropFirst()
    }
}
