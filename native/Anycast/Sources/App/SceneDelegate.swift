import UIKit

/// UIScene lifecycle is mandatory on iOS 27 and has been the template default
/// for years; the migration adopted it from day one (docs/migration/00 M1).
/// Callback entry points that moved with scenes (openURLContexts,
/// connectionOptions) are implemented where the old AppDelegate handled
/// openURL — see `scene(_:openURLContexts:)` below.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    private var rootController: RootViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let root = RootViewController()
        rootController = root

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window

        // Both URL arrival paths (docs/migration/08 §12.2): cold start via
        // connectionOptions, warm via scene(_:openURLContexts:). The handler
        // is an M3 placeholder, but the drains must both exist from day one.
        for context in connectionOptions.urlContexts {
            root.handleOpenURL(context.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            rootController?.handleOpenURL(context.url)
        }
    }
}
