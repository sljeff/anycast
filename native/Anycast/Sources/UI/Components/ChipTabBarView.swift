import UIKit

/// The secondary tab strip in the Anycast 2.0 chip language (09 §3.2): each
/// title is a capsule chip on `sandAlpha2`, and a gold capsule slides under
/// the selected one (selected = `goldAlpha7` + `sandAlpha4` hairline + sand1
/// ink, same as `CategoryStripView`). Used by Discover categories (scrolls),
/// SearchPage tabs, and Channel Newest/Oldest.
///
/// Interaction notes (03 §2.1/§3.5): the strip mirrors a TabBar — selection
/// changes animate the capsule, and the strip scrolls horizontally when its
/// chips overflow (Discover's many categories).
final class ChipTabBarView: UIView {

    /// Informed on user tap; the caller updates its page content.
    var onSelect: ((Int) -> Void)?

    let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var chips: [UIView] = []
    private var titleLabels: [UILabel] = []
    /// The sliding selected capsule. Constraint-linked to the selected chip
    /// so it is correct on the first layout pass and tracks scrolling and
    /// Dynamic Type.
    let indicator = UIView()
    private var indicatorConstraints: [NSLayoutConstraint] = []

    static let chipHeight: CGFloat = 36

    private(set) var selectedIndex: Int = 0

    init(titles: [String]) {
        super.init(frame: .zero)

        backgroundColor = .clear

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        indicator.backgroundColor = AnycastColor.goldAlpha7
        indicator.layer.borderWidth = Spacing.hairline
        indicator.layer.cornerRadius = Self.chipHeight / 2
        indicator.layer.cornerCurve = .continuous
        indicator.isUserInteractionEnabled = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        // In content space, below the chips: the capsule follows its chip
        // when the strip scrolls.
        scrollView.addSubview(indicator)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Spacing.md
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // titleSmall, capped so accessibility sizes stay inside the chip.
        let font = UIFontMetrics(forTextStyle: TypographyV2.titleSmall.scalingTextStyle).scaledFont(
            for: ThemeRegistry.current.typography.font(TypographyV2.titleSmall.size, TypographyV2.titleSmall.weight, .text),
            maximumPointSize: 20
        )
        for (index, title) in titles.enumerated() {
            let chip = UIView()
            chip.backgroundColor = AnycastColor.sandAlpha2
            chip.layer.cornerRadius = Self.chipHeight / 2
            chip.layer.cornerCurve = .continuous
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.tag = index
            chip.isAccessibilityElement = true
            chip.accessibilityTraits = [.button]
            chip.accessibilityLabel = title
            chip.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tabTapped(_:))))

            let label = UILabel()
            label.text = title
            label.font = font
            label.adjustsFontForContentSizeCategory = true
            label.textColor = Theme.onSurfaceVariant
            label.textAlignment = .center
            label.numberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(label)

            NSLayoutConstraint.activate([
                chip.heightAnchor.constraint(equalToConstant: Self.chipHeight),
                label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: Spacing.chip),
                label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -Spacing.chip),
                label.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            ])
            stackView.addArrangedSubview(chip)
            chips.append(chip)
            titleLabels.append(label)
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.pageH),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.pageH),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        applySelection(animated: false)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateStroke()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Programmatic selection (page changed by a swipe, 03 §3.5).
    func select(_ index: Int, animated: Bool) {
        guard chips.indices.contains(index) else { return }
        selectedIndex = index
        applySelection(animated: animated)
    }

    @objc private func tabTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, index != selectedIndex else {
            // Re-tapping the selected tab is a no-op here; callers that own
            // tap-to-refresh behavior do it at page level.
            return
        }
        selectedIndex = index
        UISelectionFeedbackGenerator().selectionChanged()
        applySelection(animated: true)
        onSelect?(index)
    }

    private func applySelection(animated: Bool) {
        for (index, label) in titleLabels.enumerated() {
            let isSelected = index == selectedIndex
            label.textColor = isSelected ? AnycastColor.sand1 : Theme.onSurfaceVariant
            chips[index].accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
        updateStroke()
        placeIndicator(animated: animated)
        if chips.indices.contains(selectedIndex),
           // Only overflowing strips need this, and the pre-layout init pass
           // has no meaningful frames yet.
           chips[selectedIndex].frame.width > 0,
           scrollView.contentSize.width > scrollView.bounds.width {
            scrollView.scrollRectToVisible(chips[selectedIndex].frame.insetBy(dx: -Spacing.pageH, dy: 0), animated: animated)
        }
    }

    /// The hairline runs through `layer.borderColor`, which freezes at
    /// assignment (09 §9a), so it is re-resolved on appearance changes.
    private func updateStroke() {
        indicator.layer.borderColor = AnycastColor.sandAlpha4.resolvedColor(with: traitCollection).cgColor
    }

    private func placeIndicator(animated: Bool) {
        guard chips.indices.contains(selectedIndex) else { return }
        let chip = chips[selectedIndex]
        NSLayoutConstraint.deactivate(indicatorConstraints)
        indicatorConstraints = [
            indicator.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
            indicator.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
            indicator.topAnchor.constraint(equalTo: chip.topAnchor),
            indicator.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
        ]
        NSLayoutConstraint.activate(indicatorConstraints)
        if animated {
            UIView.animate(
                withDuration: Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.layoutIfNeeded()
            }
        }
    }
}
