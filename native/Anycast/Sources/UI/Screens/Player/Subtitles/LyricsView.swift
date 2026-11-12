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
    // Aria "Words" look: 22 pt bold lines, 20 pt apart, 3 pt line spacing,
    // active line anchored 30% from the top. The content column already
    // carries the page inset, so the cell padding only tops it up to ~28.
    static let lineGap: CGFloat = 20
    static let horizontalPadding: CGFloat = 0
    static let topPadding: CGFloat = 36
    /// Minimum bottom padding; the layout raises it so the last line can
    /// still reach the anchor.
    static let bottomPadding: CGFloat = 100
    static let lineSpacing: CGFloat = 3
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
    /// Characters of the active line already spoken (word-snapped).
    private var activeSpoken: Int = 0
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

    /// The active line's anchor point sits this far down the viewport
    /// (Aria Words: `UnitPoint(y: 0.3)`).
    static let activeAnchorFraction: CGFloat = 0.3

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
                state: self.state(forLine: indexPath.item),
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
        activeSpoken = spokenCount(positionMilliseconds: positionMilliseconds)
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
        guard index != activeIndex else {
            // Same line: only the word fill moves. Restyle the active cell
            // in place (same font in every state, so no relayout).
            let spoken = spokenCount(positionMilliseconds: positionMilliseconds)
            if spoken != activeSpoken {
                activeSpoken = spoken
                refreshActiveCell()
            }
            return
        }
        activeIndex = index
        activeSpoken = spokenCount(positionMilliseconds: positionMilliseconds)
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
        activeSpoken = 0
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

    /// Put the active line on the 0.3 anchor. Duration ladder from
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

    // MARK: - Word fill

    private func state(forLine index: Int) -> LyricsTextStyling.LineState {
        if index < activeIndex { return .spoken }
        if index > activeIndex { return .upcoming }
        return .active(spokenCharacters: activeSpoken)
    }

    /// Characters said so far in the active line: progress interpolated
    /// across the line's start/end (the next line's start), snapped
    /// forward to the end of a word — AriaSpokenLine.spokenCount.
    private func spokenCount(positionMilliseconds: Int) -> Int {
        guard lines.indices.contains(activeIndex) else { return 0 }
        let line = lines[activeIndex]
        let end = lines.indices.contains(activeIndex + 1)
            ? lines[activeIndex + 1].startMilliseconds
            : line.startMilliseconds + 4000
        let span = Double(max(300, end - line.startMilliseconds))
        let progress = min(1, max(0, Double(positionMilliseconds - line.startMilliseconds) / span))
        let characters = Array(line.text)
        var count = min(characters.count, Int(Double(characters.count) * progress) + 1)
        while count < characters.count, characters[count] != " " { count += 1 }
        return count
    }

    private func refreshActiveCell() {
        guard lines.indices.contains(activeIndex),
              let cell = collectionView.cellForItem(at: IndexPath(item: activeIndex, section: 0)) as? LyricLineCell
        else { return }
        cell.configure(
            line: lines[activeIndex], state: state(forLine: activeIndex),
            isActive: true, traits: traitCollection
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

    func configure(
        line: LyricLine,
        state: LyricsTextStyling.LineState,
        isActive: Bool,
        traits: UITraitCollection?
    ) {
        label.attributedText = LyricsTextStyling.attributedText(
            for: line, state: state, traits: traits
        )
        accessibilityLabel = [line.text, line.translation ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityTraits = isActive ? [.staticText, .selected] : .staticText
        accessibilityHint = "Plays from this line"
    }
}

// MARK: - Text styling

/// Aria "Words" typography: every line is 22 pt bold (Dynamic Type via
/// `.title2`) in every state, so heights never change when the highlight
/// moves. State is colour only: spoken lines 0.42, upcoming 0.30, the
/// active line full colour for the spoken part and 0.5 for the rest.
enum LyricsTextStyling {

    enum LineState: Equatable {
        case spoken
        case upcoming
        /// `spokenCharacters` of the line's text are already said.
        case active(spokenCharacters: Int)
    }

    static let spokenAlpha: CGFloat = 0.42
    static let upcomingAlpha: CGFloat = 0.30
    static let activeRestAlpha: CGFloat = 0.5

    private static let lineStyle = TypographyV2.Style(
        size: 22, lineHeight: 28, weight: .bold, color: Theme.playerText, scalingTextStyle: .title2
    )

    static func attributedText(
        for line: LyricLine,
        state: LineState,
        traits: UITraitCollection?
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = LyricsView.lineSpacing
        paragraph.paragraphSpacing = Self.translationParagraphSpacing

        let font = lineStyle.font(traits: traits)
        func main(_ text: String, _ alpha: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: Theme.playerText.withAlphaComponent(alpha),
                .paragraphStyle: paragraph,
            ])
        }

        let attributed = NSMutableAttributedString()
        let translationColor: UIColor
        switch state {
        case .spoken:
            attributed.append(main(line.text, spokenAlpha))
            translationColor = Theme.playerSecondary.withAlphaComponent(spokenAlpha)
        case .upcoming:
            attributed.append(main(line.text, upcomingAlpha))
            translationColor = Theme.playerSecondary.withAlphaComponent(upcomingAlpha)
        case .active(let spoken):
            let characters = Array(line.text)
            let cut = min(max(spoken, 0), characters.count)
            attributed.append(main(String(characters[..<cut]), 1))
            attributed.append(main(String(characters[cut...]), activeRestAlpha))
            translationColor = Theme.playerSecondary
        }
        if let translation = line.translation, !translation.isEmpty {
            let translationAttributes: [NSAttributedString.Key: Any] = [
                .font: TypographyV2.meta.font(traits: traits),
                .foregroundColor: translationColor,
                .paragraphStyle: paragraph,
            ]
            attributed.append(NSAttributedString(string: "\n", attributes: translationAttributes))
            attributed.append(NSAttributedString(string: translation, attributes: translationAttributes))
        }
        return attributed
    }

    /// Text height at a given width. The font is the same in every state,
    /// so one measurement serves all of them.
    static func height(
        for line: LyricLine,
        width: CGFloat,
        traits: UITraitCollection?
    ) -> CGFloat {
        let constraint = CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        return ceil(attributedText(for: line, state: .upcoming, traits: traits)
            .boundingRect(with: constraint, options: options, context: nil).height)
    }

    /// Paragraph gap between a line and its translation.
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
            let height = LyricsTextStyling.height(
                for: line, width: textWidth, traits: collectionView.traitCollection
            )
            frames.append(CGRect(x: 0, y: y, width: width, height: height))
            y += height + LyricsView.lineGap
        }
        if !frames.isEmpty {
            y -= LyricsView.lineGap
            // Enough room under the last line for it to reach the anchor.
            y += max(
                LyricsView.bottomPadding,
                collectionView.bounds.height * (1 - LyricsView.activeAnchorFraction)
            )
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

    /// Offset putting the line's anchor point (the same relative height
    /// inside the line) on the viewport's anchor fraction, like SwiftUI's
    /// `scrollTo(anchor: UnitPoint(y: 0.3))`.
    func targetOffset(forLine index: Int, viewportHeight: CGFloat) -> CGFloat {
        guard frames.indices.contains(index), viewportHeight > 0 else { return 0 }
        let fraction = LyricsView.activeAnchorFraction
        return frames[index].minY + frames[index].height * fraction - viewportHeight * fraction
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
            for: line, state: .active(spokenCharacters: line.text.count), traits: traitCollection
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
