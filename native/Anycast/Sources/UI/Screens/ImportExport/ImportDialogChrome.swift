import UIKit

/// Get.dialog parity chrome (03 §2.15): the Flutter dialogs were centered
/// `AlertDialog`s over a dimmed barrier — NOT sheets. The host screens
/// present these controllers `.overFullScreen` with a cross-dissolve; the
/// chrome inside paints the 54% black barrier and the centered dark rounded
/// card. Widths stay relative to the presented container's bounds (never
/// UIScreen — iPad window-size rule, 05 §11).
class DialogBaseViewController: UIViewController {

    let cardView = UIView()

    /// While an import runs, outside taps no longer dismiss (the Dart
    /// barrier technically stayed dismissible, but dismissing mid-import
    /// desynced the Get.back pairing — closed as a crash-family fix).
    var isBusy = false

    private let dimControl = UIControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.54)
        view.overrideUserInterfaceStyle = .dark

        dimControl.translatesAutoresizingMaskIntoConstraints = false
        dimControl.addTarget(self, action: #selector(barrierTapped), for: .touchUpInside)
        view.addSubview(dimControl)

        cardView.backgroundColor = Theme.cardBackground
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        NSLayoutConstraint.activate([
            dimControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimControl.topAnchor.constraint(equalTo: view.topAnchor),
            dimControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    /// Installs the card's width for a Flutter `SizedBox(width:)`/fractional
    /// dialog width: the requested width at priority 999, clamped by the
    /// container bounds (required) so small windows and iPad split views win.
    func constrainCardWidth(constant: CGFloat) {
        let exact = cardView.widthAnchor.constraint(equalToConstant: constant)
        exact.priority = .init(999)
        NSLayoutConstraint.activate([
            exact,
            cardView.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    func constrainCardWidth(fraction: CGFloat) {
        let proportional = cardView.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: fraction
        )
        proportional.priority = .init(999)
        NSLayoutConstraint.activate([
            proportional,
            cardView.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    @objc private func barrierTapped() {
        guard !isBusy else { return }
        dismiss(animated: true)
    }
}

/// The import progress overlay (ImportIndicator / ImportProgressIndicator,
/// import_indicator.dart + share.dart:122-143): a centered determinate ring
/// (grey track + `ProgressRingView`, 07 §2.7 "reuse the download ring") or
/// an indeterminate spinner for the manual-URL flow. Presented overFullScreen
/// while an import runs; taps pass nowhere.
final class ImportProgressOverlayController: UIViewController {

    private let mode: Mode

    private enum Mode {
        case determinate(lineWidth: CGFloat)
        case indeterminate
    }

    private var progressRing: ProgressRingView?
    private var trackRing: ProgressRingView?
    private var spinner: UIActivityIndicatorView?

    /// ImportIndicator (OPML flow): default-stroke ring on a grey track.
    static func determinate(lineWidth: CGFloat = 4) -> ImportProgressOverlayController {
        ImportProgressOverlayController(mode: .determinate(lineWidth: lineWidth))
    }

    /// ImportProgressIndicator (share flow): strokeWidth 2 on a
    /// surfaceContainerHighest track (share.dart:131-136).
    static func shareStyle() -> ImportProgressOverlayController {
        ImportProgressOverlayController(mode: .determinate(lineWidth: 2))
    }

    /// The manual-URL fetch spinner (import_export.dart:192-193).
    static func indeterminate() -> ImportProgressOverlayController {
        ImportProgressOverlayController(mode: .indeterminate)
    }

    private init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.54)
        view.overrideUserInterfaceStyle = .dark
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Importing podcasts"

        switch mode {
        case .determinate(let lineWidth):
            let track = ProgressRingView(lineWidth: lineWidth)
            track.tintColorOverride = Theme.secondaryLabelGray   // Colors.grey track
            track.setProgress(1)
            let ring = ProgressRingView(lineWidth: lineWidth)

            for item in [track, ring] {
                item.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(item)
            }
            NSLayoutConstraint.activate([
                track.widthAnchor.constraint(equalToConstant: 44),
                track.heightAnchor.constraint(equalToConstant: 44),
                track.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                track.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
                ring.widthAnchor.constraint(equalTo: track.widthAnchor),
                ring.heightAnchor.constraint(equalTo: track.heightAnchor),
                ring.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                ring.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            ])
            trackRing = track
            progressRing = ring
        case .indeterminate:
            let indicator = UIActivityIndicatorView(style: .large)
            indicator.color = Theme.primaryLightMax
            indicator.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            ])
            indicator.startAnimating()
            spinner = indicator
        }
    }

    /// Progress 0…1 (TempResult `process/total` — the batch START index over
    /// the total, so the ring lags one batch behind; shipped semantics).
    /// Ignored by the indeterminate variant.
    func setProgress(_ value: Double) {
        progressRing?.setProgress(value)
    }
}
