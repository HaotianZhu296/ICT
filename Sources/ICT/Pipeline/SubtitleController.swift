import AVFoundation
import AppKit
import ICTCore
import Observation
import os

/// 运行日志：`log show --last 1h --predicate 'subsystem == "com.ict.app"'`。
/// 出问题（比如卡住、没字幕）时用来看停在哪一步。
let appLog = Logger(subsystem: "com.ict.app", category: "pipeline")

struct SubtitleLine: Identifiable, Equatable {
    enum State: Equatable { case waiting, translating, done, failed }

    let id = UUID()
    let time: Date
    let sourceLabel: String?
    var source: String
    var translation = ""
    var state: State = .waiting
    /// 例如 “Apple 兜底”，表示这一句不是用首选引擎翻译的。
    var note: String?
    /// 自动纠正改过原文时，识别器原来给出的文字（打开“保留识别原文”时才保存）。
    var originalSource: String?
    /// 这句话在音频里的起止时刻（导出 SRT/VTT 用）；没有逐词时间时为 nil。
    var audioStart: Date?
    var audioEnd: Date?
    /// 延迟分析用（ICT_DEBUG_LATENCY）：开始翻译、出第一个字的时刻。
    var translateStartedAt: Date?
    var firstTokenAt: Date?
}

/// 一个音源的完整链路：采集 → 识别 → 分句。
@MainActor
final class SourcePipeline {
    let capture: AudioCapture
    let label: String?
    let engine = TranscriptionEngine()
    var segmenter = Segmenter()
    var volatileText = ""
    /// 把分句后的片段对回音频时间。
    var timeline = SegmentTimeline()
    /// 识别器音频时间轴的 0 秒对应的时刻（开始采集时）。
    var captureStart = Date()
    /// 已经因为“没有新音频”请求过确认当前这段临时文本了（新结果到来时清掉）。
    var finalizeRequested = false

    init(capture: AudioCapture, label: String?) {
        self.capture = capture
        self.label = label
    }

    var liveSource: String { Segmenter.join(segmenter.pending, volatileText) }
}

@MainActor @Observable
/// 整条流水线的总控：开始、停止、改设置后重启。各环节的代码在 `Pipeline/` 下按步骤分开的扩展里
/// （识别 `2-Recognition`、翻译 `4-Translation`、记录 `6-Transcript`），所以下面一些状态的 setter 不是 private；
/// 界面只读取它们。
final class SubtitleController {
    private(set) var isRunning = false
    private(set) var isStarting = false
    var status = L("未开始")
    var lines: [SubtitleLine] = []
    /// 各音源正在说、还没分好句的文字（键是音源标签，只有一个音源时为空字符串）。
    var live: [String: String] = [:]
    var notesInProgress = false
    /// 状态条：最近的输入音量（0…1）、多久没有声音、翻译积压句数、识别是否困难、最近的错误。
    private(set) var inputLevel: Float = 0
    private(set) var silentFor: TimeInterval = 0
    var backlog = 0
    var recognitionDifficult = false
    var alert: String?
    /// 首选引擎（Claude）用不了（例如未登录），正在用 Apple 兜底。
    var usingFallback = false

    @ObservationIgnored let settings: AppSettings
    /// 选了 Apple 本地翻译、但语言包还没下载：由 AppDelegate 弹出系统的下载窗口。
    @ObservationIgnored var onAppleLanguagesMissing: (() -> Void)?
    /// AI 助手；每次用户点“开始”时新开一个对话。
    @ObservationIgnored let assistant: AssistantSession
    @ObservationIgnored var pipelines: [SourcePipeline] = []
    @ObservationIgnored var ticker: Timer?
    @ObservationIgnored var translator: Translator?
    @ObservationIgnored var fallback: Translator?
    /// 选了 Google 或 Apple 这类只能翻译的模型时，它们的翻译器。识别困难时 `translator` 临时换成
    /// 带纠正的 Claude 会话，清楚了再换回它；Claude 出错时也用它顶上。
    @ObservationIgnored var basicTranslator: Translator?
    /// 本机有没有 Claude Code（准备翻译器时查一次；界面上判断能不能纠正要用，不能每次重绘都去找）。
    @ObservationIgnored var claudeAvailable = false
    @ObservationIgnored var queue: [UUID] = []
    /// 正在翻译的句数。
    @ObservationIgnored var activeTranslations = 0
    @ObservationIgnored var store: TranscriptStore?
    @ObservationIgnored var listeningStatus = ""
    /// 当前识别链路是按哪些设置启动的；这些设置变了才需要重启识别。
    @ObservationIgnored var startedRecognitionKey = ""
    @ObservationIgnored var applyTask: Task<Void, Never>?
    /// 运行期间告诉系统这是实时任务：不进 App Nap、不因闲置而睡眠（一节课不碰电脑也不会断）。
    @ObservationIgnored var activity: NSObjectProtocol?
    @ObservationIgnored var quality = RecognitionQualityMonitor()
    /// 当前翻译会话是按“讲者难识别”的提示词建立的吗（重新开始时状态清零，要和它对得上）。
    @ObservationIgnored var translatorBuiltDifficult = false
    /// 翻译器刚被换掉、新的还在准备（resetTranslators 到 prepareTranslators 结束）。
    @ObservationIgnored var translatorPending = false
    @ObservationIgnored var alertAt = Date.distantPast
    /// 这份记录对应的录音从什么时候开始（导出字幕的时间零点）。
    @ObservationIgnored var sessionStart: Date?
    @ObservationIgnored var filteredCount = 0

