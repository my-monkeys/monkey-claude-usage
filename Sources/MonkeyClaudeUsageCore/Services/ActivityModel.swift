import Combine
import Foundation

/// Drives the local-activity pane: reads the cache first so the popover paints at once,
/// then rescans behind it.
@MainActor
public final class ActivityModel: ObservableObject {
    @Published public private(set) var slots: [ActivitySlot] = []
    @Published public private(set) var isScanning = false
    @Published public private(set) var isAvailable = true
    @Published public private(set) var lastScan: Date?

    private let store: LocalActivityStore
    private var scanTask: Task<Void, Never>?

    /// Rescanning on every popover opening would re-stat a hundred files for nothing.
    private static let minimumInterval: TimeInterval = 120

    public init(store: LocalActivityStore = LocalActivityStore()) {
        self.store = store
    }

    public func load() {
        guard scanTask == nil else { return }
        if let lastScan, Date().timeIntervalSince(lastScan) < Self.minimumInterval { return }

        scanTask = Task { [store] in
            let cached = await store.cachedSlots()
            if !cached.isEmpty, slots.isEmpty { slots = cached }

            isAvailable = await store.isAvailable
            guard isAvailable else {
                scanTask = nil
                return
            }

            isScanning = slots.isEmpty
            slots = await store.slots()
            lastScan = Date()
            isScanning = false
            scanTask = nil
        }
    }

    public var models: [String] {
        var totals: [String: Int] = [:]
        for slot in slots {
            for (model, counts) in slot.byModel { totals[model, default: 0] += counts.total }
        }
        return totals.sorted { $0.value > $1.value }.map(\.key)
    }
}
