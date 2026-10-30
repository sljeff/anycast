import UIKit

/// The lyrics renderer (self-drawn widget #1, docs/migration/07 §2.5):
/// a line-granular UICollectionView port of the flutter_lyric
/// configuration in lib/pages/player.dart:958-991 —
/// - one cell per LRC line; the optional translation renders inside the
///   same cell as a second paragraph (`translationLineGap` 6 below the
///   main text), so a bilingual pair is a single selectable row;
/// - main 14 pt grey[200] → active 16 pt greenAccent; translation
///   greenAccent → grey[300] when active (reversed colors, 03 §2.10);
/// - `lineGap` 12, content padding top 100 / sides 20 / bottom 100,
///   anchor 0.5 (active line vertically centered);
/// - scroll animation 240 ms easeOutCubic, 500 ms ≥500 pt; longer than the
///   viewport jumps without animation (no empty list in flight);
/// - top/bottom soft edges as an alpha-gradient mask on a NON-scrolling
///   wrapper (`fadeHost`). The page backdrop is a gradient, so
///   `ScrollEdgeChrome`'s solid page-colour scrim would show as dark bands,
///   and the fade must never live on the scrolling layer: a UIScrollView's
///   layer bounds origin is its contentOffset, so a mask there stays at the
///   content top and blanks every line once the list scrolls a viewport;
/// - a user drag stops following for good (`LyricsFollowStateMachine`);
///   `returnToNow()` scrolls back to the active line and resumes it;
/// - tapping a line reports it (the page seeks); the list itself never
///   scrolls for a tap, so the touched line stays put and only the
///   highlight moves;
/// - long-pressing a line shows a context menu with a preview of the line.
final class LyricsView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    // Dart _lyricStyle values (player.dart:981-986 over default1).
    static let lineGap: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 100
    static let bottomPadding: CGFloat = 100
    static let lineHeightMultiple: CGFloat = 1.35
    /// Length of the top/bottom fade ramps.
    static let edgeLength: CGFloat = 48
    /// How long after a tap-jump position ticks that still report the old
    /// line are ignored (the seek is asynchronous).
    private static let jumpGraceSeconds: TimeInterval = 1.5

    /// Line tap → the page seeks to the line's start.
    var onTapLine: ((Int) -> Void)?
    /// Fires when following starts or stops (true = following).
    var onFollowingChanged: ((Bool) -> Void)?
    /// Builds the long-press menu for a line; nil = no menu for that line.
    var contextMenuProvider: ((Int) -> UIMenu?)?

    private(set) var lines: [LyricLine] = []
    private(set) var activeIndex: Int = 0
    private var follow = LyricsFollowStateMachine()
    private var scrollAnimator: UIViewPropertyAnimator?
    /// The line a tap just jumped to, until a position tick confirms it.
    private var pendingJump: (index: Int, deadline: Date)?

    var isFollowing: Bool { follow.mode == .following }

    /// The text of the active line (empty for spacer lines).
    var activeLineText: String? {
        guard lines.indices.contains(activeIndex) else { return nil }
        let text = lines[activeIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// flutter_lyric `activeAnchorPosition` (default1's 0.48,
    /// lyric_style.dart:168): the active line centers slightly above the
    /// viewport middle.
    static let activeAnchorFraction: CGFloat = 0.48

    private let layout = LyricsLinearLayout()
    private let fadeHost = UIView()
    private let fadeMask = CAGradientLayer()
    /// Internal for the hosted regression tests (visibility checks).
    let collectionView: UICollectionView
    private var cellRegistration: UICollectionView.CellRegistration<LyricLineCell, Int>?

    init() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        // The player is always dark; the line context menu and its preview
        // follow this view's traits.
        overrideUserInterfaceStyle = .dark
        layout.view = self

        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.canCancelContentTouches = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        fadeHost.translatesAutoresizingMaskIntoConstraints = false
        fadeHost.layer.mask = fadeMask
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        fadeMask.colors = [UIColor.clear, .white, .white, UIColor.clear].map(\.cgColor)
        addSubview(fadeHost)
        fadeHost.addSubview(collectionView)

        NSLayoutConstraint.activate([
            fadeHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            fadeHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeHost.topAnchor.constraint(equalTo: topAnchor),
            fadeHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: fadeHost.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: fadeHost.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: fadeHost.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: fadeHost.bottomAnchor),
        ])

        cellRegistration = UICollectionView.CellRegistration<LyricLineCell, Int> {
            [weak self] (cell: LyricLineCell, indexPath: IndexPath, _: Int) in
            guard let self else { return }
            cell.configure(
                line: self.lines[indexPath.item],
                isActive: indexPath.item == self.activeIndex,
                traits: self.traitCollection
            )
            cell.onActivate = { [weak self] in self?.onTapLine?(indexPath.item) }
        }

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: LyricsView, _: UITraitCollection) in
            view.rebuildForTraits()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        guard height > 0 else { return }
        let ramp = min(Self.edgeLength / height, 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = fadeHost.bounds
        fadeMask.locations = [0, NSNumber(value: ramp), NSNumber(value: 1 - ramp), 1]
        CATransaction.commit()
    }

    // MARK: - Document / progress

    /// Replaces the lines. Follows the active line when following; a
    /// detached list keeps its place (clamped to the new content).
    func updateDocument(lines: [LyricLine], positionMilliseconds: Int = 0) {
        self.lines = lines
        activeIndex = LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: positionMilliseconds)
        pendingJump = nil
        layout.invalidateLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        if isFollowing {
            scrollToActiveLine(animated: false)
        } else {
            let clamped = min(max(collectionView.contentOffset.y, 0), maxOffset)
            collectionView.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
        }
    }

    /// `ever(positionData)` → `setProgress` (player.dart:1019-1021). The
    /// four-condition progress filter lives in the playback service (K11);
    /// this only renders what arrives.
    func setProgress(positionMilliseconds: Int) {
        let index = LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: positionMilliseconds)
        if let pendingJump {
            // A tap just moved the highlight; the seek lands a moment
            // later, and ticks that still report the old line must not
            // pull the highlight (and the list) back.
            if index == pendingJump.index || Date() >= pendingJump.deadline {
                self.pendingJump = nil
            } else {
                return
            }
        }
        guard index != activeIndex else { return }
        activeIndex = index
        reconfigureVisibleCells()
        layout.invalidateLayout()
        // Prepare synchronously: the target offset reads the layout's
        // frames, which must already carry the new active line's (taller)
        // measurement — without this the scroll lands a few points off.
        collectionView.layoutIfNeeded()
        if isFollowing {
            scrollToActiveLine(animated: true)
        }
    }

    /// Moves the highlight to a tapped line without scrolling: the touched
    /// line stays exactly where it is and only the highlight changes.
    func jump(toLine index: Int) {
        guard lines.indices.contains(index) else { return }
        pendingJump = (index, Date().addingTimeInterval(Self.jumpGraceSeconds))
        guard index != activeIndex else { return }
        activeIndex = index
        reconfigureVisibleCells()
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
    }

    /// "Back to now": scrolls to the active line and resumes following.
    func returnToNow() {
        setFollow(.backToNowRequested)
        scrollToActiveLine(animated: true)
    }

    /// A fresh document starts out following again.
    func resetFollowing() {
        setFollow(.backToNowRequested)
    }

    private func setFollow(_ event: LyricsFollowStateMachine.Event) {
        let was = isFollowing
        follow.handle(event)
        if was != isFollowing { onFollowingChanged?(isFollowing) }
    }

    // MARK: - UICollectionViewDataSource / Delegate

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        lines.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: cellRegistration!, for: indexPath, item: indexPath.item
        )
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onTapLine?(indexPath.item)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let index = indexPath.item
        guard lines.indices.contains(index),
              !lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let menu = contextMenuProvider?(index)
        else { return nil }
        let line = lines[index]
        let width = bounds.width - Self.horizontalPadding * 2
        return UIContextMenuConfiguration(
            identifier: indexPath as NSCopying,
            previewProvider: { LyricLinePreviewViewController(line: line, width: width) },
            actionProvider: { _ in menu }
        )
    }

    // MARK: - UIScrollViewDelegate (drag detaches)

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A user drag must win over an in-flight follow scroll: stop the
        // running animator where it currently is and cancel the collection
        // view's residual scrolling, so the drag starts from under the
        // finger instead of fighting the animator.
        if scrollAnimator?.state == .active {
            scrollAnimator?.stopAnimation(true)
            scrollAnimator?.finishAnimation(at: .current)
        }
        scrollAnimator = nil
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        setFollow(.dragBegan)
    }

    // MARK: - Follow scrolling

    /// Center the active line on the 0.48 active anchor. Duration ladder from
    /// default1 `scrollDurations` (240 / 500 ms) on easeOutCubic.
    private func scrollToActiveLine(animated: Bool) {
        guard collectionView.bounds.height > 0 else { return }
        let target = layout.targetOffset(
            forLine: activeIndex, viewportHeight: collectionView.bounds.height
        )
        applyOffset(target, animated: animated)
    }

    private func applyOffset(_ target: CGFloat, animated: Bool) {
        scrollAnimator?.stopAnimation(true)
        let clamped = min(max(target, 0), maxOffset)
        guard animated else {
            collectionView.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
            return
        }
        let distance = abs(collectionView.contentOffset.y - clamped)
        // A property-animated contentOffset only lays out cells for the
        // final bounds, so a scroll longer than the viewport shows an empty
        // list in flight (a far seek, Back to now): jump instead.
        if distance < 0.1 || distance > collectionView.bounds.height {
            collectionView.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
            return
        }
        let duration: TimeInterval = distance >= 500 ? 0.5 : 0.24
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.215, y: 0.61),
                controlPoint2: CGPoint(x: 0.355, y: 1)
            )
        )
        animator.addAnimations { [weak self] in
            self?.collectionView.contentOffset = CGPoint(x: 0, y: clamped)
        }
        animator.startAnimation()
        scrollAnimator = animator
    }

    private var maxOffset: CGFloat {
        max(
            0,
            layout.collectionViewContentSize.height + collectionView.contentInset.bottom
                - collectionView.bounds.height
        )
    }

    // MARK: - Traits / cells

    private func reconfigureVisibleCells() {
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return }
        collectionView.reconfigureItems(at: visible)
    }

    private func rebuildForTraits() {
        layout.invalidateLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        scrollToActiveLine(animated: false)
    }

    deinit {
        MainActor.assumeIsolated {
            scrollAnimator?.stopAnimation(true)
        }
    }
}

