import AppKit
import ICTCore
import Observation

enum AudioSourceMode: String, CaseIterable, Identifiable {
    case microphone, system, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .microphone: L("麦克风")
        case .system: L("系统音频")
        case .both: L("麦克风和系统音频")
        }
    }
    var shortTitle: String {
        switch self {
        case .microphone: L("麦克风")
        case .system: L("系统音频")
        case .both: L("两者")
        }
    }
    /// 字幕工具栏上的图标。
    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .system: "speaker.wave.2.fill"
        case .both: "waveform.badge.mic"
        }
    }
}

/// 用户添加的模型服务：自己的 API（OpenAI 兼容或 Anthropic），或 Ollama、LM Studio 等本地服务。
/// API 密钥保存在钥匙串里（`KeychainStore`），不在这里。
struct ModelEndpoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var format: ChatAPIFormat
    var baseURL: String
    var models: [String]
    var isLocal: Bool { ChatEndpointPreset.isLocal(baseURL: baseURL) }
}

/// 翻译或 AI 助手使用的模型。
enum ModelChoice: Hashable, Codable {
    /// 系统自带的离线翻译（只能翻译，不能做 AI 助手、笔记和自动纠错）。
    case apple
    /// Google 翻译的免费网页接口：不需要密钥，需要联网（同样只能翻译）。
    case google
    /// 本机 Claude Code 命令行：haiku / sonnet / opus。
    case claudeCode(String)
    /// 某个模型服务里的某个模型。
    case endpoint(UUID, String)

    var isLanguageModel: Bool { self != .apple && self != .google }
}

/// 设置界面和菜单里的一组模型。
struct ModelGroup: Identifiable {
    let title: String
    let choices: [ModelChoice]
    var id: String { title }
}

/// 外观：跟随系统（默认）、浅色、深色。字幕、AI 助手和各个窗口一起变。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("跟随系统")
        case .light: L("浅色")
        case .dark: L("深色")
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// 界面语言。macOS 按程序自己域里的 `AppleLanguages` 选界面语言，启动时就定了，改完要重新打开 App。
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    /// 语言名称用它自己的文字写，选错了也认得出来。
    var title: String {
        switch self {
        case .system: L("跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    static func load(_ d: UserDefaults) -> InterfaceLanguage {
        guard d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil,
              let first = d.stringArray(forKey: "AppleLanguages")?.first
        else { return .system }
        return first.hasPrefix("zh") ? .chinese : .english
    }

    func save(_ d: UserDefaults) {
        if self == .system { d.removeObject(forKey: "AppleLanguages") } else { d.set([rawValue], forKey: "AppleLanguages") }
    }

    /// 这次启动时用的界面语言（和设置不同时提示重新打开）。
    static let atLaunch = load(.standard)
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case bilingual, translationOnly, sourceOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bilingual: L("双语")
        case .translationOnly: L("仅译文")
        case .sourceOnly: L("仅原文")
        }
    }
}