    init(settings: AppSettings) {
        self.settings = settings
        assistant = AssistantSession(settings: settings)
        assistant.transcript = { [weak self] in
            guard let self else { return ([], "") }
            return (self.lines, self.live.keys.sorted().compactMap { self.live[$0] }.joined(separator: " "))
        }
    }

    var transcriptURL: URL? { store?.fileURL }

    // MARK: - 开始 / 停止

    /// 用户点“开始/停止”。开始时 AI 助手新开一个对话（设置变化引起的自动重启不会清空对话）。
    func toggle() {
        Task {
            if isRunning {
                await stop()
            } else {
                assistant.newConversation()
                if settings.assistantVisible { assistant.warmUp() }
                // 换了讲者/场景：重新判断好不好识别。
                quality = RecognitionQualityMonitor()
                recognitionDifficult = false
                // 上次的翻译会话是按“难识别”建立的：换回普通提示词。
                if translatorBuiltDifficult { resetTranslators() }
                await start()
            }
        }
    }

    func start() async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        status = L("准备中…")
        appLog.notice("start: source=\(self.settings.audioSource.rawValue, privacy: .public) lang=\(self.settings.sourceLanguage, privacy: .public) model=\(self.settings.displayName(self.settings.translationModel), privacy: .public)")

        let mode = settings.audioSource
        let testing = ProcessInfo.processInfo.environment["ICT_TEST_AUDIO_FILE"] != nil
        if mode != .system, !testing {
            guard await MicrophoneCapture.requestPermission() else {
                status = CaptureError.permissionDenied(L("麦克风")).localizedDescription
                return
            }
        }

        await prepareTranslators()
        appLog.notice("start: translators ready (\(self.translator?.name ?? "none", privacy: .public))")
        if store == nil { openStore() }

        var captures: [AudioCapture] = []
        if let testFile = ProcessInfo.processInfo.environment["ICT_TEST_AUDIO_FILE"] {
            captures.append(FileCapture(url: URL(fileURLWithPath: testFile)))
        } else {
            if mode != .system { captures.append(MicrophoneCapture(noiseReduction: settings.micNoiseReduction)) }
            if mode != .microphone { captures.append(SystemAudioCapture()) }
        }

