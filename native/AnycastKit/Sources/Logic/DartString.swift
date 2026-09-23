import Foundation

/// Dart `String.trim()` parity (K40). Verified against both runtimes on
/// 2026-09-23 over White_Space ∪ format candidates:
/// - both trim all of Unicode White_Space (09-0D, 20, 85, A0, 1680,
///   2000-200A, 2028, 2029, 202F, 205F, 3000);
/// - Dart ADDITIONALLY trims U+FEFF (Swift's `.whitespacesAndNewlines`
///   does not);
/// - Swift ADDITIONALLY trims U+200B (zero-width space; Dart does not);
/// - neither trims U+180E / U+2060.
/// So the parity set = `.whitespacesAndNewlines` − 200B + FEFF.
///
/// Use everywhere the Dart line calls `.trim()` — `subscription.title` is a
/// UNIQUE key, so a single trailing FEFF would otherwise turn a re-import
/// into a second row.
extension String {

    private static let dartTrimSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.remove(charactersIn: "\u{200B}")
        set.insert(charactersIn: "\u{FEFF}")
        return set
    }()

    public func dartTrimmed() -> String {
        trimmingCharacters(in: Self.dartTrimSet)
    }
}
