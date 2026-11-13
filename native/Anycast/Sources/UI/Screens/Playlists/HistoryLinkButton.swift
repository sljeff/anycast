import UIKit
import AnycastKit

/// The weak "Listening history" link at the bottom of an empty Inbox or an
/// empty Playlist. Shared so both pages look and behave the same. It is
/// shown only when History has rows, so a fresh install never offers an
/// empty sheet.
final class HistoryLinkButton: UIButton {

    private(set) var historyCount = 0
    /// True while the page behind it is in its empty state.
    private var pageIsEmpty = false
    private var refreshGeneration = 0

    init(accessibilityIdentifier identifier: String) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Listening history"
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            outgoing.foregroundColor = Theme.onSurfaceVariant
            outgoing.underlineStyle = .single
            return outgoing
        }
        self.configuration = configuration
        titleLabel?.adjustsFontForContentSizeCategory = true
        titleLabel?.textAlignment = .center
        accessibilityLabel = "Listening history"
        accessibilityIdentifier = identifier
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Adds the link to `view`, centred, 24 above the safe-area bottom.
    func install(in view: UIView) {
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Spacing.pageH),
            trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Spacing.pageH),
            bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Spacing.pageHeader),
            heightAnchor.constraint(greaterThanOrEqualToConstant: IconMetrics.minimumHit),
        ])
        view.bringSubviewToFront(self)
    }

    /// Call whenever the page renders its empty (or non-empty) state: the
    /// link follows the last known count at once, then re-reads it.
    func refresh(pageIsEmpty: Bool, database: AppDatabase) {
        self.pageIsEmpty = pageIsEmpty
        applyVisibility()
        guard pageIsEmpty else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        Task { [weak self] in
            let count = (try? await database.historyRepository().count()) ?? 0
            guard let self, generation == self.refreshGeneration else { return }
            self.historyCount = count
            self.applyVisibility()
        }
    }

    private func applyVisibility() {
        isHidden = !(pageIsEmpty && historyCount > 0)
    }
}
