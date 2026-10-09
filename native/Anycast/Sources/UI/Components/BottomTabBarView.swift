import UIKit

/// Floating three destination bar. Its surface uses iOS 26 glass with an
/// iOS 18 material fallback, matching the shared Anycast control language.
@MainActor
final class BottomTabBarView: UIView {

    struct Item {
        let title: String
        let icon: UIImage
    }

    static let pillHeight: CGFloat = 72
    static let horizontalInset: CGFloat = 16
    static let bottomGutter: CGFloat = 12

    var onTabTap: ((Int, Bool) -> Void)?

    private let items: [Item]
    private let pill = GlassContainerView(mode: .plain, cornerRadius: pillHeight / 2)
    private var chips: [UIView] = []
    private var buttons: [UIButton] = []
    private var selectedIndex = 0

    /// The tab chip centers are used by playlist fly-in animations.
    var pillButtons: [UIButton] { buttons }
    var selectedTabIndex: Int { selectedIndex }

    init(items: [Item]) {
        precondition(items.count == 3, "The bottom bar has three primary destinations")
        self.items = items
        super.init(frame: .zero)

        backgroundColor = .clear

        let gradient = GradientFadeView()
        gradient.isUserInteractionEnabled = false
        gradient.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradient)

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.08
        pill.layer.shadowOffset = CGSize(width: 0, height: 8)
        pill.layer.shadowRadius = 16
        addSubview(pill)

        for (index, item) in items.enumerated() {
            let chip = UIView()
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.layer.cornerRadius = (Self.pillHeight - 8) / 2
            chip.layer.cornerCurve = .continuous

            var config = UIButton.Configuration.plain()
            config.image = item.icon.withRenderingMode(.alwaysTemplate)
            config.imagePlacement = .top
            config.imagePadding = 4
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22)
            config.background = .clear()
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
                    for: .systemFont(ofSize: 12, weight: .medium)
                )
                return outgoing
            }

            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(item.title.uppercased(), for: .normal)
            button.tintColor = Theme.onSurfaceVariant
            button.accessibilityIdentifier = "tab-\(index)"
            button.accessibilityLabel = item.title
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            chip.addSubview(button)
            pill.glassContentView.addSubview(chip)
            chips.append(chip)
            buttons.append(button)
        }

        var constraints: [NSLayoutConstraint] = [
            gradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradient.topAnchor.constraint(equalTo: topAnchor),
            gradient.bottomAnchor.constraint(equalTo: bottomAnchor),

            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            pill.heightAnchor.constraint(equalToConstant: Self.pillHeight),
            pill.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Self.bottomGutter),
        ]

        for (index, chip) in chips.enumerated() {
            let button = buttons[index]
            constraints += [
                chip.topAnchor.constraint(equalTo: pill.glassContentView.topAnchor, constant: 4),
                chip.bottomAnchor.constraint(equalTo: pill.glassContentView.bottomAnchor, constant: -4),
                button.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
                button.topAnchor.constraint(equalTo: chip.topAnchor),
                button.bottomAnchor.constraint(equalTo: chip.bottomAnchor),
            ]
            if index == 0 {
                constraints.append(chip.leadingAnchor.constraint(equalTo: pill.glassContentView.leadingAnchor, constant: 4))
            } else {
                constraints.append(chip.leadingAnchor.constraint(equalTo: chips[index - 1].trailingAnchor))
                constraints.append(chip.widthAnchor.constraint(equalTo: chips[0].widthAnchor))
            }
            if index == chips.count - 1 {
                constraints.append(chip.trailingAnchor.constraint(equalTo: pill.glassContentView.trailingAnchor, constant: -4))
            }
        }
        NSLayoutConstraint.activate(constraints)
        applySelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The scrim is decorative; only the bar accepts touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event), view !== self else { return nil }
        return view
    }

    func select(_ index: Int, animated: Bool) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        if animated {
            UIView.animate(withDuration: Motion.quick) { self.applySelection() }
        } else {
            applySelection()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            applySelection()
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        let isRetap = index == selectedIndex
        selectedIndex = index
        UIView.animate(withDuration: Motion.quick) { self.applySelection() }
        onTabTap?(index, isRetap)
    }

    private func applySelection() {
        for (index, chip) in chips.enumerated() {
            let isActive = index == selectedIndex
            chip.backgroundColor = isActive ? Theme.primaryContainer : .clear
            chip.layer.borderColor = isActive
                ? Theme.outlineVariant.resolvedColor(with: traitCollection).cgColor
                : UIColor.clear.cgColor
            chip.layer.borderWidth = isActive ? 0.5 : 0
            buttons[index].tintColor = isActive ? Theme.primary : Theme.onSurfaceVariant
            if isActive {
                buttons[index].accessibilityTraits.insert(.selected)
            } else {
                buttons[index].accessibilityTraits.remove(.selected)
            }
        }
    }
}

/// Clear-to-surface fade behind the floating bar.
@MainActor
final class GradientFadeView: UIView {
    override public static var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGradient()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            configureGradient()
        }
    }

    private func configureGradient() {
        let gradient = layer as! CAGradientLayer
        gradient.colors = [UIColor.clear.cgColor, Theme.surface.resolvedColor(with: traitCollection).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.locations = [0, 0.845]
    }
}
