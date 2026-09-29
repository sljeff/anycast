import UIKit
import AnycastKit
import ChatLayout

/// AI chat sheet (lib/pages/chat.dart, 03 §2.8): presented BY the player's
/// subtitles page over the current episode. Header is the released
/// baseline's 64 pt playerBackground bar (anycast_theme.dart:122-123 — the
/// 2026-07 visual refresh replaced the doc-era deep purple) with a round
/// black close X, the two-line episode title and the trash (clear) button.
///
/// Body is a ChatLayout list styled to the flutter_chat_ui dark defaults
/// (03 §6) plus the hand-written input bar (ChatInputBar). Non-streaming
/// send, "..." placeholder, K8 error and K27 401 policies all live in
/// ChatConversation; closing the sheet clears the conversation (PopScope
/// parity).
final class ChatViewController: UIViewController {

    private enum Metrics {
        static let headerHeight: CGFloat = 64          // AnycastSpacing.sheetTitleH
        static let roundButtonSide: CGFloat = 40
        static let titleHorizontalPadding: CGFloat = 16 // AnycastSpacing.pageH
        static let chatSurface = UIColor(red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255, alpha: 1)
        static let headerBackground = UIColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x21 / 255, alpha: 1)
        static let headerText = UIColor(red: 0xEE / 255, green: 0xEE / 255, blue: 0xEC / 255, alpha: 1)
    }

    private let context: UIContext
    /// Explicit target overrides; nil members resolve from
    /// playback.currentEpisode so the player call site needs no arguments.
    private let explicitTitle: String?
    private let explicitEnclosureURL: String?

    private let conversation: ChatConversation
    private var sendTask: Task<Void, Never>?
    /// Chat target resolved in viewDidLoad from the explicit parameter or
    /// the current playback episode.
    private var resolvedEnclosureURL: String?

    // MARK: Chrome

    private let headerBar = UIView()
    private let closeButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let trashButton = UIButton(type: .custom)
    private let inputBar = ChatInputBar()
    private var collectionView: UICollectionView!
    private let chatLayout = CollectionViewChatLayout()

    init(
        context: UIContext,
        episodeTitle: String? = nil,
        enclosureURL: String? = nil,
        conversation: ChatConversation? = nil
    ) {
        self.context = context
        self.explicitTitle = episodeTitle
        self.explicitEnclosureURL = enclosureURL
        self.conversation = conversation
            ?? ChatConversation(transport: APIClientChatTransport(api: context.api))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installDarkBase(on: view)

        let episode = context.playback.currentEpisode
        titleLabel.text = explicitTitle ?? episode?.title ?? ""
        let url = (explicitEnclosureURL ?? episode?.enclosureUrl ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        resolvedEnclosureURL = url.isEmpty ? nil : url

        buildHeader()
        buildInputBar()
        buildList()

        conversation.onMessagesChanged = { [weak self] change in
            self?.applyConversationChange(change)
        }
        conversation.onError = { [weak self] presentation in
            self?.presentError(presentation)
        }
    }

    /// PopScope parity (lib/pages/chat.dart:17-22): closing the sheet
    /// clears the conversation — reopening starts fresh. `isBeingDismissed`
    /// keeps sheets presented ON TOP of this one (login on 401) from
    /// clearing it.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            sendTask?.cancel()
            conversation.clear()
        }
    }

    // MARK: - Chrome construction

    private func buildHeader() {
        headerBar.backgroundColor = Metrics.headerBackground
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBar)

        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.26)
        closeButton.layer.cornerRadius = Metrics.roundButtonSide / 2
        closeButton.setImage(AppIcons.close, for: .normal)
        closeButton.tintColor = .white
        closeButton.isAccessibilityElement = true
        closeButton.accessibilityLabel = "Close chat"
        closeButton.addAction(
            UIAction { [weak self] _ in self?.closeTapped() },
            for: .touchUpInside
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(closeButton)

        // Material titleMedium: 16 pt w500 on playerText, two-line ellipsis.
        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: UIFont.systemFont(ofSize: 16, weight: .medium)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Metrics.headerText
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleLabel)

        trashButton.setImage(AppIcons.delete, for: .normal)
        trashButton.tintColor = .white
        trashButton.isAccessibilityElement = true
        trashButton.accessibilityLabel = "Clear conversation"
        trashButton.addAction(
            UIAction { [weak self] _ in self?.conversation.clear() },
            for: .touchUpInside
        )
        trashButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(trashButton)

        NSLayoutConstraint.activate([
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            closeButton.leadingAnchor.constraint(
                equalTo: headerBar.leadingAnchor, constant: Metrics.titleHorizontalPadding
            ),
            closeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Metrics.roundButtonSide),
            closeButton.heightAnchor.constraint(equalToConstant: Metrics.roundButtonSide),

            titleLabel.leadingAnchor.constraint(
                equalTo: closeButton.trailingAnchor, constant: Metrics.titleHorizontalPadding
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trashButton.leadingAnchor, constant: -Metrics.titleHorizontalPadding
            ),
            // Centered like the Dart AppBar title; the fixed 64 pt bar clips
            // oversized Dynamic Type the same way the Flutter toolbar did
            // (no vertical edge constraints to fight it).
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            trashButton.trailingAnchor.constraint(
                equalTo: headerBar.trailingAnchor, constant: -Metrics.titleHorizontalPadding
            ),
            trashButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            trashButton.widthAnchor.constraint(equalToConstant: Metrics.roundButtonSide),
            trashButton.heightAnchor.constraint(equalToConstant: Metrics.roundButtonSide),
        ])
    }

    private func buildList() {
        chatLayout.settings.interItemSpacing = 8
        chatLayout.settings.additionalInsets = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
        chatLayout.keepContentAtBottomOfVisibleArea = true

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: chatLayout)
        collectionView.dataSource = self
        chatLayout.delegate = self
        collectionView.backgroundColor = Metrics.chatSurface
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
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
            collectionView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
        ])
    }

    private func buildInputBar() {
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)
        // Keyboard avoidance: the bar rides the keyboard layout guide; the
        // list sits above the bar (07 §2.6 — ChatLayout needs no extra
        // plumbing of its own here).
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        inputBar.onSend = { [weak self] text in
            self?.handleSend(text)
        }
    }

    // MARK: - Actions

    private func closeTapped() {
        conversation.clear()
        dismiss(animated: true)
    }

    private func handleSend(_ text: String) {
        // Composer InputClearMode.always: the field clears on submit even
        // when the send itself is gated by isLoading (states/chat.dart).
        inputBar.clearText()
        // Dart force-unwrapped the enclosure URL (chat.dart:64); a missing
        // episode simply cannot chat — no crash (K4 family).
        guard let enclosureURL = resolvedEnclosureURL, !enclosureURL.isEmpty else { return }
        inputBar.setSending(true)
        sendTask = Task { [weak self] in
            await self?.conversation.send(text, enclosureURL: enclosureURL)
            self?.inputBar.setSending(false)
        }
    }

    /// K8/K27: errors never become AI messages (the conversation already
    /// removed the placeholder); 401/403-code=2 opens the login sheet
    /// (03 §10.1), everything else is the ported ErrorHandler copy on the
    /// shared toast surface.
    private func presentError(_ presentation: ChatErrorPresentation) {
        switch presentation {
        case .loginRequired:
            context.presentLogin()
        case .errorMessage(let text):
            showToast(text)
        case .errorBody(let status, let body):
            showToast("Error \(status): \(body)")
        case .networkFailure:
            showToast("Network error")
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
        case .removedPlaceholder(let index):
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
            cell.customView.configure(with: conversation.messages[indexPath.item])
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
