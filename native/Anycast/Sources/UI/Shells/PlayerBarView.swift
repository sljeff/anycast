import UIKit
import Kingfisher
import AnycastKit

/// The mini player (lib/widgets/bottom_nav_bar.dart:76-241, 03 §2.9).
/// A plain UIView — hosted by the shell (iOS 26 `UITabAccessory`, iOS 18
/// floating fallback) and by bottom bars of sheets (Channel/ChannelSearch/
/// SearchPage, later tasks).
///
/// Layout: 58 pt tall, edge to edge in the host's frame (the host owns any
/// side margins). With `.capsule` the view paints the sand capsule surface
/// itself; in `.systemAccessory` the system glass capsule IS the surface —
/// this view draws no background of its own (one chrome, not two nested
/// layers), keeping only a clip shape for the progress fill. Under both
/// styles a thin progress line (width driven by position/duration against
/// OWN bounds — never screen math) runs along the inner bottom edge.
///
/// Gestures (03 §3.1): whole-bar tap opens the full-screen player; ANY
/// vertical drag — up or down, no threshold, the shipped quirk — also opens
/// it. The play/pause and +30 s controls never bubble to the open gesture.
@MainActor
final class PlayerBarView: UIView {

    /// The bar's fixed height (bottom_nav_bar.dart:76-241) — the single
    /// source for the view itself and for hosts that must avoid the
    /// floating fallback's frame (MainTabBarController.FallbackMetrics).
    static let barHeight: CGFloat = 58
    /// The capsule's progress line.
    static let capsuleProgressHeight: CGFloat = 3

    /// How the host surfaces the bar. ONE component, ONE silhouette: every
    /// style is a full capsule (radius == half the 58 pt height) — the bar
    /// must read as the same element on every screen.
    enum HostingStyle {
        /// Inside an iOS 26+ `UITabAccessory`: the system provides the
        /// glass capsule, so this view draws content only, edge to edge.
        case systemAccessory
        /// The v2 floating capsule (09 §3.6 state c, Figma 83:2562) used by
        /// sheet bottom bars and the iOS 18 floating fallback: opaque sand
        /// fill + sandAlpha4 1 pt stroke + `0 8 10` shadow, circular 36 pt
        /// cover, single centered title. The host owns the horizontal
        /// margins.
        case capsule
    }

    /// Set by the host (UIContext.makePlayerBar pre-wires it).
    var onOpenPlayer: (() -> Void)?

    private let playback: PlaybackService
    private let style: HostingStyle
    private let observation = ObservationLoop()

    private let capsule = UIView()
    private let backdrop = EpisodeProgressBackdrop()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let playPauseControl = PlayPauseIconControl(size: 32)
    private let forwardButton = UIButton(type: .custom)
    private var openedByPan = false
    /// Last URL handed to the cover view. `positionData` is in the
    /// observation read, so render() runs every 0.5 s tick — an
    /// unconditional cancel+setImage would restart an in-flight cover
    /// download on every tick (slow networks never finish loading it).
    private var renderedCoverURL: URL?

