import AVFoundation
import AudioToolbox
import CoreAudio

/// 用 Core Audio process tap（macOS 14.4+）录制电脑正在播放的声音。
/// 只需要“系统录音”权限，不需要屏幕录制权限，也不会改变声音输出。
final class SystemAudioCapture: AudioCapture {
    let label = L("系统音频")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "ICT.SystemAudio", qos: .userInitiated)
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.onBuffer = onBuffer
        try startTap()
        listenForOutputDeviceChanges()
    }

    func stop() {
        stopListening()
        stopTap()
        onBuffer = nil
    }

    // MARK: - Tap

    private func startTap() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "ICT System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "创建系统音频采集")
        tapID = tap

        // 聚合设备里只放 tap，不挂输出设备：有程序打开系统语音处理（视频会议软件的回声消除，ICT 以前的“麦克风降噪”）时
        // 会占住输出设备，挂着输出设备的聚合设备随之停摆，一帧音频都收不到（2026-10-29 实测）。
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ICT Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg), "创建聚合音频设备")
        aggregateID = agg

        // 采样率要用聚合设备的：tap 报告的总是 48 kHz，实际送来的音频却跟着输出设备走
        // （蓝牙耳机平时 44.1 kHz，有程序用它的麦克风时切到通话模式，只有 16 kHz）。
        // 当成 48 kHz 喂给识别器，声音就快了 9% 甚至 3 倍，识别不出字（2026-10-28 实测）。
        var asbd = try readProperty(tap, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
        let rate = try readProperty(agg, kAudioDevicePropertyNominalSampleRate, as: Float64.self)
        if rate > 0 { asbd.mSampleRate = rate }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw CaptureError.coreAudio("读取系统音频格式", -1)
        }
        listenForSampleRateChanges(of: agg)

        let deliver = onBuffer
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, agg, queue) { _, inputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil),
                  buffer.frameLength > 0
            else { return }
            deliver?(buffer)
        }, "注册音频回调")
        try check(AudioDeviceStart(agg, procID), "启动系统音频采集")
    }

    private func stopTap() {
        if aggregateID != kAudioObjectUnknown {
            if let block = sampleRateListener {
                AudioObjectRemovePropertyListenerBlock(aggregateID, &sampleRateAddress, queue, block)
            }
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        sampleRateListener = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - 输出设备切换（例如插拔耳机）或采样率变化（蓝牙耳机进出通话模式）时重建 tap

    private var sampleRateAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var sampleRateListener: AudioObjectPropertyListenerBlock?

    private func listenForSampleRateChanges(of device: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // 不在这个设备自己的回调里拆掉它。
            self?.queue.async { self?.restartTap(ifStillOn: device) }
        }
        sampleRateListener = block
        AudioObjectAddPropertyListenerBlock(device, &sampleRateAddress, queue, block)
    }

    private func restartTap(ifStillOn device: AudioObjectID) {
        guard onBuffer != nil, aggregateID == device else { return }
        let rate = (try? readProperty(device, kAudioDevicePropertyNominalSampleRate, as: Float64.self)) ?? 0
        appLog.notice("system audio: sample rate changed to \(rate, privacy: .public) Hz, rebuilding tap")
        stopTap()
        try? startTap()
    }

    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func listenForOutputDeviceChanges() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.onBuffer != nil else { return }
            self.stopTap()
            try? self.startTap()
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, queue, block)
    }

    private func stopListening() {
        guard let block = deviceListener else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, queue, block)
        deviceListener = nil
    }

    // MARK: - Core Audio 辅助

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw CaptureError.coreAudio(step, status) }
    }

    private func readProperty<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer), "读取音频属性")
        return pointer.load(as: T.self)
    }
}
