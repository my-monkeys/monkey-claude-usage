import Foundation

/// One reading, flattened to `limit id -> percent`, so a series survives the API
/// gaining or losing a window between two polls.
public struct UsageSample: Codable, Sendable, Equatable {
    public let date: Date
    public let values: [String: Double]

    public init(date: Date, values: [String: Double]) {
        self.date = date
        self.values = values
    }

    public init(snapshot: UsageSnapshot) {
        self.date = snapshot.fetchedAt
        self.values = Dictionary(
            snapshot.limits.map { ($0.id, $0.percent) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// The usage endpoint has no history of its own, so the app keeps its own: one JSON
/// file per account, appended on every successful poll and pruned on write.
public actor UsageHistoryStore {
    public static let defaultRetentionDays = 30

    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("fr.mymonkey.monkeyclaudeusage", isDirectory: true)
            .appendingPathComponent("history", isDirectory: true)
    }

    public func load(_ accountID: UUID) -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL(accountID)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([UsageSample].self, from: data)) ?? []
    }

    @discardableResult
    public func append(
        _ sample: UsageSample,
        for accountID: UUID,
        retentionDays: Int = defaultRetentionDays
    ) -> [UsageSample] {
        var samples = load(accountID)
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-Double(retentionDays) * 86_400)
        samples.removeAll { $0.date < cutoff }
        write(samples, for: accountID)
        return samples
    }

    public func delete(_ accountID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(accountID))
    }

    private func write(_ samples: [UsageSample], for accountID: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(samples) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(accountID), options: .atomic)
    }

    private func fileURL(_ accountID: UUID) -> URL {
        directory.appendingPathComponent("\(accountID.uuidString).json")
    }
}
