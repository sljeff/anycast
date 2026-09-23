import Foundation

/// Web-player share URLs (red line 11, docs/migration/02 §6): the query
/// keys are lowercased EXACTLY as the web app expects — `rssfeedurl`,
/// `enclosureurl` — and the values use the Dart `Uri(queryParameters:)`
/// encoding (space → `+`, `+` → `%2B`). These URLs also feed the shortlink
/// endpoint (their md5 keys are over this exact string), so a single
/// changed character breaks both the share target and the short link.
public enum ShareURL {

    /// `https://anycast.website/player?rssfeedurl=…&enclosureurl=…`
    /// (player.dart:251-258, widgets/detail.dart:174-183).
    public static func player(rssFeedURL: String, enclosureURL: String) -> String {
        "https://anycast.website/player?"
            + dartQuery(rssFeedURL, name: "rssfeedurl")
            + "&"
            + dartQuery(enclosureURL, name: "enclosureurl")
    }

    /// `https://anycast.website/channel?rssfeedurl=…` (channel.dart:379-385).
    public static func channel(rssFeedURL: String) -> String {
        "https://anycast.website/channel?" + dartQuery(rssFeedURL, name: "rssfeedurl")
    }

    private static func dartQuery(_ value: String, name: String) -> String {
        "\(name)=\(APIClient.dartQueryComponent(value))"
    }
}
