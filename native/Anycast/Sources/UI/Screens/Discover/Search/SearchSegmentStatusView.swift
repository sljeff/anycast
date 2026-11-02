import UIKit

/// The search segment's result sentence: an `EmptyStateView` with no icon
/// and no message, in a scroll view so an accessibility size can scroll.
/// The first load keeps the page's own spinner; this view stays hidden
/// until a sentence exists. The block is centered through xxxLarge and
/// top-aligned at accessibility sizes, and its bottom follows the keyboard.
@MainActor
final class SearchSegmentStatusView: UIView {

    var onAction: ((SearchResultAction) -> Void)?

    private let scrollView = UIScrollView()
    private let emptyState = EmptyStateView()
    private let actionButton = AnycastButton.make(.secondary, title: "Retry")
    private var heightConstraint: NSLayoutConstraint!
    private var applied: SearchResultPresentation?
    private var currentAction: SearchResultAction?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        accessibilityIdentifier = "search-result-status"

        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        emptyState.insetsLayoutMarginsFromSafeArea = false
        emptyState.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.pageH, leading: Spacing.pageH, bottom: Spacing.pageH, trailing: Spacing.pageH
        )
        emptyState.accessibilityTitleView().accessibilityIdentifier = "search-result-title"
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(emptyState)

        actionButton.accessibilityIdentifier = "search-result-action"
        actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        actionButton.setContentCompressionResistancePriority(.required, for: .vertical)
        actionButton.addAction(UIAction { [weak self] _ in
            guard let self, let action = self.currentAction, action != .focusSearchField else { return }
            self.onAction?(action)
        }, for: .touchUpInside)

        // A non-zero placeholder so the column's required margins are satisfiable
        // before the first layout pass measures the sentence.
        heightConstraint = emptyState.heightAnchor.constraint(equalToConstant: 800)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyState.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            emptyState.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            heightConstraint,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Pins the block to `host`, under `topInset` (the tab strip) and above
    /// the keyboard. Returns the top constraint so the page can track the inset.
    @discardableResult
    func install(in host: UIView, topInset: CGFloat) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        let top = topAnchor.constraint(equalTo: host.topAnchor, constant: topInset)
        NSLayoutConstraint.activate([
            top,
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bottomAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor),
        ])
        return top
    }

    var focusTarget: UIView { emptyState.accessibilityTitleView() }

    /// Applies the sentence for this segment, or hides when `phase` is still
    /// loading or has rows. Returns the presentation even when it did not
    /// change, so the caller can decide whether to announce it.
    @discardableResult
    func render(
        segment: SearchResultSegment,
        query: String,
        phase: SearchListPhase,
        otherPhase: SearchListPhase
    ) -> SearchResultPresentation? {
        let presentation = SearchResultState.presentation(
            segment: segment, phase: phase, otherPhase: otherPhase, query: query
        )
        guard presentation != applied else { return presentation }
        let wasShowing = applied != nil
        applied = presentation
        currentAction = presentation?.action
        if let presentation {
            let updates = { self.apply(presentation) }
            isHidden = false
            if wasShowing, window != nil, !Motion.reduceMotion {
                UIView.transition(
                    with: self, duration: Motion.quick,
                    options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                    animations: updates
                )
            } else {
                updates()
            }
        } else {
            isHidden = true
        }
        setNeedsLayout()
        return presentation
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = scrollView.bounds.width
        guard width > 1 else { return }
        let accessibilitySize = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        emptyState.setExpandsToReadableWidth(accessibilitySize)
        let content = emptyState.contentHeight(fittingWidth: width)
        let viewport = scrollView.bounds.height
        // Accessibility sizes always start at the top. A block that does not
        // fit (the keyboard is up, or the sentence wraps) also starts at the
        // top so the scroll view can reach every line.
        emptyState.setAlignsContentToTop(accessibilitySize || content > viewport + 1)
        let height = max(content, viewport)
        if abs(heightConstraint.constant - height) > 0.5 {
            heightConstraint.constant = height
        }
    }

    private func apply(_ presentation: SearchResultPresentation) {
        if let title = presentation.actionTitle {
            let image: UIImage? = presentation.action == .retry
                ? UIImage(systemName: "arrow.clockwise") : nil
            var configuration = AnycastButton.configuration(.secondary, title: title, image: image)
            configuration.titleLineBreakMode = .byWordWrapping
            actionButton.configuration = configuration
            actionButton.titleLabel?.numberOfLines = 0
            actionButton.titleLabel?.lineBreakMode = .byWordWrapping
            actionButton.titleLabel?.textAlignment = .center
            actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
            actionButton.accessibilityLabel = presentation.actionAccessibilityLabel
        }
        emptyState.configure(EmptyStateView.Content(
            icon: nil,
            title: presentation.title,
            message: nil,
            actions: presentation.actionTitle == nil ? [] : [actionButton],
            titleAccessibilityLabel: presentation.spokenTitle,
            titleIsHeader: true,
            wrapsTitleByCharacter: true
        ))
    }
}
