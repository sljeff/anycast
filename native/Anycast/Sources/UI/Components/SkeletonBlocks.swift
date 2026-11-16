import UIKit

/// The one clock every skeleton on screen sweeps to. The epoch is the first
/// moment any skeleton asked for it; each sweep animation starts at that
/// absolute media time, so blocks created at different moments (a cell
/// dequeued later, a second page) are at the same point of the same cycle.
enum SkeletonClock {

    /// One sweep, left to right.
    static let period: CFTimeInterval = 1.4

    /// Shared origin of every sweep (absolute `CACurrentMediaTime`).
    static let epoch: CFTimeInterval = CACurrentMediaTime()

    /// Where in the cycle `time` falls, 0..<1.
    static func phase(at time: CFTimeInterval = CACurrentMediaTime()) -> Double {
        let elapsed = max(0, time - epoch)
        return elapsed.truncatingRemainder(dividingBy: period) / period
    }
}

/// One rounded placeholder block, in the overlay's coordinates.
struct SkeletonBlock: Equatable {
    var frame: CGRect
    var cornerRadius: CGFloat
}

/// What a real view contributes to a skeleton.
enum SkeletonShape {
    /// A block over the view's frame with the view's own corner radius (the
    /// cover).
    case cover(UIView)
    /// One rounded bar per text line inside the label's frame; the numbers
    /// are each line's width as a fraction of the label's width. The label
    /// holds placeholder text (invisible) so it takes its real line height
    /// and its real number of lines.
    case lines(UILabel, [CGFloat])
}

/// The shared skeleton: rounded blocks drawn from the geometry of the REAL
/// views of the cell that hosts it, and one soft highlight sweeping left to
/// right across all of them. Blocks are laid out from the real labels and
/// cover, so the skeleton card is the loaded card's size by construction.
///
/// The sweep is a single gradient masked by the blocks, driven by
/// `SkeletonClock`: every skeleton view shares one period and one start
/// time, so they shimmer in unison. With Reduce Motion the blocks stay still.
final class SkeletonBlocksView: UIView {

    static let sweepKey = "skeleton.sweep"
    /// A bar fills this share of its line.
    static let barShareOfLine: CGFloat = 0.6

    /// The real views the blocks are drawn from.
    var shapes: [SkeletonShape] = [] {
        didSet { setNeedsLayout() }
    }

    /// Injection seam for the Reduce Motion setting (tests).
    var reduceMotion: () -> Bool = { Motion.reduceMotion } {
        didSet { refreshSweep() }
    }

    private(set) var blocks: [SkeletonBlock] = []

    private let baseLayer = CAShapeLayer()
    private let highlightLayer = CAGradientLayer()
    private let highlightMask = CAShapeLayer()
    private nonisolated(unsafe) var tokens: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear

