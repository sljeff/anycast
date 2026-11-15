#if DEBUG
import UIKit
import Testing
import AnycastKit
@testable import Anycast

/// Writes 402x874 PNGs of every Plus surface in each account and store state
/// (paywall loaded / loading / failed, Membership, Settings top, transcript
/// prompt capsule) so they can be looked at. Gated: runs only when
/// `PLUS_SHOTS_DIR` is set in the test process
/// (`TEST_RUNNER_PLUS_SHOTS_DIR=/path xcodebuild ... test`). The states are
/// injected through `PlusDebug`; nothing touches RevenueCat or the server.
@MainActor
struct PlusVisualCaptureTests {

    private static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["PLUS_SHOTS_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @Test("Capture Plus surfaces")
    func capture() async throws {
        guard let directory = Self.outputDirectory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let context = await Self.liveUIContext() else {
            Issue.record("No live UIContext")
            return
        }
        defer { PlusDebug.state = nil; PlusDebug.products = nil }
        let host = Self.makeHost()
        defer { host.window.isHidden = true }

        // Paywall.
        PlusDebug.state = .free
        for products in [PlusDebug.Products.loaded, .loading, .failed] {
            PlusDebug.products = products
            let paywall = PaywallViewController(context: context, variant: .standard)
            try await Self.shoot(paywall, in: host, name: "paywall-\(products.rawValue)", directory: directory)
        }
        PlusDebug.products = .loaded
        let quota = PaywallViewController(
            context: context,
            variant: .quota(PaywallModel.Episode(
                title: "Why benchmarks lie", showName: "Practical AI", durationMilliseconds: 2_880_000, artworkURL: nil
            ))
        )
        try await Self.shoot(quota, in: host, name: "paywall-quota", directory: directory)
        var model = PaywallModel(variant: .standard)
        model.setPlans(PlusDebug.samplePlans)
        try await Self.shoot(PaywallDetailsViewController(model: model), in: host, name: "paywall-details", directory: directory)

        // Membership.
        for state in [PlusDebug.State.member, .free, .freeExhausted] {
            PlusDebug.state = state
            let membership = MembershipViewController(
                context: context, isSubscribed: state.isSubscribed, plus: state.plusStatus, remaining: state.remaining
            )
            try await Self.shoot(membership, in: host, name: "membership-\(state.rawValue)", directory: directory)
        }

        // Settings top.
        for state in [PlusDebug.State.signedOut, .free, .freeExhausted, .member] {
            PlusDebug.state = state
            let settings = SettingsViewController(context: context)
            try await Self.shoot(settings, in: host, name: "settings-\(state.rawValue)", directory: directory, settle: 1.5)
        }

        // Transcript prompt capsule.
        let cases: [(String, Bool, TranscriptAllowance?)] = [
            ("capsule-signedOut", false, nil),
            ("capsule-quotaLeft", true, TranscriptAllowance(remaining: 7, isSubscribed: false)),
            ("capsule-exhausted", true, TranscriptAllowance(remaining: 0, isSubscribed: false)),
            ("capsule-plusExhausted", true, TranscriptAllowance(remaining: 0, isSubscribed: true)),
        ]
        for (name, signedIn, allowance) in cases {
            let row = DetailTranscriptState.reduce(status: nil, signedIn: signedIn, allowance: allowance)
            let controller = UIViewController()
            controller.view.backgroundColor = Theme.playerBackground
            let capsule = TranscriptStatusCapsuleView()
            capsule.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(capsule)
            NSLayoutConstraint.activate([
                capsule.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 28),
                capsule.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -28),
                capsule.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -220),
            ])
            capsule.show(.prompt(row, onAction: { _ in }), animated: false)
            try await Self.shoot(controller, in: host, name: name, directory: directory, presentAsSheet: false)
        }
    }

    // MARK: - Helpers

    private static func makeHost() -> (window: UIWindow, root: UIViewController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let root = UIViewController()
        root.view.backgroundColor = Theme.background
        window.rootViewController = root
        window.makeKeyAndVisible()
        return (window, root)
    }

    private static func shoot(
        _ controller: UIViewController,
        in host: (window: UIWindow, root: UIViewController),
        name: String,
        directory: URL,
        settle: TimeInterval = 1.0,
        presentAsSheet: Bool = true
    ) async throws {
        if presentAsSheet {
            AppSheets.presentExpand(controller, from: host.root, animated: false)
        } else {
            controller.modalPresentationStyle = .fullScreen
            host.root.present(controller, animated: false)
        }
        try await Task.sleep(for: .seconds(settle))
        let window = host.window
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        }
        host.root.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
    }

    private static func liveUIContext() async -> UIContext? {
        for _ in 0..<60 {
            if let context = (UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext {
                return context
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }
}
#endif
