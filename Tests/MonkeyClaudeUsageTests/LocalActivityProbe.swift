import Foundation
import Testing
@testable import MonkeyClaudeUsageCore

/// Not a unit test of behaviour — a probe run against the real transcripts on this Mac to
/// confirm the incremental reader agrees with a straight full parse. Skipped elsewhere.
@Suite("Local activity probe", .disabled(if: ProcessInfo.processInfo.environment["MCU_PROBE"] == nil))
struct LocalActivityProbe {
    @Test("scans the real transcripts")
    func scan() async {
        let cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let store = LocalActivityStore(cacheDirectory: cacheDirectory)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let cold = Date()
        let slots = await store.slots()
        let coldSeconds = Date().timeIntervalSince(cold)

        let warm = Date()
        _ = await store.slots()
        let warmSeconds = Date().timeIntervalSince(warm)

        let totals = slots.reduce(into: TokenCounts()) { $0.add($1.total) }
        let models = Set(slots.flatMap(\.byModel.keys)).sorted()
        let span = (slots.first?.start, slots.last?.start)

        print("""
        slots: \(slots.count)
        cold scan: \(String(format: "%.2f", coldSeconds)) s   warm scan: \(String(format: "%.2f", warmSeconds)) s
        tokens: total \(totals.total / 1_000_000) M  (output \(totals.output / 1_000_000) M, \
        cacheRead \(totals.cacheRead / 1_000_000) M)
        models: \(models)
        span: \(span.0.map(String.init(describing:)) ?? "-") → \(span.1.map(String.init(describing:)) ?? "-")
        """)

        #expect(!slots.isEmpty)
    }
}
