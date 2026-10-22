import Foundation

/// Google 翻译的免费网页接口（translate.googleapis.com，client=gtx）：不需要 API 密钥，也没有官方保证，
/// 请求太频繁时可能被限流。
public enum GoogleTranslate {
    /// Google 的语言代码：简繁中文用地区写法，其余和 Apple Translation 相同。
    public static func languageCode(_ translationCode: String) -> String {
        switch translationCode {
        case "zh-Hans": "zh-CN"
        case "zh-Hant": "zh-TW"
        default: translationCode
        }
    }

    public static func requestURL(text: String, source: String, target: String) -> URL {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: languageCode(source)),
            URLQueryItem(name: "tl", value: languageCode(target)),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        // URLComponents 不转义 “+”，服务器会把它当成空格。
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    public struct ParseError: Error {}

    /// 回复是嵌套数组：第一项是逐段译文 `[[译文, 原文, …], …]`，拼起来就是整句译文。
    public static func parse(_ data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else { throw ParseError() }
        let text = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
        guard !text.isEmpty else { throw ParseError() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
