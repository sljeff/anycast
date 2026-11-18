import UIKit

nonisolated enum ListActionMetrics {
    static let circle: CGFloat = 56
    static let spacing: CGFloat = 12
    static let itemInset: CGFloat = 16
    /// The existing 12 pt inter-item spacing supplies the space AFTER the circles.
    static let gap: CGFloat = circle + spacing
    static let travellingHitOutset: CGFloat = 8
}

nonisolated enum ListActionMotion {
    static let duration: TimeInterval = 0.32
    static let shrinkDuration: TimeInterval = 0.26
    static let fadeIn: TimeInterval = 0.15
    static let fadeOut: TimeInterval = 0.12
    static let leaveDuration: TimeInterval = 0.14
    static let translationKey = "list-actions-position"

    static var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
    }

    static var reduceMotion: Bool { Motion.reduceMotion }
}
