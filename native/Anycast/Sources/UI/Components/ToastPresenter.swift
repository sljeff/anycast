import UIKit

/// Window-level short toast — the snackbar equivalent (self-drawn widget #9,
/// docs/migration/07 §3). "Copied" on the channel RSS domain row dismisses
/// after ~1 s (03 §2.7); the same surface serves "Added to playlist"-style
/// confirmations.
final class ToastPresenter {

    static let shared = ToastPresenter()

    private var dismissalTask: Task<Void, Never>?
    private weak var toastView: UIView?
    /// Set while an action toast is on screen: runs when another toast
    /// replaces it, so its owner can settle whatever the action would undo.
    private var supersededHandler: (() -> Void)?
    private var isActionToast = false
    private var actionCapsuleIdentifier: String?

    /// Shows `message` near the bottom of `window`, auto-dismissing after
    /// `duration` (1 s matches the Dart snackbar for "Copied").
    func show(
        _ message: String,
        in window: UIWindow,
        duration: TimeInterval = 1.0
    ) {
        removeCurrentToast(supersede: true)

        let label = UILabel()
        label.text = message
        label.font = TypographyV2.body.font()
        // Inverse pair: readable over any page in both appearances.
        label.textColor = Theme.surface
        label.textAlignment = .center
        label.numberOfLines = 1

        let pill = UIView()
        pill.backgroundColor = Theme.inverseSurface
        pill.layer.cornerRadius = Radius.md
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

    /// A toast with a trailing text action ("Removed from Inbox · Undo").
    /// `bottomAnchor` is the top edge of the bottom chrome (tab bar and mini
    /// player) the capsule must sit above; without one it uses the window's
    /// safe area like a plain toast. A tap runs `onAction` and dismisses.
    /// `onSuperseded` runs if another toast replaces this one first; neither
    /// runs when it times out or `dismissAction` removes it.
    func showAction(
        _ message: String,
        actionTitle: String,
        in window: UIWindow,
        above bottomAnchor: NSLayoutYAxisAnchor? = nil,
        duration: TimeInterval = 5.0,
        capsuleIdentifier: String? = nil,
        actionIdentifier: String? = nil,
        onAction: @escaping () -> Void,
        onSuperseded: @escaping () -> Void
    ) {
        removeCurrentToast(supersede: true)

        let label = UILabel()
        label.text = message
        label.font = TypographyV2.body.font()
        label.textColor = Theme.surface
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var configuration = UIButton.Configuration.plain()
        configuration.title = actionTitle
        configuration.baseForegroundColor = Theme.surface
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.emphasis.font()
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = actionIdentifier
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let pill = UIView()
        pill.backgroundColor = Theme.inverseSurface
        pill.layer.cornerRadius = Radius.md
        pill.layer.cornerCurve = .continuous
        pill.accessibilityIdentifier = capsuleIdentifier
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        pill.addSubview(button)
        window.addSubview(pill)

        let bottom = bottomAnchor.map { pill.bottomAnchor.constraint(equalTo: $0, constant: -12) }
            ?? pill.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            button.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            button.topAnchor.constraint(equalTo: pill.topAnchor),
            button.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            pill.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            pill.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -32),
            bottom,
            pill.heightAnchor.constraint(equalToConstant: 44),
        ])

        button.addAction(UIAction { [weak self] _ in
            self?.supersededHandler = nil
            self?.dismissAction()
            onAction()
        }, for: .touchUpInside)

        toastView = pill
        isActionToast = true
        actionCapsuleIdentifier = capsuleIdentifier
        supersededHandler = onSuperseded
        UIAccessibility.post(notification: .announcement, argument: message)

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissAction()
        }
    }

    /// Removes the action toast, if one is on screen. A plain toast is left
    /// alone, and the superseded handler does not run. With
    /// `capsuleIdentifier`, only that owner's capsule goes: a late commit
    /// must not dismiss the capsule another screen has shown since.
    func dismissAction(capsuleIdentifier: String? = nil) {
        guard isActionToast else { return }
        if let capsuleIdentifier, capsuleIdentifier != actionCapsuleIdentifier { return }
        isActionToast = false
        supersededHandler = nil
        dismissalTask?.cancel()
        guard let pill = toastView else { return }
        toastView = nil
        UIView.animate(withDuration: 0.2, animations: {
            pill.alpha = 0
        }, completion: { _ in
            pill.removeFromSuperview()
        })
    }

    private func removeCurrentToast(supersede: Bool) {
        let handler = supersede ? supersededHandler : nil
        supersededHandler = nil
        isActionToast = false
        dismissalTask?.cancel()
        toastView?.removeFromSuperview()
        handler?()
    }
}
