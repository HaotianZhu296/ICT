import AVFoundation

/// 音频来源。`onBuffer` 在采集线程上同步调用，buffer 只在回调期间有效，需要立即转换/拷贝。
protocol AudioCapture: AnyObject {
    var label: String { get }
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

/// 把非 Sendable 的采集对象交给后台任务启动（采集对象自己负责线程安全）。
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

enum CaptureError: LocalizedError {
    case permissionDenied(String)
    case coreAudio(String, OSStatus)
    case noInput

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let what): L("没有%@权限。请在“系统设置 › 隐私与安全性”中允许 ICT。", what)
        case .coreAudio(let step, let status): L("%@失败，错误码 %d。", L(step), Int(status))
        case .noInput: L("找不到可用的麦克风输入设备。")
        }
    }
}

final class MicrophoneCapture: AudioCapture {
    let label = L("麦克风")
    private let engine = AVAudioEngine()
    private var running = false

    // 不要打开系统的语音处理（setVoiceProcessingEnabled，FaceTime 那套降噪、回声消除）：它只留离麦克风近的人声，
    // 坐在教室里离老师远时老师的声音几乎被全部压掉（2026-10-29 用户反馈后删掉了“麦克风降噪”）；
    // 它还会占住输出设备（见 SystemAudioCapture）。

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
