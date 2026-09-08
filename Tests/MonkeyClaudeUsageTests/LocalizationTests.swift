import Testing
@testable import MonkeyClaudeUsageCore

@Suite("Localization")
struct LocalizationTests {
    /// A missing key falls through to English rather than failing, so nothing at runtime
    /// would ever point out a half-translated string.
    @Test("every key exists in both tables")
    func tablesAgree() {
        let english = Set(englishStrings.keys)
        let french = Set(frenchStrings.keys)

        #expect(english.subtracting(french).sorted() == [], "missing from French")
        #expect(french.subtracting(english).sorted() == [], "missing from English")
    }

    @Test("format placeholders match between the two languages")
    func placeholdersAgree() {
        for (key, english) in englishStrings {
            guard let french = frenchStrings[key] else { continue }
            #expect(
                Self.placeholders(english) == Self.placeholders(french),
                "\(key): \"\(english)\" vs \"\(french)\""
            )
        }
    }

    /// Counts `%@` and `%d` so a translation cannot silently drop an argument — which
    /// would crash `String(format:)` rather than merely look wrong.
    private static func placeholders(_ value: String) -> [String] {
        var found: [String] = []
        var iterator = value.makeIterator()
        var previous: Character?
        while let character = iterator.next() {
            if previous == "%", character != "%" { found.append("%\(character)") }
            previous = previous == "%" && character == "%" ? nil : character
        }
        return found
    }
}
