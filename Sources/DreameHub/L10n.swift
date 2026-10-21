import Foundation

/// Native strings share the web UI dictionaries (assets/i18n/<language>.js), keyed by the Turkish source text.
enum L10n {
    static let supported = ["tr","en","it","sv"]
    /// Explicit choice from the panel; nil follows the macOS language order.
    static var choice:String? { UserDefaults.standard.string(forKey:"dreameLanguage").flatMap { supported.contains($0) ? $0 : nil } }
    static var language:String {
        choice ?? Locale.preferredLanguages.lazy.map { String($0.prefix(2)).lowercased() }.first(where:supported.contains) ?? "en"
    }
    private static var loaded:(language:String,strings:[String:String])?
    static func t(_ text:String) -> String {
        let language = language
        guard language != "tr" else { return text }
        if loaded?.language != language { loaded = (language,dictionary(language)) }
        return loaded?.strings[text] ?? text
    }
    private static func dictionary(_ language:String) -> [String:String] {
        let url = ResourcePaths.root.appendingPathComponent("assets/i18n/\(language).js")
        guard let source = try? String(contentsOf:url,encoding:.utf8),let start = source.firstIndex(of:"{"),let end = source.lastIndex(of:"}") else { return [:] }
        return (try? JSONDecoder().decode([String:String].self,from:Data(source[start...end].utf8))) ?? [:]
    }
}
