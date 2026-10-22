import Foundation
import Testing
@testable import ICTCore

@Suite struct GoogleTranslateTests {
    @Test func languageCodes() {
        #expect(GoogleTranslate.languageCode("zh-Hans") == "zh-CN")
        #expect(GoogleTranslate.languageCode("zh-Hant") == "zh-TW")
        #expect(GoogleTranslate.languageCode("en") == "en")
    }

    @Test func requestURLEscapesText() {
        let url = GoogleTranslate.requestURL(text: "1 + 1 = 2 & more?", source: "en", target: "zh-Hans")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "q" }?.value == "1 + 1 = 2 & more?")
        #expect(items.first { $0.name == "tl" }?.value == "zh-CN")
        #expect(url.absoluteString.contains("%2B"))
    }

    @Test func parseJoinsSegments() throws {
        let data = Data(#"[[["你好。","Hello.",null,null,10],["世界","World",null,null,10]],null,"en"]"#.utf8)
        #expect(try GoogleTranslate.parse(data) == "你好。世界")
    }

    @Test func parseRejectsUnexpectedReply() {
        #expect(throws: GoogleTranslate.ParseError.self) { try GoogleTranslate.parse(Data("{}".utf8)) }
        #expect(throws: GoogleTranslate.ParseError.self) { try GoogleTranslate.parse(Data("[[]]".utf8)) }
    }
}
