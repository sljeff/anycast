import UIKit

/// The two destinations inside the Podcast tab.
@MainActor
final class PodcastSectionBar: UIView {

    var onSelect: ((Int) -> Void)?
    private let items: [(title: String, icon: UIImage)] = [
        ("Inbox", AppIcons.inbox),
        ("Subscriptions", AppIcons.subscriptions),
    ]
    private let selectedSurface = UIView()
    private var buttons: [UIButton] = []
    private(set) var selectedIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.surfaceContainer
        layer.cornerRadius = Radius.pill
        layer.cornerCurve = .continuous

        selectedSurface.backgroundColor = Theme.surface
        selectedSurface.layer.borderColor = Theme.outlineVariant.cgColor
        selectedSurface.layer.borderWidth = 0.5
        selectedSurface.layer.cornerRadius = Radius.pill
        selectedSurface.layer.cornerCurve = .continuous
        selectedSurface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectedSurface)

        for (index, item) in items.enumerated() {
            var configuration = UIButton.Configuration.plain()
            configuration.title = item.title
            configuration.image = item.icon.withRenderingMode(.alwaysTemplate)
            configuration.imagePlacement = .top
            configuration.imagePadding = 1
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16)
            configuration.baseForegroundColor = Theme.onSurfaceVariant
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: .systemFont(ofSize: 12, weight: .semibold)
                )
                return outgoing
            }
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)

            let button = UIButton(configuration: configuration)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityIdentifier = "podcast-section-\(index)"
            button.accessibilityLabel = item.title
            button.addAction(UIAction { [weak self] _ in self?.select(index, animated: true, notify: true) }, for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }

        var constraints: [NSLayoutConstraint] = [
            selectedSurface.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            selectedSurface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            selectedSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            selectedSurface.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5, constant: -6),
        ]
        for (index, button) in buttons.enumerated() {
            constraints += [
                button.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
                button.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5, constant: -6),
            ]
            if index == 0 {
                constraints.append(button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4))
            } else {
                constraints.append(button.leadingAnchor.constraint(equalTo: buttons[index - 1].trailingAnchor, constant: 4))
                constraints.append(button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4))
            }
        }
        NSLayoutConstraint.activate(constraints)
        updateAppearance()
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            updateAppearance()
        }
    }

    func select(_ index: Int, animated: Bool, notify: Bool = false) {
        guard items.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        if animated {
            UIView.animate(withDuration: Motion.quick) { self.applySelection() }
        } else {
            applySelection()
        }
        if notify { onSelect?(index) }
    }

    private func applySelection() {
        selectedSurface.transform = CGAffineTransform(
            translationX: selectedIndex == 0 ? 0 : bounds.width / 2 - 2,
            y: 0
        )
        for (index, button) in buttons.enumerated() {
            button.configuration?.baseForegroundColor = index == selectedIndex ? Theme.primary : Theme.onSurfaceVariant
            button.accessibilityTraits = index == selectedIndex ? [.button, .selected] : [.button]
        }
    }

    private func updateAppearance() {
        selectedSurface.layer.borderColor = Theme.outlineVariant
            .resolvedColor(with: traitCollection).cgColor
    }
}
