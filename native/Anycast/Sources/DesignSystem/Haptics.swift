import UIKit

/// The one map from user events to haptic feedback (Anycast 2.0 UI kit
/// `AnycastHaptics`); screens call these names, never a generator directly.
@MainActor
enum Haptics {
    /// Any button press.
    static func tap() { impact(.light) }
    /// Tab, chip or segment selection.
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Grabbing the scrubber (drag start).
    static func scrubberGrab() { impact(.light) }
    /// A seek lands (tap or drag release).
    static func seekCommit() { impact(.light) }
    /// Added to the playlist — slightly heavier than removal.
    static func queueAdded() { impact(.medium) }
    /// Removed from the playlist or inbox.
    static func queueRemoved() { impact(.light) }
    /// Sleep timer set or cancelled.
    static func timerSet() { impact(.medium) }
    /// A press-and-hold destructive action completed.
    static func confirm() { UINotificationFeedbackGenerator().notificationOccurred(.success) }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
