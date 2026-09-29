import UIKit
import Lottie

/// The PlayIcon equivalent (lib/widgets/play_icon.dart). Given the playback
/// snapshot, it shows:
/// - a static play icon when `enclosureURL` is set and is NOT the current
///   track (or when no episode is loaded);
/// - the `loading` lottie while the CURRENT track is loading — the white
///   animation on light tints, `loading_black` on dark ones (luminance > 0.5
///   picks white, exactly the Dart rule);
/// - pause while playing the current track, play otherwise.
///
/// State is PUSHED by the owning screen (PlaybackService observation lives
/// there); this control only renders.
final class PlayPauseIconControl: UIControl {

    struct Snapshot {
        var enclosureURL: String?
        var currentEnclosureURL: String?
        var isPlaying: Bool
        var isLoading: Bool

        static let idle = Snapshot(enclosureURL: nil, currentEnclosureURL: nil, isPlaying: false, isLoading: false)
    }

    private let iconView = UIImageView()
    private var lottieView: LottieAnimationView?
    private var lottieVariantIsWhite = true
    private var tintColorValue: UIColor = Theme.primaryLightMax

    /// Icon point size (24 default, 32 mini player, 72 player center).
    private(set) var size: CGFloat

    init(size: CGFloat = 24) {
        self.size = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))

        isAccessibilityElement = true
        accessibilityTraits = [.image]

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = tintColorValue
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        render(snapshot: .idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The control's declared size. With translatesAutoresizingMaskInto
    /// Constraints = false the init frame is ignored, and without an
    /// intrinsic size the layout engine sized the control to its subviews'
    /// natural dimensions — the loading lottie's animation canvas blew the
    /// player's 72 pt button up to full-column width (its edge constraints
    /// are pinned to this control). Every embed is centered-only, so the
    /// intrinsic size is what keeps it 24/32/48 pt.
    override var intrinsicContentSize: CGSize {
        CGSize(width: size, height: size)
    }

    /// Push a new playback snapshot plus the tint icons/lottie adapt to.
    func update(snapshot: Snapshot, tint: UIColor? = nil) {
        if let tint {
            tintColorValue = tint
        }
        render(snapshot: snapshot)
    }

    private func render(snapshot: Snapshot) {
        let isCurrentTrack = snapshot.currentEnclosureURL != nil
            && snapshot.enclosureURL == snapshot.currentEnclosureURL

        // Loading lottie only ever applies to the current track (the Dart
        // early-return for non-current episodes).
        let showLoading = isCurrentTrack && snapshot.isLoading
        let playing = isCurrentTrack && snapshot.isPlaying

        if showLoading {
            // Dart rule: luminance > 0.5 picks the white animation. A color
            // whose components cannot be resolved counts as LIGHT — the
            // base white variant — so `loading_black` is only ever picked
            // for a confirmed dark tint.
            let useWhite: Bool
            if let luminance = tintColorValue.approximateLuminance {
                useWhite = luminance > 0.5
            } else {
                useWhite = true
            }
            ensureLottie(white: useWhite)
            lottieView?.isHidden = false
            // The view plays in a loop from creation; resume only if
            // something paused it, so re-renders never restart the frames.
            if let lottieView, !lottieView.isAnimationPlaying {
                lottieView.play()
            }
            iconView.isHidden = true
            accessibilityLabel = "Loading"
        } else {
            lottieView?.isHidden = true
            iconView.isHidden = false
            iconView.image = playing ? AppIcons.pause : AppIcons.play
            iconView.tintColor = tintColorValue
            accessibilityLabel = playing ? "Pause" : "Play"
        }
    }

    private func ensureLottie(white: Bool) {
        if let lottieView, lottieVariantIsWhite == white { return }
        lottieView?.removeFromSuperview()
        let lottie = LottieAnimationView(name: white ? "loading" : "loading_black")
        lottie.contentMode = .scaleAspectFit
        lottie.loopMode = .loop
        lottie.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lottie)
        NSLayoutConstraint.activate([
            lottie.leadingAnchor.constraint(equalTo: leadingAnchor),
            lottie.trailingAnchor.constraint(equalTo: trailingAnchor),
            lottie.topAnchor.constraint(equalTo: topAnchor),
            lottie.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        lottie.play()
        lottieView = lottie
        lottieVariantIsWhite = white
    }
}

private extension UIColor {
    /// Approximate relative luminance for the white-vs-black lottie choice;
    /// nil when the components cannot be resolved in this context (the
    /// leftover-zero fallback would have wrongly picked the black variant).
    var approximateLuminance: CGFloat? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
