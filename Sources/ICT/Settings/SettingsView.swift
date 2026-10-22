import AppKit
import ICTCore
import SwiftUI
import Translation

/// 设置的分组：左边侧边栏列出它们，点一下滚到那一组。
enum SettingsSection: String, CaseIterable, Identifiable {
    case translation, audio, subtitles, transcripts, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .translation: L("翻译")
        case .audio: L("音频")
        case .subtitles: L("字幕")
        case .transcripts: L("记录")
        case .advanced: L("高级")
        }
    }
    var symbol: String {
        switch self {
        case .translation: "character.bubble"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        case .transcripts: "doc.text"
        case .advanced: "gearshape.2"
        }
    }
}

/// 设置窗口的界面状态（命令行工具链不能用 @State）。
@MainActor @Observable
final class SettingsViewState {
    /// 侧边栏选中的分组。
    var section: SettingsSection? = .translation
    /// 所选语言的 Apple 翻译语言包是否已下载；nil = 还没查到（或系统不支持）。
    var appleLanguagesInstalled: Bool?
    @ObservationIgnored private var downloadStorage: AnyObject?

    /// 触发系统的语言包下载窗口（TranslationSession.Configuration 需要 macOS 15）。
    @available(macOS 15, *)
    var download: LanguageDownloadState {
        if let download = downloadStorage as? LanguageDownloadState { return download }
        let download = LanguageDownloadState()
        downloadStorage = download
        return download
    }
}

@available(macOS 15, *)
@MainActor @Observable
final class LanguageDownloadState {
    var configuration: TranslationSession.Configuration?

    func request(source: LanguageOption, target: LanguageOption) {
        let config = TranslationSession.Configuration(source: Locale.Language(identifier: source.translationCode),
                                                      target: Locale.Language(identifier: target.translationCode))
        // 同一组语言再点一次：配置相同不会重新触发，要 invalidate。
        if configuration?.source == config.source, configuration?.target == config.target {
            configuration?.invalidate()
        } else {
            configuration = config
        }
    }
}

