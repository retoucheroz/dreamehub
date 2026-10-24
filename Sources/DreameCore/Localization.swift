import Foundation

/// Interface language. Turkish source text is the key; `assets/i18n/en.json` maps it to English.
/// Missing entries fall back to Turkish, so an untranslated string never disappears.
public enum Localization {
    public static let languages = ["tr", "en"]
    private static let lock = NSLock()
    private static var english: [String: String] = [:]
    private static var preference = "system"
    private static var current = "tr"

    /// Resolved language: "tr" or "en".
    public static var language: String { lock.lock(); defer { lock.unlock() }; return current }
    /// Saved choice: "system", "tr" or "en".
    public static var savedPreference: String { lock.lock(); defer { lock.unlock() }; return preference }

    public static func configure(englishTable url: URL?, preference saved: String?) {
        let table = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        lock.lock(); english = table; lock.unlock()
        select(saved)
    }

    public static func select(_ saved: String?) {
        let choice = saved.flatMap { languages.contains($0) ? $0 : nil } ?? "system"
        let resolved = resolve(choice)
        lock.lock(); preference = choice; current = resolved; lock.unlock()
    }

    /// "system" follows macOS: Turkish when it is the first preferred language, otherwise English.
    public static func resolve(_ choice: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if languages.contains(choice) { return choice }
        return preferred.first?.lowercased().hasPrefix("tr") == true ? "tr" : "en"
    }

    /// Translates Turkish source text. `{name}` placeholders are filled from `values`.
    public static func text(_ turkish: String, _ values: [String: String] = [:]) -> String {
        lock.lock(); let translated = current == "en" ? english[turkish] ?? turkish : turkish; lock.unlock()
        return values.reduce(translated) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    /// Script for the web interface: the resolved language and, for English, the string table.
    public static func pageScript() -> String {
        lock.lock(); let language = current, choice = preference, table = current == "en" ? english : [:]; lock.unlock()
        // Default JSON escaping turns "/" into "\/", so no string can close the surrounding <script>.
        let strings = (try? JSONSerialization.data(withJSONObject: table, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "window.dreameLanguage=\"\(language)\";window.dreameLanguagePreference=\"\(choice)\";window.dreameStrings=\(strings);"
    }

    /// Replaces the `/*__LOCALE__*/` placeholder in index.html.
    public static func localizedPage(_ html: String) -> String { html.replacingOccurrences(of: "/*__LOCALE__*/", with: pageScript()) }
}
