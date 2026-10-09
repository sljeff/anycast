import UIKit

/// Email login form sheet (lib/pages/login.dart:832-936, 03 §1.3 row 10):
/// the one non-expand sheet (AppSheets.presentForm from LoginViewController).
/// Email + password fields, Login (Firebase email sign-in; pops the sheet on
/// success), and a Register button that answers with the not-supported dialog
/// — registration stays disabled (states/user.dart:152-217 commented out).
final class EmailLoginViewController: UIViewController {

    private let context: UIContext

    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)

    init(context: UIContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.installPageBase(on: view)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: 24, bottom: 24, trailing: 24
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        configureField(
            emailField,
            hint: LoginPageModel.EmailLogin.emailHint,
            secure: false
        )
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .emailAddress
        emailField.returnKeyType = .done
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.addAction(
            UIAction { [weak self] _ in self?.view.endEditing(true) },
            for: .editingDidEndOnExit
        )

        configureField(
            passwordField,
            hint: LoginPageModel.EmailLogin.passwordHint,
            secure: true
        )
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.returnKeyType = .done
        passwordField.addAction(
            UIAction { [weak self] _ in self?.view.endEditing(true) },
            for: .editingDidEndOnExit
        )

        // ElevatedButton theme: onSurface fill / surface text, pill, 48 min
        // (anycast_theme elevatedButtonTheme).
        loginButton.backgroundColor = Theme.primaryLightMax
        loginButton.setTitleColor(Theme.primaryBackgroundDark, for: .normal)
        loginButton.setTitle(LoginPageModel.EmailLogin.loginButtonTitle, for: .normal)
        loginButton.titleLabel?.font = LoginViewController.font(17, .semibold, .body)
        loginButton.titleLabel?.adjustsFontForContentSizeCategory = true
        loginButton.layer.cornerRadius = 24
        loginButton.layer.cornerCurve = .continuous
        loginButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        loginButton.addAction(
            UIAction { [weak self] _ in self?.loginTapped() },
            for: .touchUpInside
        )

        let register = UIButton(type: .system)
        register.setTitle(LoginPageModel.EmailLogin.registerButtonTitle, for: .normal)
        register.setTitleColor(Theme.primary, for: .normal)
        register.titleLabel?.font = LoginViewController.font(17, .semibold, .body)
        register.titleLabel?.adjustsFontForContentSizeCategory = true
        register.addAction(
            UIAction { [weak self] _ in self?.presentRegisterUnsupported() },
            for: .touchUpInside
        )

        stack.addArrangedSubview(emailField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(loginButton)
        stack.addArrangedSubview(register)

        // login.dart:825 — 100 pt gap below the sheet grabber, content h24.
        // The bottom is an inequality so the stack never stretches, but the
        // vertical chain is still fully determined.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100
            ),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32
            ),
        ])

        let tapOut = UITapGestureRecognizer(
            target: self, action: #selector(dismissKeyboard)
        )
        view.addGestureRecognizer(tapOut)
    }

    private func configureField(_ field: UITextField, hint: String, secure: Bool) {
        field.placeholder = hint
        field.font = LoginViewController.font(17, .regular, .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = Theme.primaryLightMax
        field.backgroundColor = Theme.cardBackground
        field.layer.borderColor = Theme.cardOutline.cgColor
        field.layer.borderWidth = 1
        field.layer.cornerRadius = 16
        field.layer.cornerCurve = .continuous
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.leftViewMode = .always
        field.rightViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Actions

    /// A sign-in attempt in flight: repeated taps (slow network, double
    /// tap) must not fire concurrent signIn calls.
    private var isSigningIn = false

    private func loginTapped() {
        guard !isSigningIn else { return }
        isSigningIn = true
        // No client-side validation and no spinner in the Dart
        // (login.dart:855-862) — the API outcome drives everything.
        let email = emailField.text ?? ""
        let password = passwordField.text ?? ""
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSigningIn = false }
            do {
                try await self.context.auth.signInWithEmail(email: email, password: password)
                // states/user.dart:223 — Get.back() pops the sheet on success.
                self.dismiss(animated: true)
            } catch {
                self.presentFeedback(for: error)
            }
        }
    }

    /// states/user.dart:224-251 — FirebaseAuthException code → title/detail,
    /// other Firebase errors keep their message under "Firebase Error", and
    /// non-Firebase errors use the generic bucket. Single OK action
    /// (EmailLoginFeedbackDialog, states/user.dart:19-72).
    private func presentFeedback(for error: Error) {
        let nsError = error as NSError
        let isFirebase = nsError.domain == "com.google.firebase.auth"
        let feedback = LoginPageModel.EmailLogin.feedback(
            isFirebaseError: isFirebase,
            firebaseCode: isFirebase ? nsError.code : nil,
            message: nsError.localizedDescription
        )
        // The sheet may already be dismissing (sign-in raced a swipe-down);
        // presenting over a vanishing VC silently no-ops and the user never
        // learns the attempt failed.
        let presenter = presentingViewController ?? self
        guard presenter.view.window != nil else { return }
        let alert = UIAlertController(
            title: feedback.title, message: feedback.detail, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private func presentRegisterUnsupported() {
        // login.dart:866-881 — the Dart dialog has no actions (barrier-tap
        // dismiss); an iOS alert needs an explicit OK.
        let alert = UIAlertController(
            title: LoginPageModel.EmailLogin.registerDialogTitle,
            message: LoginPageModel.EmailLogin.registerDialogBody,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
