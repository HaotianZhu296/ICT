import Foundation
import ICTCore

/// Google 翻译（免费网页接口，不需要密钥，需要联网）。
final class GoogleTranslator: Translator, @unchecked Sendable {
    let name = L("Google 翻译")
    private let source: String
    private let target: String
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    init(source: LanguageOption, target: LanguageOption) {
        self.source = source.translationCode
        self.target = target.translationCode
    }

    /// 每句单独翻译，不带上下文：试过把前两句原文一起发（LiveCaptions-Translator 的做法），
    /// 2026-10-22 实测 8 句里 7 句译文完全一样、1 句反而错了，Google 免费接口基本不利用上下文。
    func translate(_ text: String, context: ContextPairs, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        let url = GoogleTranslate.requestURL(text: text, source: source, target: target)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TranslatorError.googleFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TranslatorError.googleFailed("HTTP \(http.statusCode)")
        }
        do {
            return try GoogleTranslate.parse(data)
        } catch {
            throw TranslatorError.googleFailed(L("无法识别的回复"))
        }
    }

    /// 先建立好连接（第一次请求要多花约 0.4 秒握手），第一句字幕不用等。
    func warmUp() {
        Task { _ = try? await translate("Hello", context: [], onPartial: { _ in }) }
    }

    func shutdown() { session.invalidateAndCancel() }
}
