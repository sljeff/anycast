import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices

/// Firebase Auth wrapper. Behavior contract (docs/migration/02 §2):
/// - Google: GIDSignIn with the Firebase `CLIENT_ID` (the Flutter app never
///   set `GIDClientID` in Info.plist; the plugin fell back to
///   `FirebaseApp.options.clientID` — the native port makes that explicit).
///   Only the idToken is used to build the credential, never an accessToken
///   (test/google_sign_in_credential_test.dart pins this).
/// - Apple: ASAuthorizationController → OAuthProvider("apple.com") credential.
/// - Email: signInWithEmailAndPassword (registration stays disabled).
/// - No anonymous auth. `token()` returns nil when signed out, and callers
///   translate that into the synthetic 401 without emitting a request.
@MainActor
final class AuthController {

    private(set) var currentUID: String?

    /// Keeps the sheet's delegate alive for the duration of one sign-in.
    private var appleCoordinator: AppleAuthorizationCoordinator?

    /// The startup DAG's UID-change handler (set once, from
    /// `StartupSequence`); the Firebase listener below invokes it.
    private var uidObserver: (@MainActor (String?) -> Void)?

    /// True once Firebase is configured. `Auth.auth()` raises an
    /// NSException when called unconfigured, so every access is gated — a
    /// bare clone without the gitignored `GoogleService-Info.plist` degrades
    /// like the missing-`Secrets.plist` path instead of crashing at launch.
    private(set) var isFirebaseConfigured = false

    func configureFirebase() {
        guard !isFirebaseConfigured else { return }
        if FirebaseApp.app() == nil {
            guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
                return
            }
            FirebaseApp.configure()
        }
        isFirebaseConfigured = true
        currentUID = Auth.auth().currentUser?.uid
    }

    /// The Flutter line's `authStateChanges` equivalent (lib/states/user.dart):
    /// fires immediately with the current user and again on every change.
    /// Late-restored or post-startup sessions re-bind RevenueCat through this
    /// path instead of silently staying anonymous for the whole session.
    func setUIDObserver(_ handler: @escaping @MainActor (String?) -> Void) {
        uidObserver = handler
        guard isFirebaseConfigured else { return }
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            Task { @MainActor [weak self] in
                self?.currentUID = uid
                self?.uidObserver?(uid)
            }
        }
    }

    func restoreUser() {
        guard isFirebaseConfigured else { return }
        currentUID = Auth.auth().currentUser?.uid
    }

    func token() async throws -> String? {
        guard isFirebaseConfigured, let user = Auth.auth().currentUser else { return nil }
        // Firebase SDK caches + silently refreshes; no client-side refresh
        // retry on 401 (contract red line #2, docs/migration/02 §6).
        return try await user.getIDToken()
    }

    // MARK: - Sign in

    func signInWithGoogle(presenting: UIViewController) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingFirebaseClientID
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.googleMissingIDToken
        }
        // The wire contract is idToken-first: the Flutter credential carried
        // only the idToken (lib/states/user.dart:16). FirebaseAuth-iOS
        // REQUIRES an accessToken argument; the token supplied here is
        // transmitted to verifyAssertion (as provider access_token) but the
        // idToken takes precedence — harmless on the server, noted for
        // byte-level awareness.
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        _ = try await Auth.auth().signIn(with: credential)
        currentUID = Auth.auth().currentUser?.uid
    }

    func signInWithEmail(email: String, password: String) async throws {
        guard isFirebaseConfigured else { throw AuthError.firebaseNotConfigured }
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
        currentUID = Auth.auth().currentUser?.uid
    }

    /// Apple sign-in, two halves: system sheet presentation (M3 supplies the
    /// presenting context) then the Firebase credential exchange.
    func signInWithApple(presenting: UIViewController) async throws {
        guard isFirebaseConfigured else { throw AuthError.firebaseNotConfigured }
        // The coordinator holds the presenting VC; it must not outlive the
        // flow (08 §2.2: page state dies with the page).
        defer { appleCoordinator = nil }
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let authorization = try await withCheckedThrowingContinuation { continuation in
            let coordinator = AppleAuthorizationCoordinator(request: request, presenting: presenting) { result in
                continuation.resume(with: result)
            }
            appleCoordinator = coordinator
            coordinator.start()
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else { throw AuthError.appleMissingCredential }

        let oauthCredential = OAuthProvider.appleCredential(
            withIDToken: idToken, rawNonce: nil, fullName: credential.fullName
        )
        _ = try await Auth.auth().signIn(with: oauthCredential)
        currentUID = Auth.auth().currentUser?.uid
    }

    // MARK: - Sign out (docs/migration/02 §2.5)

    /// Order mirrors AuthController.signOut: RC logOut (offline-tolerant) →
    /// Firebase signOut → Google signOut. Local data is never touched.
    func signOut(purchases: RevenueCatController) async {
        await purchases.logOut()
        if isFirebaseConfigured {
            try? Auth.auth().signOut()
        }
        GIDSignIn.sharedInstance.signOut()
        currentUID = nil
    }

    enum AuthError: Error, LocalizedError {
        case missingFirebaseClientID
        case googleMissingIDToken
        case appleMissingCredential
        case firebaseNotConfigured

        var errorDescription: String? {
            switch self {
            case .missingFirebaseClientID: "Firebase CLIENT_ID unavailable"
            case .googleMissingIDToken: "Google sign-in returned no idToken"
            case .appleMissingCredential: "Apple authorization missing identity token"
            case .firebaseNotConfigured: "Firebase is not configured"
            }
        }
    }
}

/// Bridges the imperative ASAuthorizationController delegate into async.
@MainActor
private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private let completion: @MainActor (Result<ASAuthorization, Error>) -> Void
    private let request: ASAuthorizationAppleIDRequest
    private let presenting: UIViewController

    init(request: ASAuthorizationAppleIDRequest,
         presenting: UIViewController,
         completion: @escaping @MainActor (Result<ASAuthorization, Error>) -> Void) {
        self.request = request
        self.presenting = presenting
        self.completion = completion
        super.init()
    }

    func start() {
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presenting.view.window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}
