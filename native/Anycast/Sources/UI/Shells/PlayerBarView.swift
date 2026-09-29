import UIKit
import Kingfisher
import AnycastKit

/// The mini player (lib/widgets/bottom_nav_bar.dart:76-241, 03 §2.9).
/// A plain UIView — hosted by the shell (iOS 26 `UITabAccessory`, iOS 18
/// floating fallback) and by bottom bars of sheets (Channel/ChannelSearch/
/// SearchPage, later tasks).
///
/// Layout: 58 pt tall; in `.standalone` the visible capsule carries the
/// 12 pt horizontal margin and the 16 pt radius itself, so any host can
/// size this view to the full available width. In `.systemAccessory` the
/// system glass capsule IS the surface — this view draws no background of
/// its own (one chrome, not two nested layers), keeping only a clip shape
/// for the progress fill. Under either style runs a full-height
/// `EpisodeProgressBackdrop` fill (white 20%, width driven by
/// position/duration against OWN bounds — never screen math).
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

    /// How the host surfaces the bar. ONE component, ONE silhouette: both
    /// styles are full capsules (radius == half the 58 pt height) — the
    /// standalone bar must match the system accessory's contour so the
    /// mini player reads as the same element on every screen.
    enum HostingStyle {
        /// Sheet bottom bars and the iOS 18 floating fallback: this view
        /// draws its own white-10% capsule with 12 pt side margins. (The
        /// Dart source's BorderRadius.circular(16) was a rounded rect, not
        /// a capsule; the port unifies on the capsule the system chrome
        /// already uses.)
        case standalone
        /// Inside an iOS 26+ `UITabAccessory`: the system provides the
        /// glass capsule, so this view draws content only, edge to edge.
        case systemAccessory
    }

    /// Set by the host (UIContext.makePlayerBar pre-wires it).
    var onOpenPlayer: (() -> Void)?

    private let playback: PlaybackService
    private let observation = ObservationLoop()

    private let capsule = UIView()
    private let backdrop = EpisodeProgressBackdrop()
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let playPauseControl = PlayPauseIconControl(size: 32)
    private let forwardButton = UIButton(type: .custom)
    private var openedByPan = false
    /// Last URL handed to the cover view. `positionData` is in the
    /// observation read, so render() runs every 0.5 s tick — an
    /// unconditional cancel+setImage would restart an in-flight cover
    /// download on every tick (slow networks never finish loading it).
    private var renderedCoverURL: URL?

    /// `m:ss / m:ss` — PlaylistEpisodeModel.getPlayedAndTotalTime.
    static func playedAndTotalText(playedMilliseconds: Int64, totalMilliseconds: Int64) -> String {
        func clock(_ ms: Int64) -> String {
            let seconds = max(ms / 1000, 0)
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        }
        return "\(clock(playedMilliseconds)) / \(clock(totalMilliseconds))"
    }

    init(playback: PlaybackService, style: HostingStyle = .standalone) {
        self.playback = playback
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight))

        backgroundColor = .clear
        isExclusiveTouch = true

        // One chrome only when the system provides it: the accessory's
        // glass capsule is the surface; standalone paints its own
        // white-10% surface. Everything else about the capsule is shared.
        capsule.backgroundColor = style == .standalone
            ? UIColor.white.withAlphaComponent(0.10)
            : .clear
        // Half the bar height in BOTH styles — one capsule silhouette
        // everywhere (the clip shape for the progress fill; in standalone
        // also the visible surface's contour).
        capsule.layer.cornerRadius = Self.barHeight / 2
        capsule.layer.cornerCurve = .continuous
        // The progress fill is a square-cornered layer spanning the full
        // capsule bounds; without clipping its leading edge pokes past the
        // rounded caps as a vertical line instead of following the head's
        // contour (and at high fractions it would poke past the tail too).
        capsule.clipsToBounds = true
        capsule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(capsule)

        backdrop.fillColor = UIColor.white.withAlphaComponent(0.2)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(backdrop)

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = Theme.primaryBackground
        coverView.isAccessibilityElement = true
        coverView.accessibilityLabel = "Episode artwork"
        coverView.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(coverView)

        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 16, weight: .medium)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryLightMax
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        // XCUITest hook: the tap target for "tap the mini player".
        titleLabel.accessibilityIdentifier = "mini-player-title"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(titleLabel)

        timeLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        )
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = Theme.secondaryText
        timeLabel.numberOfLines = 1
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(timeLabel)

        playPauseControl.accessibilityLabel = "Play or pause"
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
            UIImage.SymbolConfiguration(pointSize: 32),
            forImageIn: .normal
        )
        forwardButton.tintColor = Theme.primaryLightMax
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
            // Standalone: the capsule owns the 12 pt horizontal margin
            // (03 §2.9). Accessory: edge to edge — the system glass
            // already carries its own padding.
            capsule.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: style == .standalone ? 12 : 0
            ),
            capsule.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: style == .standalone ? -12 : 0
            ),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),

            backdrop.leadingAnchor.constraint(equalTo: capsule.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: capsule.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: capsule.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: capsule.bottomAnchor),

            coverView.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 12),
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
            titleLabel.bottomAnchor.constraint(equalTo: capsule.centerYAnchor, constant: -1),

            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            timeLabel.topAnchor.constraint(equalTo: capsule.centerYAnchor, constant: 1),
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
        timeLabel.text = Self.playedAndTotalText(
            playedMilliseconds: position.positionMilliseconds,
            totalMilliseconds: position.durationMilliseconds
        )
        let fraction = position.durationMilliseconds > 0
            ? Double(position.positionMilliseconds) / Double(position.durationMilliseconds)
            : 0
        backdrop.setFraction(fraction)

        let coverURL = episode?.imageUrl.flatMap(URL.init(string:))
        if coverURL != renderedCoverURL {
            renderedCoverURL = coverURL
            coverView.kf.cancelDownloadTask()
            coverView.kf.setImage(
                with: coverURL,
                placeholder: nil,
                options: [.transition(.none)]
            )
        }

        playPauseControl.update(
            snapshot: .init(
                enclosureURL: episode?.enclosureUrl,
                currentEnclosureURL: episode?.enclosureUrl,
                isPlaying: playback.isPlaying,
                isLoading: playback.isLoading
            ),
            tint: Theme.primaryLightMax
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
