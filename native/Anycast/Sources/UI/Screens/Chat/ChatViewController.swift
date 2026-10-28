import UIKit
import AnycastKit
import ChatLayout

/// AI chat sheet (lib/pages/chat.dart, 03 §2.8): presented BY the player's
/// subtitles page over the current episode, on the player's always-dark
/// palette. Header is a badge with "Ask AI" over the episode title; the
/// sheet is dismissed by swipe (grabber, no close button).
///
/// Body is a ChatLayout list plus the hand-written input bar (ChatInputBar).
/// Above the composer sit the empty-state example questions (empty thread
/// only); "New chat" is a header button, shown once there is a thread, and
/// the header subtitle carries the question count. The keyboard goes down on
/// send, New chat, jump, a tap on the list and sheet dismissal. Non-streaming send, "..." placeholder, K8 error and K27
/// 401 policies live in ChatConversation. The thread belongs to the episode
/// (ChatThreadStore): closing the sheet keeps it, and a request in flight
/// lands in it even while the sheet is gone.
final class ChatViewController: UIViewController {

    private enum Metrics {
        static let headerHeight: CGFloat = 72          // room for the grabber above the badge
        static let badgeSide: CGFloat = 44
        static let badgeRadius: CGFloat = 14
        static let headerGap: CGFloat = 12
        /// Pushes the header content below the grabber.
        static let headerContentOffset: CGFloat = 6
        /// Sheet content inset shared by the header, the list and the composer.
        static let contentInset: CGFloat = 28
        /// Composer gap above the keyboard while it is up.
        static let keyboardGap: CGFloat = 8
        static let controlHeight: CGFloat = 44
        static let pillHeight: CGFloat = 52
        static let pillSpacing: CGFloat = 8
        static let chatSurface = Theme.playerBackground
        static let fill = Theme.playerText.withAlphaComponent(0.08)
    }

    private let context: UIContext
    /// Explicit target overrides; nil members resolve from
    /// playback.currentEpisode so the player call site needs no arguments.
    private let titleText: String
    private let draftQuestion: String?
    private let currentLineProvider: (() -> String?)?
    /// Plays from a moment a reply cites; the sheet closes first so the
    /// transcript (and its Undo) is in view.
    private let onJump: ((Int) -> Void)?

    private let conversation: ChatConversation
    /// Chat target resolved from the explicit parameter or the current
    /// playback episode.
    private let resolvedEnclosureURL: String?
    private var didScrollOnAppear = false

    // MARK: Chrome

    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let bottomChrome = UIStackView()
    private let emptyState = UIView()
    private let newChatButton = UIButton(type: .system)
    /// Composer bottom: riding the keyboard while it is up, resting on the
    /// sheet otherwise (`buildBottomChrome`).
    private var keyboardConstraints: [NSLayoutConstraint] = []
    private var sheetConstraints: [NSLayoutConstraint] = []
    let inputBar = ChatInputBar()
    private var collectionView: UICollectionView!
    private let chatLayout = CollectionViewChatLayout()

