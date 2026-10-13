import UIKit

/// The secondary tab strip in the Anycast 2.0 UI kit strip language (same
/// as `CategoryStripView`): text chips whose selection reads through
/// brightness alone — the selected title in full ink, the rest at
/// `sandAlpha8`, cross-faded on change. Used by Discover categories
/// (scrolls), SearchPage tabs, and Channel Newest/Oldest.
///
/// Interaction notes (03 §2.1/§3.5): the strip mirrors a TabBar — selection
/// changes animate, and the strip scrolls horizontally when its chips
/// overflow (Discover's many categories).
final class ChipTabBarView: UIView {

    /// Informed on user tap; the caller updates its page content.
    var onSelect: ((Int) -> Void)?

    let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var chips: [UIView] = []
    private var titleLabels: [UILabel] = []

    static let chipHeight: CGFloat = 44

    private(set) var selectedIndex: Int = 0

    init(titles: [String]) {
        super.init(frame: .zero)

        backgroundColor = .clear

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        // titleMedium, capped so accessibility sizes stay inside the chip.
        let font = UIFontMetrics(forTextStyle: TypographyV2.titleMedium.scalingTextStyle).scaledFont(
            for: ThemeRegistry.current.typography.font(TypographyV2.titleMedium.size, TypographyV2.titleMedium.weight, .text),
            maximumPointSize: 22
        )
        for (index, title) in titles.enumerated() {
            let chip = UIView()
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
                label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: Spacing.gap),
                label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -Spacing.gap),
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

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.xs),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.xs),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        applySelection(animated: false)
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
        Haptics.selection()
        applySelection(animated: true)
        onSelect?(index)
    }

    private func applySelection(animated: Bool) {
        let apply = {
            for (index, label) in self.titleLabels.enumerated() {
                let isSelected = index == self.selectedIndex
                label.textColor = isSelected ? Theme.onSurface : AnycastColor.sandAlpha8
                self.chips[index].accessibilityTraits = isSelected ? [.button, .selected] : [.button]
            }
        }
        if animated, !Motion.reduceMotion {
            UIView.transition(
                with: stackView, duration: Motion.quick,
                options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                animations: apply
            )
        } else {
            apply()
        }
        if chips.indices.contains(selectedIndex),
           // Only overflowing strips need this, and the pre-layout init pass
           // has no meaningful frames yet.
           chips[selectedIndex].frame.width > 0,
           scrollView.contentSize.width > scrollView.bounds.width {
            scrollView.scrollRectToVisible(chips[selectedIndex].frame.insetBy(dx: -Spacing.pageH, dy: 0), animated: animated)
        }
    }
}
