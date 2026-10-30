import UIKit
import Testing
@testable import Anycast

/// Reference captures of the shared switch (off, on, toggled back off; the
/// last switch is a plain system UISwitch for comparison) and stepper states (off, on,
/// pressed halves, disabled half) in light and dark, plus the Increase
/// Contrast variant. Written to `SNAPSHOT_OUTPUT_DIR` only — there is no
/// committed baseline — and gated like ScreenBaselineCaptureTests
/// (`TEST_RUNNER_SNAPSHOT_CAPTURE=1`).
@MainActor
struct ControlSpecimenCaptureTests {

    @Test("Switch and stepper specimens (light, dark, high contrast)")
    func captureControls() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SNAPSHOT_CAPTURE"] == "1" || environment["TEST_RUNNER_SNAPSHOT_CAPTURE"] == "1",
              let output = environment["SNAPSHOT_OUTPUT_DIR"] ?? environment["TEST_RUNNER_SNAPSHOT_OUTPUT_DIR"]
        else { return }
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let directory = URL(fileURLWithPath: output)
            .appendingPathComponent(SnapshotBaseline.osDirectoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let variants: [(String, UIUserInterfaceStyle, UIAccessibilityContrast)] = [
            ("light", .light, .normal), ("dark", .dark, .normal), ("light-hc", .light, .high),
        ]
        for (name, style, contrast) in variants {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 10
            let controller = UIViewController()
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = style
            controller.traitOverrides.accessibilityContrast = contrast
            controller.view.backgroundColor = style == .dark ? Theme.playerBackground : Theme.background
            window.makeKeyAndVisible()

            let rows = UIStackView()
            rows.axis = .vertical
            rows.spacing = 24
            rows.alignment = .leading
            rows.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(rows)
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 24),
                rows.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 40),
            ])

            func row(_ views: [UIView]) {
                let stack = UIStackView(arrangedSubviews: views)
                stack.axis = .horizontal
                stack.spacing = 24
                stack.alignment = .center
                rows.addArrangedSubview(stack)
            }
            func makeSwitch(on: Bool) -> AnycastSwitch {
                let toggle = AnycastSwitch()
                toggle.isOn = on
                return toggle
            }
            func makeStepper() -> AnycastStepperView {
                let stepper = AnycastStepperView(minusLabel: "-", plusLabel: "+", onMinus: {}, onPlus: {})
                stepper.widthAnchor.constraint(equalToConstant: 112).isActive = true
                stepper.heightAnchor.constraint(equalToConstant: 36).isActive = true
                return stepper
            }
            let minusPressed = makeStepper()
            let plusPressed = makeStepper()
            let atBound = makeStepper()
            atBound.setEnabled(minus: false, plus: true)
            let toggled = makeSwitch(on: true)
            row([makeSwitch(on: false), makeSwitch(on: true), toggled, UISwitch()])
            row([makeStepper(), minusPressed])
            row([plusPressed, atBound])
            row([makeStepper(), makeSwitch(on: false)])

            controller.view.layoutIfNeeded()
            toggled.setOn(false, animated: true)
            minusPressed.minusButton.sendActions(for: .touchDown)
            plusPressed.plusButton.sendActions(for: .touchDown)
            try await Task.sleep(for: .milliseconds(700))

            let renderer = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: 360, height: 360), format: {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                return format
            }())
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(image.pngData()).write(to: directory.appendingPathComponent("controls-\(name).png"))
            window.isHidden = true
        }
    }
}
