import Foundation
import RevenueCat
import FirebaseAuth
import UIKit

/// RevenueCat access for the paywall (docs/migration/02 §3.3): offerings,
/// purchase, restore, and the `plus` entitlement expiration. Everything is
/// gated on `RevenueCatController.configured` — a simulator run without
/// Secrets.plist degrades to "store unavailable" instead of the SDK's
/// unconfigured assertion. T11 should fold these into RevenueCatController;
/// they live here only because that file is outside this task's file set.
@MainActor
struct PaywallStore {

    enum StoreError: Error {
        case notConfigured
        case planUnavailable
    }

    private let purchases: RevenueCatController

    /// Packages from the most recent offerings fetch, keyed by product id —
    /// `purchase` uses the cached package when present so a network blip
    /// between listing and Confirm cannot degrade the flow to a silent
    /// plan-unavailable failure.
    @MainActor private static var packagesByProduct: [String: Package] = [:]

    init(purchases: RevenueCatController) {
        self.purchases = purchases
    }

    var isConfigured: Bool { purchases.configured }

    /// `Purchases.getOfferings() → current.availablePackages` mapped to plan
    /// cards (login.dart:448-462). Annual is identified by packageType
    /// (login.dart:581-583).
    func availablePlans() async throws -> [LoginPageModel.PlanCard] {
        guard purchases.configured else { throw StoreError.notConfigured }
        let offerings = try await Purchases.shared.offerings()
        let packages = offerings.current?.availablePackages ?? []
        Self.packagesByProduct = Dictionary(
            uniqueKeysWithValues: packages.map { ($0.storeProduct.productIdentifier, $0) }
        )
        return packages.map { package in
            LoginPageModel.PlanCard(
                productID: package.storeProduct.productIdentifier,
                period: package.packageType == .annual ? .annual : .monthly,
                priceString: package.localizedPriceString
            )
        }
    }

    /// `PurchaseParams.package → Purchases.purchase` (states/user.dart:306-315).
    /// The Dart caller only printed errors; failures now surface to the user
    /// (a silent Confirm is indistinguishable from a dead button), with the
    /// user-cancelled payment sheet exempt — cancelling is not an error.
    func purchase(_ card: LoginPageModel.PlanCard) async throws {
        guard purchases.configured else { throw StoreError.notConfigured }
        let package: Package
        if let cached = Self.packagesByProduct[card.productID] {
            package = cached
        } else {
            let offerings = try await Purchases.shared.offerings()
            guard let fetched = offerings.current?.availablePackages.first(where: {
                $0.storeProduct.productIdentifier == card.productID
            })
            else { throw StoreError.planUnavailable }
            package = fetched
        }
        do {
            _ = try await Purchases.shared.purchase(package: package)
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            // The user dismissed the system payment sheet.
        }
    }

    /// states/user.dart:317-330 — true only when the restored customer info
    /// has an active entitlement; every failure path returns false.
    func restorePurchases() async -> Bool {
        guard purchases.configured else { return false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            return !info.entitlements.active.isEmpty
        } catch {
            return false
        }
    }

    /// The `plus` entitlement's expirationDate (login.dart:363-368) — a true
    /// instant that the card renders in local time. Not the `/api/user`
    /// `expired_at` G11 wall-clock path.
    func plusExpirationDate() async -> Date? {
        guard purchases.configured else { return nil }
        guard let info = try? await Purchases.shared.customerInfo() else { return nil }
        return info.entitlements.active["plus"]?.expirationDate
    }
}

/// Firebase display fields for the User Info card (login.dart:165-199).
/// Gated on `AuthController.isFirebaseConfigured` — `Auth.auth()` raises when
/// unconfigured. T11 consolidation candidate: AuthController should expose
/// this itself instead of the sheet reading Firebase directly.
@MainActor
enum AuthAccountSnapshot {

    static func current(context: UIContext) -> LoginPageModel.AccountSnapshot {
        guard context.auth.isFirebaseConfigured else {
            return LoginPageModel.AccountSnapshot(
                uid: context.auth.currentUID, email: nil, providerID: nil
            )
        }
        let user = Auth.auth().currentUser
        return LoginPageModel.AccountSnapshot(
            uid: context.auth.currentUID ?? user?.uid,
            email: user?.email,
            providerID: user?.providerData.first?.providerID
        )
    }
}

/// The `Get.dialog(CircularProgressIndicator())` equivalent (login.dart:73-77,
/// 504-509): a full-screen, non-interactive spinner presented over everything
/// and dismissed by the caller when the flow ends.
@MainActor
final class FullScreenSpinnerViewController: UIViewController {

    private let indicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        indicator.color = UIColor.white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        indicator.startAnimating()
        // The presenting flow needs a window anchor for ASAuthorization /
        // GIDSignIn sheets (AuthController takes a presenting VC on purpose).
        view.isUserInteractionEnabled = true
    }

    /// Presents over `presenter` without animation and returns immediately
    /// (the Dart dialog appeared synchronously before the auth flow).
    @discardableResult
    static func present(over presenter: UIViewController) -> FullScreenSpinnerViewController {
        let controller = FullScreenSpinnerViewController()
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        controller.modalPresentationCapturesStatusBarAppearance = true
        presenter.present(controller, animated: false)
        return controller
    }

    func dismissSpinner(then completion: (() -> Void)? = nil) {
        dismiss(animated: false) { completion?() }
    }
}
