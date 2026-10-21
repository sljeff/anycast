import UIKit

/// The secondary tab strip in the Anycast 2.0 UI kit strip language (same
/// as `CategoryStripView`): text chips whose selection reads through the
/// title ink plus a small rounded underline tracking the selected title —
/// the selected chip in full ink with the indicator beneath it, the rest
/// at `sandAlpha8`, cross-faded on change. When the chips fit the strip's
/// width they spread evenly across it (SearchPage tabs, Channel
/// Newest/Oldest); when they overflow, the strip scrolls horizontally
/// (Discover's many categories).
///
/// Interaction notes (03 §2.1/§3.5): the strip mirrors a TabBar — selection
/// changes animate, and the strip scrolls horizontally when its chips
/// overflow (Discover's many categories).
final class ChipTabBarView: UIView {

    /// Informed on user tap; the caller updates its page content.
    var onSelect: ((Int) -> Void)?

    let scrollView = UIScrollView()
    private let stackView = UIStackView()
    /// The selected-title underline (the deleted v1 underline strip's language).
    private let indicator = UIView()
    private var chips: [UIView] = []
    private var titleLabels: [UILabel] = []
    /// centerX link to the selected label — constraint-driven so the
    /// indicator is correct on the FIRST layout pass (a manual frame calc
    /// runs before the stack has positioned its labels) and tracks the
    /// label through scrolls, rotations, and Dynamic Type.
    private var indicatorCenterX: NSLayoutConstraint?

    static let chipHeight: CGFloat = 44

    /// 24×3 rounded bar under the selected title.
    private static let indicatorSize = CGSize(width: 24, height: 3)

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
        // Plain .fill: the equal-width chain below (added after the chips
        // are built) splits the strip into equal segments when it fits, so
        // each title centers in its own fraction of the width — the classic
        // tab-bar rhythm — instead of two titles drifting to the far edges
        // with a dead middle.
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        indicator.backgroundColor = Theme.primary
        indicator.layer.cornerRadius = Self.indicatorSize.height / 2
        indicator.isUserInteractionEnabled = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        // Inside the scroll view (content space, above the stack): the
        // indicator follows the selected label when the strip scrolls —
        // an indicator in strip space would stay put as labels move under
        // it. All of its constraints stay in content space.
        scrollView.addSubview(indicator)

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

        // Equal segments when the chips fit: chained at 749, just below the
        // labels' 750 compression resistance. A fitting strip holds the
        // fill constraint below, and this chain splits the width into equal
        // fractions (each title centers in its own — Channels/Episodes sit
        // at the quarter points, not glued to the edges). An overflowing
        // strip keeps natural chip widths (label compression wins, the
        // chain breaks) and scrolls.
        for chip in chips.dropFirst() {
            let equalWidth = chip.widthAnchor.constraint(equalTo: chips[0].widthAnchor)
            equalWidth.priority = UILayoutPriority(749)
            equalWidth.isActive = true
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Content-guide pins use symmetric page margins: the chips
            // distribute over [pageH, width - pageH] instead of hugging the
            // screen edges. The fill constraint below carries the MATCHING
            // -2*pageH constant, so a fitting strip still has contentSize
            // EXACTLY equal to the viewport — it never scrolls, never clips
            // the trailing chip, and never jogs horizontally on selection
            // (a content wider than the viewport with nothing to scroll to).
            stackView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.pageH
            ),
            stackView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.pageH
            ),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            indicator.widthAnchor.constraint(equalToConstant: Self.indicatorSize.width),
            indicator.heightAnchor.constraint(equalToConstant: Self.indicatorSize.height),
            // Bottom in CONTENT space (stack bottom == strip bottom — the
            // strip never scrolls vertically).
            indicator.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
        ])

        // Segment fill when the chips fit: the fill sits just below the
        // labels' compression resistance (750), so it holds whenever the
        // chips fit (the equal-width chain above then splits it evenly)
        // and yields for an overflowing strip (Discover) — which then
        // keeps its natural content width and scrolls instead of
        // truncating chips. The -2*pageH constant mirrors the
        // content-guide pins above.
        let fillWidth = stackView.widthAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.widthAnchor,
            constant: -2 * Spacing.pageH
        )
        fillWidth.priority = UILayoutPriority(749)
        fillWidth.isActive = true

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
        placeIndicator(animated: animated)
        if chips.indices.contains(selectedIndex),
           // Only overflowing strips need this, and the pre-layout init pass
           // has no meaningful frames yet.
           chips[selectedIndex].frame.width > 0,
           scrollView.contentSize.width > scrollView.bounds.width {
            scrollView.scrollRectToVisible(chips[selectedIndex].frame.insetBy(dx: -Spacing.pageH, dy: 0), animated: animated)
        }
    }

    /// Slides the underline under the selected label — a constraint swap
    /// (0.2s TabBar-style slide, indicator-follows-label move), so position
    /// stays Auto Layout-driven on first layout and through Dynamic Type.
    private func placeIndicator(animated: Bool) {
        guard titleLabels.indices.contains(selectedIndex) else { return }
        let label = titleLabels[selectedIndex]
        indicatorCenterX?.isActive = false
        let center = indicator.centerXAnchor.constraint(equalTo: label.centerXAnchor)
        indicatorCenterX = center
        center.isActive = true
        if animated, !Motion.reduceMotion {
            UIView.animate(
                withDuration: 0.2, delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction]
            ) {
                self.layoutIfNeeded()
            }
        }
    }
}
