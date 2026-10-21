import UIKit

/// The Inbox category strip in the Anycast 2.0 UI kit form (`CategoryStrip`):
/// a horizontal row of text chips derived from `subscription.categories`
/// where selection reads through brightness alone — the selected label in
/// full ink, the rest at `sandAlpha8`, cross-faded on change — with the
/// selected chip scrolled into view. Data mapping lives in
/// `CategoryStripModel` so the pure dedupe/sort logic is testable without
/// the view.
@MainActor
final class CategoryStripView: UIView {

    struct Chip {
        let label: String
        /// The raw category value this chip filters on (`nil` = all).
        let value: String?
    }

    /// Fires with the selected chip's value (`nil` = the "all" chip).
    var onSelect: ((String?) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var chips: [Chip] = []
    private var buttons: [UIButton] = []
    private var selectedValue: String?

    static let chipHeight: CGFloat = 44

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.contentInset = UIEdgeInsets(top: 0, left: Spacing.xs, bottom: 0, right: Spacing.xs)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.chipHeight),

            // Symmetric page margins: an overflowing strip gets 16 pt of
            // scroll padding at both ends, and the first chip never hugs
            // the screen edge (same edge treatment as ChipTabBarView).
            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.pageH
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.pageH
            ),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Reloads the strip. `selected` not present in `categories` resets to all.
    func configure(categories: [String], selected: String?) {
        chips = CategoryStripModel.chips(categories: categories)
        selectedValue = chips.contains { $0.value == selected } ? selected : nil

        buttons.forEach { $0.removeFromSuperview() }
        buttons = chips.map { chip in
            var config = UIButton.Configuration.plain()
            config.title = chip.label
            config.titleLineBreakMode = .byClipping
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: Spacing.gap, bottom: 0, trailing: Spacing.gap
            )
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = TypographyV2.titleMedium.font()
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.accessibilityIdentifier = chip.value.map { "category-\($0)" } ?? "category-all"
            button.accessibilityLabel = chip.label
            button.heightAnchor.constraint(equalToConstant: Self.chipHeight).isActive = true
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.titleLabel?.numberOfLines = 1
            button.addAction(UIAction { [weak self] _ in
                guard let self, chip.value != self.selectedValue else { return }
                Haptics.selection()
                self.select(chip.value, animated: true)
                self.onSelect?(chip.value)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
            return button
        }
        applySelection()
    }

    var currentSelection: String? { selectedValue }

    /// The number of chips currently configured, the "All" chip included.
    /// Below 2 the strip is nothing but the lone "All" chip — hosts hide
    /// the whole row in that case (dead UI).
    var chipsCount: Int { chips.count }

    /// Silent selection update (programmatic moves).
    func select(_ value: String?, animated: Bool) {
        selectedValue = chips.contains { $0.value == value } ? value : nil
        guard animated, !Motion.reduceMotion else {
            applySelection()
            return
        }
        UIView.transition(
            with: stack, duration: Motion.quick,
            options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
            animations: applySelection
        )
        scrollSelectedChipIntoView()
    }

    private func applySelection() {
        for (index, button) in buttons.enumerated() {
            let active = chips[index].value == selectedValue
            button.configuration?.baseForegroundColor = active ? Theme.onSurface : AnycastColor.sandAlpha8
            button.accessibilityTraits = active ? [.button, .selected] : [.button]
        }
    }

    /// Keeps the selected chip — plus a peek of its neighbor — on screen.
    private func scrollSelectedChipIntoView() {
        guard let index = chips.firstIndex(where: { $0.value == selectedValue }),
              buttons.indices.contains(index) else { return }
        layoutIfNeeded()
        var rect = buttons[index].frame
        let neighbor = index + 1 < buttons.count ? buttons[index + 1] : (index > 0 ? buttons[index - 1] : nil)
        if let neighbor {
            rect = rect.union(neighbor.frame.insetBy(dx: neighbor.frame.width / 4, dy: 0))
        }
        scrollView.scrollRectToVisible(stack.convert(rect, to: scrollView), animated: true)
    }
}

/// Pure chip derivation for `CategoryStripView` (09 §3.2): the "All" chip
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
        let all = CategoryStripView.Chip(label: "All", value: nil)
        let rest = distinct.map { category in
            CategoryStripView.Chip(label: displayLabel(category), value: category)
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