    init(
        context: UIContext,
        episodeTitle: String? = nil,
        enclosureURL: String? = nil,
        conversation: ChatConversation? = nil,
        draftQuestion: String? = nil,
        currentLineProvider: (() -> String?)? = nil,
        onJump: ((Int) -> Void)? = nil
    ) {
        self.context = context
        let episode = context.playback.currentEpisode
        self.titleText = episodeTitle ?? episode?.title ?? ""
        let url = (enclosureURL ?? episode?.enclosureUrl ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.resolvedEnclosureURL = url.isEmpty ? nil : url
        self.draftQuestion = draftQuestion
        self.currentLineProvider = currentLineProvider
        self.onJump = onJump
        if let conversation {
            self.conversation = conversation
        } else if !url.isEmpty {
            self.conversation = ChatThreadStore.shared.conversation(for: url) {
                APIClientChatTransport(api: context.api)
            }
        } else {
            self.conversation = ChatConversation(transport: APIClientChatTransport(api: context.api))
        }
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPlayerBase(on: view)

        // Dismissed by swipe: the grabber is the only dismiss affordance
        // (never alongside a close button).
        sheetPresentationController?.prefersGrabberVisible = true

        buildHeader()
        buildBottomChrome()
        buildList()

        inputBar.setSending(conversation.isLoading)
        conversation.onMessagesChanged = { [weak self] change in
            self?.applyConversationChange(change)
        }
        conversation.onLoadingChanged = { [weak self] loading in
            self?.inputBar.setSending(loading)
        }
        conversation.onError = { [weak self] presentation in
            self?.presentError(presentation)
        }
        refreshBottomChrome(animated: false)
        if !conversation.messages.isEmpty {
            reloadWithoutAnimation()
        }
        if let draftQuestion {
            inputBar.setText(draftQuestion)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didScrollOnAppear {
            didScrollOnAppear = true
            scrollToBottom()
            if draftQuestion != nil { inputBar.focus() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Down before the sheet slides away, as in Search.
        view.endEditing(true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView != nil else { return }
        ScrollEdgeChrome.clearTop(of: collectionView, to: headerBar.frame.maxY)
        ScrollEdgeChrome.clearBottom(of: collectionView, to: bottomChrome.frame.minY)
    }

    // MARK: - Chrome construction

    private func buildHeader() {
        // Clear: the list runs under the bar and fades out behind it
        // (`ScrollEdgeChrome`).
        headerBar.backgroundColor = .clear
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBar)

        let badge = UIView()
        badge.backgroundColor = Metrics.fill
        badge.layer.cornerRadius = Metrics.badgeRadius
        badge.layer.cornerCurve = .continuous
        badge.isAccessibilityElement = false
        let glyph = UIImageView(image: AppIcons.aiChat)
        glyph.tintColor = Theme.playerText
        glyph.contentMode = .scaleAspectFit
        glyph.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 24),
            glyph.heightAnchor.constraint(equalToConstant: 24),
        ])

        let askLabel = UILabel()
        askLabel.text = "Ask AI"
        askLabel.font = TypographyV2.emphasis.font()
        askLabel.adjustsFontForContentSizeCategory = true
        askLabel.textColor = Theme.playerText
        askLabel.accessibilityTraits = .header

        titleLabel.font = TypographyV2.meta.font()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.playerSecondary
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let titles = UIStackView(arrangedSubviews: [askLabel, titleLabel])
        titles.axis = .vertical
        newChatButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        newChatButton.tintColor = Theme.playerText
        newChatButton.accessibilityLabel = "New chat"
        // Glyph flush with the content inset (the composer's trailing edge);
        // the 44 pt hit area extends inward.
        newChatButton.contentHorizontalAlignment = .trailing
        newChatButton.setContentHuggingPriority(.required, for: .horizontal)
        newChatButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        newChatButton.addAction(UIAction { [weak self] _ in self?.startNewChat() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [badge, titles, newChatButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Metrics.headerGap
        row.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(row)

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            badge.widthAnchor.constraint(equalToConstant: Metrics.badgeSide),
            badge.heightAnchor.constraint(equalToConstant: Metrics.badgeSide),
            newChatButton.widthAnchor.constraint(equalToConstant: Metrics.controlHeight),
            newChatButton.heightAnchor.constraint(equalToConstant: Metrics.controlHeight),
            row.leadingAnchor.constraint(
                equalTo: headerBar.leadingAnchor, constant: Metrics.contentInset
            ),
            row.trailingAnchor.constraint(
                equalTo: headerBar.trailingAnchor, constant: -Metrics.contentInset
            ),
            // The fixed bar clips oversized Dynamic Type (no vertical edge
            // constraints to fight it).
            row.centerYAnchor.constraint(
                equalTo: headerBar.centerYAnchor, constant: Metrics.headerContentOffset
            ),
        ])
    }

    private func buildList() {
        chatLayout.settings.interItemSpacing = 16
        chatLayout.settings.additionalInsets = UIEdgeInsets(
            top: 8, left: Metrics.contentInset, bottom: 8, right: Metrics.contentInset
        )
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.keepContentAtBottomOfVisibleArea = true

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: chatLayout)
        collectionView.dataSource = self
        chatLayout.delegate = self
        collectionView.backgroundColor = Metrics.chatSurface
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        // A tap on the list also lowers the keyboard; the touch still
        // reaches bubble buttons (resend, jump).
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismissTap.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(dismissTap)
        // https://openradar.appspot.com/40926834
        collectionView.isPrefetchingEnabled = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(
            ContainerCollectionViewCell<ChatBubbleView>.self,
            forCellWithReuseIdentifier: String(describing: ContainerCollectionViewCell<ChatBubbleView>.self)
        )
        collectionView.accessibilityLabel = "Messages"
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Runs under the header and the bottom chrome (content fades out
            // behind both); `viewDidLayoutSubviews` keeps the resting list
            // between them.
            collectionView.topAnchor.constraint(equalTo: headerBar.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomChrome.bottomAnchor),
        ])
        ScrollEdgeChrome.attach(
            chrome: headerBar, to: collectionView, edge: .top, in: view,
            fadeColor: Metrics.chatSurface, restingGap: 0
        )
        ScrollEdgeChrome.attach(
            chrome: bottomChrome, to: collectionView, edge: .bottom, in: view,
            fadeColor: Metrics.chatSurface, restingGap: 0
        )
    }

