import CryptoKit
import XCTest

/// Automated UI QA crawl (tool/ui_qa/README.md): drives the app through
/// every reachable screen state, dumps the accessibility tree + a screenshot
/// per state, runs invariant scans, and probes every visible interactive
/// element for dead controls — the bug class static snapshots cannot see
/// (every real UI defect the M3 review rounds caught was interaction-only).
///
/// Two entry points:
/// - testAuditCrawl   full audit: checkpoints assert, probes run, findings
///                    fail the test on P0/P1. Run by tool/ui_qa/crawl.sh.
/// - testReferenceDump same tour, no probes/asserts — used to capture the
///                    Flutter build's AX tree for axdiff.py comparison.
///
/// Data dependence: content states need the db_smoke fixture (native/README);
/// the whole class is gated behind QA_CRAWL=1 (set by crawl.sh) so CI's
/// unseeded smoke run skips it, and content-missing steps skip rather than
/// fail.
///
/// @MainActor: XCUIElementSnapshot trees are non-Sendable and `snapshot()`
/// is main-actor isolated in the iOS 27 SDK.
@MainActor
final class QACrawlUITests: XCTestCase {

    // MARK: - Model

    struct AXNode: Codable {
        var path: String
        var type: String
        var label: String
        var identifier: String
        var frame: [Double]  // x, y, w, h (points, screen space)
        var enabled: Bool
        var selected: Bool
        var value: String
        var depth: Int
    }

    struct StateDump: Codable {
        var state: String
        var screen: [Double]  // w, h
        var elements: [AXNode]
    }

    struct Finding: Codable {
        var state: String
        var kind: String
        var severity: String  // P0/P1/P2/info
        var element: String
        var detail: String
    }

    private var app: XCUIApplication!
    private var findings: [Finding] = []
    private var findingKeys = Set<String>()
    private var skippedStates = Set<String>()
    private var audit = true            // asserts + findings→failures
    private var probesEnabled = true
    private var currentTab = "tab-0"    // pill chip id, for probe recovery
    private var probeBudget = 0

    // MARK: - XCTest plumbing

    override func setUpWithError() throws {
        // The crawl needs the seeded db_smoke container and is driven by
        // tool/ui_qa/crawl.sh, which sets QA_CRAWL=1 by patching it into the
        // xctestrun's EnvironmentVariables (TEST_RUNNER_-prefixed xcodebuild
        // settings do NOT reach the runner through `test-without-building
        // -xctestrun` on this toolchain — kept as a fallback spelling only).
        // Without the gate, running the AnycastUITests bundle — as CI's smoke
        // step does — would also run these four methods against a bare
        // simulator and fail on missing content.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["QA_CRAWL"] == "1"
                || ProcessInfo.processInfo.environment["TEST_RUNNER_QA_CRAWL"] == "1",
            "QA crawl is gated behind QA_CRAWL=1 (tool/ui_qa/crawl.sh); "
                + "the CI smoke step only runs the structural suites")
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private func addFinding(_ state: String, _ kind: String, _ severity: String,
                            _ element: String, _ detail: String) {
        let key = "\(state)|\(kind)|\(element)"
        guard findingKeys.insert(key).inserted else { return }
        findings.append(Finding(state: state, kind: kind, severity: severity,
                                element: element, detail: detail))
    }

