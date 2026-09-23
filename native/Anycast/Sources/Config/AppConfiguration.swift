import Foundation

/// Compile-time constants mirrored from the shipped app (docs/migration/02).
/// Secrets never live here — see `Secrets.swift` for the materialized file.
enum AppConfiguration {
    /// `https://anycast.website` (lib/api/podcasts.dart:8 et al.)
    static let apiHost = URL(string: "https://anycast.website")!

    /// Short-link domain, `https://s.kindjeff.com/<key>` (lib/api/share.dart).
    static let shortlinkHost = URL(string: "https://s.kindjeff.com")!

    /// sentry-cocoa DSN — identical to the Flutter line (lib/main.dart:56-57);
    /// a DSN is not a secret.
    static let sentryDSN = "https://9168d8befab4c7bb5eeecd15beb2daa2@o359483.ingest.us.sentry.io/4507654787170304"
    static let sentryTracesSampleRate = 1.0
    static let sentryProfilesSampleRate = 1.0

    /// RevenueCat: entitlement `plus`, iOS product `anycast_monthly`
    /// (docs/migration/02 §3.2).
    static let plusEntitlementID = "plus"
    static let monthlyProductID = "anycast_monthly"

    /// App Group shared with the Share Extension — keep the historical
    /// spelling ("Extention") exactly; renaming orphans the stored payloads.
    static let appGroupID = "group.com.kindjeff.ShareExtention"

    /// RSS direct fetches send a generic browser UA (decision K20: the old
    /// `Dart/x.y` UA is replaced; our own API uses the native UA, RSS sources
    /// are UA-sensitive).
    static let rssUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// `Documents/anycast.db` — sqflite resolves getDatabasesPath() to the
    /// Documents directory on iOS (docs/migration/01 §1.1).
    static func mainDatabaseURL(documents: URL) -> URL {
        documents.appendingPathComponent("anycast.db")
    }

    /// `Library/Application Support/anycast_episode.db` — audio cache index
    /// (docs/migration/01 §1.2).
    static func episodeCacheMetaDatabaseURL(appSupport: URL) -> URL {
        appSupport.appendingPathComponent("anycast_episode.db")
    }
}

/// Runtime secrets. The bundle contains an optional `Secrets.plist`
/// (gitignored; materialized by the maintainer/CI the same way `.env` is on
/// the Flutter line). Missing keys disable the corresponding SDK — the L0–L2
/// test suites never need them.
struct Secrets {
    static func purchasesAPIKey(bundle: Bundle = .main) -> String? {
        string(for: "PURCHASES_IOS_API_KEY", bundle: bundle)
    }

    private static func string(for key: String, bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: String]
        else { return nil }
        let value = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}
