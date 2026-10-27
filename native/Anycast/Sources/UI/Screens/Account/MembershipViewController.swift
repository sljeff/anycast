import UIKit
import SafariServices
import StoreKit
import AnycastKit

/// Membership page (Membership B design): the signed-in account surface
/// Settings opens from its identity row. Presented as an expand sheet, so it
/// has a centered title instead of a back button. Top to bottom: the gold
/// Plus status plate, the AI-transcripts usage card, Restore Purchases, the
/// Account group (email, sign-in provider), Sign Out, Privacy · Terms, and
/// Delete Account.
final class MembershipViewController: UIViewController {

    /// Called after the account changed under this page (sign out, delete)
    /// and the sheet is gone, so the presenter can re-read it.
    var onAccountChanged: (() -> Void)?

    private let context: UIContext
    private let store: PaywallStore

    // State: seeded by the presenter, refreshed from the live sources.
    private var isSubscribed: Bool
    private var plus: AccountPageModel.PlusStatus?
    private var remaining: Int?
    private var account = LoginPageModel.AccountSnapshot(uid: nil, email: nil, providerID: nil)
    private var reloadTask: Task<Void, Never>?

    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let statusRow = AccountRowView(verticalPadding: AccountStyle.goldPadding)
    private let billingNoteLabel = UILabel()
    private let usageView = AccountUsageView()
    private let emailRow = AccountRowView()
    private let providerRow = AccountRowView()
    private var plateAction = AccountPageModel.PlateAction.upgrade

