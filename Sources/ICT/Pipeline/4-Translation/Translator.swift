import Foundation
import ICTCore

typealias ContextPairs = [(source: String, translation: String)]

protocol Translator: AnyObject, Sendable {
    var name: String { get }
    /// 翻译一个片段。`onPartial` 会收到逐步变长的译文（如果引擎支持流式输出）。
    func translate(_ text: String, context: ContextPairs, onPartial: @escaping @Sendable (String) -> Void) async throws -> String
    func shutdown()
}

extension Translator {
    func shutdown() {}
}

enum TranslatorError: LocalizedError {
    case claudeNotFound
    case claudeFailed(String)
    case timeout
    case processExited(String)
    case appleUnavailable(String, String)
    case googleFailed(String)
    /// 通过 API 调用模型出错。`persistent`：密钥错误、模型不存在等，重试没有意义。
    case apiFailed(String, persistent: Bool)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            L("找不到 claude 命令。请先安装 Claude Code，或在设置中填写 Claude 路径。")
        case .claudeFailed(let message):
            message.localizedCaseInsensitiveContains("not logged in")
                ? L("Claude Code 未登录：请在终端运行 claude，输入 /login 登录一次。")
                : L("Claude 翻译出错：%@", message)
        case .timeout:
            L("Claude 翻译超时。")
        case .processExited(let stderr):
            L("Claude 进程退出：%@", stderr.isEmpty ? L("无输出") : stderr)
        case .apiFailed(let message, _):
            L("模型服务出错：%@", message)
        case .googleFailed(let message):
            L("Google 翻译出错：%@", message)
        case .appleUnavailable(let pair, _):
            L("Apple 本地翻译不可用：%@。请在“系统设置 › 通用 › 语言与地区 › 翻译语言”中下载对应语言。", pair)
        }
    }

    /// 这类错误重试没有意义，应直接切换到兜底引擎并提示用户。
    var isPersistent: Bool {
        switch self {
        case .claudeNotFound: true
        case .claudeFailed(let m): m.localizedCaseInsensitiveContains("not logged in")
        case .apiFailed(_, let persistent): persistent
        default: false
        }
    }
}
