import Foundation
import RevenueCat

/// RevenueCat wrapper. Contract (docs/migration/02 §3):
/// - Same RC project/API key as the Flutter line; `appUserID = Firebase uid`.
/// - Entitlement `plus`; iOS product `anycast_monthly`.
/// - The old build's race (logIn fired before configure finished → error
///   swallowed by `print` → whole session anonymous, 08 §12.1-5) is fixed by
///   the startup DAG: configure completes first, logIn afterwards, failures
///   retried and reported.
@MainActor
final class RevenueCatController {

    private(set) var configured = false
    private var lastBoundUID: String?

    func configureIfPossible() async {
        guard !configured else { return }
        guard let apiKey = Secrets.purchasesAPIKey() else {
            // Secrets.plist absent (bare simulator run, L0–L2 test host).
            // Store-pipeline builds materialize it via bootstrap.
            return
        }
        // Verbose SDK logging belongs to debug builds only — an ungated
        // .debug would spam Release logs with request payloads.
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(with: Configuration.Builder(withAPIKey: apiKey).build())
        configured = true
    }

    /// Called by the startup DAG once configure has completed. Re-running with
    /// the same uid is a no-op; a uid change re-binds (logIn — idempotent for
    /// the same appUserID in current purchases-ios). Throws on real failures
    /// so the DAG can retry (fixed order: configure → logIn).
    func bind(uid: String) async throws {
        guard configured else { return }
        guard uid != lastBoundUID else { return }
        _ = try await Purchases.shared.logIn(uid)
        lastBoundUID = uid
    }

    /// logOut with the offline tolerance the Flutter tests pinned
    /// (test/revenue_cat_controller_test.dart): a PlatformException on logout
    /// must not abort the sign-out sequence.
    func logOut() async {
        guard configured else { return }
        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            // Offline logOut failure is swallowed — mirrors the shipped app.
        }
        lastBoundUID = nil
    }

    /// Any active entitlement means Plus (02 §3.2: the shipped app checks
    /// `entitlements.active.isNotEmpty`; entitlement id `plus` for display).
    func isSubscribed() async -> Bool {
        guard configured, let info = try? await Purchases.shared.customerInfo() else { return false }
        return !info.entitlements.active.isEmpty
    }
}