    /// Bottom chrome: [empty-state examples] above the composer, riding the
    /// keyboard together.
    private func buildBottomChrome() {
        buildEmptyState()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.backgroundColor = .clear   // the list fades out behind it

        bottomChrome.axis = .vertical
        bottomChrome.alignment = .fill
        bottomChrome.spacing = 0
        bottomChrome.translatesAutoresizingMaskIntoConstraints = false
        bottomChrome.addArrangedSubview(emptyState)
        bottomChrome.addArrangedSubview(inputBar)
        view.addSubview(bottomChrome)
        // Keyboard avoidance (07 §2.6 — ChatLayout needs no extra plumbing of
        // its own here). The keyboard layout guide tracks the keyboard's
        // screen frame, not the sheet, so a constraint to it that stays
        // active while the keyboard is hidden would pin the composer to the
        // screen bottom during a sheet-dismiss drag (header moves, list
        // squashes). The keyboard-relative constraints are therefore only
        // installed between keyboardWillShow and keyboardWillHide (the
        // guide's near/away-edge API cannot tell a docked keyboard from a
        // hidden one — both are "near" the bottom): with the keyboard up the
        // composer sits a small gap above it, including during the
        // interactive dismiss; with it down the chrome is pinned to the
        // sheet itself — the 28 pt content inset from the sheet bottom (the
        // home indicator's safe area wins when larger, as in Detail) — so
        // the sheet moves as one.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        let ridesKeyboard = bottomChrome.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor, constant: -Metrics.keyboardGap
        )
        ridesKeyboard.priority = .defaultHigh
        let aboveKeyboard = bottomChrome.bottomAnchor.constraint(
            lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -Metrics.keyboardGap
        )
        keyboardConstraints = [ridesKeyboard, aboveKeyboard]
        let restsOnSheet = bottomChrome.bottomAnchor.constraint(
            equalTo: view.bottomAnchor, constant: -Metrics.contentInset
        )
        restsOnSheet.priority = .defaultHigh
        sheetConstraints = [restsOnSheet]
        NSLayoutConstraint.activate([
            bottomChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomChrome.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -Metrics.contentInset),
            bottomChrome.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
            restsOnSheet,
        ])
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil
        )
        inputBar.onSend = { [weak self] text in
            self?.handleSend(text)
        }
    }

    private func buildEmptyState() {
        let hint = UILabel()
        hint.text = "Try one, or ask your own."
        hint.font = TypographyV2.meta.font()
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = Theme.playerSecondary

        let column = UIStackView(arrangedSubviews: [hint])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = Metrics.pillSpacing
        for prompt in ChatExamplePrompts.all {
            column.addArrangedSubview(makePill(title: prompt))
        }
        column.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor, constant: Metrics.contentInset),
            column.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor, constant: -Metrics.contentInset),
            column.topAnchor.constraint(equalTo: emptyState.topAnchor),
            column.bottomAnchor.constraint(equalTo: emptyState.bottomAnchor, constant: -Metrics.pillSpacing),
        ])
    }

    private func makePill(title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.background.backgroundColor = Metrics.fill
        config.baseForegroundColor = Theme.playerText
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        config.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: TypographyV2.body.font()])
        )
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.accessibilityLabel = title
        button.heightAnchor.constraint(equalToConstant: Metrics.pillHeight).isActive = true
        button.addAction(
            UIAction { [weak self] _ in self?.sendExampleQuestion(title) },
            for: .touchUpInside
        )
        return button
    }

    /// Empty thread: example questions, no "New chat" button, bare episode
    /// title. Otherwise the button appears and the subtitle leads with the
    /// question count.
    private func refreshBottomChrome(animated: Bool) {
        let isEmpty = conversation.messages.isEmpty
        let questions = conversation.messages.filter { $0.author == .human }.count
        let count = "\(questions) \(questions == 1 ? "question" : "questions")"
        titleLabel.text = isEmpty ? titleText : [count, titleText].filter { !$0.isEmpty }.joined(separator: " · ")
        let apply = {
            self.emptyState.isHidden = !isEmpty
            self.newChatButton.isHidden = isEmpty
            self.newChatButton.alpha = isEmpty ? 0 : 1
            self.inputBar.placeholder = isEmpty ? "Ask about this episode" : "Ask a follow-up"
        }
        guard animated, view.window != nil else {
            apply()
            return
        }
        UIView.animate(withDuration: Motion.quick) {
            apply()
            self.view.layoutIfNeeded()
        }
    }

    // Posted inside the keyboard's animation, so the switch animates with it.
    @objc private func keyboardWillShow() {
        NSLayoutConstraint.deactivate(sheetConstraints)
        NSLayoutConstraint.activate(keyboardConstraints)
        view.layoutIfNeeded()
    }

    @objc private func keyboardWillHide() {
        NSLayoutConstraint.deactivate(keyboardConstraints)
        NSLayoutConstraint.activate(sheetConstraints)
        view.layoutIfNeeded()
    }

    // MARK: - Actions

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func startNewChat() {
        view.endEditing(true)
        conversation.clear()
    }

    private func handleSend(_ text: String) {
        // Keyboard down so the reply area is visible.
        view.endEditing(true)
        // Composer InputClearMode.always: the field clears on submit even
        // when the send itself is gated by isLoading (states/chat.dart).
        inputBar.clearText()
        send(text)
    }

    /// The request runs on the conversation, not on this controller: it
    /// outlives the sheet and lands in the thread.
    private func send(_ text: String) {
        // Dart force-unwrapped the enclosure URL (chat.dart:64); a missing
        // episode simply cannot chat — no crash (K4 family).
        guard let enclosureURL = resolvedEnclosureURL else { return }
        let conversation = self.conversation
        Task { await conversation.send(text, enclosureURL: enclosureURL) }
    }

    private func resend(_ messageID: UUID) {
        guard let enclosureURL = resolvedEnclosureURL else { return }
        let conversation = self.conversation
        Task { await conversation.resend(messageID: messageID, enclosureURL: enclosureURL) }
    }

    /// Sends the example question for `prompt` (one of `ChatExamplePrompts`).
    func sendExampleQuestion(_ prompt: String) {
        view.endEditing(true)
        send(ChatExamplePrompts.question(for: prompt, currentLine: currentLineProvider?()))
    }

    /// K8/K27: errors never become AI messages (the conversation already
    /// removed the placeholder and marked the question failed). 401/403-code=2
    /// opens the login sheet (03 §10.1) and resends on success; a server
    /// message is the ported ErrorHandler copy on the shared toast surface;
    /// a plain network failure is left to the inline "Not sent" state.
    private func jump(to milliseconds: Int) {
        let onJump = onJump
        view.endEditing(true)
        dismiss(animated: true) { onJump?(milliseconds) }
    }

    private func presentError(_ presentation: ChatErrorPresentation) {
        switch presentation {
        case .loginRequired:
            presentLoginAndResend()
        case .errorMessage(let text):
            showToast(text)
        case .errorBody(let status, let body):
            showToast("Error \(status): \(body)")
        case .networkFailure:
            break
        }
    }

    private func presentLoginAndResend() {
        guard view.window != nil else { return }
        view.endEditing(true)
        LoginSheetViewController.present(
            from: topMostPresented(), context: context, source: .reauth
        ) { [weak self] in
            guard let self, let failed = self.conversation.lastFailedMessage else { return }
            self.resend(failed.id)
        }
    }

    private func showToast(_ message: String) {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(message, in: window, duration: 3)
    }

    // MARK: - Conversation → list updates

    /// Applies a conversation change to the list. The model is already
    /// mutated when the event arrives, so animated batches are only safe
    /// when the collection view's cached count matches the expected
    /// pre-change count; anything else (view not yet on screen, counts
    /// never queried) falls back to a plain reload.
    private func applyConversationChange(_ change: ChatConversation.MessagesChange) {
        guard isViewLoaded else { return }
        refreshBottomChrome(animated: true)
        let cachedCount = collectionView.numberOfItems(inSection: 0)
        let currentCount = conversation.messages.count
        switch change {
        case .appended(let count):
            let oldCount = currentCount - count
            guard collectionView.window != nil, cachedCount == oldCount else {
                reloadWithoutAnimation()
                return
            }
            let paths = (oldCount..<currentCount).map { IndexPath(item: $0, section: 0) }
            updateAnimated { self.collectionView.insertItems(at: paths) }
        case .replaced(let index):
            guard collectionView.window != nil, cachedCount == currentCount else {
                reloadWithoutAnimation()
                return
            }
            updateAnimated {
                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            }
        case .removed(let index):
            guard collectionView.window != nil, cachedCount == currentCount + 1 else {
                reloadWithoutAnimation()
                return
            }
            updateAnimated {
                self.collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            }
        case .cleared:
            reloadWithoutAnimation()
        }
    }

    private func reloadWithoutAnimation() {
        UIView.performWithoutAnimation {
            self.collectionView.reloadData()
        }
        // reloadData defers queries to the next layout pass; scroll after it.
        Task { @MainActor [weak self] in
            self?.scrollToBottom()
        }
    }

    private func updateAnimated(_ updates: @escaping () -> Void) {
        collectionView.performBatchUpdates {
            updates()
        } completion: { [weak self] _ in
            self?.scrollToBottom()
        }
    }

    /// Keeps the newest message fully visible (the example app's
    /// restoreContentOffsetToBottom).
    private func scrollToBottom() {
        let count = conversation.messages.count
        guard count > 0 else { return }
        collectionView.layoutIfNeeded()
        chatLayout.restoreContentOffset(
            with: ChatLayoutPositionSnapshot(
                indexPath: IndexPath(item: count - 1, section: 0), edge: .bottom
            )
        )
    }
}

