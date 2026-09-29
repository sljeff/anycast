import UIKit

/// The scene's root: owns URL routing and installs the tab shell once the
/// startup DAG hands over the `UIContext` (dark base until then — the first
/// frame never waits for the chain, docs/migration/08 §2.3).
final class RootViewController: UIViewController {

    private let router = URLRouter()
    private var context: UIContext?
    private var tabShell: MainTabBarController?

    /// Share-handoff URLs that arrived before the shell (cold start via
    /// connectionOptions can precede startup-ready); flushed on install.
    private var pendingShareHandoffURLs: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)
    }

    /// Composition-root callback target (AppEnvironment.onShellReady).
    func install(_ context: UIContext) {
        guard tabShell == nil else { return }

        let shell = MainTabBarController(context: context)
        tabShell = shell
        self.context = context

        // Late-bound wiring (weak, UI-side objects die with the scene).
        context.tabs.tabBarController = shell
        context.loginPrompt.presentingAnchor = self
        context.flyInEndpointProvider.tabBarProvider = { [weak shell] in shell }

        addChild(shell)
        view.addSubview(shell.view)
        shell.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shell.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shell.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shell.view.topAnchor.constraint(equalTo: view.topAnchor),
            shell.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        shell.didMove(toParent: self)

        let pending = pendingShareHandoffURLs
        pendingShareHandoffURLs.removeAll()
        for url in pending {
            deliverShareHandoff(url)
        }
    }

    // MARK: - URL routing (both arrival paths end here, SceneDelegate)

    /// Google sign-in return + `ShareMedia-<bundleid>` handoff
    /// (docs/migration/08 §12.2).
    func handleOpenURL(_ url: URL) {
        switch router.classify(url) {
        case .googleSignIn:
            _ = URLRouter.handleGoogleSignIn(url: url)
        case .shareHandoff:
            if context != nil {
                deliverShareHandoff(url)
            } else {
                pendingShareHandoffURLs.append(url)
            }
        case .unhandled:
            break
        }
    }

    private func deliverShareHandoff(_ url: URL) {
        guard let context else { return }
        if let presenter = context.shareHandoffPresenter {
            presenter.presentShareHandoff(for: url)
        } else {
            // T9 registers the ShareDialog implementation on
            // UIContext.shareHandoffPresenter; until then log-and-drop
            // (development trace only — keep it out of release builds).
            #if DEBUG
            print("[share-handoff] no presenter registered for \(url.absoluteString)")
            #endif
        }
    }
}
