import Foundation
import CryptoKit

/// Short-link request construction (api/share.dart, G12). The password is a
/// hard contract; md5 must be 32-char lowercase hex; body key order is
/// cmd → url → password → key.
public enum Shortlink {

    public static let password = "cjp2PGN3zuf5cfh"

    /// MD5 as lowercase hex (getMd5).
    public static func md5Hex(of input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// The exact POST body bytes.
    public static func requestBody(for url: String) -> String {
        let key = md5Hex(of: url)
        return "{\"cmd\":\"add\",\"url\":\(jsonString(url)),\"password\":\(jsonString(Shortlink.password)),\"key\":\(jsonString(key))}"
    }

    /// `https://s.kindjeff.com/<key>` when the service answered
    /// `{"status":200,"key":…}`; nil on any failure → callers degrade to the
    /// original long URL (that degradation itself is contract).
    public static func shortURL(fromResponseBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let status = object["status"] as? Int, status == 200,
              let key = object["key"] as? String
        else { return nil }
        return "https://s.kindjeff.com/\(key)"
    }

    /// JSON string escaping for the hand-built body: escapes `"`, `\`,
    /// control characters; leaves everything else (including `/` and
    /// non-ASCII) raw — matching jsonEncode byte output for these inputs.
    private static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