// MARK: - Cell

/// One lyric line: a single label whose attributed string carries the main
/// paragraph and, when aligned, the translation paragraph 6 pt below
/// (docs/migration/07 §2.5 — one UILabel styled through a two-paragraph
/// NSAttributedString).
final class LyricLineCell: UICollectionViewCell {

    private let label = UILabel()

    /// VoiceOver double-tap on the line — the same jump-to-line the
    /// collection view's didSelectItemAt serves for touch. Deliberately NO
    /// `.button` trait: the line's semantics stay "text with selection
    /// state"; only the activation hook is added.
    var onActivate: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: LyricsView.horizontalPadding),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -LyricsView.horizontalPadding),
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }

    func configure(line: LyricLine, isActive: Bool, traits: UITraitCollection?) {
        label.attributedText = LyricsTextStyling.attributedText(
            for: line, isActive: isActive, traits: traits
        )
        accessibilityLabel = [line.text, line.translation ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityTraits = isActive ? [.staticText, .selected] : .staticText
        accessibilityHint = "Plays from this line"
    }
}

// MARK: - Text styling

/// Lyric typography: `TypographyV2.body` for the line and `TypographyV2.meta`
/// for its translation, with `height: 1.35` paragraphs; the follow highlight
/// is brightness only (Anycast 2.0 transcript).
enum LyricsTextStyling {

