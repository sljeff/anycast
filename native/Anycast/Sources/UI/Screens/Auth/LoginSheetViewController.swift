import UIKit

/// The login sheet (Login A): one page sheet with a content-fitting detent
/// that serves every sign-in entry point (Settings, 401 reauth, transcribe,
/// and the paywall in batch 3). It moves through the stages of
/// `LoginSheetModel` in place: the Apple (or last-used) primary button, the
/// remaining providers, and the email form. Content stays pinned to the top
/// while the sheet's height animates, so touched controls stay still and only
/// revealed parts move.
///
/// Apple and Google run under the full-screen spinner; email signs in with
/// the form's own button. On success the sheet binds RevenueCat to the new
/// uid, dismisses, and then calls `onSignedIn`.
final class LoginSheetViewController: UIViewController {

    private static let fitDetent = UISheetPresentationController.Detent.Identifier("login.fit")
    private static let inset = Spacing.sheetContent
    private static let buttonHeight: CGFloat = 52
    private static let fieldHeight: CGFloat = 48

    private let context: UIContext
    private(set) var model: LoginSheetModel

    /// Called once the sheet has dismissed itself after a successful sign-in.
    /// By then `RevenueCatController.bind(uid:)` has run for the new uid
    /// (best effort: a bind failure is left to the startup DAG's retry), so
    /// a purchase started from here is attributed to the signed-in account.
    var onSignedIn: (() -> Void)?

    /// Called when the close button dismisses the sheet without a sign-in.
    var onCancelled: (() -> Void)?

    private var isSigningIn = false
    private var isResettingPassword = false
    private var keyboardHeight: CGFloat = 0
    /// Width and bottom safe area the detent was last refit for.
    private var lastMeasured = CGSize.zero

    // Header.
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let titleStack = UIStackView()
    private var closeButton: AnycastIconButton!

    // Layout.
    private let column = UIStackView()
    private let buttonsStack = UIStackView()
    private let formStack = UIStackView()

    // Providers.
    private var providerButtons: [LoginProvider: LoginProviderButton] = [:]
    private let otherWaysButton = UIButton(type: .system)

    // Email form.
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let statusLabel = UILabel()
    private let signInButton = LoginSheetPrimaryButton()
    private let formOtherWaysButton = UIButton(type: .system)

    /// Presents the sheet from `presenter`. `onSignedIn` fires after the
    /// sheet has dismissed itself following a successful sign-in.
    @discardableResult
    static func present(
        from presenter: UIViewController,
        context: UIContext,
        source: LoginSource,
        onSignedIn: (() -> Void)? = nil,
        completion: ((LoginSheetViewController) -> Void)? = nil
    ) -> LoginSheetViewController {
        let sheet = LoginSheetViewController(context: context, source: source)
        sheet.onSignedIn = onSignedIn
        presenter.present(sheet, animated: true) { [weak sheet] in
            if let sheet { completion?(sheet) }
        }
        return sheet
    }

