import Foundation
import Testing
@testable import AnycastKit

/// Feed depth is untrusted: `htmlToText` and `sanitizeHtml` run on 512 KB
/// GCD-worker stacks (card-cache parsing happens off-main, ingest calls
/// them directly), so deep nesting must degrade to text instead of
/// overflowing the stack. Every case executes on a thread sized exactly
/// like a GCD worker so a regression to per-level recursion fails here
/// rather than in the field.
private final class ResultBox<T> {
    var value: T?
}

struct HtmlTextDepthTests {

    private static let gcdWorkerStackSize = 512 * 1024

    private func onWorkerSizedStack<T>(_ body: @escaping () -> T) -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = body()
            done.signal()
        }
        thread.stackSize = Self.gcdWorkerStackSize
        thread.start()
        done.wait()
        return box.value!
    }

    private func nesting(_ depth: Int, payload: String = "payload") -> String {
        String(repeating: "<div>", count: depth) + payload
            + String(repeating: "</div>", count: depth)
    }

    @Test("Deeply nested HTML yields its text without overflowing the walk")
    func htmlToTextSurvivesDeepNesting() {
        let html = nesting(50_000, payload: "core text")
        let text = onWorkerSizedStack { HtmlText.htmlToText(html) }
        #expect(text.contains("core text"))
    }

    @Test("sanitizeHtml keeps within-ceiling depth and falls back past it")
    func sanitizeDepthBoundary() {
        // Depth counts every node, text included: N wrapper divs plus the
        // payload text is depth N + 1.
        let atLimit = onWorkerSizedStack {
            HtmlText.sanitizeHtml(nesting(HtmlText.maximumTreeDepth - 1))
        }
        #expect(atLimit.contains("payload"))

        let payload = onWorkerSizedStack {
            HtmlText.displayPayload(for: nesting(HtmlText.maximumTreeDepth))
        }
        guard case .text(let plain) = payload else {
            Issue.record("expected the plain-text fallback past the depth ceiling")
            return
        }
        #expect(plain.contains("payload"))
    }
}
