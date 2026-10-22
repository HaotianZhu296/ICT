import Foundation
import ICTCore
import Translation

/// Apple 系统自带的离线翻译（Translation 框架）。模型由系统管理，不占用本应用内存。
/// 不依赖界面直接创建翻译会话需要 macOS 26；更早的系统不提供这个选项。
@available(macOS 26, *)
final class AppleTranslator: Translator, @unchecked Sendable {
    let name = L("Apple 本地翻译")
    private let session: TranslationSession
    private let pair: String

    init(source: LanguageOption, target: LanguageOption) {
        session = TranslationSession(installedSource: Locale.Language(identifier: source.translationCode),
                                     target: Locale.Language(identifier: target.translationCode))
        pair = "\(L(source.displayName)) → \(L(target.displayName))"
    }

    /// 语言包是否已经下载到本机。
    static func isInstalled(source: LanguageOption, target: LanguageOption) async -> Bool {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: source.translationCode),
                                                         to: Locale.Language(identifier: target.translationCode))
        return status == .installed
    }

    func translate(_ text: String, context: ContextPairs, onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        let session = self.session
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await session.translate(text).targetText }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw TranslatorError.timeout
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch {
            throw TranslatorError.appleUnavailable(pair, String(describing: error))
        }
    }
}
