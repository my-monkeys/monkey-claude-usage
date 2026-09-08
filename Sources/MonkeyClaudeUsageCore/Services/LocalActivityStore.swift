import Foundation

/// Reads the token history Claude Code leaves behind on this Mac.
///
/// The usage endpoint reports a level, never a curve, so the only real history available
/// is the CLI's own transcripts under `~/.claude/projects/`. They carry no account
/// identifier, which is why this history is deliberately **not** attached to an account:
/// it is everything this Mac ran, whichever account was signed in at the time.
public actor LocalActivityStore {
    /// Claude Code's own bookkeeping messages, billed to nobody.
    private static let syntheticModel = "<synthetic>"
    private static let slotWidth: TimeInterval = 900
    private static let usageKey = Array("\"usage\"".utf8)
    /// Below this, a line cannot hold a usage block — skips the bookkeeping records.
    private static let minimumBilledLineLength = 64
    private static let headSampleLength = 512

    private let projectsDirectory: URL
    private let cacheURL: URL
    /// Decoded on first use, not in `init`: the cache runs to a couple of megabytes and
    /// the initialiser is reached from the main actor.
    private var loadedCache: Cache?

    public init(
        projectsDirectory: URL? = nil,
        cacheDirectory: URL? = nil
    ) {
        self.projectsDirectory = projectsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        let directory = cacheDirectory ?? UsageHistoryStore.defaultDirectory.deletingLastPathComponent()
        self.cacheURL = directory.appendingPathComponent("local-activity.json")
    }

    private var cache: Cache {
        get {
            if let loadedCache { return loadedCache }
            let loaded = Cache.load(from: cacheURL) ?? Cache()
            loadedCache = loaded
            return loaded
        }
        set { loadedCache = newValue }
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: projectsDirectory.path)
    }

    /// Slots covering every transcript found, newest scan folded into the cache.
    ///
    /// Only files whose size or modification date moved are re-read, and a growing file
    /// is read from where the last scan stopped — a full pass over ~1.7 GB takes seconds,
    /// an incremental one is immediate.
    public func slots() -> [ActivitySlot] {
        refresh()
        return merged()
    }

    /// What is on disk from the previous run, without touching the transcripts — lets the
    /// popover paint immediately while a refresh runs behind it.
    public func cachedSlots() -> [ActivitySlot] {
        merged()
    }

    public func refresh() {
        guard let files = try? FileManager.default.subpathsOfDirectory(atPath: projectsDirectory.path) else {
            return
        }

        var changed = false
        var live: Set<String> = []
        for relative in files where relative.hasSuffix(".jsonl") {
            let url = projectsDirectory.appendingPathComponent(relative)
            live.insert(relative)
            if scan(url, key: relative) { changed = true }
        }

        // A transcript the user deleted should stop counting.
        if cache.files.count != live.count {
            cache.files = cache.files.filter { live.contains($0.key) }
            changed = true
        }

        // Rewriting a few megabytes of fingerprints when nothing moved is the common case
        // — a poll every couple of minutes finds no new transcript at all.
        if changed { cache.save(to: cacheURL) }
    }

    // MARK: - Scanning

    /// - Returns: whether the cache changed and needs writing back.
    @discardableResult
    private func scan(_ url: URL, key: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return false }

        var entry = cache.files[key] ?? FileState()
        if entry.size == size, entry.modified == modified { return false }

        // A transcript that shrank was rewritten. So was one that grew while its head
        // changed — appending never rewrites what is already there, so a size that is
        // merely larger is not proof of an append. Comparing the first bytes is cheap
        // next to re-reading gigabytes, and wrong only in the impossible case of a
        // rewrite that keeps its opening line.
        if size < entry.offset || !headMatches(url, entry: entry) {
            entry = FileState()
        }

        // Memory-mapped and walked with memchr/memmem. Data's Collection conformance is
        // far too slow at this scale — the same pass costs fifty seconds through
        // `firstIndex(of:)` and two through raw pointers.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }

        var slots = entry.slots
        var seen = entry.seen
        var consumed = entry.offset
        entry.head = Self.fingerprint(data.prefix(Self.headSampleLength))

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let limit = Swift.min(raw.count, size)
            var offset = Swift.min(entry.offset, limit)

            Self.usageKey.withUnsafeBufferPointer { needle in
                while offset < limit {
                    let remaining = limit - offset
                    guard let newline = memchr(base + offset, 0x0A, remaining) else { break }
                    let length = UnsafeRawPointer(newline) - (base + offset)

                    if length > Self.minimumBilledLineLength,
                       memmem(base + offset, length, needle.baseAddress, needle.count) != nil {
                        absorb(
                            line: Data(bytes: base + offset, count: length),
                            into: &slots,
                            seen: &seen
                        )
                    }

                    offset += length + 1
                    consumed = offset
                }
            }
        }

        entry.size = size
        entry.modified = modified
        entry.offset = consumed
        entry.slots = slots
        entry.seen = seen
        cache.files[key] = entry
        return true
    }

    /// Cheap identity check for an append-only file: transcripts start with a session
    /// record that never changes, so a different opening means a different file.
    private func headMatches(_ url: URL, entry: FileState) -> Bool {
        guard entry.offset > 0 else { return true }
        guard let handle = try? FileHandle(forReadingFrom: url),
              let head = try? handle.read(upToCount: Self.headSampleLength) else { return false }
        try? handle.close()
        return Self.fingerprint(head) == entry.head
    }

    /// Most lines are user turns and tool results with no billing information; testing
    /// for the key before decoding avoids parsing JSON for nine lines out of ten.
    /// Claude Code writes each assistant message to its transcript twice — 46 945 of the
    /// 48 608 distinct ids in a three-month history — so counting lines would double every
    /// figure. Ids seen in this file are remembered across incremental scans.
    ///
    /// A further 359 ids appear in two files at once, from resumed sessions; those are
    /// left alone, being 0.7 % and only knowable by holding every id in memory at merge.
    private func absorb(
        line: Data,
        into slots: inout [Int64: [String: TokenCounts]],
        seen: inout Set<UInt64>
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String,
              model != Self.syntheticModel,
              let timestamp = ISO8601.date(from: object["timestamp"] as? String) else { return }

        if let identifier = message["id"] as? String {
            let fingerprint = Self.fingerprint(identifier)
            guard seen.insert(fingerprint).inserted else { return }
        }

        let counts = TokenCounts(
            input: usage["input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            cacheCreation: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0
        )
        guard counts.total > 0 else { return }

        let slot = Int64(floor(timestamp.timeIntervalSince1970 / Self.slotWidth))
        slots[slot, default: [:]][model, default: TokenCounts()].add(counts)
    }

    /// FNV-1a rather than `hashValue`: Swift's hashing is seeded per process, so a cached
    /// set would stop matching after a relaunch.
    private static func fingerprint(_ value: String) -> UInt64 {
        fingerprint(Data(value.utf8))
    }

    private static func fingerprint(_ value: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private func merged() -> [ActivitySlot] {
        var totals: [Int64: [String: TokenCounts]] = [:]
        for file in cache.files.values {
            for (slot, byModel) in file.slots {
                for (model, counts) in byModel {
                    totals[slot, default: [:]][model, default: TokenCounts()].add(counts)
                }
            }
        }
        return totals
            .map { ActivitySlot(start: Date(timeIntervalSince1970: Double($0.key) * Self.slotWidth), byModel: $0.value) }
            .sorted { $0.start < $1.start }
    }

    // MARK: - Cache

    private struct FileState: Codable {
        var size = 0
        var modified = Date.distantPast
        var offset = 0
        var slots: [Int64: [String: TokenCounts]] = [:]
        var seen: Set<UInt64> = []
        var head: UInt64 = 0
    }

    private struct Cache: Codable {
        var files: [String: FileState] = [:]

        static func load(from url: URL) -> Cache? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Cache.self, from: data)
        }

        func save(to url: URL) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(self) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
