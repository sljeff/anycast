import UIKit

/// The lyrics renderer (self-drawn widget #1, docs/migration/07 §2.5):
/// a line-granular UICollectionView port of the flutter_lyric
/// configuration in lib/pages/player.dart:958-991 —
/// - one cell per LRC line; the optional translation renders inside the
///   same cell as a second paragraph (`translationLineGap` 6 below the
///   main text), so a bilingual pair is a single selectable row;
/// - main 14 pt grey[200] → active 16 pt greenAccent; translation
///   greenAccent → grey[300] when active (reversed colors, 03 §2.10);
/// - `lineGap` 12, content padding top 100 / sides 20 / bottom 20,
///   anchor 0.5 (active line vertically centered);
/// - scroll animation 240 ms easeOutCubic, 500 ms ≥500 pt, 1 s ≥1000 pt;
/// - top/bottom 80 pt fade (LyricStyles.default1 `fadeRange`);
/// - drag → manual scroll + centered time bar (widget #2); no auto re-follow
///   until the 3 s active-line resume fires (`neverResume`,
///   LyricsFollowStateMachine);
/// - tapping a line is a play/pause toggle (the morph overlay belongs to
///   the page controller).
final class LyricsView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    // Dart _lyricStyle values (player.dart:981-986 over default1).
    static let lineGap: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let topPadding: CGFloat = 100
    static let bottomPadding: CGFloat = 20
    static let lineHeightMultiple: CGFloat = 1.35
    static let fadeRange: CGFloat = 80

    /// Line tap → caller toggles playback (Dart setOnTapLineCallback).
    var onTapLine: ((Int) -> Void)?
    /// Time-bar play button → caller seeks to the selected line's stamp.
    var onSeekLine: ((_ milliseconds: Int) -> Void)?

    private(set) var lines: [LyricLine] = []
    private(set) var activeIndex: Int = 0
    private var selectedIndex: Int = 0
    private var follow = LyricsFollowStateMachine()
    private var resumeTimer: Timer?
    private var scrollAnimator: UIViewPropertyAnimator?

    /// flutter_lyric anchors (player.dart `_lyricStyle`): the selection bar
    /// sits at `selectionAnchorPosition` — the app's `anchorPosition: 0.5`
    /// copyWith overrides ONLY the selection anchor; `activeAnchorPosition`
    /// keeps default1's 0.48 (lyric_style.dart:168).
    static let selectionAnchorFraction: CGFloat = 0.5
    static let activeAnchorFraction: CGFloat = 0.48

    private let layout = LyricsLinearLayout()
    private let collectionView: UICollectionView
    private var cellRegistration: UICollectionView.CellRegistration<LyricLineCell, Int>?
    private let timeBar = LyricsTimeBarView()

    init() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        layout.view = self

        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.delaysContentTouches = false
        collectionView.canCancelContentTouches = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        timeBar.isHidden = true
        timeBar.translatesAutoresizingMaskIntoConstraints = false
        timeBar.onPlayTapped = { [weak self] in self?.timeBarPlayTapped() }
        addSubview(timeBar)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),

            timeBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            timeBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            // The bar is pinned to the selection anchor — a FIXED position at
            // 0.5 × viewport height (lyric_selected_progress.dart renders it
            // `Positioned(top: state.centerY)` + `FractionalTranslation(0,-0.5)`
            // where centerY = anchorPositionNotifier = selectionAnchorPosition,
            // NOT the selected line's center).
            timeBar.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        cellRegistration = UICollectionView.CellRegistration<LyricLineCell, Int> {
            [weak self] (cell: LyricLineCell, indexPath: IndexPath, _: Int) in
            guard let self else { return }
            cell.configure(
                line: self.lines[indexPath.item],
                isActive: indexPath.item == self.activeIndex,
                isSelected: self.follow.mode == .selecting && indexPath.item == self.selectedIndex,
                traits: self.traitCollection
            )
            cell.onActivate = { [weak self] in self?.onTapLine?(indexPath.item) }
        }

        installFadeMask()

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: LyricsView, _: UITraitCollection) in
            view.rebuildForTraits()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Document / progress

    func updateDocument(lines: [LyricLine], positionMilliseconds: Int = 0) {
        self.lines = lines
        activeIndex = LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: positionMilliseconds)
        selectedIndex = activeIndex
        layout.invalidateLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        scrollToActiveLine(animated: false)
    }

    /// `ever(positionData)` → `setProgress` (player.dart:1019-1021). The
    /// four-condition progress filter lives in the playback service (K11);
    /// this only renders what arrives.
    func setProgress(positionMilliseconds: Int) {
        let index = LyricDocument.activeLineIndex(lines: lines, positionMilliseconds: positionMilliseconds)
        guard index != activeIndex else { return }
        activeIndex = index
        reconfigureVisibleCells()
        layout.invalidateLayout()
        // Prepare synchronously: the target offset reads the layout's
        // frames, which must already carry the new active line's (taller)
        // measurement — without this the scroll lands a few points off.
        collectionView.layoutIfNeeded()
        if follow.mode == .following {
            scrollToActiveLine(animated: true)
        }
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

    // MARK: - UIScrollViewDelegate (drag selection)

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A user drag must win over an in-flight follow/selection scroll:
        // stop the running animator where it currently is and cancel the
        // collection view's residual scrolling, so the drag starts from
        // under the finger instead of fighting the animator.
        if scrollAnimator?.state == .active {
            scrollAnimator?.stopAnimation(true)
            scrollAnimator?.finishAnimation(at: .current)
        }
        scrollAnimator = nil
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        schedule(.dragBegan)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // The fling keeps selecting; its end schedules the resume.
        if !decelerate { schedule(.dragEnded) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        schedule(.dragEnded)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard follow.mode == .selecting else { return }
        // Painter rule: the selected line is the FIRST line whose bottom
        // edge (+ half the gap) has crossed the selection anchor; when no
        // line crosses, the selection keeps its previous value.
        guard let index = layout.selectedLineIndex(
            anchorY: scrollView.contentOffset.y,
            viewportHeight: bounds.height
        ) else { return }
        guard index != selectedIndex else { return }
        selectedIndex = index
        reconfigureVisibleCells()
        if lines.indices.contains(index) {
            timeBar.updateTime(milliseconds: lines[index].startMilliseconds)
        }
    }

    // MARK: - Selection control

    private func timeBarPlayTapped() {
        // stopSelection() + seek(state.duration) (player.dart:1107-1110).
        schedule(.stopSelectionRequested)
        if lines.indices.contains(selectedIndex) {
            onSeekLine?(lines[selectedIndex].startMilliseconds)
        }
    }

    private func schedule(_ event: LyricsFollowStateMachine.Event) {
        if event == .activeResumeTimerFired {
            // One-shot timer already fired; drop the stale reference.
            resumeTimer = nil
        }
        let action = follow.handle(event)
        switch action {
        case .cancel:
            resumeTimer?.invalidate()
            resumeTimer = nil
        case .startActiveResume:
            resumeTimer?.invalidate()
            let timer = Timer(
                timeInterval: TimeInterval(LyricsFollowStateMachine.activeLineResumeMilliseconds) / 1000,
                repeats: false
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.schedule(.activeResumeTimerFired)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            resumeTimer = timer
        case .none:
            break
        }
        switch event {
        case .dragBegan:
            timeBar.isHidden = false
            if lines.indices.contains(selectedIndex) {
                timeBar.updateTime(milliseconds: lines[selectedIndex].startMilliseconds)
            }
            // isSelecting flipped: the anchor line repaints in selectedColor.
            reconfigureVisibleCells()
        case .activeResumeTimerFired, .stopSelectionRequested:
            if follow.mode == .following {
                timeBar.isHidden = true
                reconfigureVisibleCells()
                scrollToActiveLine(animated: true)
            }
        case .dragEnded:
            break
        }
    }

    // MARK: - Follow scrolling

    /// Center the active line on the 0.48 active anchor. Duration ladder from
    /// default1 `scrollDurations` (240 / 500 / 1000 ms) on easeOutCubic.
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
        if distance < 0.1 {
            collectionView.setContentOffset(CGPoint(x: 0, y: clamped), animated: false)
            return
        }
        let duration: TimeInterval =
            distance >= 1000 ? 1.0 : (distance >= 500 ? 0.5 : 0.24)
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
        max(0, layout.collectionViewContentSize.height - collectionView.bounds.height)
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

    private func installFadeMask() {
        let mask = CAGradientLayer()
        mask.colors = [
            UIColor.clear.cgColor,
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
        ]
        mask.locations = [0, 0.15, 0.85, 1]
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        collectionView.layer.mask = mask
        fadeMask = mask
    }

    private var fadeMask: CAGradientLayer? {
        didSet { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Absolute fade range (default1 fadeRange 80/80), not proportional.
        if let fadeMask {
            let topRatio = bounds.height > 0 ? min(Self.fadeRange / bounds.height, 0.5) : 0
            fadeMask.frame = bounds
            fadeMask.locations = [0, NSNumber(value: topRatio), NSNumber(value: 1 - topRatio), 1]
        }
    }

    deinit {
        MainActor.assumeIsolated {
            resumeTimer?.invalidate()
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

    /// VoiceOver double-tap on the line — the same tap-to-pause the
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

    func configure(line: LyricLine, isActive: Bool, isSelected: Bool, traits: UITraitCollection?) {
        label.attributedText = LyricsTextStyling.attributedText(
            for: line, isActive: isActive, isSelected: isSelected, traits: traits
        )
        accessibilityLabel = [line.text, line.translation ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityTraits = isActive ? [.staticText, .selected] : .staticText
    }
}

// MARK: - Text styling

/// Lyric typography: `Typography.lyricMain/.lyricActive/.lyricTranslation`
/// (M PLUS Rounded 1c; 03 §2.10) with `height: 1.35` paragraphs. The
/// active-translation grey[300] has no catalog token (translation-reversed
/// color of the Dart baseline); it is pinned here.
enum LyricsTextStyling {

    /// Colors.grey[300] — active translation color (Dart
    /// `translationActiveColor: grey[300]`, player.dart:742).
    static let activeTranslationColor = UIColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1)

    /// `isSelected` = the painter's `isSelecting && isInAnchorArea`: the line
    /// under the selection anchor repaints EVERYTHING in `selectedColor`
    /// (white) for as long as the time bar is visible (lyric_painter.dart:231).
    static func attributedText(
        for line: LyricLine,
        isActive: Bool,
        isSelected: Bool = false,
        traits: UITraitCollection?
    ) -> NSAttributedString {
        let mainStyle: Typography.Style = isActive ? .lyricActive : .lyricMain
        let translationColor = isActive
            ? activeTranslationColor
            : Typography.lyricTranslation.color

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = LyricsView.lineHeightMultiple
        paragraph.paragraphSpacing = Self.translationParagraphSpacing

        let attributed = NSMutableAttributedString()
        var mainAttributes = mainStyle.attributes(traits: traits)
        mainAttributes[.paragraphStyle] = paragraph
        if isSelected {
            mainAttributes[.foregroundColor] = UIColor.white
        }
        attributed.append(NSAttributedString(string: line.text, attributes: mainAttributes))
        if let translation = line.translation, !translation.isEmpty {
            var translationAttributes = Typography.lyricTranslation.attributes(traits: traits)
            translationAttributes[.paragraphStyle] = paragraph
            translationAttributes[.foregroundColor] = isSelected ? UIColor.white : translationColor
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

    /// The painter's anchor selection (lyric_painter.dart:69-75): the FIRST
    /// line whose bottom edge plus half the gap reaches the selection anchor
    /// (0.5 × viewport). Returns nil when no line has crossed it — the
    /// painter leaves the notifier untouched in that case, so the caller
    /// keeps the previous selection.
    func selectedLineIndex(anchorY offsetY: CGFloat, viewportHeight: CGFloat) -> Int? {
        guard !frames.isEmpty else { return nil }
        let anchorY = offsetY + viewportHeight * LyricsView.selectionAnchorFraction
        for (index, frame) in frames.enumerated()
        where frame.maxY + LyricsView.lineGap / 2 >= anchorY {
            return index
        }
        return nil
    }

    private func attributes(at index: Int, frame: CGRect) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
        attributes.frame = frame
        return attributes
    }
}

// MARK: - Time bar (widget #2)

/// The drag-selection bar (player.dart:1061-1130): [mm:ss comfortaa 20 pt
/// white with shadow] — [2 pt white line with shadow] — [36×36 translucent
/// circle with a play glyph; tap stops selection and seeks].
final class LyricsTimeBarView: UIView {

    var onPlayTapped: (() -> Void)?

    private let timeLabel = UILabel()
    private let separator = UIView()
    private let playButton = UIButton(type: .custom)

    private static let timeStyle = Typography.Style(
        postScriptName: "Comfortaa-Bold",
        size: 20,
        kern: 0,
        color: .white,
        scalingTextStyle: .title2
    )

    init() {
        super.init(frame: .zero)

        timeLabel.textAlignment = .left
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        separator.backgroundColor = .white
        separator.layer.shadowColor = UIColor.black.withAlphaComponent(0.26).cgColor
        separator.layer.shadowOpacity = 1
        separator.layer.shadowRadius = 2
        separator.layer.shadowOffset = .zero
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        playButton.layer.cornerRadius = 18
        playButton.layer.cornerCurve = .continuous
        playButton.backgroundColor = UIColor.white.withAlphaComponent(0.34)
        playButton.setImage(AppIcons.play, for: .normal)
        playButton.tintColor = Theme.accent
        playButton.isAccessibilityElement = true
        playButton.accessibilityLabel = "Play from selected line"
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addAction(
            UIAction { [weak self] _ in self?.onPlayTapped?() },
            for: .touchUpInside
        )
        addSubview(playButton)

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 12),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.heightAnchor.constraint(equalToConstant: 2),

            playButton.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 12),
            playButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The button's edges define the bar's height: every other
            // subview pins only centerY, so without these Auto Layout
            // leaves the bar zero-height — it still paints (views don't
            // clip) but every touch on the 36 pt button falls outside
            // bounds, making drag-to-seek's play control untappable.
            playButton.topAnchor.constraint(equalTo: topAnchor),
            playButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 36),
            playButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func updateTime(milliseconds: Int) {
        let totalSeconds = milliseconds / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let text = String(format: "%02d:%02d", minutes, seconds)

        // Dart titleLarge + tabular figures + black54 (1,1) blur-4 shadow.
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.54)
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 4
        var attributes = Self.timeStyle.attributes()
        attributes[.shadow] = shadow
        if let base = attributes[.font] as? UIFont {
            let descriptor = base.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
            attributes[.font] = UIFont(descriptor: descriptor, size: base.pointSize)
        }
        timeLabel.attributedText = NSAttributedString(string: text, attributes: attributes)
    }
}
