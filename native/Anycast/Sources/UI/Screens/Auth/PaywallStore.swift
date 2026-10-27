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

    enum StoreError: LocalizedError {
        case notConfigured
        case planUnavailable

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Purchases aren't available right now."
            case .planUnavailable: "That plan isn't available right now."
            }
        }
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

    /// How a purchase attempt ended.
    enum PurchaseOutcome: Equatable {
        /// The customer now has an active entitlement.
        case purchased
        /// The user dismissed the system payment sheet.
        case cancelled
        /// The store accepted the request but no entitlement is active yet
        /// (for example Ask to Buy); nothing to report.
        case pending
    }

    /// The current offering's yearly and monthly packages as paywall plans,
    /// plus the yearly plan's trial eligibility (unknown counts as not
    /// eligible). Throws when RevenueCat is unconfigured or the fetch fails.
    func loadPlans() async throws -> PaywallModel.Plans {
        guard purchases.configured else { throw StoreError.notConfigured }
        let offerings = try await Purchases.shared.offerings()
        let packages = offerings.current?.availablePackages ?? []
        Self.packagesByProduct = Dictionary(
            packages.map { ($0.storeProduct.productIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let yearly = packages.first { $0.packageType == .annual }
        let monthly = packages.first { $0.packageType == .monthly }
        var eligible = false
        if let yearly {
            let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(packages: [yearly])
            eligible = result[yearly]?.status.isEligible ?? false
        }
        return PaywallModel.Plans(
            yearly: yearly.map { Self.plan($0, period: .yearly) },
            monthly: monthly.map { Self.plan($0, period: .monthly) },
            yearlyTrialEligible: eligible
        )
    }

    private static func plan(_ package: Package, period: PaywallModel.Period) -> PaywallModel.Plan {
        let product = package.storeProduct
        let formatter = product.priceFormatter
        return PaywallModel.Plan(
            productID: product.productIdentifier,
            period: period,
            price: product.price,
            currencyCode: product.currencyCode ?? formatter?.currencyCode ?? "USD",
            localeIdentifier: formatter?.locale.identifier ?? Locale.current.identifier,
            priceString: product.localizedPriceString
        )
    }

    /// Buys the cached package for `productID` (re-fetching offerings when
    /// the cache is cold) and reports whether an entitlement is active after.
    func purchase(productID: String) async throws -> PurchaseOutcome {
        guard purchases.configured else { throw StoreError.notConfigured }
        let package: Package
        if let cached = Self.packagesByProduct[productID] {
            package = cached
        } else {
            let offerings = try await Purchases.shared.offerings()
            guard let fetched = offerings.current?.availablePackages.first(where: {
                $0.storeProduct.productIdentifier == productID
            })
            else { throw StoreError.planUnavailable }
            package = fetched
        }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return .cancelled }
            return result.customerInfo.entitlements.active.isEmpty ? .pending : .purchased
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            return .cancelled
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

    /// The `plus` entitlement's state for the Membership page and the
    /// Settings identity row; nil when RevenueCat is not configured, the
    /// fetch fails, or the account never had Plus.
    func plusStatus() async -> AccountPageModel.PlusStatus? {
        guard purchases.configured else { return nil }
        guard let info = try? await Purchases.shared.customerInfo(),
              let plus = info.entitlements.all["plus"] else { return nil }
        return AccountPageModel.PlusStatus(
            isActive: plus.isActive,
            isTrial: plus.periodType == .trial,
            willRenew: plus.willRenew,
            hasBillingIssue: plus.billingIssueDetectedAt != nil,
            expirationDate: plus.expirationDate,
            period: plus.productIdentifier.contains("annual") ? .annual : .monthly
        )
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
