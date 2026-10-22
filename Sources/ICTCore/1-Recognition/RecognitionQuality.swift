import Foundation

/// 根据识别器给每个词的置信度，自动判断“这位讲者是不是很难识别”（口音、语速快、噪音大）。
///
/// 实测：口音较重的讲课平均置信度约 0.73，清晰的英语 0.9 以上。判断为“难识别”时让 Claude 按发音纠正识别错误；
/// 用两个阈值（滞回）避免在临界值附近来回切换。
/// 进入快、退出慢：口音重的讲者中间常有几句说得清楚（2026-10-21 实测一节课里“清晰”多半只持续二十几秒），
/// 以前一清楚就退出，一个半小时来回切换 47 次，每次都要换翻译进程。现在要连续清楚 `exitAfter` 秒才退出；
/// 纠正多开一会儿几乎没有坏处。
/// 系统没有识别“哪种口音”的能力（需要专门的模型），而纠正识别错误也不需要知道口音名称。
public struct RecognitionQualityMonitor: Sendable {
    public struct Config: Sendable {
        /// 统计最近这么多个词（讲课约 25 秒的话）。一两句没认准不会马上判为难识别；
        /// 换成口音重的讲者时，大约 15 秒开始纠正。
        public var window = 60
        /// 至少有这么多个词才开始判断。
        public var minWords = 20
        /// 平均置信度低于它：判定为难识别。
        public var enterBelow = 0.80
        /// 难识别状态下平均置信度高于它：开始计时，准备恢复为清晰。
        public var exitAbove = 0.86
        /// 平均置信度连续这么多秒都高于 `exitAbove`，才恢复为清晰；中间有一次不够高就重新计时。
        public var exitAfter: TimeInterval = 60
        public init() {}
    }

    public var config: Config
    public private(set) var isDifficult = false
    private var confidences: [Double] = []
    /// 难识别状态下，从什么时候起平均置信度一直高于 `exitAbove`。
    private var clearSince: Date?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// 最近的平均置信度；词太少时为 nil。
    public var averageConfidence: Double? {
        guard confidences.count >= config.minWords else { return nil }
        return confidences.reduce(0, +) / Double(confidences.count)
    }

    /// 加入一句确认结果里各个词的置信度。返回 true 表示“难识别”状态变了。
    @discardableResult
    public mutating func add(_ wordConfidences: [Double], at now: Date = Date()) -> Bool {
        confidences.append(contentsOf: wordConfidences)
        if confidences.count > config.window { confidences.removeFirst(confidences.count - config.window) }
        guard let average = averageConfidence else { return false }
        if !isDifficult {
            guard average < config.enterBelow else { return false }
            isDifficult = true
            clearSince = nil
            return true
        }
        guard average > config.exitAbove else {
            clearSince = nil
            return false
        }
        let since = clearSince ?? now
        clearSince = since
        guard now.timeIntervalSince(since) >= config.exitAfter else { return false }
        isDifficult = false
        clearSince = nil
        return true
    }
}
