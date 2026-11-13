#if DEBUG
import Foundation

/// DEBUG-only account and store states for looking at every Plus surface in
/// the simulator without a real sign-in or purchase. Launch arguments:
///
///     -plus-state signedOut | free | freeExhausted | member
///     -paywall-products loading | loaded | failed
///
/// They replace the *inputs* the screens render from (account snapshot,
/// entitlement flag and details, remaining count, the offerings fetch). They
/// never touch RevenueCat or the server, and the whole file is compiled out
/// of Release builds.
@MainActor
enum PlusDebug {

    enum State: String {
        case signedOut, free, freeExhausted, member

        var signedIn: Bool { self != .signedOut }
        var isSubscribed: Bool { self == .member }

        var remaining: Int? {
            switch self {
            case .signedOut: nil
            case .free: 7
            case .freeExhausted: 0
            case .member: 32
            }
        }

        var snapshot: LoginPageModel.AccountSnapshot {
            signedIn
                ? LoginPageModel.AccountSnapshot(uid: "debug-uid", email: "listener@example.com", providerID: "apple.com")
                : LoginPageModel.AccountSnapshot(uid: nil, email: nil, providerID: nil)
        }

        var plusStatus: AccountPageModel.PlusStatus? {
            guard self == .member else { return nil }
            return AccountPageModel.PlusStatus(
                isActive: true, willRenew: true,
                expirationDate: Calendar.current.date(byAdding: .day, value: 214, to: Date()),
                period: .annual
            )
        }
    }

    enum Products: String {
        case loading, loaded, failed
    }

    /// Settable so hosted tests can switch states in-process.
    static var state: State? = value(after: "-plus-state").flatMap(State.init(rawValue:))
    static var products: Products? = value(after: "-paywall-products").flatMap(Products.init(rawValue:))

    /// Plans for `-paywall-products loaded`. Store-shaped, clearly sample
    /// values; the real paywall always renders what the store returns.
    static let samplePlans = PaywallModel.Plans(
        yearly: PaywallModel.Plan(
            productID: "debug.yearly", period: .yearly, price: Decimal(string: "23.99")!,
            currencyCode: "USD", localeIdentifier: "en_US", priceString: "$23.99"
        ),
        monthly: PaywallModel.Plan(
            productID: "debug.monthly", period: .monthly, price: Decimal(string: "2.99")!,
            currencyCode: "USD", localeIdentifier: "en_US", priceString: "$2.99"
        ),
        yearlyTrialEligible: true
    )

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
#endif