    /// The active line's translation: one step below the active main line.
    static let activeTranslationColor = Theme.playerSecondary

    /// The inactive line's translation: dimmer than the main line.
    static let translationColor = Theme.playerSecondary.withAlphaComponent(0.55)

    static func attributedText(
        for line: LyricLine,
        isActive: Bool,
        traits: UITraitCollection?
    ) -> NSAttributedString {
        let mainColor = isActive ? Theme.playerText : Theme.playerSecondary
        let translationColor = isActive
            ? activeTranslationColor
            : Self.translationColor

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = LyricsView.lineHeightMultiple
        paragraph.paragraphSpacing = Self.translationParagraphSpacing

        let attributed = NSMutableAttributedString()
        let mainAttributes: [NSAttributedString.Key: Any] = [
            .font: TypographyV2.body.font(traits: traits),
            .foregroundColor: mainColor,
            .paragraphStyle: paragraph,
        ]
        attributed.append(NSAttributedString(string: line.text, attributes: mainAttributes))
        if let translation = line.translation, !translation.isEmpty {
            let translationAttributes: [NSAttributedString.Key: Any] = [
                .font: TypographyV2.meta.font(traits: traits),
                .foregroundColor: translationColor,
                .paragraphStyle: paragraph,
            ]
            attributed.append(NSAttributedString(string: "\n"))
            attributed.append(NSAttributedString(string: translation, attributes: translationAttributes))
        }
        return attributed
    }