// MARK: - UICollectionViewDataSource

extension ChatViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    func collectionView(
        _ collectionView: UICollectionView, numberOfItemsInSection section: Int
    ) -> Int {
        conversation.messages.count
    }

    func collectionView(
        _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: String(describing: ContainerCollectionViewCell<ChatBubbleView>.self),
            for: indexPath
        )
        if let cell = cell as? ContainerCollectionViewCell<ChatBubbleView> {
            let message = conversation.messages[indexPath.item]
            cell.customView.configure(with: message)
            cell.customView.onResend = { [weak self] in self?.resend(message.id) }
            cell.customView.onJump = { [weak self] milliseconds in self?.jump(to: milliseconds) }
            cell.delegate = cell.customView
        }
        return cell
    }
}

// MARK: - ChatLayoutDelegate

extension ChatViewController: ChatLayoutDelegate {

    func sizeForItem(
        _ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath
    ) -> ItemSize {
        .estimated(CGSize(width: chatLayout.layoutFrame.width, height: 44))
    }

    func alignmentForItem(
        _ chatLayout: CollectionViewChatLayout, at indexPath: IndexPath
    ) -> ChatItemAlignment {
        // Flutter `Align`: sent messages bottom-right, received bottom-left.
        conversation.messages[indexPath.item].author == .human ? .trailing : .leading
    }
}
