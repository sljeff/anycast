import UIKit

/// The thin-underline secondary tab strip (self-drawn widget #6,
/// docs/migration/07 §3): selected title in white at 24pt with a 48×4
/// rounded white indicator beneath it, unselected titles 0x6B7280
/// (03 §2.7 OrderChooser). Used by Inbox/Subscriptions, Discover categories
/// (`isScrollable`), SearchPage tabs, and Channel Newest/Oldest.
///
/// Interaction notes (03 §2.1/§3.5): the strip mirrors a TabBar — selection
/// changes animate the indicator, and horizontal scrolling is opt-in for
/// Discover (many categories); the two- and four-item variants fit without
/// scrolling.
final class UnderlineTabBarView: UIView {

    /// Informed on user tap; the caller updates its page content.
    var onSelect: ((Int) -> Void)?

    let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var titleLabels: [UILabel] = []
    /// The selected-category underline (test-visible: the regression suite
    /// asserts its first-layout position against the selected label).
    let indicator = UIView()
    /// centerX link to the selected label — constraint-driven so the
    /// indicator is correct on the FIRST layout pass (a manual frame calc
    /// ran before the stack had positioned its labels, parking the
    /// indicator at the strip's left edge until the first selection) and
    /// tracks the label through scrolls, rotations, and Dynamic Type.
    private var indicatorCenterX: NSLayoutConstraint?

    private var selectedFont: UIFont
    private var unselectedFont: UIFont
    private let indicatorSize = CGSize(width: 48, height: 4)

    private(set) var selectedIndex: Int = 0

    /// - Parameters:
    ///   - titles: tab titles in order.
    ///   - selectedFont: defaults to 24pt comfortaa (03 §2.7).
    ///   - unselectedFont: defaults to the same size as selected.
    init(
        titles: [String],
        selectedFont: UIFont? = nil,
        unselectedFont: UIFont? = nil
    ) {
        // Fixed-size display control: 24pt titles do not scale with Dynamic
        // Type without overflowing the 44pt strip height; scaling is applied
        // by callers that pass their own fonts.
        self.selectedFont = selectedFont
            ?? UIFont(name: "Comfortaa-Regular", size: 24)
            ?? UIFont.systemFont(ofSize: 24)
        self.unselectedFont = unselectedFont ?? self.selectedFont

        super.init(frame: .zero)

        backgroundColor = .clear

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 24
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        indicator.backgroundColor = Theme.primaryLightMax
        indicator.layer.cornerRadius = indicatorSize.height / 2
        indicator.isUserInteractionEnabled = false
        // Constrained subview of the scroll view — without this the
        // autoresizing-generated constraints fight the explicit
        // width/height/centerX/bottom set (in an unhosted render the view
        // stays at a zero frame).
        indicator.translatesAutoresizingMaskIntoConstraints = false
        // Inside the scroll view (content space, above the stack): the
        // indicator follows the selected label when the strip scrolls —
        // an indicator in tab-bar space would stay put as labels move
        // under it. All of its constraints stay in content space.
        scrollView.addSubview(indicator)

        for (index, title) in titles.enumerated() {
            let label = UILabel()
            label.text = title
            label.font = unselectedFont
            label.textColor = Theme.secondaryLabelGray
            label.textAlignment = .center
            label.numberOfLines = 1
            label.adjustsFontForContentSizeCategory = false
            label.isAccessibilityElement = true
            label.accessibilityTraits = [.button]
            label.accessibilityLabel = title
            stackView.addArrangedSubview(label)
            titleLabels.append(label)

            let tap = UITapGestureRecognizer(target: self, action: #selector(tabTapped(_:)))
            label.addGestureRecognizer(tap)
            label.tag = index
            label.isUserInteractionEnabled = true
        }

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            indicator.widthAnchor.constraint(equalToConstant: indicatorSize.width),
            indicator.heightAnchor.constraint(equalToConstant: indicatorSize.height),
            // Bottom in CONTENT space (stack bottom == strip bottom — the
            // strip never scrolls vertically). A frameLayoutGuide pin
            // crosses into the scroll view's bounds/inset machinery,
            // which does not settle deterministically outside a window
            // (the specimen harness renders unhosted views and got a
            // degenerate indicator frame).
            indicator.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
        ])

        applySelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Programmatic selection (page changed by a swipe, 03 §3.5).
    func select(_ index: Int, animated: Bool) {
        guard titleLabels.indices.contains(index) else { return }
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
        applySelection(animated: true)
        onSelect?(index)
    }

    private func applySelection(animated: Bool) {
        for (index, label) in titleLabels.enumerated() {
            let isSelected = index == selectedIndex
            label.font = isSelected ? selectedFont : unselectedFont
            label.textColor = isSelected ? Theme.primaryLightMax : Theme.secondaryLabelGray
            label.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        }
        placeIndicator(animated: animated)
        if let label = titleLabels.indices.contains(selectedIndex) ? titleLabels[selectedIndex] : nil,
           label.frame.width > 0,
           // Only scrollable strips (Discover's categories) need this, and
           // the pre-layout init pass has no meaningful frames yet — calling
           // it there would scroll against a degenerate content size.
           scrollView.contentSize.width > scrollView.bounds.width {
            // Keep the selected tab fully visible when scrolling is
            // enabled — in BOTH branches: a non-animated programmatic
            // select must scroll into view too, it just does so without
            // animation.
            scrollView.scrollRectToVisible(label.frame.insetBy(dx: -16, dy: 0), animated: animated)
        }
    }

    private func placeIndicator(animated: Bool) {
        guard titleLabels.indices.contains(selectedIndex) else { return }
        let label = titleLabels[selectedIndex]
        indicatorCenterX?.isActive = false
        let center = indicator.centerXAnchor.constraint(equalTo: label.centerXAnchor)
        indicatorCenterX = center
        center.isActive = true
        if animated {
            UIView.animate(
                withDuration: 0.2, delay: 0, options: [.curveEaseInOut]
            ) {
                self.layoutIfNeeded()
            }
        }
    }
}
