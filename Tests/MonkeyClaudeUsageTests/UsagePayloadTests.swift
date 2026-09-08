import Foundation
import Testing
@testable import MonkeyClaudeUsageCore

/// Captured from a real `/api/oauth/usage` response: the legacy per-model fields are
/// null and the model-scoped window only exists inside `limits`.
private let modernPayload = """
{
  "five_hour": {"utilization": 31.0, "resets_at": "2026-09-08T21:40:00.435533+00:00"},
  "seven_day": {"utilization": 39.0, "resets_at": "2026-09-14T18:00:00.435550+00:00"},
  "seven_day_opus": null,
  "seven_day_sonnet": null,
  "limits": [
    {"kind": "session", "group": "session", "percent": 31, "severity": "normal",
     "resets_at": "2026-09-08T21:40:00.435533+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_all", "group": "weekly", "percent": 39, "severity": "normal",
     "resets_at": "2026-09-14T18:00:00.435550+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 54, "severity": "normal",
     "resets_at": "2026-09-14T18:00:00.435695+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": true}
  ],
  "extra_usage": {"is_enabled": false, "utilization": null, "used_credits": null, "monthly_limit": null}
}
"""

private let legacyPayload = """
{
  "five_hour": {"utilization": 12.0, "resets_at": "2026-09-08T21:40:00Z"},
  "seven_day": {"utilization": 20.0, "resets_at": "2026-09-14T18:00:00Z"},
  "seven_day_opus": {"utilization": 5.0, "resets_at": "2026-09-14T18:00:00Z"},
  "seven_day_sonnet": null
}
"""

private func decode(_ json: String) throws -> UsageSnapshot {
    try JSONDecoder().decode(UsagePayload.self, from: Data(json.utf8)).snapshot()
}

@Suite("Usage payload")
struct UsagePayloadTests {
    @Test("the limits array wins and carries the model-scoped window")
    func modernShape() throws {
        let snapshot = try decode(modernPayload)

        #expect(snapshot.limits.count == 3)
        #expect(snapshot.limits.map(\.shortLabel) == ["5h", "7d", "Fa"])

        let fable = try #require(snapshot.limits.last)
        #expect(fable.modelName == "Fable")
        #expect(fable.percent == 54)
        #expect(fable.isActive)
        #expect(fable.resetsAt != nil)
    }

    @Test("six fractional digits still parse")
    func fractionalSeconds() throws {
        let snapshot = try decode(modernPayload)
        let session = try #require(snapshot.limits.first)
        let expected = Date(timeIntervalSince1970: 1_788_903_600)
        #expect(abs(try #require(session.resetsAt).timeIntervalSince(expected)) < 1)
    }

    @Test("falls back to the fixed fields when limits is absent")
    func legacyShape() throws {
        let snapshot = try decode(legacyPayload)

        #expect(snapshot.limits.count == 3)
        #expect(snapshot.limits[0].isSession)
        #expect(snapshot.limits[2].modelName == "Opus")
        // seven_day_sonnet is null and must not become a phantom zero-percent window.
        #expect(!snapshot.limits.contains { $0.modelName == "Sonnet" })
    }

    @Test("ordering is session, then weekly, then per-model")
    func ordering() throws {
        let snapshot = try decode(modernPayload)
        #expect(snapshot.limits.map(\.sortRank) == [0, 1, 2])
    }

    @Test("a saturated window is what the menu bar counts down to")
    func saturation() {
        let soon = Date().addingTimeInterval(3600)
        let later = Date().addingTimeInterval(86_400)
        let snapshot = UsageSnapshot(limits: [
            UsageLimit(kind: "session", group: "session", percent: 100, resetsAt: later),
            UsageLimit(kind: "weekly_scoped", group: "weekly", percent: 100, resetsAt: soon, modelName: "Fable"),
            UsageLimit(kind: "weekly_all", group: "weekly", percent: 42, resetsAt: later),
        ])

        #expect(snapshot.saturatedLimits.count == 2)
        #expect(snapshot.nextRelease?.modelName == "Fable")
    }

    @Test("a locked window counts as saturated even below 100 %")
    func lockedCountsAsSaturated() {
        let limit = UsageLimit(kind: "session", percent: 12, lockedReason: "policy")
        #expect(limit.isSaturated)
    }

    @Test("two model windows stay distinct when only the model id is given")
    func identityFallsBackToModelID() throws {
        let json = """
        {"limits": [
          {"kind": "weekly_scoped", "group": "weekly", "percent": 10,
           "scope": {"model": {"id": "claude-opus-4-6", "display_name": null}}},
          {"kind": "weekly_scoped", "group": "weekly", "percent": 20,
           "scope": {"model": {"id": "claude-sonnet-5", "display_name": null}}}
        ]}
        """
        let snapshot = try decode(json)
        // Sharing an id would collapse them into one chart series, one menu bar row, and
        // one surviving entry in the history file.
        #expect(Set(snapshot.limits.map(\.id)).count == 2)
    }

    @Test("a spent window with no reset date loses to one that has a date")
    func releaseOrderPrefersKnownResets() {
        let dated = UsageLimit(kind: "weekly_all", percent: 100,
                               resetsAt: Date().addingTimeInterval(86_400))
        let undated = UsageLimit(kind: "session", percent: 100)
        #expect([undated, dated].firstToRelease?.kind == "weekly_all")
        #expect([undated].firstToRelease?.kind == "session")
        #expect([UsageLimit(kind: "session", percent: 40)].firstToRelease == nil)
    }
}

@Suite("Countdown")
struct CountdownTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("stays within the four characters the menu bar can fit")
    func shortForm() {
        #expect(Countdown.short(until: now.addingTimeInterval(30), now: now) == "<1m")
        #expect(Countdown.short(until: now.addingTimeInterval(45 * 60), now: now) == "45m")
        #expect(Countdown.short(until: now.addingTimeInterval(2 * 3600 + 8 * 60), now: now) == "2h08")
        #expect(Countdown.short(until: now.addingTimeInterval(6 * 86_400), now: now).count <= 4)
    }

    @Test("never counts backwards past a reset the app has not seen yet")
    func clampsToZero() {
        #expect(Countdown.short(until: now.addingTimeInterval(-3600), now: now) == "<1m")
    }
}

@Suite("History")
struct HistoryTests {
    @Test("samples flatten to limit ids and prune past the retention window")
    func appendAndPrune() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let store = UsageHistoryStore(directory: directory)
        let account = UUID()
        defer { try? FileManager.default.removeItem(at: directory) }

        let old = UsageSample(date: Date().addingTimeInterval(-40 * 86_400), values: ["session||": 10])
        _ = await store.append(old, for: account, retentionDays: 30)

        let snapshot = UsageSnapshot(limits: [
            UsageLimit(kind: "session", percent: 31),
            UsageLimit(kind: "weekly_scoped", percent: 54, modelName: "Fable"),
        ])
        let samples = await store.append(UsageSample(snapshot: snapshot), for: account, retentionDays: 30)

        #expect(samples.count == 1)
        #expect(samples[0].values["weekly_scoped|Fable|"] == 54)
    }
}