    init(context: UIContext, isSubscribed: Bool, plus: AccountPageModel.PlusStatus?, remaining: Int?) {
        self.context = context
        self.store = PaywallStore(purchases: context.purchases)
        self.isSubscribed = isSubscribed
        self.plus = plus
        self.remaining = remaining
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { reloadTask?.cancel() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surfaceContainer

        titleLabel.text = AccountPageModel.pageTitle
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        buildContent()

        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        view.addSubview(scrollView)
        view.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Spacing.pageHeader),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: Spacing.pageHeader
            ),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Runs under the title and the sheet's bottom edge, fading out
            // behind both (same arrangement as Settings).
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.pageH
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.pageH
            ),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.xl
            ),
            stack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -2 * Spacing.pageH
            ),
        ])
        ScrollEdgeChrome.attachTopBand(
            to: scrollView, in: view, below: titleLabel.bottomAnchor,
            fadeColor: Theme.surfaceContainer, restingGap: Spacing.md
        )
        ScrollEdgeChrome.attachBottomEdge(to: scrollView, in: view, fadeColor: Theme.surfaceContainer)
        view.bringSubviewToFront(titleLabel)

        account = AuthAccountSnapshot.current(context: context)
        render()
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ScrollEdgeChrome.clearTop(of: scrollView, to: titleLabel.frame.maxY + Spacing.md)
    }

    // MARK: - Content

    private func buildContent() {
        // 1. Gold status plate (+ billing note).
        statusRow.accessibilityIdentifier = "membership-status"
        statusRow.valueLabel.textColor = Theme.primary
        statusRow.addAction(UIAction { [weak self] _ in self?.statusTapped() }, for: .touchUpInside)
        statusRow.isAccessibilityElement = true
        statusRow.accessibilityTraits = .button
        let statusPlate = AccountPlateView(fill: AccountStyle.goldPlate, rows: [statusRow])

        billingNoteLabel.font = TypographyV2.meta.font()
        billingNoteLabel.textColor = Theme.onSurfaceVariant
        billingNoteLabel.adjustsFontForContentSizeCategory = true
        billingNoteLabel.numberOfLines = 0
        billingNoteLabel.text = AccountPageModel.billingNote
        let billingNote = UIView()
        billingNoteLabel.translatesAutoresizingMaskIntoConstraints = false
        billingNote.addSubview(billingNoteLabel)
        NSLayoutConstraint.activate([
            billingNoteLabel.leadingAnchor.constraint(
                equalTo: billingNote.leadingAnchor, constant: AccountRowView.horizontalInset
            ),
            billingNoteLabel.trailingAnchor.constraint(
                equalTo: billingNote.trailingAnchor, constant: -AccountRowView.horizontalInset
            ),
            billingNoteLabel.topAnchor.constraint(equalTo: billingNote.topAnchor),
            billingNoteLabel.bottomAnchor.constraint(equalTo: billingNote.bottomAnchor),
        ])
        billingNote.isHidden = true
        let statusGroup = UIStackView(arrangedSubviews: [statusPlate, billingNote])
        statusGroup.axis = .vertical
        statusGroup.spacing = Spacing.md
        stack.addArrangedSubview(statusGroup)
        stack.setCustomSpacing(Spacing.gap, after: statusGroup)
        billingNoteView = billingNote

        // 2. Usage.
        usageView.accessibilityIdentifier = "membership-usage"
        stack.addArrangedSubview(usageView)
        stack.setCustomSpacing(Spacing.pageH, after: usageView)

        // 3. Restore Purchases.
        let restoreRow = AccountRowView()
        restoreRow.titleLabel.text = AccountPageModel.restorePurchasesTitle
        restoreRow.accessibilityIdentifier = "membership-restore"
        restoreRow.addAction(UIAction { [weak self] _ in self?.restoreTapped() }, for: .touchUpInside)
        Self.makeButtonElement(restoreRow, label: AccountPageModel.restorePurchasesTitle)
        let restorePlate = AccountPlateView(fill: Theme.surface, rows: [restoreRow])
        stack.addArrangedSubview(restorePlate)
        stack.setCustomSpacing(Spacing.pageH, after: restorePlate)

        // 4. Account group.
        let groupHeader = UILabel()
        groupHeader.text = AccountPageModel.accountGroupTitle
        groupHeader.font = TypographyV2.meta.font()
        groupHeader.textColor = Theme.onSurfaceVariant
        groupHeader.adjustsFontForContentSizeCategory = true
        groupHeader.accessibilityTraits = .header
        groupHeader.translatesAutoresizingMaskIntoConstraints = false
        let headerContainer = UIView()
        headerContainer.addSubview(groupHeader)
        NSLayoutConstraint.activate([
            groupHeader.leadingAnchor.constraint(
                equalTo: headerContainer.leadingAnchor, constant: AccountRowView.horizontalInset
            ),
            groupHeader.trailingAnchor.constraint(
                equalTo: headerContainer.trailingAnchor, constant: -AccountRowView.horizontalInset
            ),
            groupHeader.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            groupHeader.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -Spacing.md),
        ])
        emailRow.titleLabel.text = AccountPageModel.emailRowTitle
        emailRow.valueLabel.lineBreakMode = .byTruncatingMiddle
        emailRow.showsPressFeedback = false
        emailRow.accessibilityIdentifier = "membership-email"
        emailRow.addInteraction(UIContextMenuInteraction(delegate: self))
        providerRow.titleLabel.text = AccountPageModel.signedInWithRowTitle
        providerRow.showsPressFeedback = false
        providerRow.accessibilityIdentifier = "membership-provider"
        for row in [emailRow, providerRow] {
            row.isAccessibilityElement = true
            row.isUserInteractionEnabled = row === emailRow
        }
        let accountGroup = UIStackView(arrangedSubviews: [
            headerContainer, AccountPlateView(fill: Theme.surface, rows: [emailRow, providerRow]),
        ])
        accountGroup.axis = .vertical
        stack.addArrangedSubview(accountGroup)
        stack.setCustomSpacing(Spacing.pageH, after: accountGroup)

        // 5. Sign Out.
        let signOutRow = AccountRowView()
        signOutRow.titleLabel.text = AccountPageModel.signOutTitle
        signOutRow.accessibilityIdentifier = "membership-signOut"
        signOutRow.addAction(UIAction { [weak self] _ in self?.signOutTapped() }, for: .touchUpInside)
        Self.makeButtonElement(signOutRow, label: AccountPageModel.signOutTitle)
        let signOutPlate = AccountPlateView(fill: Theme.surface, rows: [signOutRow])
        stack.addArrangedSubview(signOutPlate)
        stack.setCustomSpacing(Spacing.sectionGap, after: signOutPlate)

        // 6. Privacy · Terms.
        let links = makeLinks()
        stack.addArrangedSubview(links)
        stack.setCustomSpacing(Spacing.md, after: links)

        // 7. Delete Account.
        stack.addArrangedSubview(makeDeleteButton())
    }

    private var billingNoteView: UIView?

    private static func makeButtonElement(_ row: AccountRowView, label: String) {
        row.isAccessibilityElement = true
        row.accessibilityLabel = label
        row.accessibilityTraits = .button
    }

    private func makeLinks() -> UIView {
        func link(_ title: String, url: URL) -> UIButton {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(
                top: Spacing.gap, leading: Spacing.md, bottom: Spacing.gap, trailing: Spacing.md
            )
            config.attributedTitle = AttributedString(NSAttributedString(string: title, attributes: [
                .font: TypographyV2.meta.font(),
                .foregroundColor: Theme.onSurfaceVariant,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]))
            button.configuration = config
            button.accessibilityTraits = .link
            button.addAction(UIAction { [weak self] _ in
                self?.present(SFSafariViewController(url: url), animated: true)
            }, for: .touchUpInside)
            return button
        }
        let dot = UILabel()
        dot.text = "·"
        dot.font = TypographyV2.meta.font()
        dot.textColor = Theme.onSurfaceVariant
        dot.adjustsFontForContentSizeCategory = true
        dot.isAccessibilityElement = false

        let row = UIStackView(arrangedSubviews: [
            link(AccountPageModel.privacyTitle, url: LoginPageModel.privacyPolicyURL),
            dot,
            link(AccountPageModel.termsTitle, url: LoginPageModel.termsOfUseURL),
        ])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 0
        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeDeleteButton() -> UIView {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: Spacing.gap, leading: Spacing.gap, bottom: Spacing.gap, trailing: Spacing.gap
        )
        config.baseForegroundColor = Theme.error
        config.attributedTitle = AttributedString(NSAttributedString(
            string: AccountPageModel.deleteAccountTitle,
            attributes: [.font: TypographyV2.meta.font(), .foregroundColor: Theme.error]
        ))
        button.configuration = config
        button.accessibilityIdentifier = "membership-delete"
        button.addAction(UIAction { [weak self] _ in self?.deleteTapped() }, for: .touchUpInside)
        let container = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - Rendering

    private func render() {
        let plate = AccountPageModel.plate(isSubscribed: isSubscribed, plus: plus)
        plateAction = plate.action
        statusRow.titleLabel.text = plate.title
        if let issue = plate.issue {
            let text = NSMutableAttributedString(string: plate.meta, attributes: [
                .font: TypographyV2.meta.font(), .foregroundColor: Theme.onSurfaceVariant,
            ])
            text.append(NSAttributedString(string: issue, attributes: [
                .font: TypographyV2.meta.font(), .foregroundColor: Theme.error,
            ]))
            statusRow.subtitleLabel.attributedText = text
            statusRow.subtitleLabel.isHidden = false
        } else {
            statusRow.setSubtitle(plate.meta)
        }
        statusRow.setValue(plate.actionTitle, color: Theme.primary)
        statusRow.accessibilityLabel = "\(plate.title), \(plate.actionTitle)"
        statusRow.accessibilityValue = plate.meta + (plate.issue ?? "")
        billingNoteView?.isHidden = plate.billingNote == nil

        usageView.configure(AccountPageModel.usage(isSubscribed: isSubscribed, remaining: remaining))

        let email = AccountPageModel.emailRowValue(account.email)
        emailRow.setValue(email)
        emailRow.accessibilityLabel = AccountPageModel.emailRowTitle
        emailRow.accessibilityValue = email
        emailRow.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: LoginPageModel.copyEmailMenuTitle) { [weak self] _ in
                self?.copyEmail() ?? false
            },
        ]
        let provider = AccountPageModel.signedInWithText(providerID: account.providerID)
        providerRow.setValue(provider)
        providerRow.accessibilityLabel = AccountPageModel.signedInWithRowTitle
        providerRow.accessibilityValue = provider
    }

    /// Re-reads the entitlement and quota; the page keeps what it shows
    /// while the sources answer. A login-required answer is not escalated.
    private func reload() {
        reloadTask?.cancel()
        let store = store
        let context = context
        reloadTask = Task { @MainActor [weak self] in
            async let subscribed = context.purchases.isSubscribed()
            async let status = store.plusStatus()
            let isSubscribed = await subscribed
            let plus = await status
            guard !Task.isCancelled, let self else { return }
            self.isSubscribed = isSubscribed
            self.plus = plus
            self.account = AuthAccountSnapshot.current(context: context)
            self.render()

            if let result = try? await context.api.getUser(), case .user(let user) = result {
                guard !Task.isCancelled else { return }
                self.remaining = user.remaining
                self.render()
            }
        }
    }

    // MARK: - Actions

    private func statusTapped() {
        switch plateAction {
        case .manage:
            guard let scene = view.window?.windowScene else { return }
            Task { @MainActor [weak self] in
                try? await AppStore.showManageSubscriptions(in: scene)
                self?.reload()
            }
        case .upgrade, .getItBack:
            // Temporary bridge to the paywall card inside the Login sheet
            // until the standalone paywall exists.
            let login = LoginViewController(context: context)
            AppSheets.presentExpand(login, from: self)
            login.presentationController?.delegate = self
        }
    }

    private func restoreTapped() {
        let spinner = FullScreenSpinnerViewController.present(over: self)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await self.store.restorePurchases()
            spinner.dismissSpinner {
                self.presentAlert(
                    title: success ? LoginPageModel.restoreSuccessAlertTitle : LoginPageModel.restoreErrorAlertTitle,
                    message: success ? LoginPageModel.restoreSuccessAlertBody : LoginPageModel.restoreErrorAlertBody
                )
                self.reload()
            }
        }
    }

    private func signOutTapped() {
        let alert = UIAlertController(
            title: LoginPageModel.signOutAlertTitle,
            message: LoginPageModel.signOutAlertBody,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: LoginPageModel.signOutMenuTitle, style: .destructive) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.context.auth.signOut(purchases: self.context.purchases)
                    self.finishAccountChange()
                }
            }
        )
        alert.addAction(UIAlertAction(title: LoginPageModel.cancelTitle, style: .default))
        present(alert, animated: true)
    }

    private func deleteTapped() {
        AccountDeletionFlow.present(from: self, context: context) { [weak self] in
            self?.finishAccountChange()
        }
    }

    /// The account is gone (signed out or deleted): close this sheet and
    /// let the presenter re-read the account.
    private func finishAccountChange() {
        let callback = onAccountChanged
        if presentingViewController != nil {
            dismiss(animated: true) { callback?() }
        } else {
            callback?()
        }
    }

    @discardableResult
    private func copyEmail() -> Bool {
        guard let email = account.email else { return false }
        UIPasteboard.general.string = email
        return true
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Email context menu

extension MembershipViewController: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard account.email != nil else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: LoginPageModel.copyEmailMenuTitle,
                    image: UIImage(systemName: "doc.on.doc")
                ) { _ in self?.copyEmail() },
            ])
        })
    }
}

// MARK: - Child sheet dismissal

extension MembershipViewController: UIAdaptivePresentationControllerDelegate {

    /// The Login sheet (upgrade bridge) was swiped away: the entitlement may
    /// have changed.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        reload()
    }
}
