import Foundation

/// GET /api/user response (G11). `expired_at` is ISO with offset; `plus` is
/// 0/1; a field-level decode failure maps to nil (the Dart fromJson throws
/// and callers return null) rather than an error.
public struct User: Equatable, Sendable {

    public var uid: String
    /// Epoch milliseconds; nil = not Plus.
    public var expireAtEpochMilliseconds: Int64?
    public var remaining: Int
    public var plus: Int

    public init(uid: String, expireAtEpochMilliseconds: Int64?, remaining: Int, plus: Int) {
        self.uid = uid
        self.expireAtEpochMilliseconds = expireAtEpochMilliseconds
        self.remaining = remaining
        self.plus = plus
    }

    /// User.fromJson (api/user.dart:17-31) with Jiffy's
    /// `yyyy-MM-ddTHH:mm:ssZ` tolerance — implemented via the Dart ISO
    /// parser, which covers `Z`, `±HH:MM` and `±HHMM` forms.
    public static func from(jsonBody data: Data) -> User? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let uid = object["uid"] as? String,
              let remaining = object["remaining"] as? Int,
              let plus = object["plus"] as? Int
        else { return nil }

        var expireAt: Int64?
        if let raw = object["expired_at"] as? String {
            // Jiffy(`yyyy-MM-ddTHH:mm:ssZ`) parses the WALL time into the
            // device's local zone and discards the parsed offset — the
            // shipped behavior (pinned by G11, exported on a UTC+8 host:
            // "09:30:00+00:00" → 01:30Z). Strip the suffix and parse as
            // local to match.
            let wall = raw.replacingOccurrences(
                of: #"(Z|[+-]\d\d:?(\d\d)?)$"#,
                with: "",
                options: .regularExpression
            )
            expireAt = DartDate.parseToEpochMilliseconds(wall)
        }
        return User(uid: uid, expireAtEpochMilliseconds: expireAt, remaining: remaining, plus: plus)
    }
}
