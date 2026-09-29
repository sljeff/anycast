import UIKit

/// Window-level short toast — the snackbar equivalent (self-drawn widget #9,
/// docs/migration/07 §3). "Copied" on the channel RSS domain row dismisses
/// after ~1 s (03 §2.7); the same surface serves "Added to playlist"-style
/// confirmations.
final class ToastPresenter {

    static let shared = ToastPresenter()

    private var dismissalTask: Task<Void, Never>?
    private weak var toastView: UIView?

    /// Shows `message` near the bottom of `window`, auto-dismissing after
    /// `duration` (1 s matches the Dart snackbar for "Copied").
    func show(
        _ message: String,
        in window: UIWindow,
        duration: TimeInterval = 1.0
    ) {
        dismissalTask?.cancel()
        toastView?.removeFromSuperview()

        let label = UILabel()
        label.text = message
        label.font = Typography.defaultText.font()
        label.textColor = Theme.primaryLightMax
        label.textAlignment = .center
        label.numberOfLines = 1

        let pill = UIView()
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.87)
        pill.layer.cornerRadius = 16
        pill.layer.cornerCurve = .continuous
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        window.addSubview(pill)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            // Cap the pill at the app's 16pt side margins so a long message
            // cannot span edge-to-edge on an iPad window.
            pill.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -32),
            pill.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -12
            ),
            pill.heightAnchor.constraint(equalToConstant: 44),
        ])

        toastView = pill
        // The toast is transient and non-modal — VoiceOver users would
        // otherwise never receive it. Announce alongside the visual pill.
        UIAccessibility.post(notification: .announcement, argument: message)

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            UIView.animate(withDuration: 0.2, animations: {
                pill.alpha = 0
            }, completion: { _ in
                pill.removeFromSuperview()
            })
            self?.toastView = nil
        }
    }
}