        var started: [SourcePipeline] = []
        do {
            for capture in captures {
                let pipeline = SourcePipeline(capture: capture, label: mode == .both ? capture.label : nil)
                appLog.notice("start: recognizer for \(String(describing: type(of: capture)), privacy: .public)")
                try await pipeline.engine.start(
                    localeID: settings.sourceLanguage, guardLocaleID: settings.guardLocale,
                    onStatus: { [weak self] message, isError in
                        Task { @MainActor in
                            self?.status = message
                            if isError { self?.showAlert(message) }
                        }
                    },
                    onEvent: { [weak self, weak pipeline] event in
                        guard let self, let pipeline else { return }
                        self.handle(event, from: pipeline)
                    })
                let engine = pipeline.engine
                appLog.notice("start: recognizer ready, starting audio capture")
                // 在后台线程启动采集：第一次录系统声音时，Core Audio 会一直等到用户回答权限弹窗才返回，
                // 放在主线程上整个界面（字幕、菜单）都会冻住。
                let box = UncheckedSendable(capture)
                pipeline.captureStart = Date()
                try await Task.detached(priority: .userInitiated) {
                    try box.value.start { buffer in engine.append(buffer) }
                }.value
                if sessionStart == nil { sessionStart = pipeline.captureStart }
                appLog.notice("start: audio capture running")
                started.append(pipeline)
            }
        } catch {
            for p in started { p.capture.stop(); await p.engine.stop() }
            status = L("启动失败：%@", error.localizedDescription)
            appLog.error("start failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        pipelines = started
        isRunning = true
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "ICT 实时字幕")
        startedRecognitionKey = recognitionKey
        filteredCount = 0
        updateListeningStatus()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() async {
        guard isRunning else { return }
        appLog.notice("stop")
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        let current = pipelines
        pipelines = []
        for p in current { p.capture.stop() }
        for p in current {
            await p.engine.stop()
            p.volatileText = ""
            enqueue(p.segmenter.flushAll(), from: p)
        }
        live = [:]
        status = L("已停止")
    }

    /// 结束当前记录文件，下次开始时新建一个。
    func newSession() {
        Task {
            await stop()
            lines = []
            queue = []
            backlog = 0
            store = nil
            sessionStart = nil
            translator?.shutdown()
            translator = nil
            assistant.newConversation()
            status = L("已开始新的记录")
        }
    }

    /// 设置改变后自动生效：识别相关的设置变了就重启识别，否则只重建翻译器。
    /// 稍等一下再应用，避免在文本框里打字时每个字都重来一次。
    func settingsChanged() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            await self.applySettings()
        }
    }

    var recognitionKey: String {
        [settings.sourceLanguage, settings.audioSource.rawValue, settings.guardLocale ?? "", String(settings.micNoiseReduction)]
            .joined(separator: "\u{1}")
    }

    func applySettings() async {
        appLog.notice("apply settings (running: \(self.isRunning))")
        while isStarting { try? await Task.sleep(for: .milliseconds(100)) }
        resetTranslators()
        guard isRunning else { return }
        if recognitionKey != startedRecognitionKey {
            await stop()
            await start()
        } else {
            await prepareTranslators()
            updateListeningStatus()
        }
    }

    func updateListeningStatus() {
        listeningStatus = L("正在听：%@ · %@ → %@ · %@", settings.audioSource.title, L(settings.source.displayName),
                            L(settings.target.displayName), translator?.name ?? "")
        status = filteredCount > 0 ? L("%@ · 已过滤中文说话 %d 段", listeningStatus, filteredCount) : listeningStatus
    }

    func shutdown() {
        translator?.shutdown()
        assistant.shutdown()
    }

    // MARK: - 状态条

    func updateInputStatus() {
        var level: Float = 0
        var silent = TimeInterval.infinity
        for p in pipelines {
            let s = p.engine.inputStatus
            level = max(level, s.level)
            silent = min(silent, s.silentFor)
        }
        // 只在明显变化时更新，避免界面每 0.25 秒重绘。
        let quantized = (min(level * 8, 1) * 10).rounded() / 10
        if quantized != inputLevel { inputLevel = quantized }
        let silentRounded = silent.isFinite ? silent.rounded() : 999
        if silentRounded != silentFor { silentFor = silentRounded }
    }

    func showAlert(_ message: String) {
        alert = message
        alertAt = Date()
    }

    /// 仅用于 `--stress-overlay` 自检：直接追加一句字幕、更新“正在说”。
    func debugAppend(source: String, translation: String, live liveText: String) {
        var line = SubtitleLine(time: Date(), sourceLabel: nil, source: source)
        line.translation = translation
        line.state = .done
        lines.append(line)
        live = ["": liveText]
        isRunning = true
    }

    /// 压力测试：新句子先进入“翻译中”，之后由 `debugAdvanceStreaming` 逐字补全译文。
    func debugAppendStreaming(source: String, translation: String) {
        var line = SubtitleLine(time: Date(), sourceLabel: nil, source: source)
        line.state = .translating
        debugPendingTranslation = (line.id, translation)
        lines.append(line)
        isRunning = true
    }

    func debugAdvanceStreaming(by count: Int) {
        guard let (id, full) = debugPendingTranslation, let i = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[i].translation = String(full.prefix(lines[i].translation.count + count))
        if lines[i].translation.count >= full.count {
            lines[i].state = .done
            debugPendingTranslation = nil
        }
    }

    @ObservationIgnored var debugPendingTranslation: (UUID, String)?

    func debugUpdateLive(_ text: String) {
        live = ["": text]
    }

    /// 仅用于 `--render-window` 自检：填入示例字幕。
    func loadPreview(running: Bool = true) {
        var a = SubtitleLine(time: Date(), sourceLabel: nil, source: "Today we're going to look at eigenvalues and eigenvectors, which are probably the most important idea in this course.")
        a.translation = "今天我们来看特征值 (eigenvalue) 和特征向量 (eigenvector)，这可能是本课程最重要的概念。"
        a.state = .done
        var b = SubtitleLine(time: Date(), sourceLabel: nil, source: "An eigenvector of a matrix A is a nonzero vector v such that A times v equals lambda times v.")
        b.translation = "矩阵 A 的特征向量是一个非零向量 v，使得 A 乘以 v 等于 λ 乘以 v。"
        b.state = .translating
        lines = [a, b]
        live = running ? ["": "In other words, the matrix only stretches"] : [:]
        isRunning = running
    }
}