    init(playback: PlaybackService, style: HostingStyle) {
        self.playback = playback
        self.style = style
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight))

        backgroundColor = .clear
        isExclusiveTouch = true

        // One chrome only when the system provides it: the accessory's
        // glass capsule is the surface; capsule paints the v2 chrome
        // (09 §3.6). Everything else about the capsule is shared.
        switch style {
        case .systemAccessory:
            capsule.backgroundColor = .clear
        case .capsule:
            // The v2 chrome family is STATIC light (09 §3.6 — same ruling as
            // the pill bar; the dark design frame renders the card bright).
            // Opaque sand1 rather than the spec's white 80%: list text no
            // longer shows through the capsule (2.0 unification round).
            capsule.backgroundColor = AnycastColor.sand1
            capsule.layer.borderColor = AnycastColor.sandAlpha4.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            ).cgColor
            capsule.layer.borderWidth = 1
            capsule.layer.shadowColor = UIColor.black.cgColor
            capsule.layer.shadowOpacity = 0.08
            capsule.layer.shadowOffset = CGSize(width: 0, height: 8)
            capsule.layer.shadowRadius = 10
        }
        // Half the bar height in BOTH styles — one capsule silhouette
        // everywhere (the clip shape for the progress fill; in the
        // self-painting style also the visible surface's contour).
        capsule.layer.cornerRadius = Self.barHeight / 2
        capsule.layer.cornerCurve = .continuous
        // The progress fill is a square-cornered layer spanning the full
        // capsule bounds; without clipping its leading edge pokes past the
        // rounded caps as a vertical line instead of following the head's
        // contour (and at high fractions it would poke past the tail too).
        capsule.clipsToBounds = true
        capsule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)

        // Capsule and accessory share the compact content (UI kit mini
        // player): a thin gold progress line on a sand track along the
        // inner bottom edge, a round cover, one title line, small glyphs.
        if style == .systemAccessory {
            backdrop.trackColor = AnycastColor.sandAlpha3
            backdrop.fillColor = Theme.primary
        } else {
            backdrop.trackColor = AnycastColor.sandAlpha3.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            backdrop.fillColor = Theme.primary.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        }
        backdrop.layer.cornerRadius = Self.capsuleProgressHeight / 2
        backdrop.clipsToBounds = true
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(backdrop)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        // v2 capsule: circular 36 pt cover (Figma 83:2562).
        coverView.layer.cornerRadius = 18
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = style == .capsule
            ? AnycastColor.sandAlpha2.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .light)
            )
            : Theme.surfaceContainerHigh
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Episode artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(coverView)

        titleLabel.font = TypographyV2.titleMedium.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        // The capsule floats on the static white-80 surface — light-variant
        // ink; the player-hosted styles keep the legacy chrome colors.
        titleLabel.textColor = style == .capsule
            ? Theme.onSurface.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            : Theme.onSurface
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        // XCUITest hook: the tap target for "tap the mini player".
        titleLabel.accessibilityIdentifier = "mini-player-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(titleLabel)

        playPauseControl.accessibilityLabel = "Play or pause"
        // 24 pt glyph in the 44 pt slot, level with the 22 pt skip glyph.
        playPauseControl.glyphInset = 10
        // The control itself only renders (PlayPauseIconControl contract);
        // the tap toggles through the service like every other host.
        // Explicit target-action (not addAction): legacy registration is
        // introspectable, which the ShellWiring regression test relies on.
        playPauseControl.addTarget(
            self, action: #selector(playPauseTapped), for: .touchUpInside
        )
        playPauseControl.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(playPauseControl)

        forwardButton.setImage(AppIcons.forward30, for: .normal)
        forwardButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 22),
            forImageIn: .normal
        )
        forwardButton.addPressFeedback()
        forwardButton.tintColor = style == .capsule
            ? Theme.onSurface.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            : Theme.onSurface
        forwardButton.isAccessibilityElement = true
        forwardButton.accessibilityLabel = "Forward 30 seconds"
        forwardButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                let target = self.playback.positionData.positionMilliseconds + 30_000
                Task { await self.playback.seek(target) }
            },
            for: .touchUpInside
        )
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(forwardButton)

        NSLayoutConstraint.activate([
            // Edge to edge — the host chrome (system glass / the host's
            // margins) already carries padding.
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),


            coverView.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 8),
            coverView.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            coverView.widthAnchor.constraint(equalToConstant: 36),
            coverView.heightAnchor.constraint(equalToConstant: 36),

            playPauseControl.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            playPauseControl.widthAnchor.constraint(equalToConstant: 44),
            playPauseControl.heightAnchor.constraint(equalToConstant: 44),
            playPauseControl.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -8),

            forwardButton.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 44),
            forwardButton.heightAnchor.constraint(equalToConstant: 44),
            forwardButton.trailingAnchor.constraint(equalTo: playPauseControl.leadingAnchor, constant: -4),

            titleLabel.leadingAnchor.constraint(equalTo: coverView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: forwardButton.leadingAnchor, constant: -4),
            // Single centered title line (Figma 83:2562 carries only the title).
            titleLabel.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])

        // Inset by the cap radius so the line stays inside the rounded ends.
        let inset = Self.barHeight / 2
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: inset),
            backdrop.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -inset),
            backdrop.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -Spacing.xs),
            backdrop.heightAnchor.constraint(equalToConstant: Self.capsuleProgressHeight),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.delegate = self
        capsule.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panHandled(_:)))
        pan.delegate = self
        capsule.addGestureRecognizer(pan)

        heightAnchor.constraint(equalToConstant: Self.barHeight).isActive = true
        render()
        startObserving()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The capsule border runs through `layer.borderColor` — a frozen
    /// CGColor that must be re-resolved on appearance flips (09 §9a).
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) ?? false,
           capsule.layer.borderWidth > 0 {
            // The capsule chrome is static light (see init).
            capsule.layer.borderColor = AnycastColor.sandAlpha4.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor
        }
    }

    // MARK: - Playback observation (state is pushed into subviews)

    private func startObserving() {
        observation.track(
            read: { [weak self] in
                guard let self else { return }
                _ = self.playback.currentEpisode
                _ = self.playback.positionData
                _ = self.playback.isPlaying
                _ = self.playback.isLoading
            },
            onChange: { [weak self] in self?.render() }
        )
    }

    private func render() {
        let episode = playback.currentEpisode
        let position = playback.positionData

        titleLabel.text = episode?.title ?? ""
        let fraction = position.durationMilliseconds > 0
            ? Double(position.positionMilliseconds) / Double(position.durationMilliseconds)
            : 0
        backdrop.setFraction(fraction)

        let coverURL = episode?.imageUrl.flatMap(URL.init(string:))
        if coverURL != renderedCoverURL {
            renderedCoverURL = coverURL
            coverView.kf.cancelDownloadTask()
            coverView.setArtwork(coverURL, title: episode?.channelTitle)
        }

        playPauseControl.update(
            snapshot: .init(
                enclosureURL: episode?.enclosureUrl,
                currentEnclosureURL: episode?.enclosureUrl,
                isPlaying: playback.isPlaying,
                isLoading: playback.isLoading
            ),
            tint: style == .capsule
                ? Theme.onSurface.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                : Theme.onSurface
        )
    }

    // MARK: - Gestures (03 §2.9 / §3.1)

    @objc private func openTapped() {
        onOpenPlayer?()
    }

    @objc private func playPauseTapped() {
        Task { await playback.togglePlay() }
    }

    @objc private func panHandled(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            openedByPan = false
        }
        guard !openedByPan else { return }
        // The shipped quirk: ANY vertical displacement opens the player —
        // no direction or threshold judgment (bottom_nav_bar.dart:110-117).
        let translation = gesture.translation(in: self)
        if abs(translation.y) >= 1 {
            openedByPan = true
            onOpenPlayer?()
        }
    }
}

/// Inner controls win over the bar gestures (03 §2.9): touches on the
/// play/pause or +30 s controls never open the full-screen player.
extension PlayerBarView: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard let touched = touch.view else { return true }
        if touched === playPauseControl || touched === forwardButton {
            return false
        }
        // Any embedded control (present or future) opts out of the
        // whole-bar gestures.
        if let current = touched as? UIControl {
            return false
        }
        return !(touched.superview is UIControl)
    }
}
