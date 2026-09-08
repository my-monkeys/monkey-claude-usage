import Foundation
import Testing

/// `appcast.xml` is a committed file that no build step reads, and Sparkle fails silently
/// over a bad one: a repeated `sparkle:version` offers the same update forever, a version
/// that does not grow never offers anything at all. Both are invisible until a user
/// complains, so they are checked here — `scripts/update-appcast.py` writes this file and
/// `scripts/release.sh` commits it.
@Suite("Appcast")
struct AppcastTests {
    private static let feed = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Tests/MonkeyClaudeUsageTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("appcast.xml")

    @Test("each release has its own build number, newest first, and a signed enclosure")
    func feedIsConsistent() throws {
        // elements(forName:) rather than XPath: libxml cannot resolve the sparkle: prefix
        // from a node context, so "sparkle:version" throws instead of matching.
        let document = try XMLDocument(contentsOf: Self.feed)
        let channel = try #require(document.rootElement()?.elements(forName: "channel").first)
        let items = channel.elements(forName: "item")
        #expect(!items.isEmpty)

        var builds: [Int] = []
        for item in items {
            builds.append(try #require(Int(text(item, "sparkle:version"))))
            #expect(!text(item, "sparkle:shortVersionString").isEmpty)

            let enclosure = try #require(item.elements(forName: "enclosure").first)
            #expect(attribute(enclosure, "url").hasSuffix(".dmg"))
            #expect(Int(attribute(enclosure, "length")) ?? 0 > 0)
            #expect(!attribute(enclosure, "sparkle:edSignature").isEmpty)
        }

        #expect(Set(builds).count == builds.count, "two releases share a sparkle:version")
        #expect(builds == builds.sorted(by: >), "items are not ordered newest first")
    }

    private func text(_ element: XMLElement, _ name: String) -> String {
        element.elements(forName: name).first?.stringValue ?? ""
    }

    private func attribute(_ element: XMLElement, _ name: String) -> String {
        element.attribute(forName: name)?.stringValue ?? ""
    }
}
