import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Composition root (docs/migration/08 §2.2): the one long-lived object
    /// graph, constructed eagerly at process start. Scene/UI objects never
    /// reach back for globals; they receive what they need from here.
    let environment = AppEnvironment.live()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Startup DAG (docs/migration/06 §4 / 08 §2.3). Sentry is attached
        // before anything else can fail. First frame does NOT wait for the
        // chain; the UI renders a placeholder until the environment is ready.
        environment.startup.start()
        return true
    }
}