    init(
        context: UIContext,
        source: LoginSource,
        lastProvider: LoginProvider? = LastSignInProviderStore.standard.load()
    ) {
        self.context = context
        self.model = LoginSheetModel(source: source, lastProvider: lastProvider)
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [
                .custom(identifier: Self.fitDetent) { [weak self] context in
                    self?.fitHeight(maximum: context.maximumDetentValue) ?? context.maximumDetentValue
                },
            ]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface

        buildHeader()
        buildButtons()
        buildForm()

        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(titleStack)
        column.addArrangedSubview(buttonsStack)
        column.addArrangedSubview(formStack)
        view.addSubview(column)

        closeButton = AnycastIconButton(
            style: .tonal, icon: AppIcons.close, accessibilityLabel: "Close"
        )
        closeButton.accessibilityIdentifier = "login-close"
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
            self?.onCancelled?()
        }, for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.inset),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.inset),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.inset),
            // 28 pt content inset minus the 6 pt the 44 pt disc overhangs.
            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.inset - 6),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(Self.inset - 6)),
        ])

        let tapOut = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapOut.cancelsTouchesInView = false
        view.addGestureRecognizer(tapOut)

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )

        applyVisibility()
        applyCopy(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The first real width and safe area replace the presenter estimates.
        let measured = CGSize(width: view.bounds.width, height: view.safeAreaInsets.bottom)
        guard measured != lastMeasured else { return }
        lastMeasured = measured
        sheetPresentationController?.invalidateDetents()
    }

    // MARK: - Build

    private func buildHeader() {
        titleLabel.font = TypographyV2.emphasis.font()
        titleLabel.textColor = Theme.onSurface
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.font = TypographyV2.meta.font()
        subtitleLabel.textColor = Theme.onSurfaceVariant
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0

        titleStack.axis = .vertical
        titleStack.spacing = Spacing.sm
        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)
        titleStack.isLayoutMarginsRelativeArrangement = true
        // Room on the trailing side for the 44 pt close disc; 4 pt top so
        // the title sits on the disc's centre line.
        titleStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.xs, leading: 0, bottom: 0,
            trailing: AnycastIconButton.standardDiameter + Spacing.gap
        )
    }

    private func buildButtons() {
        buttonsStack.axis = .vertical
        buttonsStack.alignment = .fill
        buttonsStack.spacing = Spacing.row
        buttonsStack.isLayoutMarginsRelativeArrangement = true
        buttonsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.large, leading: 0, bottom: 0, trailing: 0
        )

        let primary = model.primaryProvider
        buttonsStack.addArrangedSubview(makeProviderButton(primary, isPrimary: true))
        buttonsStack.addArrangedSubview(makeLink(
            otherWaysButton, title: LoginSheetModel.otherWaysTitle, identifier: "login-other-ways"
        ) { [weak self] in self?.openMoreWays() })
        for provider in model.alternativeProviders {
            buttonsStack.addArrangedSubview(makeProviderButton(provider, isPrimary: false))
        }
    }

    private func makeProviderButton(_ provider: LoginProvider, isPrimary: Bool) -> LoginProviderButton {
        let button = LoginProviderButton(provider: provider, isPrimary: isPrimary)
        button.accessibilityIdentifier = "login-\(Self.identifierName(provider))"
        button.addAction(UIAction { [weak self] _ in self?.providerTapped(provider) }, for: .touchUpInside)
        providerButtons[provider] = button
        return button
    }

    private static func identifierName(_ provider: LoginProvider) -> String {
        switch provider {
        case .apple: "apple"
        case .google: "google"
        case .email: "email"
        }
    }

    /// A centered meta-styled text link, 44 pt tall.
    private func makeLink(
        _ button: UIButton, title: String, identifier: String, action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.pageH, bottom: 0, trailing: Spacing.pageH
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = identifier
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: AnycastIconButton.standardDiameter).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func buildForm() {
        formStack.axis = .vertical
        formStack.alignment = .fill
        formStack.spacing = Spacing.row
        formStack.isLayoutMarginsRelativeArrangement = true
        formStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Spacing.sectionGap, leading: 0, bottom: 0, trailing: 0
        )

        configureField(emailField, hint: LoginSheetModel.emailHint, identifier: "login-email-field")
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .username
        emailField.returnKeyType = .next
        emailField.addAction(UIAction { [weak self] _ in
            self?.passwordField.becomeFirstResponder()
        }, for: .editingDidEndOnExit)

        configureField(passwordField, hint: LoginSheetModel.passwordHint, identifier: "login-password-field")
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .go
        passwordField.addAction(UIAction { [weak self] _ in self?.signInTapped() }, for: .editingDidEndOnExit)
        passwordField.rightView = makeForgotAccessory()
        passwordField.rightViewMode = .always

        statusLabel.font = TypographyV2.meta.font()
        statusLabel.textColor = Theme.onSurfaceVariant
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.accessibilityIdentifier = "login-status"

        signInButton.setTitle(LoginSheetModel.signInTitle)
        signInButton.accessibilityIdentifier = "login-submit"
        signInButton.addAction(UIAction { [weak self] _ in self?.signInTapped() }, for: .touchUpInside)

        _ = makeLink(
            formOtherWaysButton, title: LoginSheetModel.emailOtherWaysTitle, identifier: "login-email-other-ways"
        ) { [weak self] in self?.openMoreWays() }

        formStack.addArrangedSubview(emailField)
        formStack.addArrangedSubview(passwordField)
        formStack.addArrangedSubview(statusLabel)
        formStack.addArrangedSubview(signInButton)
        // The Sign In pill sits 8 pt further from the fields.
        formStack.setCustomSpacing(Spacing.row + Spacing.md, after: passwordField)
        formStack.setCustomSpacing(Spacing.row + Spacing.md, after: statusLabel)
        formStack.addArrangedSubview(formOtherWaysButton)
    }

    private func configureField(_ field: UITextField, hint: String, identifier: String) {
        field.applyAnycastStyle(placeholder: hint)
        field.backgroundColor = AnycastColor.sandAlpha3
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.accessibilityIdentifier = identifier
        field.accessibilityLabel = hint
        field.addAction(UIAction { [weak self] _ in self?.clearStatus() }, for: .editingChanged)
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.fieldHeight).isActive = true
    }

    /// "Forgot?" inside the password field's trailing edge.
    private func makeForgotAccessory() -> UIView {
        var configuration = UIButton.Configuration.plain()
        configuration.title = LoginSheetModel.forgotTitle
        configuration.baseForegroundColor = Theme.onSurfaceVariant
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: Spacing.gap, bottom: 0, trailing: Spacing.pageH
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = TypographyV2.meta.font()
            return outgoing
        }
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityIdentifier = "login-forgot"
        button.accessibilityLabel = "Forgot password"
        button.addAction(UIAction { [weak self] _ in self?.forgotTapped() }, for: .touchUpInside)
        // iOS 26 sizes accessory views with Auto Layout, iOS 18 by frame.
        button.sizeToFit()
        button.frame.size.height = Self.fieldHeight
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: button.frame.width),
            button.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
        ])
        return button
    }

    // MARK: - Stage

    func openMoreWays() {
        show(stage: .more)
    }

    func openEmailForm() {
        show(stage: .email)
    }

    private func providerTapped(_ provider: LoginProvider) {
        switch provider {
        case .apple:
            runWithSpinner { auth, presenting in try await auth.signInWithApple(presenting: presenting) }
        case .google:
            runWithSpinner { auth, presenting in try await auth.signInWithGoogle(presenting: presenting) }
        case .email:
            openEmailForm()
        }
    }

    /// Whether the control belongs to the current stage.
    private func isShown(_ view: UIView) -> Bool {
        if view === buttonsStack { return !model.showsEmailForm }
        if view === formStack { return model.showsEmailForm }
        if view === otherWaysButton { return model.showsOtherWaysLink }
        return model.showsAlternatives // the secondary provider buttons
    }

    private var alternativeButtons: [UIView] {
        model.alternativeProviders.compactMap { providerButtons[$0] }
    }

    /// Sets every stage-dependent view's visibility without animation.
    private func applyVisibility() {
        buttonsStack.isHidden = !isShown(buttonsStack)
        formStack.isHidden = !isShown(formStack)
        otherWaysButton.isHidden = !isShown(otherWaysButton)
        for button in alternativeButtons { button.isHidden = !isShown(button) }
    }

    private func applyCopy(animated: Bool) {
        let apply = {
            self.titleLabel.text = self.model.title
            self.subtitleLabel.text = self.model.subtitle
        }
        if animated {
            UIView.transition(
                with: titleStack, duration: Motion.quick, options: .transitionCrossDissolve,
                animations: apply
            )
        } else {
            apply()
        }
    }

    private func show(stage: LoginSheetModel.Stage) {
        guard model.stage != stage else { return }
        switch stage {
        case .apple: return
        case .more: model.showMoreWays()
        case .email: model.showEmailForm()
        }
        let animated = presentingViewController != nil && view.window != nil && !Motion.reduceMotion
        clearStatus(animated: false)
        applyCopy(animated: animated)

        // Top-level groups that swap (buttons <-> form) fade and slide as a
        // whole; inside a group that stays, only the revealed children move.
        let groupSwaps = buttonsStack.isHidden != !isShown(buttonsStack)
        var entering: [UIView] = []
        var leaving: [UIView] = []
        let candidates: [UIView] = groupSwaps
            ? [buttonsStack, formStack]
            : [otherWaysButton] + alternativeButtons
        for candidate in candidates {
            let shouldShow = isShown(candidate)
            if shouldShow && candidate.isHidden { entering.append(candidate) }
            if !shouldShow && !candidate.isHidden { leaving.append(candidate) }
        }

        if animated {
            for view in entering {
                view.alpha = 0
                view.transform = CGAffineTransform(translationX: 0, y: -Motion.stripRevealOffset)
            }
            UIView.animate(withDuration: Motion.stripFadeOut) {
                for view in leaving { view.alpha = 0 }
            }
        }

        relayout(animated: animated) {
            self.applyVisibility()
        }

        guard animated else { return }
        UIView.animate(
            withDuration: Motion.standard, delay: Motion.stripFadeOut / 2, options: .curveEaseOut
        ) {
            for view in entering {
                view.alpha = 1
                view.transform = .identity
            }
        } completion: { _ in
            for view in leaving { view.alpha = 1 }
            if stage == .email { self.emailField.becomeFirstResponder() }
        }
    }

    /// Runs `changes` and refits the detent, animating both when presented.
    private func relayout(animated: Bool, _ changes: @escaping () -> Void) {
        guard animated, let sheet = sheetPresentationController else {
            changes()
            view.layoutIfNeeded()
            sheetPresentationController?.invalidateDetents()
            return
        }
        sheet.animateChanges {
            changes()
            self.view.layoutIfNeeded()
            sheet.invalidateDetents()
        }
    }

    // MARK: - Detent

    /// The sheet height that fits the current stage: top inset, content,
    /// bottom inset over the larger of the safe area and the keyboard.
    func fitHeight(maximum: CGFloat) -> CGFloat {
        guard isViewLoaded else { return maximum }
        let presenterView = presentingViewController?.view
        let width = (view.bounds.width > 0 ? view.bounds.width : (presenterView?.bounds.width ?? 402))
            - 2 * Self.inset
        let content = column.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let safeBottom = view.safeAreaInsets.bottom > 0
            ? view.safeAreaInsets.bottom
            : (presenterView?.window?.safeAreaInsets.bottom ?? 0)
        let total = Self.inset + ceil(content) + Self.inset + max(safeBottom, keyboardHeight)
        return min(total, maximum)
    }

    @objc private func keyboardFrameChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let window = view.window else { return }
        let overlap = max(0, window.bounds.maxY - window.convert(frame, from: nil).minY)
        guard overlap != keyboardHeight else { return }
        keyboardHeight = overlap
        guard let sheet = sheetPresentationController, presentingViewController != nil else { return }
        sheet.animateChanges { sheet.invalidateDetents() }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Sign in

    /// Apple and Google: the full-screen spinner covers the sheet while the
    /// provider's own UI runs; failures and cancellations stay signed out.
    private func runWithSpinner(
        _ flow: @escaping (AuthController, UIViewController) async throws -> Void
    ) {
        guard !isSigningIn else { return }
        isSigningIn = true
        let auth = context.auth
        let spinner = FullScreenSpinnerViewController.present(over: self)
        Task { @MainActor [weak self] in
            var succeeded = false
            do {
                try await flow(auth, spinner)
                succeeded = true
            } catch {
                // Stay signed out, like the all-in-one login sheet.
            }
            spinner.dismissSpinner { [weak self] in
                guard let self else { return }
                self.isSigningIn = false
                if succeeded { self.finishSignIn() }
            }
        }
    }

    private func signInTapped() {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInButton.isEnabled = false
        view.endEditing(true)
        let email = emailField.text ?? ""
        let password = passwordField.text ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.context.auth.signInWithEmail(email: email, password: password)
                self.isSigningIn = false
                self.finishSignIn()
            } catch {
                self.isSigningIn = false
                self.signInButton.isEnabled = true
                self.presentFeedback(for: error)
            }
        }
    }

    /// Binds RevenueCat to the new uid, dismisses, then reports success.
    private func finishSignIn() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let uid = self.context.auth.currentUID {
                try? await self.context.purchases.bind(uid: uid)
            }
            let completion = self.onSignedIn
            self.dismiss(animated: true) { completion?() }
        }
    }

    /// Same mapping and single-OK alert as the email form it replaces.
    private func presentFeedback(for error: Error) {
        let nsError = error as NSError
        let isFirebase = nsError.domain == "com.google.firebase.auth"
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: isFirebase,
            firebaseCode: isFirebase ? nsError.code : nil,
            message: nsError.localizedDescription
        )
        guard view.window != nil else { return }
        let alert = UIAlertController(
            title: feedback.title, message: feedback.detail, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Forgot password

    private func forgotTapped() {
        guard !isResettingPassword else { return }
        guard let email = LoginSheetModel.resetEmail(from: emailField.text ?? "") else {
            showStatus(LoginSheetModel.resetNeedsEmailMessage, isError: true)
            emailField.becomeFirstResponder()
            return
        }
        isResettingPassword = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isResettingPassword = false }
            do {
                try await self.context.auth.sendPasswordReset(email: email)
                self.showStatus(LoginSheetModel.resetSentMessage, isError: false)
            } catch {
                self.showStatus((error as NSError).localizedDescription, isError: true)
            }
        }
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusLabel.text = text
        statusLabel.textColor = isError ? Theme.error : Theme.onSurfaceVariant
        UIAccessibility.post(notification: .announcement, argument: text)
        guard statusLabel.isHidden else { return }
        let animated = presentingViewController != nil && !Motion.reduceMotion
        if animated {
            statusLabel.alpha = 0
            statusLabel.transform = CGAffineTransform(translationX: 0, y: -Motion.stripRevealOffset)
        }
        relayout(animated: animated) { self.statusLabel.isHidden = false }
        guard animated else { return }
        UIView.animate(withDuration: Motion.standard, delay: 0, options: .curveEaseOut) {
            self.statusLabel.alpha = 1
            self.statusLabel.transform = .identity
        }
    }

    private func clearStatus(animated: Bool = true) {
        guard !statusLabel.isHidden else { return }
        let animate = animated && presentingViewController != nil
        relayout(animated: animate) { self.statusLabel.isHidden = true }
    }
}

