import UIKit

/// The v2 floating pill tab bar (Figma `Buttom Tab` component set 243:7288,
/// docs/migration/09 §3.1): a bottom scrim (surface gradient) hosting
/// a translucent capsule with the three tab chips (Inbox / queue / library)
/// and a separate 72 pt circular glass search button.
///
/// The bar is a STATIC-light surface, like the player chrome (09 §9a): the
/// component's pill fill is the literal `rgba(255,255,255,.8)` — no dark
/// variable — and the dark design frame (76:2614 render) confirms the pill
/// stays white in dark mode (measured 219). Every chip token is therefore
/// pinned to its LIGHT variant (dark-variant inks would vanish on the
/// white pill). Selection styling: the active chip gets `goldAlpha2` fill +
/// `sandAlpha4` hairline + pill radius, icon/label in `goldAlpha9`;
/// inactive chips are clear with `sandAlpha10` content.
@MainActor
final class BottomTabBarView: UIView {

    /// The pinned appearance for every chip/pill color (see class docs).
    private static let lightTraits = UITraitCollection(userInterfaceStyle: .light)

    /// A light-variant token, frozen like the player's static tokens.
    private static func light(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: lightTraits)
    }

    struct Item {
        let title: String
        let icon: UIImage
    }

    /// Pill height incl. its 4 pt inner padding (chip body 64).
    static let pillHeight: CGFloat = 72
    /// The circular glass search button.
    static let searchButtonSize: CGFloat = 72
    /// Horizontal page inset on both sides of the pill + search group.
    static let horizontalInset: CGFloat = 16
    /// Gap between the pill and the search button.
    static let groupGap: CGFloat = 12
    /// Clearance between the pill bottom and the bottom safe-area edge
    /// (the home indicator zone). The Figma clone (1202:23125) keeps the
    /// pill ~28 pt clear of the indicator; anchoring to the safe area
    /// instead of the physical bottom keeps that gap on every device.
    /// Safe for pre-indicator devices: the inset collapses to 0 there.
    static let bottomGutter: CGFloat = 12
    /// Total chip width as a fraction of the pill width — each chip gets a
    /// third. Figma chips are fixed 100 in a 363/364 pt pill (component
    /// 243:7288 + clone 1202:23125) with `space-between` distribution —
    /// proportions, not absolute widths, carry over to a 402 pt screen.
    /// Equal widths + first/last pinned + middle centered reproduces
    /// space-between with equal gaps (~79 pt chips, ~21 pt gaps on 402).
    static let chipWidthRatio: CGFloat = 300.0 / 363.0

    /// Tab tap: index + whether the ALREADY-selected tab was tapped again
    /// (the scroll/refresh signal — TabZeroRetap semantics move to the pill).
    var onTabTap: ((Int, Bool) -> Void)?
    var onSearchTap: (() -> Void)?

    private let items: [Item]
    private var chips: [UIView] = []
    private var buttons: [UIButton] = []
    private(set) var searchButton: UIButton
    private var selectedIndex = 0

    /// The tab chips in order — the fly-in endpoint provider reads their
    /// centers instead of the retired UITabBar buttons.
    var pillButtons: [UIButton] { buttons }

    init(items: [Item]) {
        precondition(items.count == 3, "v2 shell is a 3-tab pill")
        self.items = items
        self.searchButton = UIButton(type: .system)
        super.init(frame: .zero)

        backgroundColor = .clear

        // Bottom scrim: the clear→surface gradient tint (Figma: the scrim
        // root is that gradient + backdrop blur 10). The blur is dropped:
        // UIVisualEffectView renders as a full-width rectangle with a hard
        // top edge (the "rigid box" over content), fading one via an
        // ancestor mask silently disables the effect entirely, and nothing
        // scrolls under the band while the content-avoidance semantics
        // stand (09 §10 patch-round note ⑥). Revisit with a real edge fade
        // when that decision lands.
        let gradient = GradientFadeView()
        gradient.isUserInteractionEnabled = false

        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        // The component's fill is the literal rgba(255,255,255,.8) — static,
        // no dark variable; the dark frame (76:2614) renders it white too
        // (measured 219 over the dark scrim). The earlier surfaceContainerHigh
        // port was measured from a polluted screenshot and read too dark.
        pill.backgroundColor = UIColor(white: 1, alpha: 0.8)
        // The Figma capsule (243:7288 pill frame): fill + shadow + pill
        // radius — no stroke, no hard rectangle. The radius went missing in
        // the first v2 build and the bar rendered as a rigid box.
        pill.layer.cornerRadius = Self.pillHeight / 2
        pill.layer.cornerCurve = .continuous
        pill.layer.shadowColor = UIColor.black.cgColor
        pill.layer.shadowOpacity = 0.1
        pill.layer.shadowOffset = CGSize(width: 0, height: 20)
        pill.layer.shadowRadius = 40 / 2

        for (index, item) in items.enumerated() {
            let chip = UIView()
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.layer.cornerRadius = (Self.pillHeight - 8) / 2
            chip.layer.cornerCurve = .continuous
            pill.addSubview(chip)

            var config = UIButton.Configuration.plain()
            config.image = item.icon.withRenderingMode(.alwaysTemplate)
            config.imagePlacement = .top
            config.imagePadding = 4
            // Figma Button component 240:7235/7243: Material Symbols 24 over
            // SF Pro 12 Regular, gap 4, TITLE case.
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: 24
            )
            // Kill any system-injected background (iOS 26 glass pills behind
            // the label) — the chip capsule is the only surface.
            config.background = .clear()
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 12, weight: .regular)
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = Self.light(AnycastColor.sandAlpha10)
            button.setTitle(item.title.uppercased(), for: .normal)
            button.accessibilityIdentifier = "tab-\(index)"
            button.accessibilityLabel = item.title
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            chip.addSubview(button)
            chips.append(chip)
            buttons.append(button)
        }

        // The search control is the sanctioned Liquid Glass surface (09 §3.1):
        // real glass on iOS 26, chrome-material blur on iOS 18.
        let searchGlass = GlassContainerView(mode: .plain, cornerRadius: Self.searchButtonSize / 2)
        searchGlass.translatesAutoresizingMaskIntoConstraints = false
        searchGlass.layer.shadowColor = UIColor.black.cgColor
        searchGlass.layer.shadowOpacity = 0.1
        searchGlass.layer.shadowOffset = CGSize(width: 0, height: 30)
        searchGlass.layer.shadowRadius = 15

        var searchConfig = UIButton.Configuration.plain()
        searchConfig.image = AppIcons.search
        searchConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        searchButton.configuration = searchConfig
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        // Dark ink on the light glass surface (the Inbox-variant frame paints
        // the glyph #000000; sandAlpha10 keeps it in the token family).
        searchButton.tintColor = Self.light(AnycastColor.sandAlpha10)
        searchButton.accessibilityIdentifier = "tab-search"
        searchButton.accessibilityLabel = "search"
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)

        gradient.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradient)
        addSubview(pill)
        addSubview(searchGlass)
        searchGlass.glassContentView.addSubview(searchButton)

        var constraints: [NSLayoutConstraint] = [
            gradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradient.topAnchor.constraint(equalTo: topAnchor),
            gradient.bottomAnchor.constraint(equalTo: bottomAnchor),

            pill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            pill.heightAnchor.constraint(equalToConstant: Self.pillHeight),
            pill.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Self.bottomGutter
            ),
            searchGlass.leadingAnchor.constraint(equalTo: pill.trailingAnchor, constant: Self.groupGap),
            searchGlass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            searchGlass.widthAnchor.constraint(equalToConstant: Self.searchButtonSize),
            searchGlass.heightAnchor.constraint(equalToConstant: Self.searchButtonSize),
            searchGlass.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Self.bottomGutter
            ),
            searchButton.centerXAnchor.constraint(equalTo: searchGlass.centerXAnchor),
            searchButton.centerYAnchor.constraint(equalTo: searchGlass.centerYAnchor),
        ]
        for (index, chip) in chips.enumerated() {
            constraints.append(chip.heightAnchor.constraint(equalToConstant: Self.pillHeight - 8))
            constraints.append(chip.centerYAnchor.constraint(equalTo: pill.centerYAnchor))
            constraints.append(buttons[index].widthAnchor.constraint(equalTo: chip.widthAnchor))
            constraints.append(buttons[index].heightAnchor.constraint(equalTo: chip.heightAnchor))
            constraints.append(buttons[index].centerXAnchor.constraint(equalTo: chip.centerXAnchor))
            constraints.append(buttons[index].centerYAnchor.constraint(equalTo: chip.centerYAnchor))
            constraints.append(chip.widthAnchor.constraint(
                equalTo: pill.widthAnchor, multiplier: Self.chipWidthRatio / 3
            ))
            if index == 0 {
                constraints.append(chip.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 4))
            } else if index == chips.count - 1 {
                constraints.append(chip.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -4))
            } else {
                // Middle chip centered between the pinned outer chips =
                // Figma `space-between` with equal gaps (286 pt pill →
                // ~78 pt chips with ~21 pt gaps on the 402 pt screen).
                constraints.append(chip.centerXAnchor.constraint(equalTo: pill.centerXAnchor))
            }
        }
        NSLayoutConstraint.activate(constraints)

        applySelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The scrim band stretches well past the pill (the fade zone over
    /// scrolling content, and the strip where the floating mini player
    /// tucks under it). Touches there must fall through to the content
    /// behind — only the pill and the search circle are targets.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event), view !== self else { return nil }
        return view
    }

    // MARK: - Selection

    /// Silent selection update (programmatic moves).
    func select(_ index: Int, animated: Bool) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        applySelection(animated: animated)
    }

    var selectedTabIndex: Int { selectedIndex }

    @objc private func tabTapped(_ sender: UIButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        let isRetap = index == selectedIndex
        selectedIndex = index
        applySelection(animated: true)
        onTabTap?(index, isRetap)
    }

    @objc private func searchTapped() {
        onSearchTap?()
    }

    private func applySelection(animated: Bool) {
        for (index, chip) in chips.enumerated() {
            let active = index == selectedIndex
            let apply = {
                chip.backgroundColor = active
                    ? Self.light(AnycastColor.goldAlpha2)
                    : .clear
                chip.layer.borderColor = active
                    ? Self.light(AnycastColor.sandAlpha4).cgColor
                    : UIColor.clear.cgColor
                chip.layer.borderWidth = active ? 0.5 : 0
                self.buttons[index].tintColor = active
                    ? Self.light(AnycastColor.goldAlpha9)
                    : Self.light(AnycastColor.sandAlpha10)
                // Selection is expressed by the chip container (fill +
                // hairline + ink). `isSelected` on a configuration button
                // makes the system paint a tinted RECTANGLE behind the
                // content on iOS 26+ (`.clear()` background does not cover
                // the selected state) — the tab-bar "boxy highlight" bug.
                // The accessibility trait keeps XCUIElement.isSelected and
                // VoiceOver working.
                if active {
                    self.buttons[index].accessibilityTraits.insert(.selected)
                } else {
                    self.buttons[index].accessibilityTraits.remove(.selected)
                }
            }
            if animated {
                UIView.transition(with: chip, duration: Motion.quick, options: [.transitionCrossDissolve]) {
                    apply()
                }
            } else {
                apply()
            }
        }
    }
}

/// Clear→surface vertical fade used as the pill bar's scrim.
@MainActor
final class GradientFadeView: UIView {
    override public static var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradient = layer as! CAGradientLayer
        // Dynamic token: re-resolved on trait changes (CGColor freeze — 09 §9a).
        gradient.colors = [UIColor.clear.cgColor, Theme.surface.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // Full surface by pill bottom + 24 (the Figma scrim root's own
        // extent: 24 above the pill, pill, 24 below) — the remaining band
        // under it stays solid surface. A full-band fade left the pill zone
        // ~8% tinted and scrolling content collided with the chips once the
        // blur rectangle was removed.
        gradient.locations = [0, 0.845]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false {
            (layer as! CAGradientLayer).colors = [UIColor.clear.cgColor, Theme.surface.cgColor]
        }
    }
}
