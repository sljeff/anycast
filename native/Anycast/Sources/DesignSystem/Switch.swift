import UIKit

/// The app's one toggle: a system `UISwitch` (the system owns the behaviour
/// and the OS-specific shape) that we only paint — sand ON track, sand
/// thumb, and an OFF track in the same `sandAlpha4` as the stepper capsule.
///
/// UISwitch has no public off-track API, and painting the switch's own
/// background does not work: both iOS 18 and iOS 27 draw the off track as a
/// translucent system-colour fill ON TOP of whatever is behind the switch,
/// so a background only darkens the system grey. The off track is a leaf
/// subview of the switch's internal element (full size, capsule-clipped,
/// opaque-coloured); this component finds it structurally and gives it the
/// sand fill. If a future OS changes that structure the lookup finds nothing
/// and the system off track stays — a graceful fallback. All colours are
/// dynamic, so they follow the switch's own trait collection (a host that
/// forces dark, like the player, gets the dark pair without any call-site
/// code).
final class AnycastSwitch: UISwitch {

    /// ON track: sand12 in light, sandDark9 in dark.
    static let onTrackColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? AnycastColor.sandDark9 : AnycastColor.sand12
    }
    /// Thumb: sand1 in light, sandDark1 in dark.
    static let thumbColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? AnycastColor.sandDark1 : AnycastColor.sand1
    }
    /// OFF track: the stepper capsule's fill.
    static let offTrackColor = AnycastColor.sandAlpha4

    override init(frame: CGRect) {
        super.init(frame: frame)
        onTintColor = Self.onTrackColor
        thumbTintColor = Self.thumbColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        paintOffTrack()
    }

    /// The system may re-apply its own off fill when the appearance flips.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        paintOffTrack()
    }

    /// Fill, plus — under Increase Contrast — a 1 pt sand edge so the OFF
    /// state stays perceivable (the system darkens its own off fill there;
    /// the sand fill alone would not). The border is a frozen CGColor,
    /// re-resolved on every layout and appearance change.
    private func paintOffTrack() {
        guard let track = offTrackView else { return }
        track.backgroundColor = Self.offTrackColor
        let highContrast = traitCollection.accessibilityContrast == .high
        track.layer.borderWidth = highContrast ? 1 : 0
        track.layer.borderColor = AnycastColor.sandAlpha9.resolvedColor(with: traitCollection).cgColor
    }

    /// The system's off-track view: a childless, switch-sized subview with
    /// a background (the ON track and the thumb lens carry subviews or a
    /// different size).
    var offTrackView: UIView? {
        func search(_ view: UIView, depth: Int) -> UIView? {
            for sub in view.subviews {
                if sub.subviews.isEmpty, sub.backgroundColor != nil,
                   abs(sub.bounds.width - bounds.width) < 0.5,
                   abs(sub.bounds.height - bounds.height) < 0.5 {
                    return sub
                }
                if depth < 2, let found = search(sub, depth: depth + 1) { return found }
            }
            return nil
        }
        return search(self, depth: 0)
    }
}
