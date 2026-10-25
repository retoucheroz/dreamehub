import XCTest
@testable import DreameCore

final class LocalizationTests: XCTestCase {
    private let table = ["Bilinmeyen komut.": "Unknown command.",
                         "Dreame sunucusu HTTP {code} döndürdü.": "The Dreame server returned HTTP {code}.",
                         "Kapat </script>": "Close </script><script>alert(1)</script>"]
    private var tableURL: URL!

    override func setUpWithError() throws {
        tableURL = FileManager.default.temporaryDirectory.appendingPathComponent("dreame-i18n-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: table).write(to: tableURL)
    }
    override func tearDownWithError() throws {
        // Other tests assert Turkish messages, so leave the shared state in Turkish.
        Localization.configure(englishTable: nil, preference: "tr")
        try? FileManager.default.removeItem(at: tableURL)
    }

    func testSystemChoiceFollowsFirstPreferredLanguage() {
        XCTAssertEqual(Localization.resolve("system", preferred: ["tr-TR", "en-US"]), "tr")
        XCTAssertEqual(Localization.resolve("system", preferred: ["TR"]), "tr")
        XCTAssertEqual(Localization.resolve("system", preferred: ["en-GB", "tr-TR"]), "en")
        XCTAssertEqual(Localization.resolve("system", preferred: ["de-DE"]), "en")
        XCTAssertEqual(Localization.resolve("system", preferred: []), "en")
    }
    func testExplicitChoicesIgnoreSystemLanguage() {
        XCTAssertEqual(Localization.resolve("tr", preferred: ["en-US"]), "tr")
        XCTAssertEqual(Localization.resolve("en", preferred: ["tr-TR"]), "en")
        Localization.configure(englishTable: tableURL, preference: "en")
        XCTAssertEqual(Localization.language, "en")
        XCTAssertEqual(Localization.savedPreference, "en")
    }
    func testInvalidChoiceFallsBackToSystem() {
        XCTAssertEqual(Localization.resolve("de", preferred: ["tr-TR"]), "tr")
        XCTAssertEqual(Localization.resolve("", preferred: ["en-US"]), "en")
        Localization.configure(englishTable: tableURL, preference: "de")
        XCTAssertEqual(Localization.savedPreference, "system")
        XCTAssertEqual(Localization.language, Localization.resolve("system"))
        Localization.select(nil)
        XCTAssertEqual(Localization.savedPreference, "system")
    }
    func testTextTranslatesAndFallsBackToTurkish() {
        Localization.configure(englishTable: tableURL, preference: "en")
        XCTAssertEqual(Localization.text("Bilinmeyen komut."), "Unknown command.")
        XCTAssertEqual(Localization.text("Tabloda olmayan metin."), "Tabloda olmayan metin.")
        Localization.select("tr")
        XCTAssertEqual(Localization.text("Bilinmeyen komut."), "Bilinmeyen komut.")
    }
    func testMissingTableKeepsTurkish() {
        Localization.configure(englishTable: URL(fileURLWithPath: "/nonexistent/dreame-en.json"), preference: "en")
        XCTAssertEqual(Localization.language, "en")
        XCTAssertEqual(Localization.text("Bilinmeyen komut."), "Bilinmeyen komut.")
    }
    func testPlaceholdersAreFilled() {
        Localization.configure(englishTable: tableURL, preference: "en")
        XCTAssertEqual(Localization.text("Dreame sunucusu HTTP {code} döndürdü.", ["code": "503"]), "The Dreame server returned HTTP 503.")
        XCTAssertEqual(Localization.text("Durum {code}", ["code": "7"]), "Durum 7")
        Localization.select("tr")
        XCTAssertEqual(Localization.text("Dreame sunucusu HTTP {code} döndürdü.", ["code": "503"]), "Dreame sunucusu HTTP 503 döndürdü.")
    }
    func testPageScriptCannotCloseScriptElement() throws {
        Localization.configure(englishTable: tableURL, preference: "en")
        let script = Localization.pageScript()
        XCTAssertTrue(script.hasPrefix("window.dreameLanguage=\"en\";window.dreameLanguagePreference=\"en\";"))
        XCTAssertFalse(script.lowercased().contains("</script"))
        let marker = try XCTUnwrap(script.range(of: "window.dreameStrings="))
        let json = String(script[marker.upperBound...].dropLast())
        let strings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
        XCTAssertEqual(strings, table)
        let page = Localization.localizedPage("<script>/*__LOCALE__*/</script>")
        XCTAssertEqual(page.components(separatedBy: "</script>").count, 2)
        Localization.select("tr")
        XCTAssertTrue(Localization.pageScript().hasSuffix("window.dreameStrings={};"))
    }
}
