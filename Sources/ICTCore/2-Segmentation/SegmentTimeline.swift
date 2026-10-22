import Foundation

/// 把分句后的字幕片段对回音频时间。
///
/// 识别器给的每段确认结果有起止时间；分句器会把它们合并、切开。这里按“非空白字符数”记账：
/// 每段确认结果的字符均匀分布在它的时间范围里，分出来的片段按顺序消耗字符，换算出起止时间。
public struct SegmentTimeline: Sendable {
    private struct Span: Sendable {
        var chars: Int
        var start: Double
        var end: Double
    }

    private var spans: [Span] = []
    /// 第一段里已经被消耗的字符数。
    private var consumed = 0

    public init() {}

    public mutating func addFinal(_ text: String, start: Double, end: Double) {
        let chars = Self.count(text)
        guard chars > 0 else { return }
        spans.append(Span(chars: chars, start: start, end: max(end, start)))
    }

    /// 取出一个片段的起止时间（音频时间轴上的秒数）；没有时间信息时返回 nil。
    public mutating func take(_ segment: String) -> (start: Double, end: Double)? {
        var remaining = Self.count(segment)
        guard remaining > 0, !spans.isEmpty else { return nil }
        let start = time(atOffset: consumed, in: spans[0])
        var end = start
        while remaining > 0, !spans.isEmpty {
            let available = spans[0].chars - consumed
            let used = min(available, remaining)
            consumed += used
            remaining -= used
            end = time(atOffset: consumed, in: spans[0])
            if consumed >= spans[0].chars {
                spans.removeFirst()
                consumed = 0
            }
        }
        return (start, end)
    }

    private func time(atOffset offset: Int, in span: Span) -> Double {
        span.start + (span.end - span.start) * Double(offset) / Double(span.chars)
    }

    private static func count(_ text: String) -> Int {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }
}