// MARK: - Buttons

/// A 52 pt pill with a leading icon and an emphasis title. Press feedback is
/// a `sandAlpha5` fill over the resting fill, never a scale.
private final class LoginProviderButton: UIControl {

    private let baseColor: UIColor
    private let pressOverlay = UIView()

    init(provider: LoginProvider, isPrimary: Bool) {
        baseColor = isPrimary ? Theme.onSurface : AnycastColor.sandAlpha4
        super.init(frame: .zero)
        let foreground = isPrimary ? Theme.surface : Theme.onSurface
        backgroundColor = baseColor
        layer.cornerCurve = .circular
        clipsToBounds = true

        pressOverlay.backgroundColor = AnycastColor.sandAlpha5
        pressOverlay.alpha = 0
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pressOverlay)

        let icon = Self.makeIcon(provider)
        icon.tintColor = foreground
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = provider.buttonTitle
        label.font = TypographyV2.emphasis.font()
        label.textColor = foreground
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.row
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let height = heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        NSLayoutConstraint.activate([
            pressOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            pressOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            pressOverlay.topAnchor.constraint(equalTo: topAnchor),
            pressOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Spacing.cardInner),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.cardInner),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.gap),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.gap),
            height,
        ])

        isAccessibilityElement = true
        accessibilityLabel = provider.buttonTitle
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeIcon(_ provider: LoginProvider) -> UIView {
        let view: UIView
        let size: CGFloat
        switch provider {
        case .apple:
            view = UIImageView(image: AppIcons.appleLogo)
            size = 22
        case .google:
            view = GoogleMarkView()
            size = 20
        case .email:
            view = UIImageView(image: AppIcons.email)
            size = 18
        }
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet { pressOverlay.alpha = isHighlighted ? 1 : 0 }
    }
}

/// The primary pill without a leading icon: the login form's "Sign In" and
/// the paywall's CTA.
final class LoginSheetPrimaryButton: UIControl {

    private let label = UILabel()
    private let pressOverlay = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.onSurface
        layer.cornerCurve = .circular
        clipsToBounds = true

        pressOverlay.backgroundColor = AnycastColor.sandAlpha5
        pressOverlay.alpha = 0
        pressOverlay.isUserInteractionEnabled = false
        pressOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pressOverlay)

        label.font = TypographyV2.emphasis.font()
        label.textColor = Theme.surface
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            pressOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            pressOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            pressOverlay.topAnchor.constraint(equalTo: topAnchor),
            pressOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.cardInner),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.cardInner),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.gap),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.gap),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setTitle(_ title: String) {
        label.text = title
        accessibilityLabel = title
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet { pressOverlay.alpha = isHighlighted ? 1 : 0 }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }
}
