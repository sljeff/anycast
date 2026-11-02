import Foundation

/// What a list shows while a fetch is in flight. An empty list gets a
/// skeleton; a list that already has rows keeps them and shows a small
/// indicator instead of a blocking spinner.
nonisolated enum MotionLoading {

    struct Chrome: Equatable, Sendable {
        var showSkeleton: Bool
        var showSubtleIndicator: Bool
    }

    nonisolated static func chrome(isLoading: Bool, hasContent: Bool) -> Chrome {
        Chrome(
            showSkeleton: isLoading && !hasContent,
            showSubtleIndicator: isLoading && hasContent
        )
    }
}
