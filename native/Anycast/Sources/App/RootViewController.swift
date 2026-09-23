import UIKit

/// M1 placeholder surface. The 21-screen UI lands in M3; until then this view
/// only proves the launch chain (scene → window → startup DAG) works.
final class RootViewController: UIViewController {

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "Anycast — native skeleton (M1)"
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// URL scheme callbacks (Google sign-in return, ShareMedia-<bundleid>:share)
    /// are routed here for now; real handling arrives with auth (M3) and the
    /// share handoff reader.
    func handleOpenURL(_ url: URL) {
        // M3: GIDSignIn.handle(url); M3: ShareController handoff for the
        // ShareMedia scheme.
    }
}