        highlightLayer.startPoint = CGPoint(x: -0.5, y: 0.5)
        highlightLayer.endPoint = CGPoint(x: 0, y: 0.5)
        highlightLayer.locations = [0, 0.5, 1]
        highlightLayer.isHidden = true
        highlightLayer.mask = highlightMask
        highlightMask.fillColor = UIColor.white.cgColor
        layer.addSublayer(baseLayer)
        layer.addSublayer(highlightLayer)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateColors()
        }

        let center = NotificationCenter.default
        tokens = [
            center.addObserver(forName: Motion.reduceMotionDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSweep() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSweep() }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }

    /// The highlight's sweep, nil while nothing runs (no window, hidden,
    /// Reduce Motion, no blocks).
    var sweepAnimation: CAAnimationGroup? {
        highlightLayer.animation(forKey: Self.sweepKey) as? CAAnimationGroup
    }

    override var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            if !isHidden { setNeedsLayout() }
            refreshSweep()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshSweep()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshBlocks()
    }

    // MARK: - Blocks

    /// Re-reads the real views' frames. The host calls this after its own
    /// layout; layout of this view calls it too.
    func refreshBlocks() {
        blocks = shapes.flatMap(blocks(for:))
        let path = UIBezierPath()
        for block in blocks {
            path.append(UIBezierPath(roundedRect: block.frame, cornerRadius: block.cornerRadius))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.frame = bounds
        baseLayer.path = path.cgPath
        highlightLayer.frame = bounds
        highlightMask.frame = bounds
        highlightMask.path = path.cgPath
        CATransaction.commit()
        if sweepAnimation == nil { refreshSweep() }
    }

    private func blocks(for shape: SkeletonShape) -> [SkeletonBlock] {
        switch shape {
        case .cover(let view):
            let frame = view.convert(view.bounds, to: self)
            guard frame.width > 0, frame.height > 0 else { return [] }
            return [SkeletonBlock(frame: frame, cornerRadius: view.layer.cornerRadius)]
        case .lines(let label, let widths):
            let frame = label.convert(label.bounds, to: self)
            guard frame.width > 0, frame.height > 0, !widths.isEmpty else { return [] }
            let lineHeight = frame.height / CGFloat(widths.count)
            let barHeight = (lineHeight * Self.barShareOfLine).rounded()
            return widths.enumerated().map { index, fraction in
                let y = frame.minY + CGFloat(index) * lineHeight + (lineHeight - barHeight) / 2
                return SkeletonBlock(
                    frame: CGRect(x: frame.minX, y: y, width: frame.width * fraction, height: barHeight),
                    cornerRadius: barHeight / 2
                )
            }
        }
    }

    // MARK: - Sweep

    private func updateColors() {
        let traits = traitCollection
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.fillColor = AnycastColor.sandAlpha4.resolvedColor(with: traits).cgColor
        let lift = Theme.surface.resolvedColor(with: traits).withAlphaComponent(0.7).cgColor
        highlightLayer.colors = [UIColor.clear.cgColor, lift, UIColor.clear.cgColor]
        CATransaction.commit()
    }

    /// Starts (or stops) the sweep to match the current state. The band is
    /// half the overlay wide; it enters past the left edge and leaves past
    /// the right one. The start time is the shared epoch, never "now".
    func refreshSweep() {
        highlightLayer.removeAnimation(forKey: Self.sweepKey)
        let sweeps = window != nil && !isHidden && !blocks.isEmpty && !reduceMotion()
        highlightLayer.isHidden = !sweeps
        guard sweeps else { return }

        let start = CABasicAnimation(keyPath: "startPoint")
        start.fromValue = CGPoint(x: -0.5, y: 0.5)
        start.toValue = CGPoint(x: 1, y: 0.5)
        let end = CABasicAnimation(keyPath: "endPoint")
        end.fromValue = CGPoint(x: 0, y: 0.5)
        end.toValue = CGPoint(x: 1.5, y: 0.5)

        let group = CAAnimationGroup()
        group.animations = [start, end]
        group.duration = SkeletonClock.period
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.isRemovedOnCompletion = false
        group.beginTime = highlightLayer.convertTime(SkeletonClock.epoch, from: nil)
        highlightLayer.add(group, forKey: Self.sweepKey)
    }
}

extension UIView {

    /// Adds a skeleton overlay pinned to this view's edges.
    func installSkeletonOverlay() -> SkeletonBlocksView {
        let overlay = SkeletonBlocksView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        return overlay
    }
}

/// A grouped plate of skeleton channel rows for a page that has no list yet
/// (Discover while its categories load). The rows are real `PodcastCardCell`s
/// on the real grouped layout, so the plate, the insets and the rows are
/// what the loaded list will use.
final class PodcastSkeletonListView: UIView, UICollectionViewDataSource {

    static let rowCount = 7

    private let collectionView = UICollectionView(
        frame: .zero, collectionViewLayout: PodcastCardCell.makeGroupedLayout()
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.register(PodcastCardCell.self, forCellWithReuseIdentifier: PodcastCardCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.rowCount
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PodcastCardCell.reuseIdentifier, for: indexPath
        ) as! PodcastCardCell
        cell.setPosition(isFirst: indexPath.item == 0, isLast: indexPath.item == Self.rowCount - 1)
        cell.configureSkeleton()
        return cell
    }
}