/// 系统翻译框架的下载窗口只能从界面里的翻译会话弹出（`prepareTranslation`）。
private struct LanguageDownload: ViewModifier {
    let state: SettingsViewState
    let onFinished: () async -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.translationTask(state.download.configuration) { session in
                do {
                    try await session.prepareTranslation()
                } catch {
                    appLog.notice("language download: \(String(describing: error), privacy: .public)")
                }
                await onFinished()
            }
        } else {
            content
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var state = SettingsViewState()
    let onTranslationSettingsChanged: () -> Void
    /// 锁定、置顶这类直接作用在字幕窗口上的设置。
    let onAppearanceChanged: () -> Void
    let onManageModels: () -> Void
    /// 字幕大小、位置恢复默认。
    let onResetOverlay: () -> Void
    /// 右上角的“完成”。
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("完成", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                ScrollViewReader { proxy in
                    form
                        .onChange(of: state.section) {
                            guard let section = state.section else { return }
                            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(section, anchor: .top) }
                        }
                }
            }
        }
        .frame(width: 660, height: 620)
        .onChange(of: translationKey) { onTranslationSettingsChanged() }
        .task(id: settings.sourceLanguage + settings.targetLanguage) { await checkAppleLanguages() }
        .modifier(LanguageDownload(state: state) {
            // 下载好了：正在运行的翻译器是在没有语言包时建的，换一个新的。
            let wasMissing = state.appleLanguagesInstalled != true
            await checkAppleLanguages()
            if wasMissing, state.appleLanguagesInstalled == true { onTranslationSettingsChanged() }
        })
        // 用户也可能在“系统设置”里下载语言包，回到本应用时重新检查。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkAppleLanguages() }
        }
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $state.section) { section in
            Label(section.title, systemImage: section.symbol).tag(section)
        }
        .listStyle(.sidebar)
        .frame(width: 160)
    }

    private var form: some View {
        Form {
            Section(SettingsSection.translation.title) {
                LabeledContent("语言") {
                    HStack(spacing: 6) {
                        Picker("讲话语言", selection: $settings.sourceLanguage) {
                            ForEach(LanguageOption.sources) { Text(L($0.displayName)).tag($0.id) }
                        }
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Picker("字幕语言", selection: $settings.targetLanguage) {
                            ForEach(LanguageOption.targets) { Text(L($0.displayName)).tag($0.id) }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Picker("翻译模型", selection: $settings.translationModel) {
                    ForEach(settings.modelGroups(includeBasic: true)) { group in
                        Section(group.title) {
                            ForEach(group.choices, id: \.self) { choice in
                                Text(settings.displayName(choice)).tag(choice)
                            }
                        }
                    }
                }
                .help("实时字幕建议选择速度快的模型，例如 Claude Haiku；Opus 最准确但最慢。Apple 本地翻译可离线使用。")
                if settings.translationModel == .google {
                    Text("免费，不需要配置；需要联网，字幕原文会发送给 Google。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if settings.translationModel == .apple { appleNote }
                LabeledContent("模型服务") {
                    HStack {
                        Text(settings.endpoints.isEmpty ? L("可添加自己的 API 或本地模型") : L("已添加 %d 个", settings.endpoints.count))
                            .foregroundStyle(.secondary)
                        Button("管理…", action: onManageModels)
                    }
                }
                Toggle("自动纠正口音", isOn: $settings.autoCorrect)
                    .help("讲者口音较重、识别不准时，自动让大模型按发音和上下文纠正识别错误。使用 Google 翻译或 Apple 本地翻译时，纠正期间临时改用 Claude Sonnet，需要本机已登录 Claude Code。")
                if settings.autoCorrect {
                    Toggle("纠正时保留识别原文", isOn: $settings.keepOriginalText)
                        .help("纠正修改了原文时，在字幕记录中同时保留识别器原来的文字。")
                        .padding(.leading, 14)
                }
            }
            .id(SettingsSection.translation)

            Section(SettingsSection.audio.title) {
                Picker("音源", selection: $settings.audioSource) {
                    ForEach(AudioSourceMode.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.audioSource != .system {
                    Toggle("麦克风降噪", isOn: $settings.micNoiseReduction)
                        .help("使用系统语音处理降低环境噪音并消除回声。讲者距离较远时可能降低识别效果。")
                }
                if !settings.sourceLanguage.hasPrefix("zh") {
                    Toggle("过滤中文说话声", isOn: $settings.filterChinese)
                        .help("识别并忽略中文说话声，例如周围的交谈。")
                }
            }
            .id(SettingsSection.audio)

            Section(SettingsSection.subtitles.title) {
                Picker("显示", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("外观", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.appearance) { NSApp.appearance = settings.appearance.nsAppearance }
                slider("字号", value: fontSize, range: 14...56, text: "\(Int(settings.translationFontSize)) pt")
                slider("背景", value: $settings.backgroundOpacity, range: 0...1,
                       text: "\(Int((settings.backgroundOpacity * 100).rounded()))%")
                if !settings.fixedOverlayHeight {
                    Stepper(L("显示最近 %d 句", settings.visibleLines), value: $settings.visibleLines, in: 1...6)
                }
                LabeledContent("大小") {
                    HStack {
                        Text("拖动字幕边框调整").foregroundStyle(.secondary)
                        Button("恢复默认", action: onResetOverlay)
                            .help("字幕恢复默认大小，移回屏幕右上角。")
                    }
                }
                Toggle("显示状态条", isOn: $settings.showStatusBar)
                    .help("在字幕底部显示音频输入、识别与翻译状态。")
                Toggle("置顶字幕", isOn: $settings.pinned)
                    .help("字幕总在所有窗口上面。关闭后可以被别的窗口盖住。")
                    .onChange(of: settings.pinned) { onAppearanceChanged() }
                Toggle("锁定字幕", isOn: $settings.clickThrough)
                    .help("字幕点不到、不挡操作。鼠标移到字幕上时右上角出现锁，点它解锁。")
                    .onChange(of: settings.clickThrough) { onAppearanceChanged() }
            }
            .id(SettingsSection.subtitles)

            Section(SettingsSection.transcripts.title) {
                LabeledContent("记录文件夹") {
                    HStack {
                        Text((settings.transcriptFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("更改…", action: chooseFolder)
                    }
                }
            }
            .id(SettingsSection.transcripts)

            Section(SettingsSection.advanced.title) {
                TextField("Claude 路径", text: $settings.claudePath, prompt: Text("自动查找"))
            }
            .id(SettingsSection.advanced)
        }
        .formStyle(.grouped)
    }

    /// 选了 Apple 本地翻译时的说明：能力范围，以及语言包还没下载时提供下载。
    @ViewBuilder
    private var appleNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("离线翻译，速度快，不需要账号。")
                .foregroundStyle(.secondary)
            if state.appleLanguagesInstalled == false {
                HStack {
                    Label(L("尚未下载“%@ → %@”语言包", L(settings.source.displayName), L(settings.target.displayName)),
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("下载…") {
                        if #available(macOS 15, *) { state.download.request(source: settings.source, target: settings.target) }
                    }
                }
            }
        }
        .font(.callout)
    }

    private func checkAppleLanguages() async {
        guard #available(macOS 26, *) else { return }
        let source = settings.source, target = settings.target
        state.appleLanguagesInstalled = source.translationCode == target.translationCode
            ? true : await AppleTranslator.isInstalled(source: source, target: target)
    }

    /// 一个滑块同时调译文和原文字号（原文约为译文的 0.62 倍）。
    private var fontSize: Binding<Double> {
        Binding(
            get: { settings.translationFontSize },
            set: { size in
                settings.translationFontSize = size.rounded()
                settings.sourceFontSize = (size * 0.62).rounded()
            })
    }

    /// 任何会影响识别或翻译的设置；改了就自动生效。
    private var translationKey: String {
        [settings.sourceLanguage, settings.targetLanguage, settings.audioSource.rawValue,
         settings.displayName(settings.translationModel), settings.claudePath,
         String(settings.filterChinese), String(settings.micNoiseReduction),
         String(settings.autoCorrect)].joined(separator: "\u{1}")
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        LabeledContent(L(title)) {
            HStack(spacing: 10) {
                Slider(value: value, in: range).frame(maxWidth: 240)
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (settings.transcriptFolder as NSString).expandingTildeInPath)
        FilePanel.present(panel) { [settings] url in
            if let url { settings.transcriptFolder = url.path }
        }
    }
}