    private func flushFindings() {
        guard let data = try? JSONEncoder().encode(findings) else { return }
        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.json", name: "findings.json", payload: data)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - AX tree dump

    private func typeName(_ t: XCUIElement.ElementType) -> String {
        switch t {
        case .button: return "button"
        case .staticText: return "staticText"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .textView: return "textView"
        case .cell: return "cell"
        case .collectionView: return "collectionView"
        case .table: return "table"
        case .scrollView: return "scrollView"
        case .tabBar: return "tabBar"
        case .navigationBar: return "navigationBar"
        case .toolbar: return "toolbar"
        case .image: return "image"
        case .switch: return "switch"
        case .slider: return "slider"
        case .picker: return "picker"
        case .pickerWheel: return "pickerWheel"
        case .alert: return "alert"
        case .dialog: return "dialog"
        case .sheet: return "sheet"
        case .activityIndicator: return "activityIndicator"
        case .progressIndicator: return "progressIndicator"
        case .link: return "link"
        case .searchField: return "searchField"
        case .segmentedControl: return "segmentedControl"
        case .keyboard: return "keyboard"
        case .key: return "key"
        case .application: return "application"
        case .window: return "window"
        case .group: return "group"
        case .webView: return "webView"
        case .stepper: return "stepper"
        case .disclosureTriangle: return "disclosureTriangle"
        case .pageIndicator: return "pageIndicator"
        case .icon: return "icon"
        case .statusBar: return "statusBar"
        case .popUpButton: return "popUpButton"
        case .checkBox: return "checkBox"
        case .radioButton: return "radioButton"
        case .other: return "other"
        default: return "type-\(t.rawValue)"
        }
    }

    private func axNodes() -> [AXNode] {
        guard let root = try? app.snapshot() else { return [] }
        var out: [AXNode] = []
        func walk(_ node: XCUIElementSnapshot, depth: Int, path: String) {
            let f = node.frame
            out.append(AXNode(
                path: path,
                type: typeName(node.elementType),
                label: node.label,
                identifier: node.identifier,
                frame: [
                    Double(f.minX), Double(f.minY),
                    Double(f.width), Double(f.height),
                ],
                enabled: node.isEnabled,
                selected: node.isSelected,
                value: node.value.map { String(describing: $0) } ?? "",
                depth: depth
            ))
            for (index, child) in node.children.enumerated() {
                walk(child, depth: depth + 1, path: "\(path).\(index)")
            }
        }
        walk(root, depth: 0, path: "0")
        return out
    }

    // MARK: - Capture & scans

    private func screenShotHash() -> String {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        return String(SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    private func signature(_ nodes: [AXNode]) -> String {
        let body = nodes.map {
            let f = $0.frame
            let grid = [0, 1, 2, 3].map { Int((f[$0] / 4).rounded()) }
            return "\($0.type)|\($0.label.prefix(80))|\($0.identifier)|\(grid)|\($0.selected)|\($0.value.prefix(40))"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Polls until the AX signature is stable for two consecutive reads or
    /// the timeout expires. Spinners/marquee labels do not churn the AX
    /// tree, so this settles on structural stillness.
    @discardableResult
    private func settle(timeout: TimeInterval = 4) -> String {
        var last = ""
        var stableReads = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let sig = signature(axNodes())
            if sig == last {
                stableReads += 1
                if stableReads >= 2 { return sig }
            } else {
                stableReads = 0
                last = sig
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return last
    }

    private func attachJSON<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.json", name: name, payload: data)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func captureState(_ name: String, settleTimeout: TimeInterval = 4) -> [AXNode] {
        _ = settle(timeout: settleTimeout)
        let nodes = axNodes()
        attachJSON(StateDump(state: name,
                             screen: [Double(app.frame.width), Double(app.frame.height)],
                             elements: nodes),
                   name: "axdump-\(name).json")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "shot-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        scanInvariants(state: name, nodes: nodes)
        return nodes
    }

    /// Cheap structural defect detectors over the AX dump: zero-size
    /// interactive elements, offscreen overflow, oversized containers,
    /// leaked placeholder copy, spinners that survived the settle.
    private func scanInvariants(state: String, nodes: [AXNode]) {
        let screen = CGRect(origin: .zero, size: app.frame.size)
        for node in nodes {
            // System dismiss overlays sit in the AX tree at giant negative
            // offsets; they are chrome, not app content.
            if node.identifier.hasPrefix("PopoverDismissRegion")
                || node.label == "dismiss popup" { continue }
            let f = CGRect(x: node.frame[0], y: node.frame[1],
                           width: node.frame[2], height: node.frame[3])
            let desc = describe(node)

            if isProbeType(node), !node.label.isEmpty || !node.identifier.isEmpty {
                if f.width < 4 || f.height < 4 {
                    addFinding(state, "zero-size-interactive", "P1", desc,
                               "interactive element has a \(f.width)x\(f.height) frame — untappable")
                } else if f.width > screen.width * 1.2 || f.height > screen.height * 1.2 {
                    addFinding(state, "oversized-element", "P2", desc,
                               "frame \(Int(f.width))x\(Int(f.height)) exceeds the \(Int(screen.width))x\(Int(screen.height)) screen")
                } else if f.intersects(screen.insetBy(dx: -2, dy: -2)),
                          !screen.insetBy(dx: -2, dy: -2).contains(f) {
                    // Scrollable content legitimately lives outside the
                    // screen; only an element straddling an edge (clipped
                    // mid-element by the layout itself) is a real defect
                    // signal.
                    addFinding(state, "clipped-element", "P2", desc,
                               "interactive frame \(f) straddles the \(Int(screen.width))x\(Int(screen.height)) screen edge — clipped mid-element")
                }
            }
            if node.type == "activityIndicator" {
                addFinding(state, "spinner-present", "P1", desc,
                           "activity indicator still visible after settle")
            }
            if node.type == "staticText" {
                let lowered = node.label.lowercased()
                for leak in ["todo", "fixme", "lorem ipsum", "placeholder", "null", "undefined"] where lowered.contains(leak) {
                    addFinding(state, "copy-leak", "P2", desc, "static text contains '\(leak)'")
                }
            }
        }
    }

    private func describe(_ node: AXNode) -> String {
        let id = node.identifier.isEmpty ? "" : "#\(node.identifier)"
        let label = node.label.isEmpty ? "" : " '\(node.label.prefix(40))'"
        return "\(node.type)\(id)\(label)@(\(Int(node.frame[0])),\(Int(node.frame[1])),\(Int(node.frame[2]))x\(Int(node.frame[3])))"
    }

    // MARK: - Control probe battery

    private func isProbeType(_ node: AXNode) -> Bool {
        switch node.type {
        case "button", "cell", "image", "switch", "segmentedControl",
             "popUpButton", "disclosureTriangle", "link":
            return true
        case "other", "icon", "staticText":
            // Bare containers flood the probe with dead taps: only labeled
            // nodes count (a label/identifier means someone deliberately
            // exposed the element — usually a custom affordance).
            return !node.label.isEmpty || !node.identifier.isEmpty
        default:
            return false
        }
    }

    /// Labels of controls whose effect mutates data, spends money, leaves
    /// the app, or is covered by a dedicated tour step — probing them would
    /// corrupt the fixture rather than find dead controls.
    private let blockedProbeLabels: [String] = [
        "remove", "delete", "clear", "unsubscribe", "subscribe", "subscribing",
        "sign out", "log out", "sign in", "delete account", "restore", "purchase",
        "buy", "send", "share", "copy rss", "add to playlist", "already in playlist",
        "remove from inbox", "transcribe", "generate transcript", "retry",
        "download", "importing", "export", "play or pause", "seek back", "seek forward",
        "play latest", "play from", "message", "email", "password", "search episodes",
        "shows, episodes", "rss feed url", "google", "apple", "cancel",
    ]

    private func isBlocked(_ node: AXNode) -> Bool {
        let haystack = "\(node.label) \(node.identifier)".lowercased()
        return blockedProbeLabels.contains { haystack.contains($0) }
    }

    private func isProbeCandidate(_ node: AXNode, screen: CGRect,
                                  textInputRects: [CGRect]) -> Bool {
        guard isProbeType(node), !isBlocked(node) else { return false }
        // Disabled controls are inert by design (Import with an empty URL);
        // an already-selected tab is a no-op on tap; scroll indicators are
        // not controls.
        guard node.enabled, !node.selected,
              !node.label.localizedCaseInsensitiveContains("scroll bar")
        else { return false }
        let f = CGRect(x: node.frame[0], y: node.frame[1],
                       width: node.frame[2], height: node.frame[3])
        guard f.width >= 6, f.height >= 6, f.width <= screen.width,
              f.height <= screen.height else { return false }
        guard screen.insetBy(dx: 2, dy: 2).contains(f) else { return false }
        // A coordinate tap hits whatever is topmost at the point: an element
        // sitting inside a text field's frame would only focus the field.
        let center = CGPoint(x: f.midX, y: f.midY)
        return !textInputRects.contains { $0.contains(center) }
    }

    /// Taps every visible interactive element once and records what happened:
    /// `changed` / `visual-only` / `dead-candidate` / `dialog` / `external`.
    /// A dead candidate means a control-looking element consumed a tap with
    /// zero observable effect — the R1/R3 bug class.
    private func probeControls(state: String, nodes: [AXNode],
                               reenter: (() -> Bool)? = nil) {
        guard probesEnabled else { return }
        let screen = CGRect(origin: .zero, size: app.frame.size)
        let textInputRects = nodes
            .filter { ["textField", "secureTextField", "searchField", "textView"].contains($0.type) }
            .map { CGRect(x: $0.frame[0], y: $0.frame[1], width: $0.frame[2], height: $0.frame[3]) }
        var seen = Set<String>()
        var candidates: [AXNode] = []
        var framesSeen = Set<String>()
        for node in nodes where isProbeCandidate(node, screen: screen, textInputRects: textInputRects) {
            // Duplicate AX nodes (layered scroll views) produce identical
            // probes; repeated list controls keep up to two instances.
            let frameKey = "\(node.type)|\(node.label.prefix(40))|(\(Int(node.frame[0])),\(Int(node.frame[1])))"
            guard framesSeen.insert(frameKey).inserted else { continue }
            let key = "\(node.type)|\(node.label.prefix(40))"
            let count = seen.filter { $0.hasPrefix(key) }.count
            seen.insert("\(key)#\(count)")
            guard count < 2 else { continue }
            candidates.append(node)
        }
        guard !candidates.isEmpty else { return }

        // Dismiss affordances (sheet grabbers, the pill-shaped "Close") are
        // probed last: a working one removes the very state the battery is
        // probing, and the tour cannot cheaply re-open it mid-battery.
        let ordered = candidates.filter { !isDismissAffordance($0) }
            + candidates.filter { isDismissAffordance($0) }

        let baselineSig = signature(nodes)
        let baselineShot = screenShotHash()
        let baselineHadGrabber = nodes.contains { $0.label == "Sheet Grabber" }
        var probed = 0
        for candidate in ordered {
            guard probed < 22, probeBudget > 0 else { return }
            probed += 1
            probeBudget -= 1

            let beforeSig = signature(axNodes())
            let beforeShot = screenShotHash()
            let center = CGPoint(x: candidate.frame[0] + candidate.frame[2] / 2,
                                 y: candidate.frame[1] + candidate.frame[3] / 2)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: Double(center.x), dy: Double(center.y)))
                .tap()
            _ = settle(timeout: 1.0)

            if app.state != .runningForeground {
                addFinding(state, "external-app", "P1", describe(candidate),
                           "tap backgrounded the app")
                app.activate()
                _ = settle(timeout: 1.0)
            }
            if app.alerts.firstMatch.exists || app.sheets.firstMatch.exists {
                addFinding(state, "dialog", "info", describe(candidate),
                           "tap surfaced an alert/sheet")
                dismissDialogs()
            }

            let afterNodes = axNodes()
            let afterSig = signature(afterNodes)
            var afterShot = screenShotHash()
            let desc = describe(candidate)

            if isDismissAffordance(candidate), afterSig != baselineSig {
                // Its job is removing the state; that it did so is a pass.
                addFinding(state, "dismiss-ok", "info", desc,
                           "tap dismissed the state as designed")
                return
            }

            var sig = afterSig
            // The tap's own observable effect — an overlay artifact may later
            // hide it, so remember what the FIRST read saw.
            var pixelMoved = afterShot != beforeShot
            if sig == beforeSig && !pixelMoved {
                // Async effects (category refetch, lazy images) can land
                // after the first settle window; give the tap a second
                // chance before calling the control dead.
                _ = settle(timeout: 2.5)
                sig = signature(axNodes())
                pixelMoved = pixelMoved || screenShotHash() != beforeShot
            } else if sig == beforeSig {
                // Pixels moved without an AX change. If the tap surfaced an
                // overlay that races the AX snapshot (sheets mid-presentation,
                // system popovers), it stays on screen and swallows the NEXT
                // probes' taps — clear it before recording.
                dismissCenteredDialog()
                if !baselineHadGrabber {
                    let grabber = app.buttons["Sheet Grabber"]
                    if grabber.exists { tapElement(grabber) }
                }
                if let region = axNodes().first(where: {
                    $0.identifier.hasPrefix("PopoverDismissRegion")
                }) {
                    tapPoint(CGPoint(
                        x: region.frame[0] + region.frame[2] / 2,
                        y: region.frame[1] + region.frame[3] / 2
                    ))
                }
                _ = settle(timeout: 0.8)
                sig = signature(axNodes())
            }
            if sig == beforeSig {
                // Buttons/cells are unambiguous controls; labeled texts and
                // images are often accessibility labels on static content —
                // report those a notch lower.
                let hardControl = ["button", "cell", "switch", "segmentedControl",
                                   "popUpButton", "link", "other"]
                    .contains(candidate.type)
                addFinding(state,
                           pixelMoved ? "visual-only" : "dead-candidate",
                           pixelMoved ? "info" : (hardControl ? "P1" : "P2"),
                           desc,
                           pixelMoved
                               ? "tap produced no AX change (pixels moved — may be marquee/animation noise)"
                               : "tap produced no AX and no pixel change")
            }

            if sig != baselineSig {
                if !recoverToBaseline(state: state, baselineSig: baselineSig,
                                      baselineShot: baselineShot, probePoint: center,
                                      reenter: reenter) {
                    addFinding(state, "recovery-failed", "P2", desc,
                               "could not restore the state after probing this element — relaunched to keep the tour clean")
                    relaunchToShell()
                    return
                }
            }
        }
    }

    /// Elements whose only job is dismissing the presented state.
    private func isDismissAffordance(_ node: AXNode) -> Bool {
        guard node.type == "button" else { return false }
        if node.label == "Sheet Grabber" { return true }
        // Top-of-sheet close controls: "Close" pill, "Close channel",
        // "Close chat". A bottom-bar "Close" (detail sheet) is also purely
        // dismissive — probing it last keeps the battery intact either way.
        if node.label.hasPrefix("Close"),
           node.frame[1] < 120 || node.label == "Close" {
            return true
        }
        return false
    }

    private func dismissDialogs() {
        for label in ["Cancel", "Close", "Close chat", "Done", "Back", "OK",
                      "Not Now", "Don't Allow", "Allow", "取消", "关闭", "完成",
                      "返回", "好"] {
            let button = app.buttons[label]
            if button.exists { tapElement(button); return }
        }
        let alert = app.alerts.firstMatch
        if alert.exists, alert.buttons.count > 0 {
            tapElement(alert.buttons.element(boundBy: 0))
        }
    }

    /// Returns to the state baseline after a probe navigated away: re-tap the
    /// same point (toggle controls collapse back), then dialog buttons, a
    /// sheet-grabber/swipe-down dismiss, the current tab, and finally a
    /// re-run of the state's own navigation action.
    private func recoverToBaseline(state: String, baselineSig: String,
                                   baselineShot: String, probePoint: CGPoint,
                                   reenter: (() -> Bool)? = nil) -> Bool {
        for attempt in 0..<5 where signature(axNodes()) != baselineSig {
            switch attempt {
            case 0:
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: Double(probePoint.x), dy: Double(probePoint.y)))
                    .tap()
            case 1:
                dismissDialogs()
                dismissCenteredDialog()
                if app.keyboards.firstMatch.exists {
                    // Keyboard buttons fail element.tap() with kAXErrorFailure
                    // (they are not scroll-to-visible) — tap by frame instead.
                    for label in ["return", "Search", "Done", "done", "搜索"] {
                        let key = app.keyboards.buttons[label]
                        if key.exists {
                            tapPoint(CGPoint(x: key.frame.midX, y: key.frame.midY))
                            break
                        }
                    }
                }
            case 2:
                // Sheets expose a "Sheet Grabber" affordance that closes on
                // tap (detail.dart quirk); a blind swipe-down only scrolls
                // the sheet's list otherwise.
                let grabber = app.buttons["Sheet Grabber"]
                if grabber.exists { tapElement(grabber) }
                _ = settle(timeout: 0.8)
                app.swipeDown()
            case 3:
                let tab = app.buttons[currentTab]
                if tab.exists { tapElement(tab) }
            default:
                _ = reenter?()
            }
            _ = settle(timeout: 1.2)
        }
        return signature(axNodes()) == baselineSig || screenShotHash() == baselineShot
    }

    /// Last resort after a failed recovery: relaunch to the shell so a stuck
    /// sheet cannot poison the rest of the tour.
    private func relaunchToShell() {
        app.terminate()
        app.launch()
        _ = app.buttons["tab-0"].waitForExistence(timeout: 15)
        _ = settle(timeout: 2)
    }

    // MARK: - Navigation helpers

    /// Taps an element at its frame center via a synthesized coordinate
    /// event. Unlike element.tap() this never attempts scroll-to-visible —
    /// AX scroll failures record an error that aborts the whole test even
    /// with continueAfterFailure, so every crawl tap goes through here.
    /// Off-screen elements fall back to element.tap() (expected-failure
    /// paths only).
    private func tapElement(_ element: XCUIElement) {
        // A predicate that resolves to several elements fails the whole test
        // on .frame/.tap — bind to the first match before touching it.
        let target = element.firstMatch
        let screen = CGRect(origin: .zero, size: app.frame.size)
        if target.exists {
            let frame = target.frame
            if frame.width > 0, frame.height > 0,
               screen.insetBy(dx: -4, dy: -4).intersects(frame) {
                tapPoint(CGPoint(x: frame.midX, y: frame.midY))
                return
            }
        }
        target.tap()
    }

    private func tap(_ element: XCUIElement, _ what: String) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            addFinding("nav", "nav-miss", "P2", what, "element never appeared")
            return false
        }
        tapElement(element)
        return true
    }

    private func tapPoint(_ point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: Double(point.x), dy: Double(point.y)))
            .tap()
    }

    private func tapRow(identifier: String, title: String) -> Bool {
        let cell = app.cells[identifier]
        if cell.exists && cell.isHittable { tapElement(cell); return true }
        // Scroll the settings list until the row renders (short lists skip).
        let list = app.collectionViews.firstMatch
        for _ in 0..<4 where !cell.exists {
            if list.exists { list.swipeUp() } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.4)
        }
        if cell.exists { tapElement(cell); return true }
        let byTitle = app.staticTexts[title]
        if byTitle.waitForExistence(timeout: 2) {
            tapPoint(CGPoint(x: byTitle.frame.midX, y: byTitle.frame.midY))
            return true
        }
        addFinding("nav", "nav-miss", "P2", "settings row \(identifier)", "row never appeared")
        return false
    }

    /// Detail body probe: the description UITextView (or a long static text
    /// fallback) has rendered real show-notes content right now.
    private func detailBodyPopulated() -> Bool {
        app.textViews.allElementsBoundByIndex.contains {
            ($0.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 60
        } || app.staticTexts.allElementsBoundByIndex.contains {
            $0.label.count > 120
        }
    }

    private func detailBodyLength() -> Int {
        let lengths = app.textViews.allElementsBoundByIndex.map {
            ($0.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        }
        return lengths.max() ?? 0
    }

    /// Detail body check (the "tap show icon → see show notes" flow): after
    /// the sheet opens, the description must materialize as real text —
    /// HTML rendering used to arrive seconds late or never (issues #3/R8).
    private func assertDetailBody(state: String) {
        let populated = waitUntil(timeout: 9) { self.detailBodyPopulated() }
        if !populated {
            addFinding(state, "show-notes-empty", "P0", "Detail body",
                       "show notes never rendered after 9s (max body text \(detailBodyLength()) chars across the tried cards)")
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return condition()
    }

    private func skipIfUnseeded(_ state: String, _ exists: Bool, _ needs: String) -> Bool {
        guard exists else {
            skippedStates.insert(state)
            addFinding(state, "skipped-unseeded", "info", needs,
                       "needs the db_smoke fixture — run tool/ui_qa/crawl.sh which seeds it")
            return true
        }
        return false
    }

    private func markSkipped(_ state: String, _ needs: String, _ why: String) {
        skippedStates.insert(state)
        addFinding(state, "skipped", "info", needs, why)
    }

    // MARK: - State re-entry helpers
    //
    // A relaunch after a failed recovery lands back on the shell, so every
    // dependent step re-establishes its own prerequisite screen instead of
    // assuming the previous step left it open.

    private func settingsRowsVisible() -> Bool {
        ["settings-row-account", "settings-row-country",
         "settings-row-importExport", "settings-row-history",
         "settings-row-autoRefreshInterval"]
            .contains { app.cells[$0].exists }
    }

    private func ensureSettingsOpen() -> Bool {
        if settingsRowsVisible() { return true }
        currentTab = "tab-0"
        _ = tap(app.buttons["tab-0"], "Inbox chip")
        guard tap(app.buttons["Settings"].firstMatch, "settings gear") else { return false }
        return waitUntil(timeout: 8) { self.settingsRowsVisible() }
    }

    private func ensurePlayerOpen() -> Bool {
        if app.buttons["player-page-tab-1"].exists { return true }
        closeSheet()
        let title = app.staticTexts["mini-player-title"]
        guard title.waitForExistence(timeout: 4) else { return false }
        tapElement(title)
        return app.buttons["player-page-tab-1"].waitForExistence(timeout: 8)
    }

    private func ensureDetailOpen() -> Bool {
        if app.buttons["Share episode"].exists { return true }
        closeSheet()
        // v2 inbox cards are located by their `more` menu button; the whole
        // card opens Detail (09 §10 批次1).
        let card = app.collectionViews.cells
            .containing(.button, identifier: "inbox-card-more")
            .firstMatch
        guard card.waitForExistence(timeout: 4) else { return false }
        tapElement(card)
        return app.buttons["Share episode"].waitForExistence(timeout: 6)
    }

    /// Subscriptions is the second section within Podcast — tap it, then
    /// the subscriptions collection must show rows.
    private func ensureSubscriptionsPage() -> Bool {
        closeSheet()
        currentTab = "tab-0"
        _ = tap(app.buttons["tab-0"], "Podcast chip")
        _ = tap(app.buttons["podcast-section-1"], "Subscriptions section")
        return app.collectionViews.firstMatch.waitForExistence(timeout: 4)
            && app.collectionViews.firstMatch.cells.count > 0
    }

    private func closeSheet(times: Int = 1) {
        for _ in 0..<times {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.6)
            dismissCenteredDialog()
        }
    }

    /// Centered card dialogs (Import/Export, help popups) ignore swipe-down
    /// gestures; they close on a barrier tap outside the card, like the
    /// Flutter modal barrier.
    private func dismissCenteredDialog() {
        guard let card = centeredDialogFrame() else { return }
        let midX = app.frame.width / 2
        for point in [
            CGPoint(x: midX, y: card.minY - 50),
            CGPoint(x: 24, y: card.minY - 40),
            CGPoint(x: midX, y: card.maxY + 50),
        ] {
            guard point.y > 24, point.y < app.frame.height - 24 else { continue }
            tapPoint(point)
            Thread.sleep(forTimeInterval: 0.5)
            if centeredDialogFrame() == nil { return }
        }
    }

    /// A centered, unlabeled `other` container smaller than the screen — the
    /// shape the app's modal dialogs take (e.g. Import/Export: 300x285 at
    /// (51,309)).
    private func centeredDialogFrame() -> CGRect? {
        let screen = app.frame
        return axNodes().first(where: {
            $0.type == "other" && $0.label.isEmpty && $0.identifier.isEmpty
                && $0.frame[2] > 200 && $0.frame[2] < screen.width * 0.95
                && $0.frame[3] > 200 && $0.frame[3] < screen.height * 0.9
                && abs($0.frame[0] + $0.frame[2] / 2 - screen.width / 2) < 80
                && $0.frame[1] > 100
        }).map {
            CGRect(x: $0.frame[0], y: $0.frame[1],
                   width: $0.frame[2], height: $0.frame[3])
        }
    }

    // MARK: - The tour

    private struct Checkpoint {
        var state: String
        var action: (QACrawlUITests) -> Bool
        var required: [String]          // element labels that must exist
        var probe: Bool
        var settle: TimeInterval
    }

    // swiftlint:disable:next function_body_length
    private func runCrawl() {
        app.launch()
        guard app.buttons["tab-0"].waitForExistence(timeout: 20) else {
            addFinding("nav", "nav-fail", "P0", "tab bar", "shell never installed")
            if audit { XCTFail("pill tab bar did not install — app did not reach the shell") }
            _ = captureState("no-shell", settleTimeout: 1)
            flushFindings()
            return
        }

        let steps: [Checkpoint] = [
            Checkpoint(state: "inbox",
                       action: { _ in true },
                       // Podcast owns an inner Inbox / Subscriptions selector.
                       required: ["Podcast", "Inbox", "Subscriptions", "Search", "Settings"],
                       probe: true, settle: 5),

            Checkpoint(state: "inbox-expanded",
                       action: { s in
                           // The v2 card surfaces its actions through the
                           // long-press context menu (09 §7a-C1) — the v1
                           // strip and its offset-tap target are retired.
                           let card = s.app.collectionViews.cells
                               .containing(.button, identifier: "inbox-card-more")
                               .firstMatch
                           guard card.waitForExistence(timeout: 5) else {
                               s.markSkipped("inbox-expanded", "inbox cards", "needs db_smoke")
                               return false
                           }
                           card.press(forDuration: 1.2)
                           return s.app.buttons["Add to playlist"].waitForExistence(timeout: 4)
                       },
                       required: ["Add to playlist", "Remove from inbox"],
                       probe: false, settle: 2),

            Checkpoint(state: "detail",
                       action: { s in
                           // Cell subtrees merge into the cell's accessibility
                           // element, so the description identifier is not
                           // queryable — instead try cards (located by the
                           // `more` button) until a Detail sheet renders a
                           // real show-notes body (up to 3 visible cards).
                           // The sheet grabber tap closes.
                           let cards = s.app.collectionViews.cells
                               .containing(.button, identifier: "inbox-card-more")
                           guard cards.count > 0 else {
                               s.markSkipped("detail", "inbox cards", "needs db_smoke")
                               return false
                           }
                           let tries = min(3, cards.count)
                           for index in 0..<tries {
                               let card = cards.element(boundBy: index)
                               s.tapElement(card)
                               guard s.app.buttons["Share episode"]
                                       .waitForExistence(timeout: 6) else { continue }
                               if s.detailBodyPopulated() { return true }
                               // Empty body: close and try the next card.
                               let grabber = s.app.buttons["Sheet Grabber"]
                               if grabber.exists { s.tapElement(grabber) } else { s.app.swipeDown() }
                               Thread.sleep(forTimeInterval: 0.6)
                           }
                           // Last opened sheet may still be up; keep it for
                           // the capture and let assertDetailBody file the
                           // finding with the observed body length.
                           return s.app.buttons["Share episode"].exists
                       },
                       required: ["Share episode"],
                       probe: true, settle: 3),

            Checkpoint(state: "channel-on-detail",
                       action: { s in
                           guard s.ensureDetailOpen() else { return false }
                           let channel = s.app.buttons.matching(
                               NSPredicate(format: "label BEGINSWITH 'Open channel'")).firstMatch
                           guard channel.waitForExistence(timeout: 4) else { return false }
                           s.tapElement(channel)
                           let marker = s.app.buttons["Subscribe"]
                           let alt = s.app.buttons["Unsubscribe"]
                           return marker.waitForExistence(timeout: 10)
                               || alt.waitForExistence(timeout: 3)
                       },
                       required: [],
                       probe: true, settle: 3),

            Checkpoint(state: "subscriptions",
                       action: { s in
                           s.closeSheet(times: 2)  // channel, then detail
                           s.currentTab = "tab-0"
                           guard s.tap(s.app.buttons["tab-0"], "Podcast chip") else { return false }
                           guard s.tap(s.app.buttons["podcast-section-1"], "Subscriptions section") else { return false }
                           return s.app.collectionViews.firstMatch.waitForExistence(timeout: 4)
                       },
                       required: [],
                       probe: true, settle: 3),

            Checkpoint(state: "channel",
                       action: { s in
                           guard s.ensureSubscriptionsPage() else { return false }
                           let list = s.app.collectionViews.firstMatch
                           guard list.exists, list.cells.count > 0 else {
                               s.markSkipped("channel", "subscription rows", "needs db_smoke")
                               return false
                           }
                           s.tapElement(list.cells.firstMatch)
                           return s.app.buttons["Subscribe"].waitForExistence(timeout: 10)
                               || s.app.buttons["Unsubscribe"].waitForExistence(timeout: 3)
                               || s.app.buttons["Subscribing"].waitForExistence(timeout: 3)
                       },
                       required: ["Copy RSS URL"],
                       probe: true, settle: 3),

            Checkpoint(state: "search",
                       action: { s in
                           s.closeSheet()
                           s.currentTab = "tab-0"
                           let field = s.app.textFields["header-search-field"]
                           guard field.waitForExistence(timeout: 5) else { return false }
                           s.tapElement(field)
                           // The native header field uses the standard
                           // keyboard submit path into global results.
                           guard s.audit else {
                               s.markSkipped("search", "keyboard submission",
                                             "reference capture does not drive text input")
                               return false
                           }
                           s.tapElement(field)
                           if !field.hasFocus {
                               field.tap()
                               _ = s.app.keyboards.firstMatch.waitForExistence(timeout: 3)
                                   || field.hasFocus
                           }
                           guard field.hasFocus
                                   || s.app.keyboards.firstMatch.exists else {
                               s.markSkipped("search", "keyboard focus",
                                             "text field did not take focus on this app")
                               return false
                           }
                           field.typeText("news")
                           let searchKey = s.app.keyboards.buttons["search"]
                           if searchKey.exists {
                               s.tapPoint(CGPoint(x: searchKey.frame.midX,
                                                  y: searchKey.frame.midY))
                           } else {
                               field.typeText("\n")
                           }
                           return s.app.staticTexts["You are searching for"]
                               .waitForExistence(timeout: 8)
                       },
                       required: ["You are searching for"],
                       probe: true, settle: 3),

            Checkpoint(state: "playlists",
                       action: { s in
                           s.closeSheet()
                           s.currentTab = "tab-1"
                           return s.tap(s.app.buttons["tab-1"], "Playlist chip")
                       },
                       required: ["Settings"],
                       probe: true, settle: 3),

            Checkpoint(state: "player-main",
                       action: { s in
                           let title = s.app.staticTexts["mini-player-title"]
                           guard title.waitForExistence(timeout: 4) else {
                               s.markSkipped("player-main", "mini player", "needs db_smoke queue")
                               return false
                           }
                           s.tapElement(title)
                           return s.app.buttons["player-page-tab-1"].waitForExistence(timeout: 8)
                       },
                       required: ["Play or pause", "Seek back 10 seconds", "Seek forward 30 seconds"],
                       probe: true, settle: 3),

            Checkpoint(state: "player-transcript",
                       action: { s in
                           guard s.ensurePlayerOpen(),
                                 s.app.buttons["player-page-tab-2"].exists else { return false }
                           s.tapElement(s.app.buttons["player-page-tab-2"])
                           return s.app.buttons["player-page-tab-2"].firstMatch.isSelected
                       },
                       required: [],
                       probe: true, settle: 3),

            Checkpoint(state: "chat",
                       action: { s in
                           guard s.ensurePlayerOpen() else { return false }
                           let transcriptTab = s.app.buttons["player-page-tab-2"]
                           if transcriptTab.exists, !transcriptTab.firstMatch.isSelected {
                               s.tapElement(transcriptTab)
                               _ = s.settle(timeout: 1.5)
                           }
                           // The affordance is a labeled image, not a button.
                           let chat = s.app.descendants(matching: .any)
                               .matching(NSPredicate(format: "label == 'AI chat'"))
                               .firstMatch
                           guard chat.waitForExistence(timeout: 4) else {
                               s.markSkipped("chat", "AI chat affordance",
                                            "not visible on the transcript page")
                               return false
                           }
                           s.tapElement(chat)
                           return s.app.buttons["Close chat"].waitForExistence(timeout: 6)
                               || s.app.staticTexts["Ask about this episode"]
                                   .waitForExistence(timeout: 3)
                       },
                       required: [],
                       probe: false, settle: 2),

            Checkpoint(state: "player-settings",
                       action: { s in
                           let close = s.app.buttons["Close chat"]
                           if close.exists { s.tapElement(close) ; Thread.sleep(forTimeInterval: 0.5) }
                           guard s.ensurePlayerOpen(),
                                 s.app.buttons["player-page-tab-0"].exists else { return false }
                           s.tapElement(s.app.buttons["player-page-tab-0"])
                           return s.app.buttons["player-page-tab-0"].firstMatch.isSelected
                       },
                       required: ["Continuous play"],
                       probe: true, settle: 3),

            Checkpoint(state: "subscriptions",
                       action: { s in
                           s.closeSheet()
                           s.currentTab = "tab-0"
                           guard s.tap(s.app.buttons["tab-0"], "Podcast chip") else { return false }
                           return s.tap(s.app.buttons["podcast-section-1"], "Subscriptions section")
                       },
                       required: ["Settings"],
                       probe: true, settle: 3),

            Checkpoint(state: "settings",
                       action: { s in
                           s.currentTab = "tab-0"
                           guard s.tap(s.app.buttons["Settings"].firstMatch, "settings gear") else {
                               return false
                           }
                           return s.app.cells["settings-row-autoRefreshInterval"]
                               .waitForExistence(timeout: 8)
                               || s.app.staticTexts["Account"].waitForExistence(timeout: 4)
                       },
                       required: [],
                       probe: true, settle: 3),

            Checkpoint(state: "settings-picker",
                       action: { s in
                           guard s.ensureSettingsOpen(),
                                 s.tapRow(identifier: "settings-row-autoRefreshInterval",
                                          title: "Auto refresh") else { return false }
                           return s.app.pickerWheels.firstMatch.waitForExistence(timeout: 6)
                       },
                       required: [],
                       probe: false, settle: 2),

            Checkpoint(state: "settings-country",
                       action: { s in
                           let close = s.app.buttons["Close"]
                           if close.exists { s.tapElement(close) ; Thread.sleep(forTimeInterval: 0.5) }
                           else { s.closeSheet() }
                           guard s.ensureSettingsOpen(),
                                 s.tapRow(identifier: "settings-row-country", title: "Country") else {
                               return false
                           }
                           return s.waitUntil(timeout: 6) {
                               s.app.buttons["Close"].exists
                                   || s.app.cells.count > 5 && s.app.cells["settings-row-country"].exists == false
                           }
                       },
                       required: [],
                       probe: false, settle: 2),

            Checkpoint(state: "import-export",
                       action: { s in
                           let close = s.app.buttons["Close"]
                           if close.exists { s.tapElement(close) ; Thread.sleep(forTimeInterval: 0.5) }
                           else { s.closeSheet() }
                           guard s.ensureSettingsOpen(),
                                 s.tapRow(identifier: "settings-row-importExport",
                                          title: "Import / Export") else { return false }
                           return s.app.textFields["RSS Feed URL"].waitForExistence(timeout: 6)
                               || s.app.buttons["Import help"].waitForExistence(timeout: 3)
                       },
                       required: [],
                       probe: true, settle: 2),

            Checkpoint(state: "history",
                       action: { s in
                           s.closeSheet()
                           guard s.ensureSettingsOpen(),
                                 s.tapRow(identifier: "settings-row-history", title: "History") else {
                               return false
                           }
                           return s.waitUntil(timeout: 6) {
                               s.app.buttons["Clear All"].exists
                                   || s.app.staticTexts["No history"].exists
                                   || s.app.buttons["Delete"].exists
                           }
                       },
                       required: [],
                       probe: true, settle: 2),

            Checkpoint(state: "login",
                       action: { s in
                           s.closeSheet()
                           guard s.ensureSettingsOpen(),
                                 s.tapRow(identifier: "settings-row-account", title: "Account") else {
                               return false
                           }
                           return s.waitUntil(timeout: 10) {
                               s.app.buttons["Sign in with Apple"].exists
                                   || s.app.staticTexts["User Info"].exists
                                   || s.app.staticTexts["Basic Plan"].exists
                                   || s.app.staticTexts
                                       .containing(NSPredicate(format: "label CONTAINS 'free audio transcriptions'"))
                                       .firstMatch.exists
                           }
                       },
                       required: [],
                       probe: true, settle: 3),
        ]

        for step in steps {
            let reached = step.action(self)
            if reached {
                let nodes = captureState(step.state, settleTimeout: step.settle)
                for marker in step.required {
                    let hit = app.descendants(matching: .any)
                        .matching(NSPredicate(format: "label == %@", marker))
                        .firstMatch.exists
                    if !hit {
                        addFinding(step.state, "checkpoint-missing", "P0", marker,
                                   "required marker not present")
                    }
                }
                if step.state == "detail" { assertDetailBody(state: step.state) }
                probeControls(state: step.state, nodes: nodes,
                              reenter: { step.action(self) })
            } else if skippedStates.contains(step.state) {
                continue  // already recorded why
            } else {
                addFinding(step.state, "nav-fail", "P1", step.state,
                           "state was not reached; downstream steps may be stale")
            }
        }
        _ = captureState("shell-final", settleTimeout: 2)
        flushFindings()
    }

    // MARK: - Entry points

    /// Full audit on the seeded simulator (tool/ui_qa/crawl.sh). Skips on a
    /// bare simulator so CI stays green — the CI job never seeds db_smoke.
    func testAuditCrawl() {
        audit = true
        probesEnabled = true
        probeBudget = 160
        runCrawl()

        let blocking = findings.filter { ["P0", "P1"].contains($0.severity) }
        if !blocking.isEmpty {
            XCTFail("QA crawl: \(blocking.count) P0/P1 findings — "
                + blocking.prefix(8).map { "[\($0.state)] \($0.kind) \($0.element)" }
                    .joined(separator: "; "))
        }
    }

    /// Dump-only pass used for cross-app comparison (axdiff.py). Runs against
    /// whatever is installed as com.kindjeff.anycast — install the Flutter
    /// build first (tool/ui_qa/capture_flutter.sh), run this, then diff its
    /// states against the native audit run.
    func testReferenceDump() {
        audit = false
        probesEnabled = false
        continueAfterFailure = true
        runCrawl()
    }

    /// Focused check for the channel-card description parity question: the
    /// Flutter channel list renders a 2-line description under each episode
    /// while qa-6's native channel dump showed none. The card resolves the
    /// HTML description asynchronously — this measures whether (and when)
    /// the label populates, separating a real parity gap from a capture
    /// race.
    func testChannelDesc() throws {
        app.launch()
        // Podcasts tab → Subscriptions strip.
        let strip = app.staticTexts["Subscriptions"]
        guard strip.waitForExistence(timeout: 8) else {
            XCTFail("subscriptions strip missing"); return
        }
        tapElement(strip)
        let list = app.collectionViews.firstMatch
        guard list.waitForExistence(timeout: 5), list.cells.count > 0 else {
            // Content-dependent: without the seeded container the
            // subscriptions list is legitimately empty (native/README
            // seeding steps) — skip instead of failing.
            throw XCTSkip("subscription rows missing — needs db_smoke")
        }
        tapElement(list.cells.firstMatch)
        guard app.buttons["Subscribe"].waitForExistence(timeout: 12)
                || app.buttons["Unsubscribe"].waitForExistence(timeout: 4) else {
            XCTFail("channel sheet never opened"); return
        }

        // Poll up to 30 s: the episode list itself arrives via live fetch,
        // then each card's HTML→plain task fills the label.
        var cellsSeen = false
        var descSeen = false
        for tick in 0..<60 {
            let cells = app.collectionViews.cells
            if cells.count > 0 { cellsSeen = true }
            let desc = app.staticTexts.matching(
                NSPredicate(format: "identifier == 'episode-card-description'"))
            for i in 0..<desc.count {
                let el = desc.element(boundBy: i)
                if el.exists, el.frame.height > 5, !(el.label.isEmpty) {
                    descSeen = true
                }
            }
            if descSeen { print("[desc-check] visible after ~\(tick * 500) ms"); break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        print("[desc-check] cellsSeen=\(cellsSeen) descSeen=\(descSeen)")
        if !descSeen {
            let anyDesc = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == 'episode-card-description'"))
            print("[desc-check] any-type matches: \(anyDesc.count)")
            for i in 0..<min(5, anyDesc.count) {
                let el = anyDesc.element(boundBy: i)
                print("[desc-check]   exists=\(el.exists) frame=\(el.frame) label='\(el.label)'")
            }
            _ = captureState("channel-desc-debug", settleTimeout: 1)
        }
        if !cellsSeen { XCTFail("channel episode list never loaded") }
        if !descSeen { XCTFail("episode-card-description never populated within 30 s") }
    }

    /// Screenshot-only tour for the Flutter reference build. Flutter's
    /// semantics tree uses different element types than the audit crawl's
    /// UIKit queries (no tabBar/cells — nodes surface as other/staticText/
    /// button with merged multi-line labels), so navigation taps labels and
    /// coordinates. Captures land in states/fl-* via the same captureState
    /// path for side-by-side comparison with the native run.
    func testFlutterShots() {
        audit = false
        probesEnabled = false
        app.launch()

        // Flutter semantics expose no frames worth tapping, so the remaining
        // taps use coordinates. The absolute points were recorded on the
        // 402pt-wide primary device; express them as fractions of the live
        // window frame so the iOS 18 acceptance device works too.
        let window = app.windows.firstMatch.frame
        let relativeTap = { (xFraction: CGFloat, yFraction: CGFloat) in
            self.tapPoint(CGPoint(
                x: window.minX + window.width * xFraction,
                y: window.minY + window.height * yFraction
            ))
        }

        // Shell marker: Flutter's bottom nav is three staticTexts.
        let playlistTab = app.staticTexts["Playlist"]
        guard playlistTab.waitForExistence(timeout: 25) else {
            _ = captureState("fl-no-shell", settleTimeout: 1)
            return
        }
        _ = settle(timeout: 5)
        _ = captureState("fl-inbox")

        tapElement(app.staticTexts["Discover"])
        _ = settle(timeout: 4)
        _ = captureState("fl-discover")

        tapElement(playlistTab)
        _ = settle(timeout: 3)
        _ = captureState("fl-playlists")

        tapElement(app.staticTexts["Podcast"])
        _ = settle(timeout: 2)
        let subTab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Subscriptions'")).firstMatch
        if subTab.waitForExistence(timeout: 4) {
            tapElement(subTab)
            _ = settle(timeout: 2)
            _ = captureState("fl-subscriptions")
            relativeTap(0.5, 0.40)
            _ = settle(timeout: 5)
            _ = captureState("fl-channel")
            app.swipeDown()
            _ = settle(timeout: 1.5)
        }

        let inboxTab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Inbox'")).firstMatch
        if inboxTab.exists { tapElement(inboxTab) }
        _ = settle(timeout: 2)
        relativeTap(0.17, 0.39)
        _ = settle(timeout: 4)
        _ = captureState("fl-detail")
        app.swipeDown()
        _ = settle(timeout: 1)
        relativeTap(0.5, 0.875)
        _ = settle(timeout: 3)
        _ = captureState("fl-player")
    }
}