/// 所有用户设置，改动即时写入 UserDefaults。
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()
    @ObservationIgnored private let defaults = UserDefaults.standard

    var sourceLanguage: String { didSet { save("sourceLanguage", sourceLanguage) } }
    var targetLanguage: String { didSet { save("targetLanguage", targetLanguage) } }
    var audioSource: AudioSourceMode { didSet { save("audioSource", audioSource.rawValue) } }
    /// 字幕翻译使用的模型。
    var translationModel: ModelChoice { didSet { saveJSON("translationModel", translationModel) } }
    /// 用户添加的模型服务。
    var endpoints: [ModelEndpoint] { didSet { saveJSON("endpoints", endpoints) } }
    var claudePath: String { didSet { save("claudePath", claudePath) } }
    /// 并行跑一个中文识别器，过滤掉旁边的中文说话声（讲话语言不是中文时才有效）。
    var filterChinese: Bool { didSet { save("filterChinese", filterChinese) } }
    /// 麦克风降噪（系统语音处理：降噪、回声消除、自动增益）。
    var micNoiseReduction: Bool { didSet { save("micNoiseReduction", micNoiseReduction) } }
    /// 字幕底部的运行状态条（有没有声音、识别是否清晰、翻译积压）。
    var showStatusBar: Bool { didSet { save("showStatusBar", showStatusBar) } }
    /// 识别困难（口音重、语速快、噪音大）时让大模型按发音和上下文纠正识别错误。默认打开（2026-10-22 用户要求）。
    var autoCorrect: Bool { didSet { save("autoCorrect", autoCorrect) } }
    /// 纠正改过原文时，在记录和字幕记录窗口里同时保留识别器原来给出的文字。
    var keepOriginalText: Bool { didSet { save("keepOriginalText", keepOriginalText) } }
    /// AI 助手和笔记使用的模型（必须是大模型），以及面板是否显示、大小。
    var assistantModel: ModelChoice { didSet { saveJSON("assistantModelChoice", assistantModel) } }
    /// AI 助手面板是否打开：每次启动都默认收起，用到时才打开（不保存）。
    var assistantVisible = false
    var assistantWidth: Double { didSet { save("assistantWidth", assistantWidth) } }
    var assistantHeight: Double { didSet { save("assistantHeight", assistantHeight) } }

    var displayMode: DisplayMode { didSet { save("displayMode", displayMode.rawValue) } }
    var appearance: AppearanceMode { didSet { save("appearance", appearance.rawValue) } }
    var interfaceLanguage: InterfaceLanguage { didSet { interfaceLanguage.save(.standard) } }
    var translationFontSize: Double { didSet { save("translationFontSize", translationFontSize) } }
    var sourceFontSize: Double { didSet { save("sourceFontSize", sourceFontSize) } }
    var backgroundOpacity: Double { didSet { save("backgroundOpacity", backgroundOpacity) } }
    var visibleLines: Int { didSet { save("visibleLines", visibleLines) } }
    var overlayWidth: Double { didSet { save("overlayWidth", overlayWidth) } }
    /// 最小化到菜单栏时小字幕的宽度（pt）。
    var menuBarWidth: Double { didSet { save("menuBarWidth", menuBarWidth) } }
    /// 0 = 自动高度（显示最近 N 句）；大于 0 = 固定高度，字幕可滚动查看历史。
    var overlayHeight: Double { didSet { save("overlayHeight", overlayHeight) } }
    var clickThrough: Bool { didSet { save("clickThrough", clickThrough) } }
    /// 字幕置顶：总在所有窗口上面；取消后像普通窗口一样可以被别的窗口盖住。
    var pinned: Bool { didSet { save("pinned", pinned) } }


    var transcriptFolder: String { didSet { save("transcriptFolder", transcriptFolder) } }

    private init() {
        let d = UserDefaults.standard
        sourceLanguage = d.string(forKey: "sourceLanguage") ?? "en-US"
        targetLanguage = d.string(forKey: "targetLanguage") ?? "zh-Hans"
        audioSource = AudioSourceMode(rawValue: d.string(forKey: "audioSource") ?? "") ?? .both
        // 旧版本只有“引擎 + Claude 模型”两个设置，迁移过来保持原来的选择。
        // 新用户默认用 Google 翻译：不需要配置，所有系统版本都能用。
        let legacyModel = d.string(forKey: "claudeModel") ?? "haiku"
        let legacyEngine = d.string(forKey: "engine")
        let translation = Self.loadJSON(ModelChoice.self, "translationModel")
            ?? (legacyEngine == "apple" ? .apple : legacyEngine != nil ? .claudeCode(legacyModel) : .google)
        translationModel = translation
        endpoints = Self.loadJSON([ModelEndpoint].self, "endpoints") ?? []
        claudePath = d.string(forKey: "claudePath") ?? ""
        filterChinese = d.object(forKey: "filterChinese") as? Bool ?? true
        let assistant = Self.loadJSON(ModelChoice.self, "assistantModelChoice")
            ?? .claudeCode(d.string(forKey: "assistantModel") ?? "sonnet")
        assistantModel = assistant
        autoCorrect = d.object(forKey: "autoCorrect") as? Bool ?? true
        keepOriginalText = d.object(forKey: "keepOriginalText") as? Bool ?? false
        showStatusBar = d.object(forKey: "showStatusBar") as? Bool ?? true
        micNoiseReduction = d.object(forKey: "micNoiseReduction") as? Bool ?? false
        assistantWidth = d.object(forKey: "assistantWidth") as? Double ?? 380
        assistantHeight = d.object(forKey: "assistantHeight") as? Double ?? 420
        displayMode = DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .bilingual
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        interfaceLanguage = .atLaunch
        translationFontSize = d.object(forKey: "translationFontSize") as? Double ?? 18
        sourceFontSize = d.object(forKey: "sourceFontSize") as? Double ?? 11
        backgroundOpacity = d.object(forKey: "backgroundOpacity") as? Double ?? 0.62
        visibleLines = d.object(forKey: "visibleLines") as? Int ?? 2
        let overlaySize = Self.defaultOverlaySize
        overlayWidth = d.object(forKey: "overlayWidth") as? Double ?? overlaySize.width
        menuBarWidth = d.object(forKey: "menuBarWidth") as? Double ?? 240
        overlayHeight = d.object(forKey: "overlayHeight") as? Double ?? overlaySize.height
        clickThrough = d.object(forKey: "clickThrough") as? Bool ?? false
        pinned = d.object(forKey: "pinned") as? Bool ?? true

        transcriptFolder = d.string(forKey: "transcriptFolder")
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/ICT").path
    }

    var source: LanguageOption { LanguageOption.source(sourceLanguage) }
    var target: LanguageOption { LanguageOption.target(targetLanguage) }
    /// 字幕语言是中文/日文/韩文（用来清理 Claude 偶尔混进译文的英文自言自语）。
    var targetIsCJK: Bool { ["zh", "ja", "ko"].contains { target.translationCode.hasPrefix($0) } }
    var fixedOverlayHeight: Bool {
        get { overlayHeight > 0 }
        set { overlayHeight = newValue ? 260 : 0 }
    }
    /// 字幕窗口的默认大小：面积是屏幕的 1/16，宽高比 3:1。
    static var defaultOverlaySize: (width: Double, height: Double) {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.frame.size ?? NSSize(width: 1470, height: 956)
        let width = max(320, (3 * screen.width * screen.height / 16).squareRoot().rounded())
        return (width, (width / 3).rounded())
    }

    func resetOverlaySize() {
        let size = Self.defaultOverlaySize
        overlayWidth = size.width
        overlayHeight = size.height
    }

    /// 用来识别“旁边有人说中文”的哨兵识别语言；不需要过滤时为 nil。
    var guardLocale: String? { filterChinese && !sourceLanguage.hasPrefix("zh") ? "zh-CN" : nil }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }

    private func saveJSON(_ key: String, _ value: some Encodable) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - 打开设置时的快照

    /// 打开设置窗口时的值：关窗口时选“取消”就恢复成这样。
    /// 字幕窗口的大小（在字幕上拖出来的）和模型服务（单独的窗口）不在里面。
    struct Snapshot: Equatable {
        var sourceLanguage, targetLanguage: String
        var audioSource: AudioSourceMode
        var translationModel: ModelChoice
        var claudePath: String
        var filterChinese, micNoiseReduction, showStatusBar, autoCorrect, keepOriginalText: Bool
        var displayMode: DisplayMode
        var appearance: AppearanceMode
        var translationFontSize, sourceFontSize, backgroundOpacity: Double
        var visibleLines: Int
        var clickThrough, pinned: Bool
        var transcriptFolder: String
    }

    var snapshot: Snapshot {
        Snapshot(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, audioSource: audioSource,
                 translationModel: translationModel, claudePath: claudePath, filterChinese: filterChinese,
                 micNoiseReduction: micNoiseReduction, showStatusBar: showStatusBar, autoCorrect: autoCorrect,
                 keepOriginalText: keepOriginalText, displayMode: displayMode, appearance: appearance,
                 translationFontSize: translationFontSize, sourceFontSize: sourceFontSize,
                 backgroundOpacity: backgroundOpacity, visibleLines: visibleLines, clickThrough: clickThrough,
                 pinned: pinned, transcriptFolder: transcriptFolder)
    }

    func restore(_ s: Snapshot) {
        sourceLanguage = s.sourceLanguage
        targetLanguage = s.targetLanguage
        audioSource = s.audioSource
        translationModel = s.translationModel
        claudePath = s.claudePath
        filterChinese = s.filterChinese
        micNoiseReduction = s.micNoiseReduction
        showStatusBar = s.showStatusBar
        autoCorrect = s.autoCorrect
        keepOriginalText = s.keepOriginalText
        displayMode = s.displayMode
        appearance = s.appearance
        translationFontSize = s.translationFontSize
        sourceFontSize = s.sourceFontSize
        backgroundOpacity = s.backgroundOpacity
        visibleLines = s.visibleLines
        clickThrough = s.clickThrough
        pinned = s.pinned
        transcriptFolder = s.transcriptFolder
    }

    // MARK: - 模型

    func endpoint(_ id: UUID) -> ModelEndpoint? { endpoints.first { $0.id == id } }

    /// Apple 本地翻译需要 macOS 26。
    static var appleTranslationAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    func displayName(_ choice: ModelChoice) -> String {
        switch choice {
        case .apple:
            return L("Apple 本地翻译")
        case .google:
            return L("Google 翻译")
        case .claudeCode(let model):
            return "Claude " + model.prefix(1).uppercased() + model.dropFirst()
        case .endpoint(let id, let model):
            guard let endpoint = endpoint(id) else { return model }
            return "\(endpoint.name) · \(model)"
        }
    }

    /// 可选的模型，分为基础（只能翻译）、云端（Claude Code 与自己的 API）、本地三组。
    func modelGroups(includeBasic: Bool) -> [ModelGroup] {
        // Opus 最准确但最慢，也一直列出来（以前要在“更多”里打开，用户觉得为一个模型单设开关多余）。
        let cloud = ["haiku", "sonnet", "opus"].map(ModelChoice.claudeCode)
            + endpoints.filter { !$0.isLocal }.flatMap { e in e.models.map { ModelChoice.endpoint(e.id, $0) } }
        let local = endpoints.filter(\.isLocal).flatMap { e in e.models.map { ModelChoice.endpoint(e.id, $0) } }
        var groups: [ModelGroup] = []
        if includeBasic {
            groups.append(ModelGroup(title: L("基础"), choices: [.google] + (Self.appleTranslationAvailable ? [.apple] : [])))
        }
        groups.append(ModelGroup(title: L("云端模型"), choices: cloud))
        if !local.isEmpty { groups.append(ModelGroup(title: L("本地模型"), choices: local)) }
        return groups
    }
}
