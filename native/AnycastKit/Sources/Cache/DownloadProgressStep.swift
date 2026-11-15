import Foundation

/// Download progress arrives once per network chunk — dozens of times a
/// second on a fast connection. The UI only draws whole percents, so a new
/// value is worth storing (and re-rendering) only when it reaches the next
/// percent, or completes.
public enum DownloadProgressStep {

    public static func isVisibleChange(from old: Double?, to new: Double) -> Bool {
        guard let old else { return true }
        if new >= 1 { return old < 1 }
        return percent(new) != percent(old)
    }

    private static func percent(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded(.down))
    }
}
