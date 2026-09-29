import Foundation
import GoogleSignIn

/// URL scheme dispatch for both arrival paths (cold start via
/// connectionOptions, warm via openURLContexts — SceneDelegate drains both).
///
/// The classification is pure and unit-tested; the side effects (GIDSignIn
/// handoff, share-handoff presentation) live in `RootViewController`.
struct URLRouter {

    enum Destination: Equatable {
        /// `ShareMedia-<bundleid>` — media shared from the Share Extension.
        case shareHandoff
        /// Google sign-in return URL (reverse client ID scheme).
        case googleSignIn
        case unhandled
    }

    let bundleIdentifier: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "") {
        self.bundleIdentifier = bundleIdentifier
    }

    func classify(_ url: URL) -> Destination {
        guard let scheme = url.scheme?.lowercased() else { return .unhandled }
        if scheme == "sharemedia-\(bundleIdentifier.lowercased())" {
            return .shareHandoff
        }
        if scheme.hasPrefix("com.googleusercontent.apps") {
            return .googleSignIn
        }
        return .unhandled
    }

    /// Google sign-in callback (docs/migration/02 §2). Returns whether the
    /// URL was consumed by GIDSignIn.
    nonisolated static func handleGoogleSignIn(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