    /// Text height at a given width for both active variants (the Dart
    /// layout measures the normal and active painters of every line).
    static func heights(
        for line: LyricLine,
        width: CGFloat,
        traits: UITraitCollection?
    ) -> (normal: CGFloat, active: CGFloat) {
        let width = max(width, 1)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let normal = ceil(attributedText(for: line, isActive: false, traits: traits)
            .boundingRect(with: constraint, options: options, context: nil).height)
        let active = ceil(attributedText(for: line, isActive: true, traits: traits)
            .boundingRect(with: constraint, options: options, context: nil).height)
        return (normal, active)
    }

    /// Static paragraph style for measurement calls that do not need the
    /// attributed string itself.
    static let translationParagraphSpacing: CGFloat = 6
}

// MARK: - Layout

/// Deterministic line layout: frames are computed from pre-measured text
/// heights (Dart `LyricLayout.compute`), so follow offsets are exact —
/// no self-sizing dance.
final class LyricsLinearLayout: UICollectionViewLayout {

    weak var view: LyricsView?

    private var frames: [CGRect] = []
    private var contentHeight: CGFloat = 0
    private var lastPreparedWidth: CGFloat = 0

    override func prepare() {
        super.prepare()
        guard let view, let collectionView else { return }
        let width = collectionView.bounds.width
        lastPreparedWidth = width

        let textWidth = width - LyricsView.horizontalPadding * 2
        var y = LyricsView.topPadding
        frames.removeAll(keepingCapacity: true)
        for (index, line) in view.lines.enumerated() {
            let measured = LyricsTextStyling.heights(
                for: line, width: textWidth, traits: collectionView.traitCollection
            )
            let height = index == view.activeIndex ? measured.active : measured.normal
            frames.append(CGRect(x: 0, y: y, width: width, height: height))
            y += height + LyricsView.lineGap
        }
        if !frames.isEmpty {
            y -= LyricsView.lineGap
            y += LyricsView.bottomPadding
        }
        contentHeight = y
    }

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }
        return CGSize(width: collectionView.bounds.width, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        frames.enumerated().compactMap { index, frame in
            guard frame.intersects(rect) else { return nil }
            return attributes(at: index, frame: frame)
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard frames.indices.contains(indexPath.item) else { return nil }
        return attributes(at: indexPath.item, frame: frames[indexPath.item])
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // Width changes re-measure; vertical scrolls do not invalidate.
        newBounds.width != lastPreparedWidth
    }

    /// Offset centering `index` on the ACTIVE anchor (flutter_lyric
    /// `calcActiveLineOffsetY` → `lineOffsetY` at `activeAnchorPosition`,
    /// 0.48 under the app's `anchorPosition: 0.5` copyWith).
    func targetOffset(forLine index: Int, viewportHeight: CGFloat) -> CGFloat {
        guard frames.indices.contains(index), viewportHeight > 0 else { return 0 }
        return frames[index].midY - viewportHeight * LyricsView.activeAnchorFraction
    }

    private func attributes(at index: Int, frame: CGRect) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
        attributes.frame = frame
        return attributes
    }
}

// MARK: - Long-press preview

/// The context-menu preview of one line: its timestamp in Meta over the
/// line text (and translation), on the player surface.
final class LyricLinePreviewViewController: UIViewController {

    private let line: LyricLine
    private let width: CGFloat

    init(line: LyricLine, width: CGFloat) {
        self.line = line
        self.width = max(width, 1)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Theme.playerBackground

        let timeLabel = UILabel()
        timeLabel.font = TypographyV2.meta.font()
        timeLabel.textColor = Theme.playerSecondary
        timeLabel.text = LyricsTimestamp.string(milliseconds: line.startMilliseconds)

        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.attributedText = LyricsTextStyling.attributedText(
            for: line, isActive: true, traits: traitCollection
        )

        let stack = UIStackView(arrangedSubviews: [timeLabel, textLabel])
        stack.axis = .vertical
        stack.spacing = Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let inset = Spacing.gap
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
        ])

        let fitting = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        preferredContentSize = CGSize(width: width, height: fitting.height)
    }
}

/// `mm:ss` (or `h:mm:ss`) stamp for a line start.
enum LyricsTimestamp {
    static func string(milliseconds: Int) -> String {
        let total = max(milliseconds, 0) / 1000
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
