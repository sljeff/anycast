import UIKit
import Kingfisher
import AnycastKit

/// The pure rules of the Podcast tab's shows shelf: how many covers fit in
/// one row, and in which order the subscriptions appear.
nonisolated enum ShowsShelfLayout {

    /// Posted when subscriptions were written outside the Inbox (import,
    /// Channel subscribe / unsubscribe, the refresh batch) so the shelf and
    /// the category strip reload.
    static let subscriptionsDidChange = Notification.Name("AnycastSubscriptionsDidChange")

    /// Side of a cover and of the "All shows" button.
    static let itemSide: CGFloat = 56
    static let itemGap: CGFloat = Spacing.gap

    /// How many items (covers plus the trailing "All shows" button) one row
    /// holds between the 16 pt page insets. The row never scrolls or wraps,
    /// so the button always counts and at least it is shown.
    static func itemCapacity(width: CGFloat) -> Int {
        let available = width - 2 * Spacing.pageH
        let fitting = Int(((available + itemGap) / (itemSide + itemGap)).rounded(.down))
        return max(fitting, 1)
    }

    /// How many covers show: all of them when they fit, otherwise whatever
    /// room the button leaves.
    static func coverCount(width: CGFloat, showCount: Int) -> Int {
        min(showCount, itemCapacity(width: width) - 1)
    }

    /// Most recently updated first (`lastUpdated` descending, never-updated
    /// last); ties keep the stored order.
    static func ordered(_ rows: [SubscriptionRow]) -> [SubscriptionRow] {
        rows.enumerated().sorted { lhs, rhs in
            switch (lhs.element.lastUpdated, rhs.element.lastUpdated) {
            case let (left?, right?) where left != right: return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

/// One row of subscribed show covers (56 pt rounded squares, 12 pt apart,
/// leading at the page inset) ending in the "All shows" button. It fits as
/// many covers as the width allows; it never scrolls and never wraps.
@MainActor
final class ShowsShelfView: UIView {

    /// A cover was tapped.
    var onSelect: ((SubscriptionRow) -> Void)?
    /// The "All shows" button was tapped.
    var onAllShows: (() -> Void)?

    private let stack = UIStackView()
    private let allShowsButton = AnycastIconButton(
        style: .tonal,
        icon: AppIcons.subscriptions,
        accessibilityLabel: "All shows",
        diameter: ShowsShelfLayout.itemSide,
        glyphSize: 17
    )
    private var coverButtons: [ShowShelfCoverButton] = []
    private var shows: [SubscriptionRow] = []
    /// Covers currently visible, for tests and VoiceOver.
    private(set) var visibleCoverCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = ShowsShelfLayout.itemGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        allShowsButton.accessibilityIdentifier = "shows-shelf-all"
        allShowsButton.addAction(UIAction { [weak self] _ in self?.onAllShows?() }, for: .touchUpInside)
        stack.addArrangedSubview(allShowsButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.pageH),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: ShowsShelfLayout.itemSide),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Replaces the shown subscriptions (already in display order).
    func configure(shows: [SubscriptionRow]) {
        self.shows = shows
        applyCovers()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        applyCovers()
        super.layoutSubviews()
    }

    /// Dynamic Type does not resize the 56 pt items, but the row is
    /// recomputed from the current width on every layout pass, so width and
    /// size-category changes both land here.
    private func applyCovers() {
        let count = ShowsShelfLayout.coverCount(width: bounds.width, showCount: shows.count)
        while coverButtons.count < count {
            let button = ShowShelfCoverButton()
            let index = coverButtons.count
            button.accessibilityIdentifier = "shows-shelf-cover-\(index)"
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button, let show = button.show else { return }
                self.onSelect?(show)
            }, for: .touchUpInside)
            coverButtons.append(button)
            stack.insertArrangedSubview(button, at: index)
        }
        for (index, button) in coverButtons.enumerated() {
            if index < count {
                button.show = shows[index]
                button.isHidden = false
            } else {
                button.show = nil
                button.isHidden = true
            }
        }
        visibleCoverCount = count
    }
}

/// A show cover on the shelf: the shared artwork treatment (rounded square,
/// show-initial placeholder, hairline), no shadow.
@MainActor
private final class ShowShelfCoverButton: UIControl {

    private let coverView = UIImageView()
    private var shownKey: String?

    var show: SubscriptionRow? {
        didSet {
            let key = show.map { "\($0.rssFeedUrl ?? "")|\($0.imageUrl ?? "")|\($0.title ?? "")" }
            guard key != shownKey else { return }
            shownKey = key
            coverView.kf.cancelDownloadTask()
            if let show {
                coverView.setArtwork(show.imageUrl.flatMap(URL.init(string:)), title: show.title)
                accessibilityLabel = show.title
            } else {
                coverView.image = nil
                accessibilityLabel = nil
            }
        }
    }

    init() {
        super.init(frame: .zero)
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = Radius.md
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.surfaceContainerHigh
        coverView.isUserInteractionEnabled = false
        coverView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coverView)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverView.topAnchor.constraint(equalTo: topAnchor),
            coverView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: ShowsShelfLayout.itemSide),
            heightAnchor.constraint(equalToConstant: ShowsShelfLayout.itemSide),
        ])
        isAccessibilityElement = true
        accessibilityTraits = [.button]
        addPressFeedback(scale: Motion.pressScaleSubtle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
