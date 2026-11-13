import Testing
@testable import AnycastKit

/// Download progress is stored (and re-rendered) once per visible percent,
/// not once per network chunk.
struct DownloadProgressStepTests {

    @Test("the first value, each new whole percent and completion are visible; sub-percent chunks are not")
    func steps() {
        #expect(DownloadProgressStep.isVisibleChange(from: nil, to: 0))
        #expect(!DownloadProgressStep.isVisibleChange(from: 0.001, to: 0.009))
        #expect(DownloadProgressStep.isVisibleChange(from: 0.009, to: 0.01))
        #expect(!DownloadProgressStep.isVisibleChange(from: 0.42, to: 0.4299))
        #expect(DownloadProgressStep.isVisibleChange(from: 0.995, to: 1))
        #expect(!DownloadProgressStep.isVisibleChange(from: 1, to: 1))
    }

    @Test("a thousand chunk callbacks store at most 101 values")
    func chunkStorm() {
        var stored: Double?
        var writes = 0
        for chunk in 1...1_000 {
            let progress = Double(chunk) / 1_000
            if DownloadProgressStep.isVisibleChange(from: stored, to: progress) {
                stored = progress
                writes += 1
            }
        }
        #expect(writes == 101, "the first chunk, then one per whole percent up to 100")
        #expect(stored == 1)
    }
}
