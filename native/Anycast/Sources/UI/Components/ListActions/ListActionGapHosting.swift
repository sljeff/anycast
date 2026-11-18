import UIKit

/// A list-owned group is a sibling behind the cells. Its spacer must decline
/// hit testing so the collection view can reach that sibling through the gap.
@MainActor
protocol ListActionGapHosting: AnyObject {
    var actionGap: CGFloat { get }
    func setActionGap(_ gap: CGFloat)
    var cardFrameInCell: CGRect { get }
}
