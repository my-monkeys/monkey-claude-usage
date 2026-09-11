import Foundation

/// What identifies an account in the menu bar, where there is room for about two
/// characters and nothing more.
public enum AccountBadge: Equatable, Sendable {
    case text(String)
    /// An SF Symbol name. Renders as a template image, so it inherits the menu bar's
    /// contrast the same way the bars do.
    case symbol(String)

    /// Symbols offered in Settings. Deliberately few and unambiguous at nine points —
    /// anything with fine detail turns to mush at that size.
    public static let offered = [
        "person.fill", "briefcase.fill", "house.fill", "building.2.fill",
        "star.fill", "heart.fill", "bolt.fill", "leaf.fill",
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill",
    ]

    /// Round-trips through the single string stored in preferences.
    public init?(stored: String?) {
        guard let stored, !stored.isEmpty else { return nil }
        if let name = stored.stripping(prefix: Self.symbolPrefix) {
            self = .symbol(name)
        } else {
            self = .text(stored)
        }
    }

    public var stored: String {
        switch self {
        case let .text(value): value
        case let .symbol(name): Self.symbolPrefix + name
        }
    }

    private static let symbolPrefix = "sf:"
}

private extension String {
    func stripping(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
